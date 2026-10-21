import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum
from typing import Annotated, Literal

from pydantic import Field, StringConstraints, field_validator

from app.models import StrictModel

ShortLabel = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=40)]


class MediaType(StrEnum):
    PHOTO = "photo"
    VIDEO_FRAME = "video_frame"


class MediaProcessingStatus(StrEnum):
    AWAITING_UPLOAD = "awaiting_upload"
    UPLOADED = "uploaded"
    PROCESSING = "processing"
    READY = "ready"
    FAILED = "failed"


class GarmentCategory(StrEnum):
    TOPS = "tops"
    BOTTOMS = "bottoms"
    DRESSES = "dresses"
    OUTERWEAR = "outerwear"
    SHOES = "shoes"
    BAGS = "bags"
    ACCESSORIES = "accessories"
    KNITWEAR = "knitwear"
    ACTIVEWEAR = "activewear"
    UNCATEGORISED = "uncategorised"


class Formality(StrEnum):
    CASUAL = "casual"
    SMART_CASUAL = "smartCasual"
    FORMAL = "formal"


class JobStatus(StrEnum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


ALLOWED_CONTENT_TYPES: frozenset[str] = frozenset(
    {
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/heic",
        "image/heif",
    }
)

MAX_UPLOAD_BYTES = 12 * 1024 * 1024
MAX_MEDIA_PER_USER = 80
MAX_PENDING_UPLOADS = 10
EXTENSION_FOR_CONTENT_TYPE = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/heic": "heic",
    "image/heif": "heif",
}


@dataclass(frozen=True, slots=True)
class ExtractedGarment:
    """Attributes proposed by a vision provider. Always stored unconfirmed for user review."""

    category: GarmentCategory
    subcategory: str | None = None
    primary_color: str | None = None
    secondary_colors: tuple[str, ...] = field(default_factory=tuple)
    pattern: str | None = None
    material: str | None = None
    silhouette: str | None = None
    formality: Formality | None = None
    season_tags: tuple[str, ...] = field(default_factory=tuple)
    style_tags: tuple[str, ...] = field(default_factory=tuple)
    confidence: float | None = None


class CreateUploadRequest(StrictModel):
    media_type: MediaType
    content_type: str
    byte_size: int = Field(gt=0, le=MAX_UPLOAD_BYTES)
    # Client-generated idempotency for the upload slot itself.
    client_upload_id: uuid.UUID

    @field_validator("content_type")
    @classmethod
    def _allowed_type(cls, value: str) -> str:
        normalised = value.lower().strip()
        if normalised not in ALLOWED_CONTENT_TYPES:
            raise ValueError("Unsupported media type")
        return normalised


class UploadSlotResponse(StrictModel):
    media_id: uuid.UUID
    object_key: str
    upload_url: str
    expires_in_seconds: int
    job_id: uuid.UUID | None = None


class CompleteUploadResponse(StrictModel):
    media_id: uuid.UUID
    processing_status: MediaProcessingStatus
    job_id: uuid.UUID


class WardrobeMediaResponse(StrictModel):
    id: uuid.UUID
    media_type: MediaType
    content_type: str
    processing_status: MediaProcessingStatus
    created_at: datetime


class JobResponse(StrictModel):
    id: uuid.UUID
    media_id: uuid.UUID | None
    job_type: Literal["garment_extraction"]
    status: JobStatus
    progress_stage: str | None
    error_code: str | None
    created_at: datetime
    completed_at: datetime | None


class GarmentResponse(StrictModel):
    id: uuid.UUID
    media_id: uuid.UUID | None
    category: GarmentCategory
    subcategory: str | None
    primary_color: str | None
    secondary_colors: list[str]
    pattern: str | None
    material: str | None
    silhouette: str | None
    formality: Formality | None
    season_tags: list[str]
    style_tags: list[str]
    image_url: str
    confidence: float | None
    user_confirmed: bool
    created_at: datetime
    updated_at: datetime


class UpdateGarmentRequest(StrictModel):
    category: GarmentCategory | None = None
    subcategory: ShortLabel | None = None
    primary_color: ShortLabel | None = None
    secondary_colors: list[ShortLabel] | None = Field(default=None, max_length=5)
    pattern: ShortLabel | None = None
    material: ShortLabel | None = None
    silhouette: ShortLabel | None = None
    formality: Formality | None = None
    season_tags: list[ShortLabel] | None = Field(default=None, max_length=8)
    style_tags: list[ShortLabel] | None = Field(default=None, max_length=12)


class ConfirmWardrobeRequest(StrictModel):
    garment_ids: list[uuid.UUID] | None = Field(default=None, max_length=200)


class ConfirmWardrobeResponse(StrictModel):
    confirmed_count: int


class WardrobeSummaryResponse(StrictModel):
    media: list[WardrobeMediaResponse]
    garments: list[GarmentResponse]
    jobs: list[JobResponse]
    unconfirmed_count: int
    confirmed_count: int
