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
