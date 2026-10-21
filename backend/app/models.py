import uuid
from datetime import datetime
from enum import StrEnum
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

# These enums mirror ios/Grymode/Domain/StyleProfile.swift. Values are the Swift raw values.


class StyleAxis(StrEnum):
    SILHOUETTE = "silhouette"
    CHARACTER = "character"
    FINISH = "finish"


class StylePole(StrEnum):
    FIRST = "first"
    SECOND = "second"


class Occasion(StrEnum):
    WORK = "work"
    WEEKEND = "weekend"
    EVENINGS_OUT = "eveningsOut"
    TRAVEL = "travel"
    SPECIAL_OCCASIONS = "specialOccasions"


class PalettePreference(StrEnum):
    NEUTRALS = "neutrals"
    EARTH_TONES = "earthTones"
    BLACK_AND_WHITE = "blackAndWhite"
    COLOUR = "colour"


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class StyleProfile(StrictModel):
    axes: dict[StyleAxis, StylePole] = Field(default_factory=dict)
    occasions: list[Occasion] = Field(default_factory=list, max_length=len(Occasion))
    palettes: list[PalettePreference] = Field(default_factory=list, max_length=len(PalettePreference))

    @field_validator("occasions", "palettes")
    @classmethod
    def _unique_in_canonical_order(cls, values: list[StrEnum]) -> list[StrEnum]:
        if not values:
            return values
        members = list(type(values[0]))
        return sorted(set(values), key=members.index)


DisplayName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]


class UpdateProfileRequest(StrictModel):
    display_name: DisplayName | None


class UpdateStyleProfileRequest(StrictModel):
    style_profile: StyleProfile
    onboarding_completed: bool = False


class ProfileResponse(StrictModel):
    id: uuid.UUID
    email: str | None
    display_name: str | None
    style_profile: StyleProfile
    onboarding_completed_at: datetime | None
    created_at: datetime
    updated_at: datetime


class AccountDeletionResponse(StrictModel):
    status: Literal["completed"]
    request_id: uuid.UUID
    subscription_notice: str


class HealthResponse(StrictModel):
    status: Literal["ok"]
    environment: str
    version: str
