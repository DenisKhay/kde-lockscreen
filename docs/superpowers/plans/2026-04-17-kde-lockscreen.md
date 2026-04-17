# KDE Lock Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a custom KDE Plasma 5 lock screen with multi-monitor Bing-style backgrounds, PIN-without-focus input, save/skip gestures, sleep-inhibit, and a PAM optimization that cuts unlock latency from 3s to <200ms.

**Architecture:** A KDE Look-and-Feel package (QML greeter under `package/contents/lockscreen/`) + two small Python systemd --user services (daily image fetcher, D-Bus-driven sleep inhibitor) + a reversible `/etc/pam.d/kde` replacement. The greeter is purely reactive — it reads an image cache written by the fetcher and calls PAM via `authenticator.tryUnlock`. State flows through `~/.cache/kde-lockscreen/manifest.json` (images) and `~/.config/kde-lockscreen.conf` (settings).

**Tech Stack:** QML (Qt5/QtQuick 2.15) · KDE Plasma 5.27 · KPackage Look-and-Feel · Python 3.11 (stdlib-only for daemons, `pytest` for tests) · systemd --user units · PAM · Kubuntu 24.04.

**Commit message format:** `[kde-lockscreen] (F) <Area> | <Description>` — matches the user's project-wide convention. Valid `<Area>` values used below: `Package`, `QML`, `Daemon`, `SystemD`, `PAM`, `Install`, `Test`, `Docs`.

---

## File Structure

```
kde-lockscreen/
├── package/
│   ├── metadata.desktop                          # KPackage manifest
│   └── contents/lockscreen/
│       ├── LockScreen.qml                        # entry point (~30 LOC)
│       ├── LockScreenUi.qml                      # root UI + Keys routing (~150 LOC)
│       ├── BackgroundLayer.qml                   # image + blur + dim (~60 LOC)
│       ├── CenterStack.qml                       # clock/user/dots stack (~100 LOC)
│       ├── Clock.qml                             # live clock (~40 LOC)
│       ├── PinInput.qml                          # invisible TextInput (~80 LOC)
│       ├── PinDots.qml                           # mm-sized dots (~60 LOC)
│       ├── ImageRegistry.qml                     # manifest reader (~80 LOC)
│       ├── NextImageHint.qml                     # skip cue (~30 LOC)
│       ├── SaveImageHint.qml                     # save cue + toast (~40 LOC)
│       ├── config.qml                            # KDE config panel (~120 LOC)
│       ├── config.xml                            # config schema (~40 LOC)
│       └── fallback.jpg                          # bundled gradient fallback
├── daemon/
│   ├── kde_lockscreen/
│   │   ├── __init__.py
│   │   ├── fetcher.py                            # daily fetch orchestrator
│   │   ├── inhibitd.py                           # sleep-inhibit daemon
│   │   ├── manifest.py                           # manifest.json I/O + flock
│   │   └── sources/
│   │       ├── __init__.py
│   │       ├── bing.py
│   │       ├── wikimedia.py
│   │       ├── nasa.py
│   │       └── picsum.py                         # also handles unsplash if key set
│   ├── tests/
│   │   ├── test_manifest.py
│   │   ├── test_bing.py
│   │   ├── test_wikimedia.py
│   │   ├── test_nasa.py
│   │   └── test_picsum.py
│   └── pyproject.toml
├── systemd/
│   ├── kde-lockscreen-fetcher.service
│   ├── kde-lockscreen-fetcher.timer
│   └── kde-lockscreen-inhibitd.service
├── pam/
│   └── kde.optimized                             # reference PAM config
├── scripts/
│   ├── install.sh
│   ├── install-dev.sh
│   ├── install-pam.sh
│   ├── uninstall.sh
│   ├── pam-diagnose.sh
│   └── test-greeter.sh
├── docs/superpowers/
│   ├── specs/2026-04-17-kde-lockscreen-design.md
│   └── plans/2026-04-17-kde-lockscreen.md
├── CLAUDE.md
└── README.md
```

---

## Pre-flight

- [ ] Confirm `/home/denisk/Projects/kde-lockscreen` is the working directory and is already a git repo with the design spec committed. `git log --oneline` should show the spec commits.
- [ ] Confirm installed prereqs: `plasmashell --version` reports 5.27.x, `which pamtester` exists (`sudo apt install pamtester` if not), `python3 --version` ≥ 3.11.

---

## Task 1: Repo skeleton + .gitignore

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/.gitignore`
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/` (directory only)
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/kde_lockscreen/sources/` (directory only)
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/tests/` (directory only)
- Create: `/home/denisk/Projects/kde-lockscreen/systemd/` (directory only)
- Create: `/home/denisk/Projects/kde-lockscreen/pam/` (directory only)
- Create: `/home/denisk/Projects/kde-lockscreen/scripts/` (directory only)

- [ ] **Step 1: Write .gitignore**

```gitignore
__pycache__/
*.pyc
*.pyo
.pytest_cache/
.venv/
*.egg-info/
dist/
build/
.idea/
.vscode/
*.swp
```

- [ ] **Step 2: Create directories with placeholders so git tracks them**

```bash
cd /home/denisk/Projects/kde-lockscreen
mkdir -p package/contents/lockscreen daemon/kde_lockscreen/sources daemon/tests systemd pam scripts
touch package/contents/lockscreen/.gitkeep daemon/kde_lockscreen/sources/.gitkeep daemon/tests/.gitkeep systemd/.gitkeep pam/.gitkeep scripts/.gitkeep
touch daemon/kde_lockscreen/__init__.py daemon/kde_lockscreen/sources/__init__.py
```

- [ ] **Step 3: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add .gitignore package/ daemon/ systemd/ pam/ scripts/
git commit -m "[kde-lockscreen] (F) Package | Initial repo skeleton"
```

---

## Task 2: Look-and-Feel metadata.desktop

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/package/metadata.desktop`

- [ ] **Step 1: Reference existing Plasma LNF manifest for format**

Run: `cat /usr/share/plasma/look-and-feel/org.kde.breeze.desktop/metadata.desktop | head -30`
Confirms required keys: `X-KDE-PluginInfo-Name`, `X-Plasma-MainScript`, `X-KDE-ServiceTypes`.

- [ ] **Step 2: Write metadata.desktop**

```ini
[Desktop Entry]
Comment=Custom KDE lock screen with dynamic backgrounds
Comment[en_US]=Custom KDE lock screen with dynamic backgrounds
Name=Denis Lockscreen
Name[en_US]=Denis Lockscreen
Type=Service
X-KDE-PluginInfo-Author=Denis Khaydarshin
X-KDE-PluginInfo-Email=dkhaydarshin@lifedl.net
X-KDE-PluginInfo-License=MIT
X-KDE-PluginInfo-Name=com.denisk.lockscreen
X-KDE-PluginInfo-Version=0.1.0
X-KDE-PluginInfo-Website=https://github.com/DenisKhay/kde-lockscreen
X-KDE-ServiceTypes=Plasma/LookAndFeel
X-Plasma-APIVersion=6.0
```

- [ ] **Step 3: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/metadata.desktop
git commit -m "[kde-lockscreen] (F) Package | Add Look-and-Feel metadata.desktop"
```

---

## Task 3: Minimal LockScreen.qml entry point

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/LockScreen.qml`
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/LockScreenUi.qml` (stub)

- [ ] **Step 1: Write LockScreen.qml**

```qml
import QtQuick 2.15
import QtQuick.Window 2.15

LockScreenUi {
    id: lockScreen
    anchors.fill: parent
    Component.onCompleted: forceActiveFocus()
}
```

- [ ] **Step 2: Write stub LockScreenUi.qml (replaced in later tasks)**

```qml
import QtQuick 2.15

Rectangle {
    id: root
    color: "#102030"

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 48
        text: "Denis Lockscreen — skeleton"
    }
}
```

- [ ] **Step 3: Smoke test — install dev-style and launch greeter**

Run:
```bash
cd /home/denisk/Projects/kde-lockscreen
mkdir -p ~/.local/share/plasma/look-and-feel/com.denisk.lockscreen
rm -rf ~/.local/share/plasma/look-and-feel/com.denisk.lockscreen
ln -s "$PWD/package" ~/.local/share/plasma/look-and-feel/com.denisk.lockscreen
QT_QPA_PLATFORM=xcb kscreenlocker_greet --testing --theme com.denisk.lockscreen &
sleep 3
pkill -f kscreenlocker_greet
```

Expected: a dark-blue window with "Denis Lockscreen — skeleton" appears briefly and exits. Any QML errors show in terminal stderr.

- [ ] **Step 4: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/
git commit -m "[kde-lockscreen] (F) QML | Minimal LockScreen skeleton that loads in kscreenlocker_greet"
```

---

