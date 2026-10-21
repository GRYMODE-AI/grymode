"""OpenAI-backed outfit composer.

The model sees only the user's confirmed garments (by short reference, never database IDs or
images) and their style profile. Every proposed outfit is validated server-side: references must
resolve to confirmed garments, slots are derived from each garment's category, structurally
incomplete looks are rejected, and duplicates are removed. Nothing is persisted that the
validator did not accept.
"""

from __future__ import annotations

import hashlib
import json
import logging
import uuid
from collections import Counter
from typing import Any

from app import outfits as outfits_repo
from app.db import Database
from app.models import Occasion, PalettePreference, StyleAxis, StylePole, StyleProfile
from app.openai_client import AIProviderError, OpenAIResponsesClient
from app.outfit_models import OutfitSlot

logger = logging.getLogger("grymode.outfits")

OCCASION_TAGS = ("Work", "Weekend", "Evening", "Travel", "Celebration", "Casual", "Smart casual", "Dinner")
CONTEXT_TAGS = ("Daytime", "Evening", "Warm weather", "Cold weather", "Layered")
SLOT_ORDER = (
    OutfitSlot.PRIMARY,
    OutfitSlot.BOTTOM,
    OutfitSlot.FOOTWEAR,
    OutfitSlot.OUTERWEAR,
    OutfitSlot.BAG,
    OutfitSlot.ACCESSORY,
)
MAX_ACCESSORIES = 2
TITLE_MAX = 60

_AXIS_LABELS = {
    (StyleAxis.SILHOUETTE, StylePole.FIRST): "Relaxed",
    (StyleAxis.SILHOUETTE, StylePole.SECOND): "Structured",
    (StyleAxis.CHARACTER, StylePole.FIRST): "Classic",
    (StyleAxis.CHARACTER, StylePole.SECOND): "Contemporary",
    (StyleAxis.FINISH, StylePole.FIRST): "Effortless",
    (StyleAxis.FINISH, StylePole.SECOND): "Refined",
}
_OCCASION_LABELS = {
    Occasion.WORK: "Work",
    Occasion.WEEKEND: "Weekend",
    Occasion.EVENINGS_OUT: "Evenings out",
    Occasion.TRAVEL: "Travel",
    Occasion.SPECIAL_OCCASIONS: "Special occasions",
}
_PALETTE_LABELS = {
    PalettePreference.NEUTRALS: "Neutrals",
    PalettePreference.EARTH_TONES: "Earth tones",
    PalettePreference.BLACK_AND_WHITE: "Black and white",
    PalettePreference.COLOUR: "Colour",
}

COMPOSER_INSTRUCTIONS = """\
You are Grymode, a precise personal stylist. Build complete outfits using ONLY the garments listed
in the user's wardrobe, referenced by their "ref" values. Never invent garments.

Each outfit must be wearable as a whole look:
- exactly one main piece: a dress, OR a top (tops, knitwear, or activewear) worn with exactly one bottom;
- a knit layered over a top is allowed when it suits the look;
- at most one pair of shoes, one outer layer, one bag, and two accessories;
- include shoes whenever the wardrobe has suitable shoes.

Respect the user's style direction, occasions, and palette preferences. Favour colour harmony,
consistent formality, and seasonal sense. Vary the looks: avoid repeating the same pair of pieces
across many outfits when alternatives exist.

Return up to {max_outfits} distinct outfits, best first. If the wardrobe cannot form any complete
outfit, return an empty list. Titles are short and evocative (2-5 words, no emoji, no garment refs).
score is 0-1 for how strongly the outfit fits the user's style and occasions.
"""


def composer_schema() -> dict[str, Any]:
    outfit = {
        "type": "object",
        "additionalProperties": False,
        "required": ["title", "piece_refs", "occasion_tags", "context_tags", "style_tags", "score"],
        "properties": {
            "title": {"type": "string"},
            "piece_refs": {"type": "array", "items": {"type": "string"}},
            "occasion_tags": {"type": "array", "items": {"type": "string", "enum": list(OCCASION_TAGS)}},
            "context_tags": {"type": "array", "items": {"type": "string", "enum": list(CONTEXT_TAGS)}},
            "style_tags": {"type": "array", "items": {"type": "string"}},
            "score": {"type": "number"},
        },
    }
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["outfits"],
        "properties": {"outfits": {"type": "array", "items": outfit}},
    }


