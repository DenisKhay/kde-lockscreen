import json
from unittest.mock import patch, MagicMock
from kde_lockscreen.sources.picsum import fetch


def _fake(image_bytes=b"\xff\xd8\xffP", api_json=None):
    def inner(url, timeout):
        mock = MagicMock()
        if "api.unsplash.com" in url:
            mock.read.return_value = api_json or b""
        elif "picsum.photos" in url:
            mock.read.return_value = image_bytes
        else:
            mock.read.return_value = image_bytes
        mock.__enter__.return_value = mock
        mock.__exit__.return_value = False
        mock.geturl.return_value = url
        return mock
    return inner


def test_picsum_path():
    with patch("kde_lockscreen.sources.picsum.urlopen", side_effect=_fake()):
        data, meta = fetch(use_picsum=True, unsplash_key="")
    assert meta["source"] == "picsum"
    assert "picsum.photos" in meta["url"]


def test_unsplash_path_when_key_provided():
    api = json.dumps({"urls": {"full": "https://images.unsplash.com/foo.jpg"}, "user": {"name": "Alice"}}).encode()
    with patch("kde_lockscreen.sources.picsum.urlopen", side_effect=_fake(api_json=api)):
        data, meta = fetch(use_picsum=False, unsplash_key="KEY123")
    assert meta["source"] == "unsplash"
    assert "images.unsplash.com" in meta["url"]