## Task 4: BackgroundLayer (static image, no blur yet)

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/BackgroundLayer.qml`
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/fallback.jpg`
- Modify: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/LockScreenUi.qml`

- [ ] **Step 1: Generate a simple gradient fallback.jpg (small, ship-ready)**

Run:
```bash
cd /home/denisk/Projects/kde-lockscreen/package/contents/lockscreen
python3 -c "
from PIL import Image
img = Image.new('RGB', (1920, 1080))
px = img.load()
for y in range(1080):
    t = y / 1079
    r = int(16 + (8-16)*t); g = int(32 + (20-32)*t); b = int(48 + (32-48)*t)
    for x in range(1920): px[x,y] = (r,g,b)
img.save('fallback.jpg', quality=85)
"
ls -lh fallback.jpg
```

Expected: `fallback.jpg` ~50-100 KB.

- [ ] **Step 2: Write BackgroundLayer.qml**

```qml
import QtQuick 2.15
import QtGraphicalEffects 1.15

Item {
    id: root
    property string source: ""
    property real blurRadius: 32
    property real dimAlpha: 0.4
    property string fitMode: "smart"  // cover | contain | smart

    Image {
        id: baseImage
        anchors.fill: parent
        source: root.source
        asynchronous: true
        cache: true
        fillMode: {
            if (root.fitMode === "cover") return Image.PreserveAspectCrop
            if (root.fitMode === "contain") return Image.PreserveAspectFit
            if (!baseImage.sourceSize.width) return Image.PreserveAspectCrop
            var imgAspect = baseImage.sourceSize.width / baseImage.sourceSize.height
            var screenAspect = parent.width / parent.height
            return (imgAspect < 1 || Math.abs(imgAspect - screenAspect) > 0.5)
                ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        }
    }

    FastBlur {
        anchors.fill: baseImage
        source: baseImage
        radius: root.blurRadius
        visible: root.blurRadius > 0
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.dimAlpha
    }
}
```

- [ ] **Step 3: Rewrite LockScreenUi.qml to use BackgroundLayer**

```qml
import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    BackgroundLayer {
        anchors.fill: parent
        source: "file://" + Qt.resolvedUrl("fallback.jpg").toString().replace("file://", "")
        blurRadius: 24
        dimAlpha: 0.35
    }

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 48
        text: "Denis Lockscreen — bg"
    }
}
```

- [ ] **Step 4: Smoke test**

Run:
```bash
QT_QPA_PLATFORM=xcb kscreenlocker_greet --testing --theme com.denisk.lockscreen &
sleep 3
pkill -f kscreenlocker_greet
```

Expected: blurred dark-blue gradient fills the window with "Denis Lockscreen — bg" readable on top. No QML errors.

- [ ] **Step 5: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/BackgroundLayer.qml package/contents/lockscreen/fallback.jpg package/contents/lockscreen/LockScreenUi.qml
git commit -m "[kde-lockscreen] (F) QML | BackgroundLayer with blur/dim + fallback gradient"
```

---

## Task 5: Python manifest module with flock + TDD

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/kde_lockscreen/manifest.py`
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/tests/test_manifest.py`
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/pyproject.toml`

- [ ] **Step 1: Write pyproject.toml for the daemon package**

```toml
[project]
name = "kde-lockscreen-daemon"
version = "0.1.0"
description = "KDE lockscreen image fetcher + sleep-inhibit daemons"
requires-python = ">=3.11"
dependencies = [
    "dbus-next>=0.2.3",
]

[project.optional-dependencies]
dev = ["pytest>=8.0", "pytest-asyncio>=0.23"]

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
include = ["kde_lockscreen*"]

[tool.pytest.ini_options]
testpaths = ["tests"]
```

- [ ] **Step 2: Write the failing test**

```python
# daemon/tests/test_manifest.py
import json
from pathlib import Path
from kde_lockscreen.manifest import Manifest, ImageEntry


def test_add_and_list(tmp_path: Path):
    m = Manifest(tmp_path / "manifest.json")
    entry = ImageEntry(
        path=str(tmp_path / "a.jpg"),
        source="bing",
        date="2026-04-17",
        width=1920,
        height=1080,
    )
    m.add(entry)
    assert [e.source for e in m.list()] == ["bing"]


def test_mark_disliked_persists(tmp_path: Path):
    m = Manifest(tmp_path / "manifest.json")
    m.add(ImageEntry(path="x.jpg", source="bing", date="2026-04-17", width=1, height=1))
    m.mark_disliked("x.jpg")
    m2 = Manifest(tmp_path / "manifest.json")
    assert m2.list()[0].disliked is True


def test_mark_saved_persists(tmp_path: Path):
    m = Manifest(tmp_path / "manifest.json")
    m.add(ImageEntry(path="x.jpg", source="bing", date="2026-04-17", width=1, height=1))
    m.mark_saved("x.jpg")
    m2 = Manifest(tmp_path / "manifest.json")
    assert m2.list()[0].saved is True


def test_evict_older_than(tmp_path: Path):
    m = Manifest(tmp_path / "manifest.json")
    m.add(ImageEntry(path="old.jpg", source="bing", date="2026-01-01", width=1, height=1))
    m.add(ImageEntry(path="new.jpg", source="bing", date="2026-04-17", width=1, height=1))
    m.evict_older_than(days=14, today="2026-04-17")
    paths = [e.path for e in m.list()]
    assert paths == ["new.jpg"]


def test_corrupt_manifest_rebuilds_empty(tmp_path: Path):
    (tmp_path / "manifest.json").write_text("{not json")
    m = Manifest(tmp_path / "manifest.json")
    assert m.list() == []
```

- [ ] **Step 3: Run tests to verify they fail**

Run:
```bash
cd /home/denisk/Projects/kde-lockscreen/daemon
python3 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
pytest tests/test_manifest.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'kde_lockscreen.manifest'` or `ImportError`.

- [ ] **Step 4: Implement manifest.py**

```python
# daemon/kde_lockscreen/manifest.py
from __future__ import annotations

import fcntl
import json
from dataclasses import asdict, dataclass, field
from datetime import date
from pathlib import Path
from typing import List


@dataclass
class ImageEntry:
    path: str
    source: str
    date: str  # YYYY-MM-DD
    width: int
    height: int
    disliked: bool = False
    saved: bool = False
    assigned_to_screen: int | None = None


@dataclass
class _ManifestData:
    version: int = 1
    entries: List[ImageEntry] = field(default_factory=list)


class Manifest:
    """JSON-backed image manifest with flock-based concurrent safety."""

    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._data = self._load()

    def _load(self) -> _ManifestData:
        if not self.path.exists():
            return _ManifestData()
        try:
            raw = json.loads(self.path.read_text())
            entries = [ImageEntry(**e) for e in raw.get("entries", [])]
            return _ManifestData(version=raw.get("version", 1), entries=entries)
        except (json.JSONDecodeError, TypeError):
            # Corrupt manifest: rebuild empty. Fetcher will repopulate from files.
            return _ManifestData()

    def _save(self) -> None:
        tmp = self.path.with_suffix(".json.tmp")
        with tmp.open("w") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            json.dump(
                {
                    "version": self._data.version,
                    "entries": [asdict(e) for e in self._data.entries],
                },
                f,
                indent=2,
            )
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        tmp.replace(self.path)

    def list(self) -> list[ImageEntry]:
        return list(self._data.entries)

    def add(self, entry: ImageEntry) -> None:
        self._data.entries = [e for e in self._data.entries if e.path != entry.path]
        self._data.entries.append(entry)
        self._save()

    def mark_disliked(self, path: str) -> None:
        for e in self._data.entries:
            if e.path == path:
                e.disliked = True
        self._save()

    def mark_saved(self, path: str) -> None:
        for e in self._data.entries:
            if e.path == path:
                e.saved = True
        self._save()

    def evict_older_than(self, days: int, today: str | None = None) -> None:
        today_d = date.fromisoformat(today) if today else date.today()
        keep: list[ImageEntry] = []
        for e in self._data.entries:
            try:
                age = (today_d - date.fromisoformat(e.date)).days
            except ValueError:
                age = 0
            if age <= days:
                keep.append(e)
            else:
                try:
                    Path(e.path).unlink(missing_ok=True)
                except OSError:
                    pass
        self._data.entries = keep
        self._save()
```

- [ ] **Step 5: Run tests to verify all pass**

Run:
```bash
cd /home/denisk/Projects/kde-lockscreen/daemon
pytest tests/test_manifest.py -v
```

Expected: 5 PASSED.

- [ ] **Step 6: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add daemon/
git commit -m "[kde-lockscreen] (F) Daemon | Manifest module with flock + tests"
```

---

## Task 6: Bing image source (TDD)

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/kde_lockscreen/sources/bing.py`
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/tests/test_bing.py`

- [ ] **Step 1: Write the failing test**

```python
# daemon/tests/test_bing.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/denisk/Projects/kde-lockscreen/daemon && pytest tests/test_bing.py -v`
Expected: FAIL — `ModuleNotFoundError`.

- [ ] **Step 3: Implement bing.py**

```python
# daemon/kde_lockscreen/sources/bing.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/denisk/Projects/kde-lockscreen/daemon && pytest tests/test_bing.py -v`
Expected: PASSED.

- [ ] **Step 5: Live smoke test (optional, needs network)**

