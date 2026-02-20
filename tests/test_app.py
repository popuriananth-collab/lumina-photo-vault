"""
tests/test_app.py — Basic tests for Lumina Photo Vault

Run with:  pytest tests/ -v --cov=app
"""
import io
from unittest.mock import MagicMock, patch

import pytest

from app import app as flask_app


@pytest.fixture
def client():
    flask_app.config["TESTING"] = True
    flask_app.config["WTF_CSRF_ENABLED"] = False
    with flask_app.test_client() as client:
        yield client


# ── Helper to mock S3 responses ───────────────────────────────
def mock_s3_list(objects):
    """Return a mock s3 client whose list_objects_v2 returns given objects."""
    mock = MagicMock()
    mock.list_objects_v2.return_value = {
        "Contents": objects,
        "IsTruncated": False,
    }
    return mock


def make_obj(key, size=1024):
    from datetime import datetime
    return {
        "Key": key,
        "Size": size,
        "LastModified": datetime(2024, 8, 14, 12, 0, 0),
    }


# ── Index / albums page ───────────────────────────────────────
class TestIndex:
    def test_index_returns_200(self, client):
        with patch("app.list_all_objects", return_value=[]):
            resp = client.get("/")
        assert resp.status_code == 200

    def test_index_shows_albums(self, client):
        objects = [
            make_obj("vacation-2024/beach.jpg"),
            make_obj("vacation-2024/sunset.jpg"),
            make_obj("family/christmas.jpg"),
        ]
        with patch("app.list_all_objects", return_value=objects):
            resp = client.get("/")
        assert b"vacation-2024" in resp.data
        assert b"family" in resp.data

    def test_index_groups_uncategorized(self, client):
        objects = [make_obj("random-photo.jpg")]
        with patch("app.list_all_objects", return_value=objects):
            resp = client.get("/")
        assert b"Uncategorized" in resp.data


# ── Album detail page ─────────────────────────────────────────
class TestAlbum:
    def test_album_returns_200(self, client):
        objects = [make_obj("vacation-2024/beach.jpg")]
        with patch("app.list_all_objects", return_value=objects):
            resp = client.get("/album/vacation-2024")
        assert resp.status_code == 200

    def test_album_shows_photos(self, client):
        objects = [
            make_obj("vacation-2024/beach.jpg"),
            make_obj("vacation-2024/sunset.jpg"),
        ]
        with patch("app.list_all_objects", return_value=objects):
            resp = client.get("/album/vacation-2024")
        assert b"beach.jpg" in resp.data
        assert b"sunset.jpg" in resp.data

    def test_uncategorized_album(self, client):
        objects = [make_obj("stray-photo.jpg")]
        with patch("app.list_all_objects", return_value=objects):
            resp = client.get("/album/__uncategorized__")
        assert resp.status_code == 200
        assert b"stray-photo.jpg" in resp.data


# ── Upload ────────────────────────────────────────────────────
class TestUpload:
    def test_upload_to_album_redirects(self, client):
        mock_s3 = MagicMock()
        with patch("app.get_s3", return_value=mock_s3):
            data = {"files": (io.BytesIO(b"fake image data"), "test.jpg")}
            resp = client.post(
                "/upload/vacation-2024",
                data=data,
                content_type="multipart/form-data",
                follow_redirects=False,
            )
        assert resp.status_code == 302

    def test_upload_uses_album_prefix(self, client):
        mock_s3 = MagicMock()
        with patch("app.get_s3", return_value=mock_s3):
            data = {"files": (io.BytesIO(b"fake image data"), "beach.jpg")}
            client.post(
                "/upload/vacation-2024",
                data=data,
                content_type="multipart/form-data",
            )
        # Check the S3 key includes the album prefix
        call_args = mock_s3.upload_fileobj.call_args
        assert call_args[0][2] == "vacation-2024/beach.jpg"

    def test_upload_uncategorized_no_prefix(self, client):
        mock_s3 = MagicMock()
        with patch("app.get_s3", return_value=mock_s3):
            data = {"files": (io.BytesIO(b"fake image data"), "random.jpg")}
            client.post(
                "/upload/__uncategorized__",
                data=data,
                content_type="multipart/form-data",
            )
        call_args = mock_s3.upload_fileobj.call_args
        assert call_args[0][2] == "random.jpg"  # no prefix

    def test_upload_rejects_non_image(self, client):
        mock_s3 = MagicMock()
        with patch("app.get_s3", return_value=mock_s3):
            data = {"files": (io.BytesIO(b"not an image"), "virus.exe")}
            client.post(
                "/upload/vacation-2024",
                data=data,
                content_type="multipart/form-data",
            )
        mock_s3.upload_fileobj.assert_not_called()


# ── Delete ────────────────────────────────────────────────────
class TestDelete:
    def test_delete_calls_s3(self, client):
        mock_s3 = MagicMock()
        with patch("app.get_s3", return_value=mock_s3):
            resp = client.post("/delete/vacation-2024/beach.jpg")
        mock_s3.delete_object.assert_called_once_with(
            Bucket="", Key="vacation-2024/beach.jpg"
        )
        assert resp.status_code == 302

    def test_delete_redirects_to_album(self, client):
        mock_s3 = MagicMock()
        with patch("app.get_s3", return_value=mock_s3):
            resp = client.post("/delete/vacation-2024/beach.jpg")
        assert "/album/vacation-2024" in resp.headers["Location"]


# ── Helpers ───────────────────────────────────────────────────
class TestHelpers:
    def test_allowed_file_accepts_images(self):
        from app import allowed_file
        assert allowed_file("photo.jpg") is True
        assert allowed_file("image.PNG") is True
        assert allowed_file("anim.webp") is True

    def test_allowed_file_rejects_non_images(self):
        from app import allowed_file
        assert allowed_file("script.py")  is False
        assert allowed_file("doc.pdf")    is False
        assert allowed_file("noext")      is False

    def test_is_image(self):
        from app import is_image
        assert is_image("vacation/beach.jpg") is True
        assert is_image("vacation/notes.txt") is False
