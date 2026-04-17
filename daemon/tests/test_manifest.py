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