Run:
```bash
cd /home/denisk/Projects/kde-lockscreen/daemon
python3 -c "
from kde_lockscreen.sources.bing import fetch
d, m = fetch()
print(len(d), 'bytes', m)
"
```
Expected: prints byte count (>100000) and metadata dict.

- [ ] **Step 6: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add daemon/kde_lockscreen/sources/bing.py daemon/tests/test_bing.py
git commit -m "[kde-lockscreen] (F) Daemon | Bing image source + test"
```

---

## Task 7: Wikimedia POTD source (TDD)

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/kde_lockscreen/sources/wikimedia.py`
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/tests/test_wikimedia.py`

- [ ] **Step 1: Write the failing test**

```python
# daemon/tests/test_wikimedia.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/denisk/Projects/kde-lockscreen/daemon && pytest tests/test_wikimedia.py -v`
Expected: FAIL — `ModuleNotFoundError`.

- [ ] **Step 3: Implement wikimedia.py**

```python
# daemon/kde_lockscreen/sources/wikimedia.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/denisk/Projects/kde-lockscreen/daemon && pytest tests/test_wikimedia.py -v`
Expected: PASSED.

- [ ] **Step 5: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add daemon/kde_lockscreen/sources/wikimedia.py daemon/tests/test_wikimedia.py
git commit -m "[kde-lockscreen] (F) Daemon | Wikimedia POTD source + test"
```

---

## Task 8: NASA APOD source (TDD, handles video skip)

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/kde_lockscreen/sources/nasa.py`
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/tests/test_nasa.py`

- [ ] **Step 1: Write the failing test**

```python
# daemon/tests/test_nasa.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/denisk/Projects/kde-lockscreen/daemon && pytest tests/test_nasa.py -v`
Expected: FAIL — `ModuleNotFoundError`.

- [ ] **Step 3: Implement nasa.py**

```python
# daemon/kde_lockscreen/sources/nasa.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/denisk/Projects/kde-lockscreen/daemon && pytest tests/test_nasa.py -v`
Expected: 3 PASSED.

- [ ] **Step 5: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add daemon/kde_lockscreen/sources/nasa.py daemon/tests/test_nasa.py
git commit -m "[kde-lockscreen] (F) Daemon | NASA APOD source with video-skip + tests"
```

---

## Task 9: Picsum / Unsplash source (TDD)

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/kde_lockscreen/sources/picsum.py`
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/tests/test_picsum.py`

- [ ] **Step 1: Write the failing test**

```python
# daemon/tests/test_picsum.py
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
        return mock
    return inner


def test_picsum_path(monkeypatch):
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/denisk/Projects/kde-lockscreen/daemon && pytest tests/test_picsum.py -v`
Expected: FAIL — `ModuleNotFoundError`.

- [ ] **Step 3: Implement picsum.py**

```python
# daemon/kde_lockscreen/sources/picsum.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/denisk/Projects/kde-lockscreen/daemon && pytest tests/test_picsum.py -v`
Expected: 2 PASSED.

- [ ] **Step 5: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add daemon/kde_lockscreen/sources/picsum.py daemon/tests/test_picsum.py
git commit -m "[kde-lockscreen] (F) Daemon | Picsum/Unsplash source + tests"
```

---

## Task 10: Fetcher orchestrator (no TDD — integration glue)

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/kde_lockscreen/fetcher.py`

- [ ] **Step 1: Write fetcher.py**

```python
# daemon/kde_lockscreen/fetcher.py
"""Daily image fetcher. Fetches one image per enabled source, writes to cache
and manifest. Run via systemd --user timer.
"""
from __future__ import annotations

import argparse
import configparser
import logging
import os
import sys
from datetime import date
from pathlib import Path
from tempfile import NamedTemporaryFile

from .manifest import ImageEntry, Manifest
from .sources import bing, wikimedia, nasa, picsum

log = logging.getLogger("kde-lockscreen-fetcher")

DEFAULT_CONFIG = Path.home() / ".config" / "kde-lockscreen.conf"
DEFAULT_CACHE = Path.home() / ".cache" / "kde-lockscreen"

SOURCE_MODULES = {
    "bing": bing,
    "wikimedia": wikimedia,
    "nasa": nasa,
    "picsum": picsum,
}


def _load_config(path: Path) -> configparser.ConfigParser:
    cp = configparser.ConfigParser()
    cp.read_dict({
        "Sources": {"bing": "true", "wikimedia": "true", "nasa": "true", "unsplash": "false",
                    "unsplashApiKey": "", "usePicsumInstead": "true"},
        "Cache": {"maxDays": "14", "cacheDir": str(DEFAULT_CACHE)},
    })
    if path.exists():
        cp.read(path)
    return cp


def _atomic_write(data: bytes, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=target.parent, delete=False) as tmp:
        tmp.write(data)
        tmp_path = Path(tmp.name)
    tmp_path.replace(target)


def _fetch_one(name: str, cfg: configparser.ConfigParser) -> tuple[bytes, dict] | None:
    try:
        if name == "picsum":
            use_picsum = cfg.getboolean("Sources", "usePicsumInstead", fallback=True)
            key = cfg.get("Sources", "unsplashApiKey", fallback="")
            return picsum.fetch(use_picsum=use_picsum, unsplash_key=key)
        return SOURCE_MODULES[name].fetch()
    except Exception as exc:
        log.warning("source %s failed: %s", name, exc)
        return None


def _enabled_sources(cfg: configparser.ConfigParser) -> list[str]:
    enabled = []
    for name in ["bing", "wikimedia", "nasa"]:
        if cfg.getboolean("Sources", name, fallback=True):
            enabled.append(name)
    # picsum/unsplash unified under the picsum module
    if cfg.getboolean("Sources", "usePicsumInstead", fallback=True) or cfg.get("Sources", "unsplashApiKey", fallback=""):
        enabled.append("picsum")
    return enabled


def run(config_path: Path = DEFAULT_CONFIG) -> int:
    cfg = _load_config(config_path)
    cache_dir = Path(os.path.expanduser(cfg.get("Cache", "cacheDir", fallback=str(DEFAULT_CACHE))))
    max_days = cfg.getint("Cache", "maxDays", fallback=14)

    manifest = Manifest(cache_dir / "manifest.json")
    today = date.today().isoformat()
    failures = 0

    for name in _enabled_sources(cfg):
        result = _fetch_one(name, cfg)
        if not result:
            failures += 1
            continue
        data, meta = result
        target = cache_dir / f"{today}-{meta['source']}.jpg"
        _atomic_write(data, target)
        manifest.add(ImageEntry(
            path=str(target), source=meta["source"], date=today,
            width=0, height=0,  # PIL-free: sizes unknown, QML handles any size
        ))
        log.info("fetched %s -> %s (%d bytes)", meta["source"], target, len(data))

    manifest.evict_older_than(days=max_days, today=today)
    return 1 if failures == len(_enabled_sources(cfg)) else 0


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    sys.exit(run(args.config))


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Live smoke test with network**

Run:
```bash
cd /home/denisk/Projects/kde-lockscreen/daemon
source .venv/bin/activate
python3 -m kde_lockscreen.fetcher
ls -lh ~/.cache/kde-lockscreen/
cat ~/.cache/kde-lockscreen/manifest.json | head -40
```

Expected: 3-4 JPEGs present, manifest.json lists them.

- [ ] **Step 3: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add daemon/kde_lockscreen/fetcher.py
git commit -m "[kde-lockscreen] (F) Daemon | Fetcher orchestrator + eviction"
```

---

## Task 11: ImageRegistry QML — reads manifest from QML

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/ImageRegistry.qml`
- Modify: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/LockScreenUi.qml`

- [ ] **Step 1: Write ImageRegistry.qml**

