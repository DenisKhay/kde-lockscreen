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
