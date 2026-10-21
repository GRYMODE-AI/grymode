import uuid

import pytest
from pydantic import ValidationError

from app.wardrobe_models import CreateUploadRequest, MediaType, UpdateGarmentRequest


def test_create_upload_rejects_unsupported_content_type() -> None:
    with pytest.raises(ValidationError):
        CreateUploadRequest(
            media_type=MediaType.PHOTO,
            content_type="application/pdf",
            byte_size=1000,
            client_upload_id=uuid.uuid4(),
        )


def test_create_upload_rejects_oversized_payload() -> None:
    with pytest.raises(ValidationError):
        CreateUploadRequest(
            media_type=MediaType.PHOTO,
            content_type="image/jpeg",
            byte_size=20 * 1024 * 1024,
            client_upload_id=uuid.uuid4(),
        )


def test_create_upload_accepts_jpeg() -> None:
    body = CreateUploadRequest(
        media_type=MediaType.PHOTO,
        content_type="image/jpeg",
        byte_size=2048,
        client_upload_id=uuid.uuid4(),
    )
    assert body.content_type == "image/jpeg"


def test_update_garment_forbids_unknown_fields() -> None:
    with pytest.raises(ValidationError):
        UpdateGarmentRequest.model_validate({"category": "tops", "secret": "x"})
