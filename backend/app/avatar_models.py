"""Request/response models for personal avatar try-on profiles."""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from typing import Literal

from pydantic import Field

from app.models import StrictModel


class BodyBuild(StrEnum):
    SLIM = "slim"
    REGULAR = "regular"
    ATHLETIC = "athletic"
    BROAD = "broad"


class AvatarProfileResponse(StrictModel):
    height_cm: int = Field(ge=120, le=230)
    body_build: BodyBuild
    has_face: bool
    face_url: str | None = None
    updated_at: datetime | None = None


class UpsertAvatarProfileRequest(StrictModel):
    height_cm: int = Field(ge=120, le=230)
    body_build: BodyBuild


class AvatarFaceUploadResponse(StrictModel):
    object_key: str
    upload_url: str
    expires_in_seconds: int


TryOnView = Literal["front", "three_quarter", "side", "back"]
TryOnStatus = Literal["unavailable", "idle", "rendering", "ready", "partial", "failed"]


class TryOnViewResponse(StrictModel):
    view: TryOnView
    status: Literal["pending", "running", "succeeded", "failed"]
    image_url: str | None = None
    error_code: str | None = None


class TryOnSessionResponse(StrictModel):
    """Personal try-on for an unlocked look.

    ``ai_multi_view``: AI renders of the user wearing the look from four angles (``views``).
    ``personal_2d``: face + garment composition when AI rendering is not configured.
    """

    look_id: str
    title: str
    height_cm: int
    body_build: BodyBuild
    face_url: str | None
    garment_image_urls: list[str]
    preview_mode: Literal["personal_2d", "ai_multi_view"] = "personal_2d"
    status: TryOnStatus = "unavailable"
    views: list[TryOnViewResponse] = Field(default_factory=list)
    notice: str = "Personal fit preview from your face photo and measurements."