def style_brief(style: StyleProfile) -> dict[str, Any]:
    return {
        "style_direction": [_AXIS_LABELS[(axis, pole)] for axis, pole in style.axes.items()],
        "occasions": [_OCCASION_LABELS[o] for o in style.occasions],
        "palettes": [_PALETTE_LABELS[p] for p in style.palettes],
    }


def wardrobe_brief(garments: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    """Returns the model-facing garment list and a ref → garment row map."""
    by_ref: dict[str, dict[str, Any]] = {}
    brief: list[dict[str, Any]] = []
    for index, garment in enumerate(garments, start=1):
        ref = f"g{index}"
        by_ref[ref] = garment
        entry: dict[str, Any] = {"ref": ref, "category": garment["category"]}
        for key in ("subcategory", "primary_color", "pattern", "material", "silhouette", "formality"):
            if garment.get(key):
                entry[key] = garment[key]
        for key in ("secondary_colors", "season_tags", "style_tags"):
            values = list(garment.get(key) or [])
            if values:
                entry[key] = values
        brief.append(entry)
    return brief, by_ref


def _assign_slots(pieces: list[dict[str, Any]]) -> list[tuple[dict[str, Any], OutfitSlot]] | None:
    """Maps categories to slots and enforces a complete, non-conflicting look. None = reject."""
    categories = Counter(p["category"] for p in pieces)
    dresses = categories["dresses"]
    tops = categories["tops"] + categories["activewear"]
    knits = categories["knitwear"]
    bottoms = categories["bottoms"]

    if categories["uncategorised"]:
        return None
    if dresses > 1 or bottoms > 1 or tops > 1 or knits > 1:
        return None
    if dresses == 1 and (tops or bottoms):
        return None
    if dresses == 0 and (tops + knits == 0 or bottoms != 1):
        return None
    if categories["shoes"] > 1 or categories["outerwear"] > 1 or categories["bags"] > 1:
        return None
    if categories["accessories"] > MAX_ACCESSORIES:
        return None
    # A knit over a top takes the outer-layer slot, so it cannot also carry a coat.
    if knits and tops and categories["outerwear"]:
        return None

    assigned: list[tuple[dict[str, Any], OutfitSlot]] = []
    for piece in pieces:
        category = piece["category"]
        slot: OutfitSlot
        if category in ("dresses", "tops", "activewear"):
            slot = OutfitSlot.PRIMARY
        elif category == "knitwear":
            slot = OutfitSlot.OUTERWEAR if tops else OutfitSlot.PRIMARY
        elif category == "bottoms":
            slot = OutfitSlot.BOTTOM
        elif category == "shoes":
            slot = OutfitSlot.FOOTWEAR
        elif category == "outerwear":
            slot = OutfitSlot.OUTERWEAR
        elif category == "bags":
            slot = OutfitSlot.BAG
        elif category == "accessories":
            slot = OutfitSlot.ACCESSORY
        else:
            return None
        assigned.append((piece, slot))
    assigned.sort(key=lambda item: SLOT_ORDER.index(item[1]))
    return assigned


def _clean_tags(values: Any, allowed: tuple[str, ...] | None, *, limit: int) -> list[str]:
    if not isinstance(values, list):
        return []
    out: list[str] = []
    for value in values:
        if not isinstance(value, str):
            continue
        tag = " ".join(value.strip().split())[:30]
        if not tag or (allowed is not None and tag not in allowed):
            continue
        if allowed is None:
            tag = tag[:1].upper() + tag[1:]
        if tag not in out:
            out.append(tag)
        if len(out) >= limit:
            break
    return out


def validate_outfits(
    payload: dict[str, Any], by_ref: dict[str, dict[str, Any]], *, max_outfits: int
) -> list[dict[str, Any]]:
    raw_outfits = payload.get("outfits")
    if not isinstance(raw_outfits, list):
        raise AIProviderError("ai_schema_mismatch")

    accepted: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in raw_outfits:
        if not isinstance(raw, dict):
            continue
        refs = raw.get("piece_refs")
        if not isinstance(refs, list) or not refs:
            continue
        unique_refs = list(dict.fromkeys(r for r in refs if isinstance(r, str)))
        if len(unique_refs) != len(refs) or any(r not in by_ref for r in unique_refs):
            continue
        pieces = [by_ref[r] for r in unique_refs]
        assigned = _assign_slots(pieces)
        if assigned is None:
            continue
        signature = "|".join(sorted(str(p["id"]) for p, _ in assigned))
        if len(signature) > 200:
            signature = "sha256:" + hashlib.sha256(signature.encode()).hexdigest()
        if signature in seen:
            continue
        seen.add(signature)

        title_raw = raw.get("title")
        title = " ".join(title_raw.split())[:TITLE_MAX].strip() if isinstance(title_raw, str) else ""
        score_raw = raw.get("score")
        score = (
            max(0.0, min(1.0, float(score_raw)))
            if isinstance(score_raw, int | float) and not isinstance(score_raw, bool)
            else 0.5
        )
        occasion_tags = _clean_tags(raw.get("occasion_tags"), OCCASION_TAGS, limit=3) or ["Casual"]
        accepted.append(
            {
                "title": title or "Wardrobe look",
                "signature": signature,
                "occasion_tags": occasion_tags,
                "style_tags": _clean_tags(raw.get("style_tags"), None, limit=4),
                "contextual_tags": _clean_tags(raw.get("context_tags"), CONTEXT_TAGS, limit=3),
                "score": score,
                "garments": [
                    {"garment_id": piece["id"], "slot": slot.value, "position": position}
                    for position, (piece, slot) in enumerate(assigned)
                ],
            }
        )

    accepted.sort(key=lambda o: o["score"], reverse=True)
    return accepted[:max_outfits]


class OpenAIOutfitComposer:
    """Composes outfits with an OpenAI model and persists only validator-accepted looks."""

    def __init__(self, *, database: Database, client: OpenAIResponsesClient, model: str) -> None:
        self._database = database
        self._client = client
        self._model = model

    @property
    def version(self) -> str:
        return f"openai-v1:{self._model}"

    async def generate(
        self,
        *,
        user_id: uuid.UUID,
        job_id: uuid.UUID,
        garments: list[dict[str, Any]],
        style_profile: StyleProfile,
    ) -> int:
        brief, by_ref = wardrobe_brief(garments)
        max_outfits = outfits_repo.MAX_ACCEPTED_OUTFITS
        request = {"style_profile": style_brief(style_profile), "wardrobe": brief}
        payload = await self._client.structured(
            model=self._model,
            instructions=COMPOSER_INSTRUCTIONS.format(max_outfits=max_outfits),
            content=[{"type": "input_text", "text": json.dumps(request, ensure_ascii=False)}],
            schema_name="outfit_batch",
            schema=composer_schema(),
            purpose="outfit_generation",
        )
        proposed = payload.get("outfits")
        accepted = validate_outfits(payload, by_ref, max_outfits=max_outfits)
        logger.info(
            "outfit_validation",
            extra={
                "job_id": str(job_id),
                "proposed_count": len(proposed) if isinstance(proposed, list) else 0,
                "accepted_count": len(accepted),
            },
        )
        if not accepted:
            raise AIProviderError("no_valid_outfits")

        async with self._database.as_service() as connection:
            await outfits_repo.mark_outfit_job_progress(connection, job_id, "persisting")
            count = await outfits_repo.replace_outfits_for_job(
                connection, user_id=user_id, job_id=job_id, outfits=accepted
            )
            await outfits_repo.succeed_outfit_job(connection, job_id)
        logger.info(
            "outfit_generation_ready",
            extra={"job_id": str(job_id), "accepted_count": count, "user_id": str(user_id)},
        )
        return count
