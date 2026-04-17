"""Image fetcher for the KDE lockscreen.

Modes:
  daily  — fetch today's curated set (Bing up-to-8 + Wikimedia POTD + NASA APOD)
           plus a Picsum seed buffer. Run by the daily timer.
  refill — fetch a batch of Picsum-only images. Triggered on-demand by the
           systemd .path unit when the lockscreen sees few unseen images left.

Cache policy: cap at `maxCacheSize` (default 100). Eviction prefers removing
older Picsum entries first; Bing/Wikimedia/NASA are preserved within `maxDays`.
"""
from __future__ import annotations

import argparse
import configparser
import hashlib
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
SOURCE_PRIORITY = {"bing": 1, "wikimedia": 2, "nasa": 3, "picsum": 4}


def _load_config(path: Path) -> configparser.ConfigParser:
    cp = configparser.ConfigParser()
    cp.read_dict({
        "Sources": {"bing": "true", "wikimedia": "true", "nasa": "true",
                    "unsplash": "false", "unsplashApiKey": "",
                    "usePicsumInstead": "true"},
        "Cache": {"maxDays": "30", "maxCacheSize": "100",
                  "cacheDir": str(DEFAULT_CACHE),
                  "dailyPicsumSeed": "20", "refillCount": "15"},
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


def _save(data: bytes, meta: dict, cache_dir: Path, manifest: Manifest,
          today: str) -> None:
    url_hash = meta.get("url_hash") or hashlib.md5(
        meta.get("url", "").encode()).hexdigest()[:8]
    date_for_name = meta.get("date") or today
    target = cache_dir / f"{date_for_name}-{meta['source']}-{url_hash}.jpg"
    if target.exists():
        log.debug("already cached: %s", target.name)
        return
    _atomic_write(data, target)
    manifest.add(ImageEntry(
        path=str(target), source=meta["source"],
        date=date_for_name, width=0, height=0,
    ))
    log.info("fetched %s -> %s (%d bytes)", meta["source"], target.name, len(data))


def _run_daily(cfg: configparser.ConfigParser, cache_dir: Path,
               manifest: Manifest, today: str) -> int:
    fail = 0

    if cfg.getboolean("Sources", "bing", fallback=True):
        try:
            for data, meta in bing.fetch_many(count=8):
                _save(data, meta, cache_dir, manifest, today)
        except Exception as exc:
            log.warning("bing failed: %s", exc)
            fail += 1

    if cfg.getboolean("Sources", "wikimedia", fallback=True):
        try:
            data, meta = wikimedia.fetch()
            _save(data, meta, cache_dir, manifest, today)
        except Exception as exc:
            log.warning("wikimedia failed: %s", exc)
            fail += 1

    if cfg.getboolean("Sources", "nasa", fallback=True):
        try:
            data, meta = nasa.fetch()
            _save(data, meta, cache_dir, manifest, today)
        except Exception as exc:
            log.warning("nasa failed: %s", exc)
            fail += 1

    seed = cfg.getint("Cache", "dailyPicsumSeed", fallback=20)
    use_picsum = cfg.getboolean("Sources", "usePicsumInstead", fallback=True)
    key = cfg.get("Sources", "unsplashApiKey", fallback="")
    if seed > 0 and (use_picsum or key):
        for _ in range(seed):
            try:
                data, meta = picsum.fetch(use_picsum=use_picsum, unsplash_key=key)
                _save(data, meta, cache_dir, manifest, today)
            except Exception as exc:
                log.warning("picsum failed: %s", exc)
                fail += 1

    return fail


def _run_refill(cfg: configparser.ConfigParser, cache_dir: Path,
                manifest: Manifest, today: str, count: int) -> int:
    """Top up the Picsum pool so there's always a buffer of unseen images.
    Self-throttles: exits without network work if cache already has plenty
    of Picsums. Triggered either by the 5-min timer or by the refill-request
    file the lockscreen writes when unseen drops below 10."""
    cap = cfg.getint("Cache", "maxCacheSize", fallback=100)
    entries = manifest.list()
    picsum_count = sum(1 for e in entries if e.source == "picsum" and not e.disliked)
    buffer_target = max(20, cap - len([e for e in entries if e.source != "picsum"]))
    if picsum_count >= buffer_target:
        log.info("refill skipped: %d picsum entries already cached (target %d)",
                 picsum_count, buffer_target)
        return 0

    to_fetch = min(count, buffer_target - picsum_count)
    use_picsum = cfg.getboolean("Sources", "usePicsumInstead", fallback=True)
    key = cfg.get("Sources", "unsplashApiKey", fallback="")
    fail = 0
    for _ in range(to_fetch):
        try:
            data, meta = picsum.fetch(use_picsum=use_picsum, unsplash_key=key)
            _save(data, meta, cache_dir, manifest, today)
        except Exception as exc:
            log.warning("picsum refill failed: %s", exc)
            fail += 1
    return fail


def _enforce_cap(manifest: Manifest, cache_dir: Path, cap: int) -> None:
    """Keep manifest at most `cap` entries. Evict oldest Picsum first, then
    oldest entries from lower-priority sources."""
    entries = manifest.list()
    if len(entries) <= cap:
        return
    # Sort: oldest first, lowest-priority first (picsum evicted before bing)
    entries_sorted = sorted(
        entries,
        key=lambda e: (-SOURCE_PRIORITY.get(e.source, 99),  # higher priority → kept longer; invert for pop order
                       e.date)
    )
    remove_count = len(entries) - cap
    to_remove = entries_sorted[:remove_count]
    for e in to_remove:
        try:
            Path(e.path).unlink(missing_ok=True)
        except OSError:
            pass
    kept = [e for e in entries if e.path not in {x.path for x in to_remove}]
    manifest._data.entries = kept
    manifest._save()


def run(mode: str = "daily", config_path: Path = DEFAULT_CONFIG,
        refill_count: int | None = None) -> int:
    cfg = _load_config(config_path)
    cache_dir = Path(os.path.expanduser(
        cfg.get("Cache", "cacheDir", fallback=str(DEFAULT_CACHE))))
    max_days = cfg.getint("Cache", "maxDays", fallback=30)
    max_cache = cfg.getint("Cache", "maxCacheSize", fallback=100)

    manifest = Manifest(cache_dir / "manifest.json")
    today = date.today().isoformat()

    if mode == "daily":
        _run_daily(cfg, cache_dir, manifest, today)
    elif mode == "refill":
        count = refill_count or cfg.getint("Cache", "refillCount", fallback=15)
        _run_refill(cfg, cache_dir, manifest, today, count)
    else:
        log.error("unknown mode: %s", mode)
        return 2

    manifest.evict_older_than(days=max_days, today=today)
    _enforce_cap(manifest, cache_dir, max_cache)

    # Clear the refill-request trigger file so the .path unit can re-arm.
    trigger = cache_dir / "refill-request"
    trigger.unlink(missing_ok=True)

    return 0


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--mode", choices=["daily", "refill"], default="daily")
    parser.add_argument("--count", type=int, default=None,
                        help="For refill mode: how many Picsum images to pull")
    args = parser.parse_args()
    sys.exit(run(mode=args.mode, config_path=args.config,
                 refill_count=args.count))


if __name__ == "__main__":
    main()
