"""Sleep-inhibit daemon + save-request watcher.

Two long-running jobs:
1. Sleep-inhibit: watches `org.freedesktop.ScreenSaver.ActiveChanged` and holds
   a `systemd-inhibit sleep:idle` lock while the screen is locked. DPMS is not
   inhibited on purpose.
2. Save queue: polls `~/.cache/kde-lockscreen/save-request` and copies each
   listed image into `~/Pictures/kde-lockscreen-saves/` using a real filesystem
   copy. The QML greeter writes this file because QML's XMLHttpRequest can't
   safely write binary data.
"""
from __future__ import annotations

import asyncio
import logging
import os
import shutil
import signal
import subprocess
from pathlib import Path

from dbus_next.aio import MessageBus
from dbus_next import BusType

log = logging.getLogger("kde-lockscreen-inhibitd")

CACHE_DIR = Path.home() / ".cache" / "kde-lockscreen"
SAVE_REQ = CACHE_DIR / "save-request"
SAVE_DIR = Path.home() / "Pictures" / "kde-lockscreen-saves"
SAVE_POLL_SECONDS = 0.5


class Inhibitor:
    def __init__(self) -> None:
        self._proc: subprocess.Popen | None = None

    def on(self) -> None:
        if self._proc and self._proc.poll() is None:
            return
        log.info("screen locked - starting systemd-inhibit sleep:idle")
        self._proc = subprocess.Popen([
            "systemd-inhibit",
            "--what=sleep:idle",
            "--why=KDE lock screen active",
            "--mode=block",
            "sleep", "infinity",
        ])

    def off(self) -> None:
        if self._proc and self._proc.poll() is None:
            log.info("screen unlocked - releasing inhibit")
            self._proc.terminate()
            try:
                self._proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self._proc.kill()
        self._proc = None


def _process_save_request() -> None:
    """Read pending save paths, copy each to SAVE_DIR with a stable name,
    then delete the request file. Safe to call repeatedly."""
    if not SAVE_REQ.exists():
        return
    try:
        raw = SAVE_REQ.read_text().strip()
    except OSError as exc:
        log.warning("save-request read failed: %s", exc)
        return

    SAVE_DIR.mkdir(parents=True, exist_ok=True)
    for line in raw.splitlines():
        src_path = line.strip()
        if not src_path:
            continue
        src = Path(src_path)
        if not src.exists():
            log.warning("save source does not exist: %s", src)
            continue
        # Derive target name from the source name directly. If the QML wants
        # a richer name (source-date-hash) it already encodes that in the
        # filename itself, so copy verbatim.
        dst = SAVE_DIR / src.name
        if dst.exists():
            log.info("save target already exists: %s", dst)
            continue
        try:
            shutil.copy2(src, dst)
            log.info("saved %s -> %s (%d bytes)", src.name, dst, dst.stat().st_size)
        except OSError as exc:
            log.warning("save failed for %s: %s", src, exc)

    try:
        SAVE_REQ.unlink()
    except OSError:
        pass


async def _save_watcher(stop: asyncio.Event) -> None:
    while not stop.is_set():
        _process_save_request()
        try:
            await asyncio.wait_for(stop.wait(), timeout=SAVE_POLL_SECONDS)
        except asyncio.TimeoutError:
            pass


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    SAVE_DIR.mkdir(parents=True, exist_ok=True)

    inhib = Inhibitor()

    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    introspection = await bus.introspect("org.freedesktop.ScreenSaver", "/ScreenSaver")
    proxy = bus.get_proxy_object("org.freedesktop.ScreenSaver", "/ScreenSaver", introspection)
    iface = proxy.get_interface("org.freedesktop.ScreenSaver")

    def on_active_changed(active: bool) -> None:
        (inhib.on if active else inhib.off)()

    iface.on_active_changed(on_active_changed)
    log.info("subscribed to org.freedesktop.ScreenSaver.ActiveChanged")

    try:
        active = await iface.call_get_active()
        if active:
            inhib.on()
    except Exception as exc:
        log.warning("GetActive failed: %s", exc)

    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        asyncio.get_event_loop().add_signal_handler(sig, stop.set)

    save_task = asyncio.create_task(_save_watcher(stop))
    try:
        await stop.wait()
    finally:
        save_task.cancel()
        inhib.off()


if __name__ == "__main__":
    asyncio.run(main())
