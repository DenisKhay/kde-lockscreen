from __future__ import annotations

import json
from urllib.request import urlopen

API = "https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY"
TIMEOUT = 10


class SkipSource(Exception):
    """Raised when today's APOD is not an image (e.g. video)."""


def fetch() -> tuple[bytes, dict]:
    with urlopen(API, timeout=TIMEOUT) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    if payload.get("media_type") != "image":
        raise SkipSource(f"nasa: media_type={payload.get('media_type')}")
    url = payload.get("hdurl") or payload.get("url")
    if not url:
        raise SkipSource("nasa: no url in response")
    with urlopen(url, timeout=TIMEOUT) as resp:
        data = resp.read()
    return data, {"source": "nasa", "url": url, "copyright": payload.get("copyright", "NASA/APOD")}
