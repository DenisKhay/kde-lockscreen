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
