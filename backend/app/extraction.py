"""Garment extraction adapters.

``LocalDraftExtractor`` turns each uploaded photo into one unlabelled draft (no external call).
``OpenAIGarmentExtractor`` sends the photo to a vision model and stores every proposed garment
unconfirmed, so the user always reviews and confirms before outfit generation uses it. If the
provider fails, the upload still becomes an unlabelled draft rather than a fabricated label.
"""

from __future__ import annotations

import logging
import uuid
from typing import Any, Protocol

from app import wardrobe
from app.db import Database
from app.openai_client import AIProviderError, OpenAIResponsesClient, image_data_url
from app.storage import StorageClient
from app.wardrobe_models import MAX_UPLOAD_BYTES, ExtractedGarment, Formality, GarmentCategory

logger = logging.getLogger("grymode.extraction")

VISION_CONTENT_TYPES = frozenset({"image/jpeg", "image/png", "image/webp", "image/gif"})
SEASONS = ("spring", "summer", "autumn", "winter")
LABEL_MAX = 40


class GarmentExtractor(Protocol):
    async def extract(self, *, user_id: uuid.UUID, media_id: uuid.UUID, object_key: str) -> None: ...


async def _claim_extraction_job(database: Database, user_id: uuid.UUID, media_id: uuid.UUID) -> uuid.UUID | None:
    async with database.as_service() as connection:
        job = await connection.fetchrow(
            """
            select id from public.generation_jobs
             where media_id = $1 and user_id = $2 and job_type = 'garment_extraction'
             order by created_at desc limit 1
            """,
            media_id,
            user_id,
        )
        if job is None:
            return None
        claimed = await wardrobe.claim_job(connection, job["id"], user_id)
        if claimed is None:
            return None
        await wardrobe.mark_media_processing(connection, media_id)
        job_id: uuid.UUID = job["id"]
        return job_id


class LocalDraftExtractor:
    """Creates one reviewable garment per upload. No external AI call."""

    def __init__(self, database: Database) -> None:
        self._database = database

    async def extract(self, *, user_id: uuid.UUID, media_id: uuid.UUID, object_key: str) -> None:
        job_id = await _claim_extraction_job(self._database, user_id, media_id)
        if job_id is None:
            return
        async with self._database.as_service() as connection:
            await wardrobe.complete_extraction(
                connection, user_id=user_id, media_id=media_id, job_id=job_id, object_key=object_key
            )
        logger.info("extraction_ready_for_review", extra={"job_id": str(job_id), "media_id": str(media_id)})


EXTRACTION_INSTRUCTIONS = """\
You catalogue clothing for a private personal wardrobe app.

Look at the photo and list each distinct wearable item that is a clear subject of the photo
(garments, shoes, bags, accessories). Ignore background objects, furniture, hangers, and
partially visible items at the edges. Never describe or identify the person wearing the clothes.

Rules:
- Return at most {max_items} items, most prominent first. If the photo shows no wearable item, return an empty list.
- category must be one of the allowed values. Use "knitwear" for sweaters/cardigans, "outerwear"
  for coats/jackets/blazers, "activewear" for sportswear.
- subcategory: a short lowercase noun phrase of 1-3 words (e.g. "oxford shirt", "wide-leg trousers", "loafers").
- primary_color and secondary_colors: plain lowercase colour names (e.g. "navy", "cream", "olive", "black").
- pattern, material, silhouette: short lowercase words, or null when you cannot tell from the photo.
  Do not guess a material you cannot see.
- formality: casual, smartCasual, or formal.
- season_tags: the seasons the item suits.
- style_tags: up to 4 short lowercase style descriptors (e.g. "minimal", "tailored", "relaxed").
- confidence: 0 to 1 for how sure you are of the category and colour.
"""


def extraction_schema() -> dict[str, Any]:
    nullable_label = {"type": ["string", "null"]}
    item = {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "category",
            "subcategory",
            "primary_color",
            "secondary_colors",
            "pattern",
            "material",
            "silhouette",
            "formality",
            "season_tags",
            "style_tags",
            "confidence",
        ],
        "properties": {
            "category": {
                "type": "string",
                "enum": [c.value for c in GarmentCategory if c is not GarmentCategory.UNCATEGORISED],
            },
            "subcategory": {"type": "string"},
            "primary_color": {"type": "string"},
            "secondary_colors": {"type": "array", "items": {"type": "string"}},
            "pattern": nullable_label,
            "material": nullable_label,
            "silhouette": nullable_label,
            "formality": {"type": "string", "enum": [f.value for f in Formality]},
            "season_tags": {"type": "array", "items": {"type": "string", "enum": list(SEASONS)}},
            "style_tags": {"type": "array", "items": {"type": "string"}},
            "confidence": {"type": "number"},
        },
    }
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["garments"],
        "properties": {"garments": {"type": "array", "items": item}},
    }


