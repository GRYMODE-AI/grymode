"""Request/response models for the outfit library and generation jobs."""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Literal

from pydantic import Field

from app.models import StrictModel
from app.wardrobe_models import GarmentCategory, JobStatus


class OutfitSlot(StrEnum):
    PRIMARY = "primary"
    BOTTOM = "bottom"
    FOOTWEAR = "footwear"
    OUTERWEAR = "outerwear"
    BAG = "bag"
    ACCESSORY = "accessory"


class OutfitGarmentRef(StrictModel):
    garment_id: uuid.UUID
    category: GarmentCategory
    slot: OutfitSlot
    position: int
    image_url: str
    primary_color: str | None = None
    subcategory: str | None = None
    material: str | None = None


RenderStatus = Literal["pending", "running", "succeeded", "failed"]


class OutfitVisualResponse(StrictModel):
    """AI-styled image of the whole look. ``image_url`` is set only when ``status`` is succeeded."""

    status: RenderStatus
    image_url: str | None = None
    error_code: str | None = None


class OutfitResponse(StrictModel):
    id: uuid.UUID
    title: str
    occasion_tags: list[str]
    style_tags: list[str]
    contextual_tags: list[str]
    score: float | None
    is_free_reveal: bool
    is_locked: bool
    is_saved: bool = False
    piece_count: int = Field(ge=0)
    garments: list[OutfitGarmentRef]
    visual: OutfitVisualResponse | None = None
    created_at: datetime


class OutfitJobResponse(StrictModel):
    id: uuid.UUID
    job_type: Literal["outfit_generation"] = "outfit_generation"
    status: JobStatus
    progress_stage: str | None
    error_code: str | None
    accepted_count: int
    created_at: datetime
    completed_at: datetime | None


class StartOutfitGenerationResponse(StrictModel):
    job: OutfitJobResponse
    reused_existing: bool = False


class EntitlementResponse(StrictModel):
    plan: Literal["free", "premium"]
    can_open_full_library: bool


class OutfitLibraryResponse(StrictModel):
    accepted_count: int = Field(ge=0)
    locked_count: int = Field(ge=0)
    saved_count: int = Field(ge=0)
    entitlement: EntitlementResponse
    filter_occasions: list[str] = Field(default_factory=list)
    outfits: list[OutfitResponse]
    active_job: OutfitJobResponse | None = None


class HomeResponse(StrictModel):
    greeting_hint: str | None = None
    todays_look: OutfitResponse | None
    accepted_count: int = Field(ge=0)
    saved_count: int = Field(ge=0)
    locked_count: int = Field(ge=0)
    entitlement: EntitlementResponse
    wardrobe_confirmed_count: int = Field(ge=0)
