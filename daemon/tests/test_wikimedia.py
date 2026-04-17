from unittest.mock import patch, MagicMock
from kde_lockscreen.sources.wikimedia import fetch


def test_fetch_parses_atom_enclosure():
    atom = (
        b"<?xml version='1.0'?>"
        b"<feed xmlns='http://www.w3.org/2005/Atom'>"
        b"<entry><link rel='enclosure' href='https://upload.wikimedia.org/img.jpg'/></entry>"
        b"</feed>"
    )
    image_bytes = b"\xff\xd8\xff" + b"B" * 500

    def fake_urlopen(url, timeout):
        mock = MagicMock()
        mock.read.return_value = atom if "w/api.php" in url else image_bytes
        mock.__enter__.return_value = mock
        mock.__exit__.return_value = False
        return mock

    with patch("kde_lockscreen.sources.wikimedia.urlopen", side_effect=fake_urlopen):
        data, meta = fetch()

    assert data == image_bytes
    assert meta["source"] == "wikimedia"
    assert meta["url"] == "https://upload.wikimedia.org/img.jpg"
