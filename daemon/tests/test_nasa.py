import json
import pytest
from unittest.mock import patch, MagicMock
from kde_lockscreen.sources.nasa import fetch, SkipSource


def _make_fake(api_json: bytes, image_bytes: bytes = b"\xff\xd8\xffZ"):
    def fake_urlopen(url, timeout):
        mock = MagicMock()
        mock.read.return_value = api_json if "api.nasa.gov" in url else image_bytes
        mock.__enter__.return_value = mock
        mock.__exit__.return_value = False
        return mock
    return fake_urlopen


def test_fetch_image_uses_hdurl():
    api = json.dumps({"media_type": "image", "hdurl": "https://apod.nasa.gov/hd.jpg", "url": "https://apod.nasa.gov/sd.jpg"}).encode()
    with patch("kde_lockscreen.sources.nasa.urlopen", side_effect=_make_fake(api)):
        data, meta = fetch()
    assert meta["url"].endswith("hd.jpg")


def test_fetch_image_falls_back_to_url_when_no_hdurl():
    api = json.dumps({"media_type": "image", "url": "https://apod.nasa.gov/only.jpg"}).encode()
    with patch("kde_lockscreen.sources.nasa.urlopen", side_effect=_make_fake(api)):
        data, meta = fetch()
    assert meta["url"].endswith("only.jpg")


def test_fetch_raises_skip_for_video():
    api = json.dumps({"media_type": "video", "url": "https://youtube.com/abc"}).encode()
    with patch("kde_lockscreen.sources.nasa.urlopen", side_effect=_make_fake(api)):
        with pytest.raises(SkipSource):
            fetch()
