from __future__ import annotations

import json
from urllib.request import urlopen

API = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US"
BASE = "https://www.bing.com"
TIMEOUT = 10


def fetch() -> tuple[bytes, dict]:
    """Return (jpeg_bytes, metadata_dict) for today's Bing image."""
    with urlopen(API, timeout=TIMEOUT) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    image_info = payload["images"][0]
    url = BASE + image_info["url"]
    with urlopen(url, timeout=TIMEOUT) as resp:
        data = resp.read()
    return data, {"source": "bing", "url": url, "copyright": image_info.get("copyright", "")}