def _label(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    cleaned = " ".join(value.strip().split())[:LABEL_MAX].strip()
    return cleaned or None


def _labels(values: Any, *, limit: int) -> tuple[str, ...]:
    if not isinstance(values, list):
        return ()
    out: list[str] = []
    for value in values:
        label = _label(value)
        if label and label.lower() not in {existing.lower() for existing in out}:
            out.append(label.lower())
        if len(out) >= limit:
            break
    return tuple(out)


def parse_extraction(payload: dict[str, Any], *, max_items: int) -> list[ExtractedGarment]:
    """Validates provider output into garments. Invalid items are dropped, never repaired by guessing."""
    raw_items = payload.get("garments")
    if not isinstance(raw_items, list):
        raise AIProviderError("ai_schema_mismatch")
    garments: list[ExtractedGarment] = []
    for raw in raw_items[:max_items]:
        if not isinstance(raw, dict):
            continue
        try:
            category = GarmentCategory(str(raw.get("category")))
        except ValueError:
            continue
        if category is GarmentCategory.UNCATEGORISED:
            continue
        formality: Formality | None
        try:
            formality = Formality(str(raw.get("formality")))
        except ValueError:
            formality = None
        confidence_raw = raw.get("confidence")
        confidence = (
            max(0.0, min(1.0, float(confidence_raw)))
            if isinstance(confidence_raw, int | float) and not isinstance(confidence_raw, bool)
            else None
        )
        primary = _label(raw.get("primary_color"))
        garments.append(
            ExtractedGarment(
                category=category,
                subcategory=(_label(raw.get("subcategory")) or "").lower() or None,
                primary_color=primary.lower() if primary else None,
                secondary_colors=tuple(
                    c for c in _labels(raw.get("secondary_colors"), limit=5) if c != (primary or "").lower()
                ),
                pattern=(_label(raw.get("pattern")) or "").lower() or None,
                material=(_label(raw.get("material")) or "").lower() or None,
                silhouette=(_label(raw.get("silhouette")) or "").lower() or None,
                formality=formality,
                season_tags=tuple(s for s in _labels(raw.get("season_tags"), limit=4) if s in SEASONS),
                style_tags=_labels(raw.get("style_tags"), limit=4),
                confidence=confidence,
            )
        )
    return garments


class OpenAIGarmentExtractor:
    """Proposes garment labels from the uploaded photo with an OpenAI vision model."""

    def __init__(
        self,
        *,
        database: Database,
        storage: StorageClient,
        client: OpenAIResponsesClient,
        model: str,
        max_items: int,
    ) -> None:
        self._database = database
        self._storage = storage
        self._client = client
        self._model = model
        self._max_items = max_items

    async def extract(self, *, user_id: uuid.UUID, media_id: uuid.UUID, object_key: str) -> None:
        job_id = await _claim_extraction_job(self._database, user_id, media_id)
        if job_id is None:
            return

        garments: list[ExtractedGarment] = []
        note_code: str | None = None
        try:
            data, content_type = await self._storage.download_object(object_key, max_bytes=MAX_UPLOAD_BYTES)
            if content_type not in VISION_CONTENT_TYPES:
                note_code = "unsupported_image_format"
            else:
                payload = await self._client.structured(
                    model=self._model,
                    instructions=EXTRACTION_INSTRUCTIONS.format(max_items=self._max_items),
                    content=[
                        {"type": "input_text", "text": "Catalogue the wearable items in this photo."},
                        {"type": "input_image", "image_url": image_data_url(data, content_type), "detail": "auto"},
                    ],
                    schema_name="wardrobe_extraction",
                    schema=extraction_schema(),
                    purpose="garment_extraction",
                )
                garments = parse_extraction(payload, max_items=self._max_items)
                if not garments:
                    note_code = "no_garment_detected"
        except AIProviderError as exc:
            note_code = exc.code
            logger.warning("extraction_provider_failed", extra={"media_id": str(media_id), "code": exc.code})

        async with self._database.as_service() as connection:
            await wardrobe.complete_extraction(
                connection,
                user_id=user_id,
                media_id=media_id,
                job_id=job_id,
                object_key=object_key,
                garments=garments,
                note_code=note_code,
            )
        logger.info(
            "extraction_ready_for_review",
            extra={
                "job_id": str(job_id),
                "media_id": str(media_id),
                "garment_count": len(garments),
                "note_code": note_code,
            },
        )


async def run_extraction_job(
    *,
    database: Database,
    extractor: GarmentExtractor,
    user_id: uuid.UUID,
    media_id: uuid.UUID,
    object_key: str,
) -> None:
    try:
        await extractor.extract(user_id=user_id, media_id=media_id, object_key=object_key)
    except Exception:
        logger.exception("extraction_failed", extra={"media_id": str(media_id)})
        async with database.as_service() as connection:
            job = await connection.fetchrow(
                """
                select id from public.generation_jobs
                 where media_id = $1 and user_id = $2
                 order by created_at desc limit 1
                """,
                media_id,
                user_id,
            )
            if job is not None:
                await wardrobe.fail_job(connection, job_id=job["id"], media_id=media_id, error_code="extraction_failed")
