from __future__ import annotations

import hashlib
import json
from urllib.request import urlopen

API_TEMPLATE = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n={n}&mkt=en-US"
BASE = "https://www.bing.com"
TIMEOUT = 10
DEFAULT_COUNT = 8  # Bing's API cap


def fetch() -> tuple[bytes, dict]:
    """Fetch today's Bing image. Kept for backward compatibility."""
    with urlopen(API_TEMPLATE.format(n=1), timeout=TIMEOUT) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    image_info = payload["images"][0]
    url = BASE + image_info["url"]
    with urlopen(url, timeout=TIMEOUT) as resp:
        data = resp.read()
    return data, {"source": "bing", "url": url,
                  "copyright": image_info.get("copyright", "")}


def fetch_many(count: int = DEFAULT_COUNT) -> list[tuple[bytes, dict]]:
    """Fetch up to `count` recent Bing images (API caps at 8)."""
    count = min(count, DEFAULT_COUNT)
    with urlopen(API_TEMPLATE.format(n=count), timeout=TIMEOUT) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    results: list[tuple[bytes, dict]] = []
    for image_info in payload["images"]:
        url = BASE + image_info["url"]
        try:
            with urlopen(url, timeout=TIMEOUT) as resp:
                data = resp.read()
        except Exception:
            continue
        startdate = image_info.get("startdate", "")  # YYYYMMDD
        date_iso = (f"{startdate[0:4]}-{startdate[4:6]}-{startdate[6:8]}"
                    if len(startdate) == 8 else "")
        results.append((data, {
            "source": "bing", "url": url, "date": date_iso,
            "copyright": image_info.get("copyright", ""),
            "url_hash": hashlib.md5(url.encode()).hexdigest()[:8],
        }))
    return results
