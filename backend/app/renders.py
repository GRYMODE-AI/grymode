"""AI-rendered look visuals and personal multi-angle try-on.

Two render kinds, both stored privately under ``{user_id}/renders/{outfit_id}/``:

- ``look``: one styled image of the outfit's exact garments assembled as worn (ghost mannequin),
  so a look reads as one replicable outfit rather than separate product photos.
- ``try_on``: the user, from their face photo and measurements, wearing the look from four
  angles (front, three-quarter, side, back). The front render anchors the other angles so
  identity, garments, lighting, and framing stay consistent while the viewer rotates.

Every render is conditioned on the user's own garment photos; nothing is invented when a
render fails — the row records an error code and the client keeps the garment view.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import uuid
from collections import Counter
from collections.abc import Coroutine
from datetime import UTC, datetime, timedelta
from typing import Any

from app import outfits as outfits_repo
from app import usage as usage_repo
from app.config import Settings
from app.db import Database, DBConnection
from app.entitlements import Plan
from app.openai_client import AIProviderError, OpenAIImageClient, ReferenceImage
from app.storage import StorageClient
from app.wardrobe_models import MAX_UPLOAD_BYTES

logger = logging.getLogger("grymode.renders")

KIND_LOOK = "look"
KIND_TRY_ON = "try_on"
VIEW_FRONT = "front"
TRY_ON_VIEWS = ("front", "three_quarter", "side", "back")
RENDER_SIZE = "1024x1536"
STALE_IN_FLIGHT = timedelta(minutes=15)
LOOK_PROMPT_VERSION = "look-v3"
TRY_ON_PROMPT_VERSION = "tryon-v4"

_CATEGORY_NOUN = {
    "tops": "top",
    "bottoms": "trousers",
    "dresses": "dress",
    "outerwear": "jacket",
    "shoes": "shoes",
    "bags": "bag",
    "accessories": "accessory",
    "knitwear": "knit sweater",
    "activewear": "activewear top",
}
_SLOT_ROLE = {
    "primary": "main piece",
    "bottom": "bottom",
    "footwear": "shoes",
    "outerwear": "outer layer, worn over the main piece",
    "bag": "bag",
    "accessory": "accessory",
}
_BUILD_PHRASE = {
    "slim": "a slim, lean build",
    "regular": "an average, medium build",
    "athletic": "an athletic, muscular build",
    "broad": "a broad, solid build",
}
_VIEW_PHRASE = {
    "three_quarter": "turned about 45 degrees to their left — a three-quarter view showing the front and one side",
    "side": "turned 90 degrees to their left — a full side profile view",
    "back": "turned fully around — a back view seen from directly behind, face not visible",
}


# --- prompt building (pure, unit-tested) ---


def garment_label(piece: dict[str, Any]) -> str:
    noun = piece.get("subcategory") or _CATEGORY_NOUN.get(str(piece.get("category")), str(piece.get("category")))
    words = [piece.get("primary_color"), noun]
    details = [d for d in (piece.get("material"), piece.get("pattern")) if d and d not in ("solid", "plain")]
    label = " ".join(str(w) for w in words if w)
    return f"{label} ({', '.join(str(d) for d in details)})" if details else label


def reference_plan(pieces: list[dict[str, Any]]) -> tuple[list[str], list[tuple[dict[str, Any], int]]]:
    """Unique garment photo keys in order, and each piece paired with its 0-based photo index."""
    keys: list[str] = []
    paired: list[tuple[dict[str, Any], int]] = []
    for piece in sorted(pieces, key=lambda p: p["position"]):
        key = str(piece["image_object_key"])
        if key not in keys:
            keys.append(key)
        paired.append((piece, keys.index(key)))
    return keys, paired


def _garment_lines(paired: list[tuple[dict[str, Any], int]], *, image_offset: int) -> str:
    shared = Counter(index for _, index in paired)
    lines = []
    for piece, index in paired:
        image_no = index + 1 + image_offset
        source = f"Image {image_no}"
        if shared[index] > 1:
            source += f" (that photo shows several items — use only the {garment_label(piece)})"
        role = _SLOT_ROLE.get(str(piece.get("slot")), "piece")
        lines.append(f"- {role}: {garment_label(piece)} — from {source}")
    return "\n".join(lines)


GARMENT_FIDELITY = (
    "Reproduce every garment exactly as photographed: same colour, fabric, texture, pattern, cut, length, "
    "collar, buttons, hardware, and any logos. Do not add, remove, or substitute any clothing item or accessory. "
    "No text or watermarks."
)


def _only_these(paired: list[tuple[dict[str, Any], int]]) -> str:
    count = len(paired)
    return (
        f"Show ONLY these {count} item{'s' if count != 1 else ''} and nothing else. Never add an item that is "
        "not listed — no extra belt, bag, watch, jewellery, hat, scarf, sunglasses, socks, or layer."
    )


def _styling_notes(paired: list[tuple[dict[str, Any], int]]) -> str:
    slots = {str(piece.get("slot")) for piece, _ in paired}
    notes = ["shoes are placed beneath the trousers as if worn"]
    if "outerwear" in slots:
        notes.insert(0, "the outer layer is worn open over the main piece")
    if "bag" in slots:
        notes.append("the listed bag rests beside the legs")
    if "accessory" in slots:
        notes.append("each listed accessory appears exactly where it would be worn")
    return "Style it the way a stylist would: " + ", ".join(notes) + "."


def look_prompt(paired: list[tuple[dict[str, Any], int]]) -> str:
    return (
        "Create a photorealistic fashion lookbook photograph of ONE complete outfit assembled as it would be "
        "worn, on an invisible ghost mannequin: no visible person, no head, no hands. Full length from collar to "
        "shoes, front view, centred, soft even studio lighting, plain warm light-grey seamless background, "
        "subtle floor shadow.\n\n"
        "The outfit is made of exactly these garments from the reference photos:\n"
        f"{_garment_lines(paired, image_offset=0)}\n\n"
        f"{_only_these(paired)}\n"
        f"{_styling_notes(paired)}\n"
        f"{GARMENT_FIDELITY}"
    )


def try_on_front_prompt(*, height_cm: int, body_build: str, paired: list[tuple[dict[str, Any], int]]) -> str:
    build = _BUILD_PHRASE.get(body_build, "an average build")
    return (
        "Image 1 is a photo of the user's face. Create a photorealistic full-body photograph of this exact "
        "person. Preserve their identity precisely: face shape, facial features, skin tone, hair, and "
        "expression character must match Image 1.\n\n"
        f"Body: {height_cm} cm tall with {build}; realistic, natural proportions for that height and build.\n"
        "Pose and framing: standing naturally facing the camera, arms relaxed, entire body visible from the top "
        "of the head to below the shoes with a little space above and below, camera at chest height.\n"
        "Setting: clean photo studio, plain warm light-grey seamless background, soft even lighting, sharp focus.\n\n"
        "They are wearing exactly this outfit from the garment reference photos:\n"
        f"{_garment_lines(paired, image_offset=1)}\n\n"
        f"{_only_these(paired)} A listed bag is carried in one hand or over the shoulder.\n"
        f"{GARMENT_FIDELITY} No other people."
    )


def try_on_view_prompt(view: str, *, paired: list[tuple[dict[str, Any], int]]) -> str:
    return (
        "Image 1 is a full-body studio photo of a person wearing an outfit. Image 2 is that person's face. "
        "Create a new photograph of the SAME person in the SAME outfit, "
        f"{_VIEW_PHRASE[view]}.\n\n"
        "Keep everything else identical to Image 1: identity, hair, body proportions, height, every garment and "
        "how it is worn, lighting, background, camera distance, and full head-to-toe framing. Show the parts "
        "of each garment visible from this angle accurately (backs of jackets, side seams, heels of shoes).\n\n"
        "Garment references for accuracy:\n"
        f"{_garment_lines(paired, image_offset=2)}\n\n"
        f"{_only_these(paired)}\n"
        f"{GARMENT_FIDELITY} No other people."
    )


def look_signature(outfit_signature: str) -> str:
    """Stable cache key for a look visual: prompt version + hashed garment-set signature.

    Outfit signatures can exceed the 128-char ``input_signature`` column when many UUIDs
    are pipe-joined, so we store a short digest.
    """
    digest = hashlib.sha256(outfit_signature.encode()).hexdigest()[:40]
    return f"{LOOK_PROMPT_VERSION}:{digest}"


def face_revision(avatar: dict[str, Any]) -> str:
    """Epoch seconds of the avatar row so replacing face.jpg at a fixed key invalidates try-on cache."""
    updated = avatar.get("updated_at")
    if isinstance(updated, datetime):
        return str(int(updated.timestamp()))
    if updated is None:
        return ""
    return str(updated)


def try_on_signature(avatar: dict[str, Any], *, outfit_signature: str) -> str:
    """Cache key for try-on angles: face key + face revision + measurements + garment set."""
    raw = (
        f"{avatar.get('face_object_key')}|{face_revision(avatar)}|"
        f"{avatar.get('height_cm')}|{avatar.get('body_build')}|{outfit_signature}"
    )
    return f"{TRY_ON_PROMPT_VERSION}:" + hashlib.sha256(raw.encode()).hexdigest()[:40]


def needs_render(existing: dict[str, Any] | None, *, signature: str, now: datetime) -> bool:
    if existing is None:
        return True
    status = existing["status"]
    if status == "failed" or existing.get("input_signature") != signature:
        return True
    if status in ("pending", "running"):
        updated = existing.get("updated_at")
        return isinstance(updated, datetime) and now - updated > STALE_IN_FLIGHT
    return False


def render_object_key(user_id: uuid.UUID, outfit_id: uuid.UUID, render_id: uuid.UUID) -> str:
    return f"{user_id}/renders/{outfit_id}/{render_id}.jpg"


# --- persistence ---


async def claim_render(
    connection: DBConnection,
    *,
    user_id: uuid.UUID,
    outfit_id: uuid.UUID,
    kind: str,
    view: str,
    signature: str,
    force: bool = False,
) -> tuple[uuid.UUID, str | None] | None:
    """Queues a render if forced, missing, failed, stale, or built from different inputs.

    Returns ``(render_id, previous_object_key)`` when queued, ``None`` when nothing to do.
    """
    existing = await connection.fetchrow(
        """
        select id, status, object_key, input_signature, updated_at
          from public.outfit_renders
         where outfit_id = $1 and kind = $2 and view = $3 and user_id = $4
        """,
        outfit_id,
        kind,
        view,
        user_id,
    )
    if not force and not needs_render(dict(existing) if existing else None, signature=signature, now=datetime.now(UTC)):
        return None
    render_id = await connection.fetchval(
        """
        insert into public.outfit_renders (user_id, outfit_id, kind, view, status, input_signature)
        values ($1, $2, $3, $4, 'pending', $5)
        on conflict (outfit_id, kind, view) do update
           set status = 'pending', object_key = null, error_code = null,
               input_signature = excluded.input_signature
        returning id
        """,
        user_id,
        outfit_id,
        kind,
        view,
        signature,
    )
    if not isinstance(render_id, uuid.UUID):
        return None
    previous = str(existing["object_key"]) if existing and existing["object_key"] else None
    return render_id, previous


async def mark_running(connection: DBConnection, render_id: uuid.UUID) -> None:
    await connection.execute(
        "update public.outfit_renders set status = 'running' where id = $1 and status = 'pending'", render_id
    )


async def succeed_render(connection: DBConnection, render_id: uuid.UUID, object_key: str, model: str) -> None:
    await connection.execute(
        """
        update public.outfit_renders
           set status = 'succeeded', object_key = $2, model = $3, error_code = null
         where id = $1
        """,
        render_id,
        object_key,
        model,
    )


async def fail_render(connection: DBConnection, render_id: uuid.UUID, error_code: str) -> None:
    await connection.execute(
        "update public.outfit_renders set status = 'failed', object_key = null, error_code = $2 where id = $1",
        render_id,
        error_code[:64],
    )


async def list_renders(
    connection: DBConnection, user_id: uuid.UUID, outfit_ids: list[uuid.UUID], kind: str
) -> list[dict[str, Any]]:
    if not outfit_ids:
        return []
    rows = await connection.fetch(
        """
        select id, outfit_id, kind, view, status, object_key, input_signature, error_code, updated_at
          from public.outfit_renders
         where user_id = $1 and kind = $2 and outfit_id = any($3::uuid[])
        """,
        user_id,
        kind,
        outfit_ids,
    )
    return [dict(row) for row in rows]


async def render_object_keys(connection: DBConnection, user_id: uuid.UUID) -> list[str]:
    rows = await connection.fetch(
        "select object_key from public.outfit_renders where user_id = $1 and object_key is not null", user_id
    )
    return [str(row["object_key"]) for row in rows]


# --- service ---


class RenderService:
    def __init__(
        self,
        *,
        database: Database,
        storage: StorageClient,
        images: OpenAIImageClient,
        settings: Settings,
        model: str,
        quality: str,
        concurrency: int,
    ) -> None:
        self._database = database
        self._storage = storage
        self._images = images
        self._settings = settings
        self._model = model
        self._quality = quality
        self._semaphore = asyncio.Semaphore(concurrency)
        self._tasks: set[asyncio.Task[None]] = set()
        self._in_flight: set[tuple[uuid.UUID, str]] = set()

    def _spawn(self, coro: Coroutine[Any, Any, None]) -> None:
        task = asyncio.create_task(coro)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    # Look visuals

    def schedule_looks(self, user_id: uuid.UUID, outfit_ids: list[uuid.UUID], *, plan: Plan) -> None:
        """Demo/ops helper only. Production leaves ``ai_render_looks_after_generation`` false."""

        async def run() -> None:
            for outfit_id in outfit_ids:
                async with self._database.as_service() as connection:
                    row = await outfits_repo.fetch_outfit(connection, user_id, outfit_id)
                await self.ensure_look(user_id, outfit_id, plan=plan, outfit_signature=str(row["signature"]))

        self._spawn(run())

    async def ensure_look(self, user_id: uuid.UUID, outfit_id: uuid.UUID, *, plan: Plan, outfit_signature: str) -> bool:
        """Starts a look visual if missing/stale. Returns True when a new billable claim was made."""
        marker = (outfit_id, KIND_LOOK)
        if marker in self._in_flight:
            return False
        self._in_flight.add(marker)
        signature = look_signature(outfit_signature)
        claim: tuple[uuid.UUID, str | None] | None = None
        try:
            async with self._database.as_service() as connection:
                existing = await connection.fetchrow(
                    """
                    select id, status, object_key, input_signature, updated_at
                      from public.outfit_renders
                     where outfit_id = $1 and kind = $2 and view = $3 and user_id = $4
                    """,
                    outfit_id,
                    KIND_LOOK,
                    VIEW_FRONT,
                    user_id,
                )
                if not needs_render(dict(existing) if existing else None, signature=signature, now=datetime.now(UTC)):
                    self._in_flight.discard(marker)
                    return False
                await usage_repo.assert_quota(
                    connection,
                    user_id=user_id,
                    plan=plan,
                    kind="look_render",
                    units=1,
                    settings=self._settings,
                )
                claim = await claim_render(
                    connection,
                    user_id=user_id,
                    outfit_id=outfit_id,
                    kind=KIND_LOOK,
                    view=VIEW_FRONT,
                    signature=signature,
                )
                if claim is not None:
                    await usage_repo.record_usage(
                        connection, user_id=user_id, kind="look_render", outfit_id=outfit_id, units=1
                    )
        except BaseException:
            self._in_flight.discard(marker)
            raise
        if claim is None:
            self._in_flight.discard(marker)
            return False
        self._spawn(self._render_look(user_id, outfit_id, *claim))
        return True

    async def _render_look(
        self, user_id: uuid.UUID, outfit_id: uuid.UUID, render_id: uuid.UUID, previous_key: str | None
    ) -> None:
        try:
            async with self._database.as_service() as connection:
                await mark_running(connection, render_id)
                pieces = await _outfit_pieces(connection, user_id, outfit_id)
            keys, paired = reference_plan(pieces)
            references = await self._download(keys)
            image = await self._edit(look_prompt(paired), references, purpose="look_render")
            await self._store(user_id, outfit_id, render_id, image, previous_key)
            logger.info("look_render_ready", extra={"outfit_id": str(outfit_id), "pieces": len(pieces)})
        except Exception as exc:
            await self._fail(render_id, exc, outfit_id=outfit_id)
        finally:
            self._in_flight.discard((outfit_id, KIND_LOOK))

    # Personal try-on

    async def ensure_try_on(
        self,
        user_id: uuid.UUID,
        outfit_id: uuid.UUID,
        avatar: dict[str, Any],
        *,
        plan: Plan,
        outfit_signature: str,
    ) -> bool:
        """Starts missing try-on angles. Returns True when any new billable claim was made."""
        marker = (outfit_id, KIND_TRY_ON)
        if marker in self._in_flight:
            return False
        self._in_flight.add(marker)
        signature = try_on_signature(avatar, outfit_signature=outfit_signature)
        claims: dict[str, tuple[uuid.UUID, str | None]] = {}
        try:
            async with self._database.as_service() as connection:
                existing_rows = await list_renders(connection, user_id, [outfit_id], KIND_TRY_ON)
                by_view = {row["view"]: row for row in existing_rows}
                now = datetime.now(UTC)
                front_needed = needs_render(by_view.get(VIEW_FRONT), signature=signature, now=now)
                # A new front invalidates every angle anchored on the previous front image.
                if front_needed:
                    needed_views = list(TRY_ON_VIEWS)
                else:
                    needed_views = [
                        view for view in TRY_ON_VIEWS if needs_render(by_view.get(view), signature=signature, now=now)
                    ]
                if not needed_views:
                    self._in_flight.discard(marker)
                    return False
                await usage_repo.assert_quota(
                    connection,
                    user_id=user_id,
                    plan=plan,
                    kind="try_on",
                    units=len(needed_views),
                    settings=self._settings,
                )
                front = None
                if VIEW_FRONT in needed_views:
                    front = await claim_render(
                        connection,
                        user_id=user_id,
                        outfit_id=outfit_id,
                        kind=KIND_TRY_ON,
                        view=VIEW_FRONT,
                        signature=signature,
                    )
                    if front is not None:
                        claims[VIEW_FRONT] = front
                for view in TRY_ON_VIEWS[1:]:
                    if view not in needed_views:
                        continue
                    claim = await claim_render(
                        connection,
                        user_id=user_id,
                        outfit_id=outfit_id,
                        kind=KIND_TRY_ON,
                        view=view,
                        signature=signature,
                        force=front is not None,
                    )
                    if claim is not None:
                        claims[view] = claim
                if claims:
                    await usage_repo.record_usage(
                        connection,
                        user_id=user_id,
                        kind="try_on",
                        outfit_id=outfit_id,
                        units=len(claims),
                    )
        except BaseException:
            self._in_flight.discard(marker)
            raise
        if not claims:
            self._in_flight.discard(marker)
            return False
        self._spawn(self._render_try_on(user_id, outfit_id, avatar, claims))
        return True

    async def _render_try_on(
        self,
        user_id: uuid.UUID,
        outfit_id: uuid.UUID,
        avatar: dict[str, Any],
        claims: dict[str, tuple[uuid.UUID, str | None]],
    ) -> None:
        try:
            async with self._database.as_service() as connection:
                for render_id, _ in claims.values():
                    await mark_running(connection, render_id)
                pieces = await _outfit_pieces(connection, user_id, outfit_id)
                front_row = None
                if VIEW_FRONT not in claims:
                    rows = await list_renders(connection, user_id, [outfit_id], KIND_TRY_ON)
                    front_row = next((r for r in rows if r["view"] == VIEW_FRONT and r["object_key"]), None)

            keys, paired = reference_plan(pieces)
            garment_refs = await self._download(keys[: OpenAIImageClient.MAX_REFERENCES - 2])
            [face] = await self._download([str(avatar["face_object_key"])])

            if VIEW_FRONT in claims:
                render_id, previous = claims[VIEW_FRONT]
                try:
                    prompt = try_on_front_prompt(
                        height_cm=int(avatar["height_cm"]), body_build=str(avatar["body_build"]), paired=paired
                    )
                    front_bytes = await self._edit(prompt, [face, *garment_refs], purpose="try_on_front")
                    await self._store(user_id, outfit_id, render_id, front_bytes, previous)
                except Exception as exc:
                    await self._fail(render_id, exc, outfit_id=outfit_id)
                    for view, (other_id, _) in claims.items():
                        if view != VIEW_FRONT:
                            await self._fail(other_id, AIProviderError("front_render_failed"), outfit_id=outfit_id)
                    return
                front = ReferenceImage(front_bytes, "image/jpeg")
            elif front_row is not None:
                [front] = await self._download([str(front_row["object_key"])])
            else:
                for render_id, _ in claims.values():
                    await self._fail(render_id, AIProviderError("front_render_missing"), outfit_id=outfit_id)
                return

            async def render_view(view: str) -> None:
                render_id, previous = claims[view]
                try:
                    image = await self._edit(
                        try_on_view_prompt(view, paired=paired), [front, face, *garment_refs], purpose=f"try_on_{view}"
                    )
                    await self._store(user_id, outfit_id, render_id, image, previous)
                except Exception as exc:
                    await self._fail(render_id, exc, outfit_id=outfit_id)

            await asyncio.gather(*(render_view(v) for v in TRY_ON_VIEWS[1:] if v in claims))
            logger.info("try_on_render_ready", extra={"outfit_id": str(outfit_id), "views": sorted(claims)})
        except Exception as exc:
            for render_id, _ in claims.values():
                await self._fail(render_id, exc, outfit_id=outfit_id, only_unfinished=True)
        finally:
            self._in_flight.discard((outfit_id, KIND_TRY_ON))

    # Helpers

    async def _download(self, keys: list[str]) -> list[ReferenceImage]:
        results = await asyncio.gather(
            *(self._storage.download_object(key, max_bytes=MAX_UPLOAD_BYTES) for key in keys)
        )
        return [
            ReferenceImage(data, content_type if content_type.startswith("image/") else "image/jpeg")
            for data, content_type in results
        ]

    async def _edit(self, prompt: str, references: list[ReferenceImage], *, purpose: str) -> bytes:
        async with self._semaphore:
            return await self._images.edit(
                model=self._model,
                prompt=prompt,
                references=references,
                size=RENDER_SIZE,
                quality=self._quality,
                purpose=purpose,
            )

    async def _store(
        self,
        user_id: uuid.UUID,
        outfit_id: uuid.UUID,
        render_id: uuid.UUID,
        image: bytes,
        previous_key: str | None,
    ) -> None:
        key = render_object_key(user_id, outfit_id, render_id)
        await self._storage.upload_object(key, image, "image/jpeg")
        async with self._database.as_service() as connection:
            await succeed_render(connection, render_id, key, self._model)
        if previous_key and previous_key != key:
            try:
                await self._storage.remove_objects([previous_key])
            except Exception:
                logger.warning("render_cleanup_failed", extra={"render_id": str(render_id)})

    async def _fail(
        self, render_id: uuid.UUID, exc: BaseException, *, outfit_id: uuid.UUID, only_unfinished: bool = False
    ) -> None:
        code = exc.code if isinstance(exc, AIProviderError) else "render_failed"
        if not isinstance(exc, AIProviderError):
            logger.error(
                "render_failed", exc_info=exc, extra={"render_id": str(render_id), "outfit_id": str(outfit_id)}
            )
        else:
            logger.warning("render_provider_failed", extra={"render_id": str(render_id), "code": code})
        async with self._database.as_service() as connection:
            if only_unfinished:
                await connection.execute(
                    """
                    update public.outfit_renders set status = 'failed', object_key = null, error_code = $2
                     where id = $1 and status in ('pending', 'running')
                    """,
                    render_id,
                    code[:64],
                )
            else:
                await fail_render(connection, render_id, code)


async def _outfit_pieces(connection: DBConnection, user_id: uuid.UUID, outfit_id: uuid.UUID) -> list[dict[str, Any]]:
    pieces = await outfits_repo.list_outfit_garments(connection, user_id, [outfit_id])
    if not pieces:
        raise AIProviderError("outfit_has_no_pieces")
    return pieces