```qml
import QtQuick 2.15

Item {
    id: registry

    property var _entries: []
    property string cacheDir: Qt.resolvedUrl("file://" + Qt.application.arguments[0])  // placeholder
        .toString()
    property string manifestPath: {
        // kscreenlocker_greet runs as the user; $HOME is available via env.
        var home = Qt.application.organizationName ? "" : ""
        return "file://" + (Qt.resolvedUrl("/home/" + Qt.application.name) + "")
    }

    signal entriesChanged()

    function _load() {
        var xhr = new XMLHttpRequest()
        var url = "file://" + _homeDir() + "/.cache/kde-lockscreen/manifest.json"
        xhr.open("GET", url, false)  // synchronous OK — file is local + tiny
        try {
            xhr.send(null)
            if (xhr.status === 200 || xhr.status === 0) {
                var raw = JSON.parse(xhr.responseText)
                _entries = raw.entries || []
            }
        } catch (e) {
            console.warn("ImageRegistry: manifest load failed:", e)
            _entries = []
        }
    }

    function _homeDir() {
        // Qt.resolvedUrl gives us a file:// path we can extract HOME from.
        // Hardcoded fallback because kscreenlocker_greet may not expose env.
        return "/home/denisk"
    }

    function _usable() {
        return _entries.filter(function (e) { return !e.disliked })
    }

    function pickForScreen(index) {
        var list = _usable()
        if (list.length === 0) return Qt.resolvedUrl("fallback.jpg").toString()
        // Deterministic: seeded by date + screen index
        var d = new Date()
        var seed = (d.getFullYear() * 372 + d.getMonth() * 31 + d.getDate()) + index * 17
        return "file://" + list[seed % list.length].path
    }

    function markDisliked(filePath) {
        var p = filePath.replace(/^file:\/\//, "")
        for (var i = 0; i < _entries.length; i++) {
            if (_entries[i].path === p) _entries[i].disliked = true
        }
        _writeManifest()
        entriesChanged()
    }

    function markSaved(filePath) {
        var p = filePath.replace(/^file:\/\//, "")
        for (var i = 0; i < _entries.length; i++) {
            if (_entries[i].path === p) _entries[i].saved = true
        }
        _writeManifest()
    }

    function _writeManifest() {
        var xhr = new XMLHttpRequest()
        var url = "file://" + _homeDir() + "/.cache/kde-lockscreen/manifest.json"
        xhr.open("PUT", url, false)
        try {
            xhr.send(JSON.stringify({version: 1, entries: _entries}, null, 2))
        } catch (e) {
            console.warn("ImageRegistry: manifest write failed:", e)
        }
    }

    Component.onCompleted: _load()
}
```

- [ ] **Step 2: Modify LockScreenUi.qml to use ImageRegistry for one screen**

```qml
import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    ImageRegistry { id: registry }

    BackgroundLayer {
        anchors.fill: parent
        source: registry.pickForScreen(0)
        blurRadius: 24
        dimAlpha: 0.35
    }

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 48
        text: "Denis Lockscreen — registry"
    }
}
```

- [ ] **Step 3: Smoke test**

Run:
```bash
QT_QPA_PLATFORM=xcb kscreenlocker_greet --testing --theme com.denisk.lockscreen &
sleep 3
pkill -f kscreenlocker_greet
```

