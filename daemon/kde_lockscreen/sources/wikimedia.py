from __future__ import annotations

import xml.etree.ElementTree as ET
from urllib.request import urlopen

API = "https://en.wikipedia.org/w/api.php?action=featuredfeed&feed=potd&feedformat=atom"
NS = {"atom": "http://www.w3.org/2005/Atom"}
TIMEOUT = 10


def fetch() -> tuple[bytes, dict]:
    with urlopen(API, timeout=TIMEOUT) as resp:
        tree = ET.fromstring(resp.read())
    link = tree.find(".//atom:link[@rel='enclosure']", NS)
    if link is None or "href" not in link.attrib:
        raise RuntimeError("wikimedia: no enclosure in POTD feed")
    url = link.attrib["href"]
    with urlopen(url, timeout=TIMEOUT) as resp:
        data = resp.read()
    return data, {"source": "wikimedia", "url": url, "copyright": "Wikimedia Commons"}
