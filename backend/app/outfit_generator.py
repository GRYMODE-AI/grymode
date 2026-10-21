"""Rule-based outfit composer for Phase 4.

Builds wardrobe-grounded combinations from confirmed garments only. No external model
call and no fabricated counts — accepted outfits are whatever passes scoring + dedupe
and is persisted. ``app.ai_outfit_composer.OpenAIOutfitComposer`` replaces it when
``GRYMODE_AI_PROVIDER=openai``.
"""

from __future__ import annotations

import itertools
import logging
import uuid
from dataclasses import dataclass
from typing import Any, Protocol

from app import outfits as outfits_repo
from app.db import Database
from app.models import Occasion, PalettePreference, StyleProfile
from app.openai_client import AIProviderError
from app.outfit_models import OutfitSlot

logger = logging.getLogger("grymode.outfits")

MAX_CANDIDATES = 64
MAX_ACCEPTED = outfits_repo.MAX_ACCEPTED_OUTFITS


@dataclass(frozen=True, slots=True)
class CandidatePiece:
    garment_id: uuid.UUID
    category: str
    primary_color: str | None
    formality: str | None
    season_tags: tuple[str, ...]
    style_tags: tuple[str, ...]
    slot: OutfitSlot
    position: int


@dataclass(frozen=True, slots=True)
class OutfitCandidate:
    title: str
    signature: str
    occasion_tags: tuple[str, ...]
    style_tags: tuple[str, ...]
    contextual_tags: tuple[str, ...]
    score: float
    garments: tuple[CandidatePiece, ...]


class OutfitComposer(Protocol):
    # Part of the generation idempotency key: a different composer regenerates the same wardrobe.
    @property
    def version(self) -> str: ...

    async def generate(
        self,
        *,
        user_id: uuid.UUID,
        job_id: uuid.UUID,
        garments: list[dict[str, Any]],
        style_profile: StyleProfile,
    ) -> int: ...


