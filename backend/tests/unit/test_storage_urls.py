from datetime import UTC, datetime

from app.storage import build_signed_upload_url, with_media_version


def test_build_signed_upload_url_keeps_token_already_on_path() -> None:
    path = "/object/upload/sign/wardrobe/user/media/original.jpg?token=abc.def.ghi"
    url = build_signed_upload_url("http://127.0.0.1:54321", path, "abc.def.ghi")
    assert url == (
        "http://127.0.0.1:54321/storage/v1/object/upload/sign/wardrobe/user/media/original.jpg?token=abc.def.ghi"
    )
    assert url.count("token=") == 1


def test_build_signed_upload_url_appends_token_when_missing() -> None:
    path = "/object/upload/sign/wardrobe/user/media/original.jpg"
    url = build_signed_upload_url("http://127.0.0.1:54321", path, "abc.def.ghi")
    assert url.endswith("?token=abc.def.ghi")
    assert url.count("token=") == 1


def test_build_signed_upload_url_absolute_path_without_duplicate() -> None:
    path = "http://127.0.0.1:54321/storage/v1/object/upload/sign/wardrobe/x.jpg?token=already"
    url = build_signed_upload_url("http://127.0.0.1:54321", path, "already")
    assert url == path
    assert url.count("token=") == 1


def test_with_media_version_appends_v_for_cache_bust() -> None:
    stamped = datetime(2026, 10, 13, 12, 41, 58, tzinfo=UTC)
    signed = "http://host/storage/v1/object/sign/wardrobe/u/face.jpg?token=abc"
    assert with_media_version(signed, stamped).endswith(f"&v={int(stamped.timestamp())}")
    assert with_media_version("http://host/bare.jpg", "9") == "http://host/bare.jpg?v=9"
    assert with_media_version(signed, None) == signed