Expected: a real cached Bing/Wikimedia/NASA/Picsum image (from Task 10's smoke) fills the window, blurred/dimmed.

- [ ] **Step 4: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/
git commit -m "[kde-lockscreen] (F) QML | ImageRegistry reads manifest + single-screen wiring"
```

---

## Task 12: Multi-monitor Repeater

**Files:**
- Modify: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/LockScreenUi.qml`

- [ ] **Step 1: Replace LockScreenUi.qml with multi-screen version**

```qml
import QtQuick 2.15
import QtQuick.Window 2.15

Item {
    id: root
    anchors.fill: parent

    ImageRegistry { id: registry }

    Repeater {
        model: Qt.application.screens.length || 1
        delegate: BackgroundLayer {
            x: Qt.application.screens[index] ? Qt.application.screens[index].virtualX : 0
            y: Qt.application.screens[index] ? Qt.application.screens[index].virtualY : 0
            width: Qt.application.screens[index] ? Qt.application.screens[index].width : root.width
            height: Qt.application.screens[index] ? Qt.application.screens[index].height : root.height
            source: registry.pickForScreen(index)
            blurRadius: 24
            dimAlpha: 0.35
        }
    }

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 48
        text: "Denis Lockscreen — multi-monitor"
    }
}
```

- [ ] **Step 2: Smoke test (single-monitor dev)**

Run:
```bash
QT_QPA_PLATFORM=xcb kscreenlocker_greet --testing --theme com.denisk.lockscreen &
sleep 3
pkill -f kscreenlocker_greet
```

Expected: same behavior as Task 11 on single-monitor. No crash. (Multi-monitor test requires actual second display attached.)

- [ ] **Step 3: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/LockScreenUi.qml
git commit -m "[kde-lockscreen] (F) QML | Per-screen BackgroundLayer Repeater"
```

---

## Task 13: Clock component

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/Clock.qml`

- [ ] **Step 1: Write Clock.qml**

```qml
import QtQuick 2.15

Column {
    id: root
    spacing: 8
    property var _now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._now = new Date()
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        font.pixelSize: 80
        font.weight: Font.Light
        text: Qt.formatTime(root._now, "HH:mm")
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        opacity: 0.8
        font.pixelSize: 22
        text: Qt.formatDate(root._now, "dddd, d MMMM yyyy")
    }
}
```

- [ ] **Step 2: Commit (used in later task)**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/Clock.qml
git commit -m "[kde-lockscreen] (F) QML | Clock component"
```

---

## Task 14: PinDots with physical millimeter sizing

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/PinDots.qml`

- [ ] **Step 1: Write PinDots.qml**

```qml
import QtQuick 2.15
import QtQuick.Window 2.15

Row {
    id: root
    property int pinLength: 6
    property int filled: 0
    property real dotSizeMm: 4.0
    spacing: _dotSize * 0.6

    readonly property real _dotSize: dotSizeMm * Screen.pixelDensity

    Repeater {
        model: root.pinLength
        delegate: Rectangle {
            width: root._dotSize
            height: root._dotSize
            radius: width / 2
            color: index < root.filled ? "white" : "transparent"
            border.color: "white"
            border.width: 2
            opacity: index < root.filled ? 1.0 : 0.5
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/PinDots.qml
git commit -m "[kde-lockscreen] (F) QML | PinDots with physical-mm sizing"
```

---

## Task 15: PinInput — invisible TextInput + auto-submit

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/PinInput.qml`

- [ ] **Step 1: Write PinInput.qml**

```qml
import QtQuick 2.15

Item {
    id: root
    property int pinLength: 6
    property bool autoSubmit: true
    property alias text: input.text

    signal submitted(string pin)
    signal wrongPin()

    function clear() { input.text = "" }
    function appendChar(ch) {
        if (input.text.length < pinLength + 20) input.text += ch
    }
    function backspace() { input.text = input.text.slice(0, -1) }
    function submit() {
        if (input.text.length === 0) return
        root.submitted(input.text)
    }

    TextInput {
        id: input
        visible: false
        echoMode: TextInput.Password
        onTextChanged: {
            if (root.autoSubmit && text.length === root.pinLength) {
                root.submitted(text)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/PinInput.qml
git commit -m "[kde-lockscreen] (F) QML | PinInput with auto-submit"
```

---

## Task 16: CenterStack (composes clock + username + dots)

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/CenterStack.qml`

- [ ] **Step 1: Write CenterStack.qml**

```qml
import QtQuick 2.15

Column {
    id: root
    spacing: 40
    property int pinLength: 6
    property int pinFilled: 0
    property real dotSizeMm: 4.0
    property string username: "user"

    signal shake()

    Clock {
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        font.pixelSize: 24
        text: root.username
    }

    PinDots {
        id: dots
        anchors.horizontalCenter: parent.horizontalCenter
        pinLength: root.pinLength
        filled: root.pinFilled
        dotSizeMm: root.dotSizeMm
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "x"; to: root.x - 20; duration: 50 }
        NumberAnimation { target: root; property: "x"; to: root.x + 20; duration: 50 }
        NumberAnimation { target: root; property: "x"; to: root.x - 12; duration: 50 }
        NumberAnimation { target: root; property: "x"; to: root.x; duration: 50 }
    }

    onShake: shakeAnim.start()
}
```

- [ ] **Step 2: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/CenterStack.qml
git commit -m "[kde-lockscreen] (F) QML | CenterStack composing clock/user/dots"
```

---

## Task 17: NextImageHint + SaveImageHint

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/NextImageHint.qml`
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/SaveImageHint.qml`

- [ ] **Step 1: Write NextImageHint.qml**

```qml
import QtQuick 2.15

Rectangle {
    id: root
    signal clicked()
    width: 36; height: 36; radius: 18
    color: "#80000000"
    border.color: "white"; border.width: 1
    opacity: hover.containsMouse ? 1.0 : 0.5
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 18
        text: "\u2715"  // ✕
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
```

- [ ] **Step 2: Write SaveImageHint.qml**

```qml
import QtQuick 2.15

Item {
    id: root
    signal clicked()
    property bool saved: false
    width: 36; height: 36

    Rectangle {
        id: btn
        anchors.fill: parent
        radius: 18
        color: "#80000000"
        border.color: "white"; border.width: 1
        opacity: hover.containsMouse ? 1.0 : 0.5
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            color: root.saved ? "#ff6070" : "white"
            font.pixelSize: 18
            text: root.saved ? "\u2665" : "\u2193"  // ♥ filled when saved, ↓ otherwise
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }

    // Toast
    Rectangle {
        id: toast
        anchors.right: parent.right
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        color: "#cc000000"
        radius: 6
        visible: opacity > 0
        opacity: 0
        width: toastText.implicitWidth + 24
        height: toastText.implicitHeight + 12

        Text {
            id: toastText
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 13
            text: ""
        }

        NumberAnimation on opacity {
            id: toastAnim
            duration: 2000
            from: 1.0; to: 0.0
            running: false
        }
    }

    function showToast(msg) {
        toastText.text = msg
        toast.opacity = 1.0
        toastAnim.restart()
    }
}
```

- [ ] **Step 3: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/NextImageHint.qml package/contents/lockscreen/SaveImageHint.qml
git commit -m "[kde-lockscreen] (F) QML | Next/Save hint components with toast"
```

---

## Task 18: ImageRegistry — save to Pictures

**Files:**
- Modify: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/ImageRegistry.qml`

- [ ] **Step 1: Add saveImage function to ImageRegistry.qml**

Open `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/ImageRegistry.qml` and insert this function before the final `Component.onCompleted`:

```qml
    property string saveDir: _homeDir() + "/Pictures/kde-lockscreen-saves"

    function saveImage(filePath) {
        // Returns one of: "saved", "exists", "failed"
        var p = filePath.replace(/^file:\/\//, "")
        var entry = null
        for (var i = 0; i < _entries.length; i++) {
            if (_entries[i].path === p) { entry = _entries[i]; break }
        }
        if (!entry) return "failed"

        // Build target: <saveDir>/<source>-<date>-<basename>
        var basename = p.split("/").pop()
        var target = saveDir + "/" + entry.source + "-" + entry.date + "-" + basename

        // Use XMLHttpRequest HEAD to check existence
        var check = new XMLHttpRequest()
        check.open("HEAD", "file://" + target, false)
        try { check.send(null) } catch (e) {}
        if (check.status === 200) return "exists"

        // Copy by reading source as binary and writing to target.
        // Qt.labs.platform / FileIO is not always available in greeter; fall back to shelling out.
        var proc = Qt.createQmlObject(
            'import QtQuick 2.15; QtObject { property string out: "" }', registry
        )
        // We use Qt.openUrlExternally or a known-available API. In kscreenlocker_greet,
        // the safest path is to use the manifest-side flag and have a tiny user
        // service copy on demand. For now we do a JS-level copy using XMLHttpRequest
        // (blocking, local file).
        var reader = new XMLHttpRequest()
        reader.open("GET", "file://" + p, false)
        reader.overrideMimeType("text/plain; charset=x-user-defined")
        try { reader.send(null) } catch (e) { return "failed" }
        if (reader.status !== 200 && reader.status !== 0) return "failed"

        // Ensure dir exists by attempting to write a sibling marker
        var writer = new XMLHttpRequest()
        writer.open("PUT", "file://" + target, false)
        try { writer.send(reader.responseText) } catch (e) { return "failed" }
        if (writer.status !== 200 && writer.status !== 0 && writer.status !== 201) return "failed"

        markSaved(filePath)
        return "saved"
    }
```

**Note for the implementer:** if QML's file:// PUT fails due to greeter sandboxing, fall back to invoking a helper: `Qt.application.arguments.push(...)` is not available here — instead, extend the inhibit daemon (Task 23) with a `copy_to_saves` command over a Unix socket the greeter can speak to. Flag this to the user; do not silently skip.

- [ ] **Step 2: Ensure save directory exists on load**

Add inside `ImageRegistry.qml`'s `_load()` function, at the top:

```qml
        // Ensure saveDir exists (silent no-op if it does)
        var mkReq = new XMLHttpRequest()
        mkReq.open("PUT", "file://" + saveDir + "/.keep", false)
        try { mkReq.send("") } catch (e) { /* ignore */ }
```

- [ ] **Step 3: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/ImageRegistry.qml
git commit -m "[kde-lockscreen] (F) QML | ImageRegistry.saveImage + save-dir bootstrap"
```

---

## Task 19: LockScreenUi — full UI composition with key routing

**Files:**
- Modify: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/LockScreenUi.qml`

- [ ] **Step 1: Rewrite LockScreenUi.qml with full composition**

```qml
import QtQuick 2.15
import QtQuick.Window 2.15

Item {
    id: root
    anchors.fill: parent
    focus: true

    // From Plasma's lockscreen injection. At --testing time, authenticator may be null.
    property var authenticator: typeof authenticator !== "undefined" ? authenticator : null

    // Config (populated from KConfig in Plasma; defaults here for --testing).
    property int pinLength: 6
    property real dotSizeMm: 4.0
    property real blurRadius: 32
    property real dimAlpha: 0.4
    property string fitMode: "smart"
    property bool autoSubmit: true
    property string username: Qt.application.organizationName || "denisk"

    ImageRegistry { id: registry }

    // Per-screen backgrounds + hints
    Repeater {
        model: Qt.application.screens.length || 1
        delegate: Item {
            x: Qt.application.screens[index] ? Qt.application.screens[index].virtualX : 0
            y: Qt.application.screens[index] ? Qt.application.screens[index].virtualY : 0
            width: Qt.application.screens[index] ? Qt.application.screens[index].width : root.width
            height: Qt.application.screens[index] ? Qt.application.screens[index].height : root.height

            property string currentImage: registry.pickForScreen(index)

            BackgroundLayer {
                id: bg
                anchors.fill: parent
                source: parent.currentImage
                blurRadius: root.blurRadius
                dimAlpha: root.dimAlpha
                fitMode: root.fitMode
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 24
                spacing: 8

                SaveImageHint {
                    id: saveHint
                    saved: registry._usable().some(function (e) {
                        return "file://" + e.path === parent.parent.currentImage && e.saved
                    })
                    onClicked: {
                        var r = registry.saveImage(parent.parent.currentImage)
                        if (r === "saved") saveHint.showToast("Saved to Pictures")
                        else if (r === "exists") saveHint.showToast("Already saved")
                        else saveHint.showToast("Save failed")
                    }
                }

                NextImageHint {
                    onClicked: {
                        registry.markDisliked(parent.parent.currentImage)
                        parent.parent.currentImage = registry.pickForScreen(index)
                    }
                }
            }
        }
    }

    // Center stack on primary screen
    CenterStack {
        id: center
        anchors.centerIn: parent
        pinLength: root.pinLength
        pinFilled: pin.text.length
        dotSizeMm: root.dotSizeMm
        username: root.username
    }

    PinInput {
        id: pin
        pinLength: root.pinLength
        autoSubmit: root.autoSubmit
        onSubmitted: {
            if (root.authenticator) {
                root.authenticator.tryUnlock(pin.text)
            } else {
                // Testing mode: simulate wrong PIN on non-"1234" input
                if (pin.text !== "1234") rootWrongPin()
            }
        }
    }

    function rootWrongPin() {
        center.shake()
        pin.clear()
    }

    // Wire authenticator signals if available
    Connections {
        target: root.authenticator
        ignoreUnknownSignals: true
        function onFailed() { root.rootWrongPin() }
    }

    // Key routing — load-bearing trick for typing-without-focus
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Backspace) {
            pin.backspace(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            pin.submit(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Escape) {
            pin.clear(); event.accepted = true; return
        }
        // Next image: Right arrow or 'N'
        if (event.key === Qt.Key_Right || event.key === Qt.Key_N) {
            var firstScreen = _firstScreenItem()
            if (firstScreen) {
                registry.markDisliked(firstScreen.currentImage)
                firstScreen.currentImage = registry.pickForScreen(0)
            }
            event.accepted = true; return
        }
        // Save image: Down arrow or 'S'
        if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
            var firstScreenS = _firstScreenItem()
            if (firstScreenS) {
                var r = registry.saveImage(firstScreenS.currentImage)
                // Toast lives in the SaveImageHint on the primary screen
                var hint = _firstSaveHint()
                if (hint) {
                    if (r === "saved") hint.showToast("Saved to Pictures")
                    else if (r === "exists") hint.showToast("Already saved")
                    else hint.showToast("Save failed")
                }
            }
            event.accepted = true; return
        }
        // Printable: append to PIN
        if (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32) {
            pin.appendChar(event.text)
            event.accepted = true
        }
    }

    function _firstScreenItem() {
        for (var i = 0; i < root.children.length; i++) {
            var c = root.children[i]
            if (c.hasOwnProperty && c.hasOwnProperty("currentImage")) return c
        }
        return null
    }
    function _firstSaveHint() {
        var s = _firstScreenItem()
        if (!s) return null
        // The Row is a direct child; walk its children to find SaveImageHint
        for (var i = 0; i < s.children.length; i++) {
            var row = s.children[i]
            if (row.children) {
                for (var j = 0; j < row.children.length; j++) {
                    if (row.children[j].showToast) return row.children[j]
                }
            }
        }
        return null
    }

    Component.onCompleted: forceActiveFocus()
}
```

- [ ] **Step 2: Smoke test the full flow (no real unlock)**

Run:
```bash
QT_QPA_PLATFORM=xcb kscreenlocker_greet --testing --theme com.denisk.lockscreen &
sleep 2
# Window is up; you should be able to click it and type
sleep 8
pkill -f kscreenlocker_greet
```

Expected during the 8-second window:
- Clock and "denisk" visible.
- Empty 6 dots in a row under username.
- Typing fills dots.
- Backspace removes.
- Pressing N skips image.
- Pressing S shows "Saved to Pictures" toast and creates `~/Pictures/kde-lockscreen-saves/<something>.jpg`.
- Escape clears PIN.

Verify after:
```bash
ls ~/Pictures/kde-lockscreen-saves/
```

- [ ] **Step 3: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/LockScreenUi.qml
git commit -m "[kde-lockscreen] (F) QML | Full LockScreenUi composition with key routing + save/skip"
```

---

## Task 20: config.xml + config.qml

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/config.xml`
- Create: `/home/denisk/Projects/kde-lockscreen/package/contents/lockscreen/config.qml`

- [ ] **Step 1: Write config.xml (KCfg schema)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0
      http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
    <kcfgfile name=""/>
    <group name="General">
        <entry name="pinLength" type="Int"><default>6</default></entry>
        <entry name="autoSubmit" type="Bool"><default>true</default></entry>
        <entry name="dotSizeMm" type="Double"><default>4.0</default></entry>
        <entry name="blurRadius" type="Int"><default>32</default></entry>
        <entry name="dimAlpha" type="Double"><default>0.4</default></entry>
        <entry name="fitMode" type="String"><default>smart</default></entry>
    </group>
    <group name="Sources">
        <entry name="bing" type="Bool"><default>true</default></entry>
        <entry name="wikimedia" type="Bool"><default>true</default></entry>
        <entry name="nasa" type="Bool"><default>true</default></entry>
        <entry name="usePicsumInstead" type="Bool"><default>true</default></entry>
        <entry name="unsplashApiKey" type="String"><default></default></entry>
    </group>
    <group name="Save">
        <entry name="saveDir" type="String"><default>~/Pictures/kde-lockscreen-saves</default></entry>
    </group>
</kcfg>
```

- [ ] **Step 2: Write config.qml (settings panel)**

```qml
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ColumnLayout {
    id: root
    property alias cfg_pinLength: pinLengthSpin.value
    property alias cfg_autoSubmit: autoSubmitCheck.checked
    property alias cfg_dotSizeMm: dotSizeSpin.value
    property alias cfg_blurRadius: blurSpin.value
    property alias cfg_dimAlpha: dimSpin.value
    property alias cfg_fitMode: fitCombo.currentText
    property alias cfg_bing: bingCheck.checked
    property alias cfg_wikimedia: wikiCheck.checked
    property alias cfg_nasa: nasaCheck.checked
    property alias cfg_usePicsumInstead: picsumCheck.checked
    property alias cfg_unsplashApiKey: keyField.text
    property alias cfg_saveDir: saveDirField.text

    GroupBox {
        title: "PIN"
        Layout.fillWidth: true
        ColumnLayout {
            SpinBox { id: pinLengthSpin; from: 4; to: 8; editable: true }
            CheckBox { id: autoSubmitCheck; text: "Auto-submit at fixed length" }
        }
    }

    GroupBox {
        title: "Appearance"
        Layout.fillWidth: true
        GridLayout {
            columns: 2
            Label { text: "Dot size (mm)" }
            SpinBox { id: dotSizeSpin; from: 2; to: 8; stepSize: 1 }
            Label { text: "Blur radius" }
            SpinBox { id: blurSpin; from: 0; to: 50 }
            Label { text: "Dim alpha" }
            SpinBox { id: dimSpin; from: 0; to: 100; stepSize: 5 }
            Label { text: "Image fit" }
            ComboBox { id: fitCombo; model: ["cover", "contain", "smart"] }
        }
    }

    GroupBox {
        title: "Image sources"
        Layout.fillWidth: true
        ColumnLayout {
            CheckBox { id: bingCheck; text: "Bing Image of the Day" }
            CheckBox { id: wikiCheck; text: "Wikimedia Picture of the Day" }
            CheckBox { id: nasaCheck; text: "NASA APOD" }
            CheckBox { id: picsumCheck; text: "Use Picsum (no API key needed)" }
            Label { text: "Unsplash API key (optional)" }
            TextField { id: keyField; Layout.fillWidth: true }
        }
    }

    GroupBox {
        title: "Save destination"
        Layout.fillWidth: true
        TextField { id: saveDirField; Layout.fillWidth: true }
    }
}
```

- [ ] **Step 3: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add package/contents/lockscreen/config.xml package/contents/lockscreen/config.qml
git commit -m "[kde-lockscreen] (F) QML | KDE config panel schema + UI"
```

---

## Task 21: Sleep-inhibit daemon

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/daemon/kde_lockscreen/inhibitd.py`

- [ ] **Step 1: Write inhibitd.py**

```python
# daemon/kde_lockscreen/inhibitd.py
"""Sleep-inhibit daemon. Watches the screen saver D-Bus signal and holds a
systemd-inhibit lock for sleep/idle while the session is locked. Display DPMS
is explicitly not inhibited.
"""
from __future__ import annotations

import asyncio
import logging
import signal
import subprocess

from dbus_next.aio import MessageBus
from dbus_next import BusType

log = logging.getLogger("kde-lockscreen-inhibitd")


class Inhibitor:
    def __init__(self) -> None:
        self._proc: subprocess.Popen | None = None

    def on(self) -> None:
        if self._proc and self._proc.poll() is None:
            return
        log.info("screen locked — starting systemd-inhibit sleep:idle")
        self._proc = subprocess.Popen([
            "systemd-inhibit",
            "--what=sleep:idle",
            "--why=KDE lock screen active",
            "--mode=block",
            "sleep", "infinity",
        ])

    def off(self) -> None:
        if self._proc and self._proc.poll() is None:
            log.info("screen unlocked — releasing inhibit")
            self._proc.terminate()
            try:
                self._proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self._proc.kill()
        self._proc = None


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    inhib = Inhibitor()

    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    introspection = await bus.introspect("org.freedesktop.ScreenSaver", "/ScreenSaver")
    proxy = bus.get_proxy_object("org.freedesktop.ScreenSaver", "/ScreenSaver", introspection)
    iface = proxy.get_interface("org.freedesktop.ScreenSaver")

    def on_active_changed(active: bool) -> None:
        (inhib.on if active else inhib.off)()

    iface.on_active_changed(on_active_changed)
    log.info("subscribed to org.freedesktop.ScreenSaver.ActiveChanged")

    # Initial state
    try:
        active = await iface.call_get_active()
        if active:
            inhib.on()
    except Exception as exc:
        log.warning("GetActive failed: %s", exc)

    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        asyncio.get_event_loop().add_signal_handler(sig, stop.set)
    await stop.wait()
    inhib.off()


if __name__ == "__main__":
    asyncio.run(main())
```

- [ ] **Step 2: Live smoke test**

Run:
```bash
cd /home/denisk/Projects/kde-lockscreen/daemon
source .venv/bin/activate
python3 -m kde_lockscreen.inhibitd &
INHIB_PID=$!
sleep 2
loginctl lock-session
sleep 3
systemd-inhibit --list | grep -i 'lock screen'
# In a second terminal, unlock manually (or loginctl unlock-session)
loginctl unlock-session
sleep 2
systemd-inhibit --list | grep -i 'lock screen' || echo "OK: inhibit released"
kill $INHIB_PID
```

Expected: `systemd-inhibit --list` shows a "KDE lock screen active" entry while locked; it's gone after unlock.

- [ ] **Step 3: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add daemon/kde_lockscreen/inhibitd.py
git commit -m "[kde-lockscreen] (F) Daemon | Sleep-inhibit daemon with D-Bus subscription"
```

---

## Task 22: systemd units

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/systemd/kde-lockscreen-fetcher.service`
- Create: `/home/denisk/Projects/kde-lockscreen/systemd/kde-lockscreen-fetcher.timer`
- Create: `/home/denisk/Projects/kde-lockscreen/systemd/kde-lockscreen-inhibitd.service`

- [ ] **Step 1: Write kde-lockscreen-fetcher.service**

```ini
[Unit]
Description=KDE lockscreen daily image fetcher
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/lib/kde-lockscreen/venv/bin/python -m kde_lockscreen.fetcher
Nice=10
```

- [ ] **Step 2: Write kde-lockscreen-fetcher.timer**

```ini
[Unit]
Description=Fire the KDE lockscreen image fetcher daily at 06:00

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true
RandomizedDelaySec=15min

[Install]
WantedBy=timers.target
```

- [ ] **Step 3: Write kde-lockscreen-inhibitd.service**

```ini
[Unit]
Description=KDE lockscreen sleep-inhibitor daemon
After=plasma-core.target

[Service]
Type=simple
ExecStart=%h/.local/lib/kde-lockscreen/venv/bin/python -m kde_lockscreen.inhibitd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

- [ ] **Step 4: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add systemd/
git commit -m "[kde-lockscreen] (F) SystemD | User units for fetcher timer + inhibit service"
```

---

## Task 23: Install / uninstall scripts

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/scripts/install.sh`
- Create: `/home/denisk/Projects/kde-lockscreen/scripts/install-dev.sh`
- Create: `/home/denisk/Projects/kde-lockscreen/scripts/uninstall.sh`
- Create: `/home/denisk/Projects/kde-lockscreen/scripts/test-greeter.sh`

- [ ] **Step 1: Write install.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"
DAEMON_DIR="$HOME/.local/lib/kde-lockscreen"
UNIT_DIR="$HOME/.config/systemd/user"
VENV="$DAEMON_DIR/venv"

echo ">> Installing Look-and-Feel package"
rm -rf "$LNF_DIR"
mkdir -p "$(dirname "$LNF_DIR")"
cp -r "$REPO/package" "$LNF_DIR"

echo ">> Installing daemon + venv"
mkdir -p "$DAEMON_DIR"
python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q "$REPO/daemon"

echo ">> Installing systemd user units"
mkdir -p "$UNIT_DIR"
cp "$REPO/systemd/"*.service "$REPO/systemd/"*.timer "$UNIT_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now kde-lockscreen-fetcher.timer kde-lockscreen-inhibitd.service

echo ">> Seeding image cache"
systemctl --user start kde-lockscreen-fetcher.service || true

echo ">> Activating theme"
kwriteconfig5 --file kscreenlockerrc --group Greeter --key Theme com.denisk.lockscreen
kwriteconfig5 --file kscreenlockerrc --group Greeter --key LookAndFeelPackage com.denisk.lockscreen

echo ""
echo ">> PAM optimization (sudo required)"
read -rp "Install optimized /etc/pam.d/kde now? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  sudo "$REPO/scripts/install-pam.sh"
else
  echo ">> Skipped. Run scripts/install-pam.sh later."
fi

echo ">> Done. Test: loginctl lock-session"
```

- [ ] **Step 2: Write install-dev.sh (symlink mode)**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"

echo ">> Symlinking package for live edits"
rm -rf "$LNF_DIR"
mkdir -p "$(dirname "$LNF_DIR")"
ln -s "$REPO/package" "$LNF_DIR"

echo ">> Activating theme"
kwriteconfig5 --file kscreenlockerrc --group Greeter --key Theme com.denisk.lockscreen
kwriteconfig5 --file kscreenlockerrc --group Greeter --key LookAndFeelPackage com.denisk.lockscreen

echo ">> Done. QML edits apply on next lock."
```

- [ ] **Step 3: Write uninstall.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"
DAEMON_DIR="$HOME/.local/lib/kde-lockscreen"
UNIT_DIR="$HOME/.config/systemd/user"

echo ">> Disabling systemd units"
systemctl --user disable --now kde-lockscreen-fetcher.timer kde-lockscreen-inhibitd.service 2>/dev/null || true
rm -f "$UNIT_DIR/kde-lockscreen-fetcher.service" \
      "$UNIT_DIR/kde-lockscreen-fetcher.timer" \
      "$UNIT_DIR/kde-lockscreen-inhibitd.service"
systemctl --user daemon-reload

echo ">> Removing package + daemon"
rm -rf "$LNF_DIR" "$DAEMON_DIR"

echo ">> Reverting theme to Breeze"
kwriteconfig5 --file kscreenlockerrc --group Greeter --key Theme org.kde.breeze.desktop

echo ">> Restoring PAM (most recent backup)"
BACKUP="$(ls -t /etc/pam.d/kde.bak.* 2>/dev/null | head -n1 || true)"
if [[ -n "$BACKUP" ]]; then
  sudo install -m644 "$BACKUP" /etc/pam.d/kde
  echo ">> Restored from $BACKUP"
else
  echo ">> No PAM backup found. Skipping."
fi

echo ">> Done."
```

- [ ] **Step 4: Write test-greeter.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"

if [[ ! -e "$LNF_DIR" ]]; then
  echo "Installing dev symlink first"
  "$REPO/scripts/install-dev.sh"
fi

echo ">> Running kscreenlocker_greet in testing mode"
QT_QPA_PLATFORM=xcb kscreenlocker_greet --testing --theme com.denisk.lockscreen
```

- [ ] **Step 5: Make scripts executable + commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
chmod +x scripts/*.sh
git add scripts/install.sh scripts/install-dev.sh scripts/uninstall.sh scripts/test-greeter.sh
git commit -m "[kde-lockscreen] (F) Install | Install/uninstall/dev/test scripts"
```

---

## Task 24: PAM diagnostic script

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/scripts/pam-diagnose.sh`

- [ ] **Step 1: Write pam-diagnose.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Run this with sudo: sudo $0"
  exit 1
fi

PAM_LIVE="/etc/pam.d/kde"
PAM_TIMED="/etc/pam.d/kde-timed"
LOG="/tmp/pam-time.log"
PROBE="/tmp/pam-time.sh"

if [[ ! -f "$PAM_LIVE" ]]; then
  echo "No $PAM_LIVE — is this Kubuntu with Plasma?"
  exit 1
fi

echo ">> Writing probe"
cat > "$PROBE" <<'EOF'
#!/bin/sh
echo "$(date +%s%N) $PAM_TYPE $PAM_SERVICE $1" >> /tmp/pam-time.log
exit 0
EOF
chmod +x "$PROBE"

echo ">> Building $PAM_TIMED"
rm -f "$LOG"
awk -v probe="$PROBE" '
BEGIN { i = 0 }
/^#/ || /^\s*$/ { print; next }
{
  i++
  printf "auth  optional  pam_exec.so quiet seteuid %s BEFORE_%d\n", probe, i
  print
  printf "auth  optional  pam_exec.so quiet seteuid %s AFTER_%d\n", probe, i
}
' "$PAM_LIVE" > "$PAM_TIMED"

echo ">> Running pamtester x3 with wrong password (expects failures)"
for i in 1 2 3; do
  echo "wrong-password" | pamtester kde-timed "$(logname)" authenticate 2>/dev/null || true
done

echo ""
echo ">> Per-module elapsed times (median of 3 runs):"
python3 - <<'PY'
import collections, statistics
from pathlib import Path

log = Path("/tmp/pam-time.log")
if not log.exists():
    print("No log. Probe did not fire.")
    raise SystemExit(0)

events = [line.split() for line in log.read_text().splitlines() if line.strip()]
deltas = collections.defaultdict(list)
runs = []
run = {}
for ts_s, _type, _svc, tag in events:
    ts = int(ts_s)
    if tag.startswith("BEFORE_"):
        run[tag[7:]] = ts
    elif tag.startswith("AFTER_"):
        i = tag[6:]
        before = run.pop(i, None)
        if before:
            deltas[i].append((ts - before) / 1e6)  # ns → ms

rows = [(int(i), statistics.median(v)) for i, v in deltas.items()]
rows.sort(key=lambda r: -r[1])
for i, ms in rows:
    print(f"  module #{i:>2}: {ms:7.2f} ms")
PY

echo ""
echo ">> Done. Review above. Remove probes: sudo rm $PAM_TIMED $PROBE $LOG"
```

- [ ] **Step 2: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
chmod +x scripts/pam-diagnose.sh
git add scripts/pam-diagnose.sh
git commit -m "[kde-lockscreen] (F) PAM | Diagnostic script for per-module timing"
```

---

## Task 25: Run PAM diagnosis + produce kde.optimized

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/pam/kde.optimized`
- Create: `/home/denisk/Projects/kde-lockscreen/scripts/install-pam.sh`

- [ ] **Step 1: Run diagnostic to find the slow module**

Run:
```bash
sudo /home/denisk/Projects/kde-lockscreen/scripts/pam-diagnose.sh 2>&1 | tee /tmp/pam-diag-output.txt
```

Expected: a list like `module #3: 2845.12 ms` identifying the culprit by line number. Typical suspect (Kubuntu 24.04): a `pam_kwallet5.so` line in the `auth` block.

- [ ] **Step 2: Derive pam/kde.optimized from the live config**

```bash
sudo cp /etc/pam.d/kde /home/denisk/Projects/kde-lockscreen/pam/kde.optimized
sudo chown denisk:denisk /home/denisk/Projects/kde-lockscreen/pam/kde.optimized
```

Open `pam/kde.optimized` and:
- Comment out (prefix with `#`) any `pam_kwallet*.so` line in the `auth` section. Plasma autostart will still open kwallet after login.
- For any network-auth module flagged by the diagnostic (`sss_pam`, `pam_krb5`), change its control flag to `[success=ok default=ignore]` so failures don't add delay.

Verify `auth` section looks minimal. A reasonable target:

```
#%PAM-1.0
auth    required        pam_env.so
auth    include         common-auth
# pam_kwallet disabled for speed — Plasma autostart opens kwallet at login
# auth    optional        pam_kwallet5.so
account include         common-account
password include        common-password
session include         common-session
# session optional        pam_kwallet5.so auto_start
```

- [ ] **Step 3: Write install-pam.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Run this with sudo: sudo $0"
  exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/pam/kde.optimized"
DST="/etc/pam.d/kde"
BAK="$DST.bak.$(date +%Y-%m-%d)"

if [[ ! -f "$SRC" ]]; then
  echo "Missing $SRC — run Task 25 first."
  exit 1
fi

if [[ ! -f "$BAK" ]]; then
  echo ">> Backing up $DST -> $BAK"
  cp "$DST" "$BAK"
fi

echo ">> Installing optimized config"
install -m644 "$SRC" "$DST"

echo ">> Testing with pamtester (wrong password expected to fail quickly)"
time (echo "wrong-password" | pamtester kde "$(logname)" authenticate || true)
echo ""
echo ">> If the timing above is >200ms, re-run pam-diagnose.sh and iterate."
```

- [ ] **Step 4: Test**

Run:
```bash
sudo /home/denisk/Projects/kde-lockscreen/scripts/install-pam.sh
time (echo "wrongpin" | pamtester kde "$(whoami)" authenticate || true)
```

Expected: final `time` output shows `real 0m0.1xxs` or similar (<200 ms).

- [ ] **Step 5: Commit (the optimized config is checked in; it reflects what's running locally)**

```bash
cd /home/denisk/Projects/kde-lockscreen
chmod +x scripts/install-pam.sh
git add pam/kde.optimized scripts/install-pam.sh
git commit -m "[kde-lockscreen] (F) PAM | Optimized /etc/pam.d/kde + install script"
```

---

## Task 26: End-to-end install + real lock test

**Files:** (none new — integration)

- [ ] **Step 1: Clean install**

Run:
```bash
cd /home/denisk/Projects/kde-lockscreen
./scripts/uninstall.sh || true
./scripts/install.sh
```

Expected: seeds cache, enables units, activates theme, prompts for PAM (answer `y`).

- [ ] **Step 2: Verify units are running**

Run:
```bash
systemctl --user status kde-lockscreen-inhibitd.service --no-pager
systemctl --user list-timers | grep kde-lockscreen
```

Expected: inhibitd active (running); timer listed with next firing time.

- [ ] **Step 3: Verify cache seeded**

Run:
```bash
ls -lh ~/.cache/kde-lockscreen/
cat ~/.cache/kde-lockscreen/manifest.json | python3 -m json.tool | head -30
```

Expected: 3-4 JPEGs; manifest has matching entries.

- [ ] **Step 4: Real lock test — full user flow**

Run:
```bash
loginctl lock-session
```

Confirm interactively:
- Clock shows current time.
- Username "denisk" shows.
- 6 empty dots below.
- Start typing your PIN → dots fill, no clicking needed.
- Auto-submit fires at 6 chars → unlocks.
- Time from last keystroke to desktop: < 500 ms perceived, < 200 ms in logs.

Measure:
```bash
journalctl --user -b -t kscreenlocker_greet -t pam --since "1 min ago"
```

- [ ] **Step 5: Skip / save smoke**

Lock again (`loginctl lock-session`). Before typing PIN:
- Press `N` → image on primary screen changes.
- Press `S` → toast "Saved to Pictures"; verify file appears in `~/Pictures/kde-lockscreen-saves/`.
- Click `✕` on secondary screen (if attached) → that screen changes.
- Click `↓` on secondary screen → that screen's image saves.
- Type PIN to unlock.

- [ ] **Step 6: Sleep-inhibit smoke**

Lock the session, leave for 5 minutes. The laptop must NOT suspend. After unlocking and waiting the normal idle-timeout, it SHOULD suspend. Verify with:

```bash
journalctl --user -b -t systemd-logind --since "10 min ago" | grep -i 'suspend\|inhibit'
```

- [ ] **Step 7: Commit integration fixes if any emerged**

If any step above revealed a bug (wrong path, permission issue, etc.), fix the specific file and commit with a descriptive message following the format:

```bash
git add <file>
git commit -m "[kde-lockscreen] (F) <Area> | Fix <specific issue>"
```

---

## Task 27: README + CLAUDE.md

**Files:**
- Create: `/home/denisk/Projects/kde-lockscreen/README.md`
- Create: `/home/denisk/Projects/kde-lockscreen/CLAUDE.md`

- [ ] **Step 1: Write README.md**

```markdown
# KDE Lockscreen

Custom KDE Plasma 5 lock screen for Kubuntu 24.04:
- Fast unlock (<200 ms) via an optimized `/etc/pam.d/kde`.
- Per-monitor rotating backgrounds from Bing, Wikimedia POTD, NASA APOD, and Picsum.
- Type your PIN without clicking — 4-8 mm physical dots show progress.
- "Next image" (N / right arrow) skips the current one; "Save" (S / down arrow) keeps it in `~/Pictures/kde-lockscreen-saves/`.
- Sleep-inhibit daemon keeps the machine awake while locked (display DPMS still works).

## Install

```bash
git clone https://github.com/DenisKhay/kde-lockscreen.git
cd kde-lockscreen
./scripts/install.sh
```

The installer will prompt for sudo at the PAM step (reversible).

## Uninstall

```bash
./scripts/uninstall.sh
```

Restores the Breeze lock screen and the original `/etc/pam.d/kde`.

## Configuration

System Settings → Screen Locking → Configure, or edit `~/.config/kde-lockscreen.conf`. The file wins on conflict.

## Dev loop

```bash
./scripts/install-dev.sh         # symlink mode — edits apply on next lock
./scripts/test-greeter.sh        # run greeter in a window without locking
journalctl --user -fb -t kscreenlocker_greet
```

## Requirements

- Kubuntu 24.04 / KDE Plasma 5.27 / Qt5
- Python 3.11+
- `pamtester`, `plasmapkg2`, `kwriteconfig5` (pre-installed on Kubuntu)
```

- [ ] **Step 2: Write CLAUDE.md**

```markdown
# CLAUDE.md

## What this is

Custom KDE Plasma 5 lock screen on Kubuntu 24.04. A Look-and-Feel package (QML greeter) + two Python user-systemd services + a PAM config replacement.

## Dev commands

```bash
# Dev install (symlink, live QML edits)
./scripts/install-dev.sh

# Preview in a window (no real lock)
./scripts/test-greeter.sh

# Real lock test
loginctl lock-session

# Runtime logs
journalctl --user -fb -t kscreenlocker_greet -t kded5 -t plasmashell

# Daemon tests
cd daemon && source .venv/bin/activate && pytest -v

# PAM benchmark
time (echo wrong | pamtester kde "$(whoami)" authenticate || true)
```

## Architecture

3 pieces (see `docs/superpowers/specs/` for full spec):

1. **QML greeter** — `package/contents/lockscreen/`. Pure reactive. Reads manifest + config. Calls PAM via `authenticator.tryUnlock`.
2. **Fetcher** — `daemon/kde_lockscreen/fetcher.py`. Systemd timer, daily. Pulls 3-4 images, writes cache + manifest.
3. **Inhibitor** — `daemon/kde_lockscreen/inhibitd.py`. Always-on user service. Subscribes to `org.freedesktop.ScreenSaver.ActiveChanged`, holds `systemd-inhibit sleep:idle` while locked.

Plus `/etc/pam.d/kde` replacement (reversible) for speed.

## Known gotchas

- `kscreenlocker_greet` is short-lived (dies on unlock). Don't put persistent state in QML — use the manifest.
- QML `file://` PUT works for writes but is fragile; fall back to shelling out if sandboxing bites.
- Multi-monitor iterates `Qt.application.screens`. Some Qt versions give [{}] on greeter startup — re-read on `screensChanged`.
- PAM changes need `sudo`. `scripts/install-pam.sh` handles backup/install; `scripts/uninstall.sh` restores.
```

- [ ] **Step 3: Commit**

```bash
cd /home/denisk/Projects/kde-lockscreen
git add README.md CLAUDE.md
git commit -m "[kde-lockscreen] (F) Docs | README + CLAUDE.md"
```

---

## Task 28: Final verification checklist

**Files:** (none — verification only)

- [ ] **Step 1: Run full test suite**

```bash
cd /home/denisk/Projects/kde-lockscreen/daemon
source .venv/bin/activate
pytest -v
```

Expected: all tests pass.

- [ ] **Step 2: PAM latency benchmark**

```bash
for i in 1 2 3 4 5; do
  time (echo "wrong-password" | pamtester kde "$(whoami)" authenticate 2>/dev/null || true)
done 2>&1 | grep real
```

Expected: every `real` < 0.2s.

- [ ] **Step 3: Manual smoke on all 7 test steps from the spec**

Walk through spec section 11:
1. test-greeter.sh — window mode ✓
2. install-dev.sh — symlink mode ✓
3. QML error tail — no errors ✓
4. PAM benchmark — under 200ms ✓
5. Real lock flow — PIN works ✓
6. "Next image" — N key replaces ✓
7. "Save image" — S key saves to ~/Pictures/ ✓

- [ ] **Step 4: Git log sanity**

```bash
git log --oneline
```

Expected: a clean sequence of commits, all following the `[kde-lockscreen] (F) <Area> | <desc>` format.

- [ ] **Step 5: Final commit if anything emerged**

No new file required — this task is verification only. If regressions are found, open a new task (not this plan).

---

## Deferred to v2 (not this plan)

- Teams unread indicator — requires extending `teams-notifications` daemon.
- Avatar display alongside username.
- Wayland / Plasma 6 port.
- Hot-reload config without re-locking.
- Multi-user support.