def _bucket(garments: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    buckets: dict[str, list[dict[str, Any]]] = {
        "tops": [],
        "bottoms": [],
        "dresses": [],
        "shoes": [],
        "outerwear": [],
        "bags": [],
        "accessories": [],
        "knitwear": [],
        "activewear": [],
    }
    for garment in garments:
        category = garment["category"]
        if category in buckets:
            buckets[category].append(garment)
    return buckets


def _piece(garment: dict[str, Any], slot: OutfitSlot, position: int) -> CandidatePiece:
    return CandidatePiece(
        garment_id=garment["id"],
        category=garment["category"],
        primary_color=garment.get("primary_color"),
        formality=garment.get("formality"),
        season_tags=tuple(garment.get("season_tags") or ()),
        style_tags=tuple(garment.get("style_tags") or ()),
        slot=slot,
        position=position,
    )


def _signature(pieces: list[CandidatePiece]) -> str:
    return "|".join(sorted(str(p.garment_id) for p in pieces))


def _title(pieces: list[CandidatePiece], occasion: str) -> str:
    cats = [p.category for p in pieces if p.slot in (OutfitSlot.PRIMARY, OutfitSlot.BOTTOM)]
    if "dresses" in cats:
        lead = "Dress look"
    elif "knitwear" in cats:
        lead = "Knit edit"
    else:
        lead = "Wardrobe look"
    label = occasion.replace("_", " ").title()
    return f"{lead} · {label}"[:80]


def _score(
    pieces: list[CandidatePiece],
    *,
    style: StyleProfile,
    usage: dict[uuid.UUID, int],
) -> float:
    score = 0.55
    formalities = {p.formality for p in pieces if p.formality}
    if len(formalities) <= 1:
        score += 0.12
    else:
        score -= 0.08

    colors = [p.primary_color.lower() for p in pieces if p.primary_color]
    if style.palettes:
        preferred = {p.value for p in style.palettes}
        wants_neutrals = (
            PalettePreference.NEUTRALS in style.palettes or PalettePreference.BLACK_AND_WHITE in style.palettes
        )
        if wants_neutrals and any(c in {"black", "white", "cream", "beige", "grey", "gray", "navy"} for c in colors):
            score += 0.08
        if PalettePreference.EARTH_TONES in preferred and any(
            c in {"brown", "tan", "olive", "camel", "rust"} for c in colors
        ):
            score += 0.06
        if PalettePreference.COLOUR in preferred and colors:
            score += 0.04

    # Prefer more complete looks.
    slots = {p.slot for p in pieces}
    if OutfitSlot.FOOTWEAR in slots:
        score += 0.1
    if OutfitSlot.OUTERWEAR in slots:
        score += 0.04

    # Penalize overused garments so the library stays varied.
    repeats = sum(usage.get(p.garment_id, 0) for p in pieces)
    score -= min(0.25, repeats * 0.05)

    return max(0.0, min(1.0, score))


def _occasion_tags(style: StyleProfile, pieces: list[CandidatePiece]) -> tuple[str, ...]:
    if style.occasions:
        mapping = {
            Occasion.WORK: "Work",
            Occasion.WEEKEND: "Weekend",
            Occasion.EVENINGS_OUT: "Evening",
            Occasion.TRAVEL: "Travel",
            Occasion.SPECIAL_OCCASIONS: "Celebration",
        }
        return tuple(mapping[o] for o in style.occasions[:3])
    formalities = {p.formality for p in pieces if p.formality}
    if "formal" in formalities:
        return ("Dinner",)
    if "smartCasual" in formalities:
        return ("Smart casual",)
    return ("Casual",)


def _style_tags(style: StyleProfile) -> tuple[str, ...]:
    tags: list[str] = []
    for pole in style.axes.values():
        tags.append(pole.value)
    if not tags:
        tags.append("Classic")
    return tuple(dict.fromkeys(tags))[:4]


def compose_candidates(
    garments: list[dict[str, Any]], style: StyleProfile, *, max_candidates: int = MAX_CANDIDATES
) -> list[OutfitCandidate]:
    buckets = _bucket(garments)
    tops = buckets["tops"] + buckets["knitwear"] + buckets["activewear"]
    bottoms = buckets["bottoms"]
    dresses = buckets["dresses"]
    shoes = buckets["shoes"]
    outer = buckets["outerwear"]

    raw: list[list[CandidatePiece]] = []

    shoe_options: list[dict[str, Any] | None] = list(shoes) if shoes else [None]
    for dress, shoe in itertools.product(dresses, shoe_options):
        pieces = [_piece(dress, OutfitSlot.PRIMARY, 0)]
        if shoe is not None:
            pieces.append(_piece(shoe, OutfitSlot.FOOTWEAR, 1))
        raw.append(pieces)

    for top, bottom in itertools.product(tops, bottoms):
        if top["id"] == bottom["id"]:
            continue
        base = [
            _piece(top, OutfitSlot.PRIMARY, 0),
            _piece(bottom, OutfitSlot.BOTTOM, 1),
        ]
        if shoes:
            for shoe in shoes:
                look = [*base, _piece(shoe, OutfitSlot.FOOTWEAR, 2)]
                raw.append(look)
                if outer:
                    for coat in outer[:2]:
                        raw.append([*look, _piece(coat, OutfitSlot.OUTERWEAR, 3)])
        else:
            raw.append(base)

    # Cap early before scoring.
    raw = raw[: max_candidates * 2]

    usage: dict[uuid.UUID, int] = {}
    accepted: list[OutfitCandidate] = []
    seen: set[str] = set()

    scored: list[tuple[float, list[CandidatePiece]]] = []
    for pieces in raw:
        sig = _signature(pieces)
        if sig in seen:
            continue
        seen.add(sig)
        provisional = _score(pieces, style=style, usage=usage)
        scored.append((provisional, pieces))

    scored.sort(key=lambda item: item[0], reverse=True)

    for _, pieces in scored:
        if len(accepted) >= max_candidates:
            break
        occasions = _occasion_tags(style, pieces)
        score = _score(pieces, style=style, usage=usage)
        if score < 0.35:
            continue
        candidate = OutfitCandidate(
            title=_title(pieces, occasions[0] if occasions else "Everyday"),
            signature=_signature(pieces),
            occasion_tags=occasions,
            style_tags=_style_tags(style),
            contextual_tags=("Daytime",),
            score=score,
            garments=tuple(pieces),
        )
        accepted.append(candidate)
        for piece in pieces:
            usage[piece.garment_id] = usage.get(piece.garment_id, 0) + 1

    accepted.sort(key=lambda c: c.score, reverse=True)
    return accepted[:MAX_ACCEPTED]


class LocalOutfitGenerator:
    """Composes and persists an initial outfit batch from confirmed wardrobe pieces."""

    version = "local-v1"

    def __init__(self, database: Database) -> None:
        self._database = database

    async def generate(
        self,
        *,
        user_id: uuid.UUID,
        job_id: uuid.UUID,
        garments: list[dict[str, Any]],
        style_profile: StyleProfile,
    ) -> int:
        candidates = compose_candidates(garments, style_profile)
        payload = [
            {
                "title": c.title,
                "signature": c.signature,
                "occasion_tags": list(c.occasion_tags),
                "style_tags": list(c.style_tags),
                "contextual_tags": list(c.contextual_tags),
                "score": c.score,
                "garments": [
                    {
                        "garment_id": p.garment_id,
                        "slot": p.slot.value,
                        "position": p.position,
                    }
                    for p in c.garments
                ],
            }
            for c in candidates
        ]
        async with self._database.as_service() as connection:
            await outfits_repo.mark_outfit_job_progress(connection, job_id, "persisting")
            accepted = await outfits_repo.replace_outfits_for_job(
                connection, user_id=user_id, job_id=job_id, outfits=payload
            )
            await outfits_repo.succeed_outfit_job(connection, job_id)
        logger.info(
            "outfit_generation_ready",
            extra={"job_id": str(job_id), "accepted_count": accepted, "user_id": str(user_id)},
        )
        return accepted


async def run_outfit_generation_job(
    *,
    database: Database,
    composer: OutfitComposer,
    user_id: uuid.UUID,
    job_id: uuid.UUID,
    style_profile: StyleProfile,
) -> None:
    try:
        async with database.as_service() as connection:
            claimed = await outfits_repo.claim_outfit_job(connection, job_id, user_id)
            if claimed is None:
                return
            garments = await outfits_repo.list_confirmed_garments(connection, user_id)
        if len(garments) < outfits_repo.MIN_CONFIRMED_GARMENTS:
            async with database.as_service() as connection:
                await outfits_repo.fail_outfit_job(connection, job_id, "insufficient_wardrobe")
            return
        await composer.generate(user_id=user_id, job_id=job_id, garments=garments, style_profile=style_profile)
    except AIProviderError as exc:
        logger.warning("outfit_generation_provider_failed", extra={"job_id": str(job_id), "code": exc.code})
        async with database.as_service() as connection:
            await outfits_repo.fail_outfit_job(connection, job_id, exc.code)
    except Exception:
        logger.exception("outfit_generation_failed", extra={"job_id": str(job_id)})
        async with database.as_service() as connection:
            await outfits_repo.fail_outfit_job(connection, job_id, "generation_failed")
