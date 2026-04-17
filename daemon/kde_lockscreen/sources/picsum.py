from __future__ import annotations

import json
from urllib.request import urlopen

PICSUM = "https://picsum.photos/2560/1600"
UNSPLASH = "https://api.unsplash.com/photos/random?orientation=landscape&client_id={key}"
TIMEOUT = 10


def fetch(use_picsum: bool = True, unsplash_key: str = "") -> tuple[bytes, dict]:
    if use_picsum or not unsplash_key:
        with urlopen(PICSUM, timeout=TIMEOUT) as resp:
            data = resp.read()
            final_url = resp.geturl()
        return data, {"source": "picsum", "url": final_url, "copyright": "picsum.photos"}

    with urlopen(UNSPLASH.format(key=unsplash_key), timeout=TIMEOUT) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    url = payload["urls"]["full"]
    with urlopen(url, timeout=TIMEOUT) as resp:
        data = resp.read()
    author = payload.get("user", {}).get("name", "")
    return data, {"source": "unsplash", "url": url, "copyright": f"Unsplash/{author}"}
