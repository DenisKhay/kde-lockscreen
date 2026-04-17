from unittest.mock import patch, MagicMock
from kde_lockscreen.sources.bing import fetch


def test_fetch_returns_bytes_and_meta():
    api_response = b'{"images":[{"url":"/th?id=abc.jpg","copyright":"X"}]}'
    image_bytes = b"\xff\xd8\xff" + b"A" * 1000

    def fake_urlopen(url, timeout):
        mock = MagicMock()
        if "HPImageArchive" in url:
            mock.read.return_value = api_response
        else:
            assert url.startswith("https://www.bing.com/th?id=")
            mock.read.return_value = image_bytes
        mock.__enter__.return_value = mock
        mock.__exit__.return_value = False
        return mock

    with patch("kde_lockscreen.sources.bing.urlopen", side_effect=fake_urlopen):
        data, meta = fetch()

    assert data == image_bytes
    assert meta["source"] == "bing"
    assert meta["url"].endswith("abc.jpg")
