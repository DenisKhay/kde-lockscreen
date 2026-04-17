"""Fingerprint unlock watcher.

Watches logind for session Lock/Unlock signals. While the session is locked,
loops fprintd Verify (re-arming after each timeout / no-match). On a
verify-match, calls logind Session.UnlockSession — kscreenlocker receives the
logind Unlock signal, terminates its greeter process, and releases the lock
without PAM. (See upstream ksldapp.cpp:257 — logind Unlock is an authoritative
unlock path that bypasses PAM entirely.)

Design choice: fingerprint does NOT go through /etc/pam.d/kde. pam_fprintd
doesn't poll pam_conv for typed input and blocks the auth stack for its whole
timeout, so it's a bad fit for continuous fingerprint unlock. Running verify
in a separate watcher with logind-triggered unlock keeps the password path
(<200ms) and the fingerprint path (continuous while locked) fully decoupled.
"""
from __future__ import annotations

import asyncio
import logging
import os
import pwd
import signal

from dbus_next.aio import MessageBus
from dbus_next import BusType, DBusError

log = logging.getLogger("kde-lockscreen-fprintd-watcher")

LOGIND_SERVICE = "org.freedesktop.login1"
LOGIND_MANAGER_PATH = "/org/freedesktop/login1"
LOGIND_MANAGER_IFACE = "org.freedesktop.login1.Manager"
LOGIND_SESSION_IFACE = "org.freedesktop.login1.Session"

FPRINT_SERVICE = "net.reactivated.Fprint"
FPRINT_MANAGER_PATH = "/net/reactivated/Fprint/Manager"
FPRINT_MANAGER_IFACE = "net.reactivated.Fprint.Manager"
FPRINT_DEVICE_IFACE = "net.reactivated.Fprint.Device"


def _username() -> str:
    # os.getlogin() fails when stdin is not a tty (systemd user service case).
    return pwd.getpwuid(os.getuid()).pw_name


class FprintWatcher:
    def __init__(self, bus: MessageBus, username: str) -> None:
        self.bus = bus
        self.username = username
        self._device = None
        self._running = False
        self._task: asyncio.Task | None = None
        self._stop_evt = asyncio.Event()

    async def _device_iface(self):
        if self._device is not None:
            return self._device
        try:
            mgr_intro = await self.bus.introspect(FPRINT_SERVICE, FPRINT_MANAGER_PATH)
        except DBusError as exc:
            log.warning("fprintd unavailable: %s", exc)
            return None
        mgr = self.bus.get_proxy_object(FPRINT_SERVICE, FPRINT_MANAGER_PATH, mgr_intro)
        mgr_iface = mgr.get_interface(FPRINT_MANAGER_IFACE)
        try:
            path = await mgr_iface.call_get_default_device()
        except DBusError as exc:
            log.warning("no fprintd default device: %s", exc)
            return None
        dev_intro = await self.bus.introspect(FPRINT_SERVICE, path)
        dev = self.bus.get_proxy_object(FPRINT_SERVICE, path, dev_intro)
        self._device = dev.get_interface(FPRINT_DEVICE_IFACE)
        log.info("fprintd device: %s", path)
        return self._device

    async def _verify_loop(self) -> None:
        dev = await self._device_iface()
        if dev is None:
            log.info("no fingerprint hardware — watcher idle this cycle")
            return
        try:
            await dev.call_claim(self.username)
        except DBusError as exc:
            log.warning("Claim failed (%s) — no finger enrolled?", exc)
            return

        match_evt = asyncio.Event()

        def on_verify_status(result: str, done: bool) -> None:
            log.debug("VerifyStatus result=%s done=%s", result, done)
            if result == "verify-match":
                match_evt.set()
            elif done:
                # Non-match + done = this verify attempt finished. Restart in
                # the loop below unless we're stopping.
                pass

        dev.on_verify_status(on_verify_status)
        try:
            while self._running:
                match_evt.clear()
                try:
                    await dev.call_verify_start("any")
                except DBusError as exc:
                    log.warning("VerifyStart failed: %s", exc)
                    await asyncio.sleep(1.0)
                    continue

                waiter = asyncio.create_task(match_evt.wait())
                stopper = asyncio.create_task(self._stop_evt.wait())
                _done, pending = await asyncio.wait(
                    {waiter, stopper}, return_when=asyncio.FIRST_COMPLETED
                )
                for p in pending:
                    p.cancel()

                try:
                    await dev.call_verify_stop()
                except DBusError:
                    pass

                if match_evt.is_set() and self._running:
                    log.info("fingerprint match — calling logind UnlockSession")
                    await self._unlock_session()
                    # logind.Unlock signal will flip _running off via stop()
                    break
        finally:
            dev.off_verify_status(on_verify_status)
            try:
                await dev.call_release()
            except DBusError:
                pass

    async def _unlock_session(self) -> None:
        try:
            mgr_intro = await self.bus.introspect(LOGIND_SERVICE, LOGIND_MANAGER_PATH)
            mgr = self.bus.get_proxy_object(LOGIND_SERVICE, LOGIND_MANAGER_PATH, mgr_intro)
            mgr_iface = mgr.get_interface(LOGIND_MANAGER_IFACE)
            session_path = await mgr_iface.call_get_session_by_pid(os.getpid())
            sess_intro = await self.bus.introspect(LOGIND_SERVICE, session_path)
            sess = self.bus.get_proxy_object(LOGIND_SERVICE, session_path, sess_intro)
            sess_iface = sess.get_interface(LOGIND_SESSION_IFACE)
            await sess_iface.call_unlock()
        except DBusError as exc:
            log.error("UnlockSession failed: %s", exc)

    async def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._stop_evt.clear()
        log.info("session locked — starting fingerprint verify loop")
        self._task = asyncio.create_task(self._verify_loop())

    async def stop(self) -> None:
        if not self._running:
            return
        log.info("session unlocked — stopping fingerprint verify loop")
        self._running = False
        self._stop_evt.set()
        if self._task:
            try:
                await asyncio.wait_for(self._task, timeout=2.0)
            except (asyncio.TimeoutError, asyncio.CancelledError):
                pass
            self._task = None


async def _session_iface(bus: MessageBus):
    mgr_intro = await bus.introspect(LOGIND_SERVICE, LOGIND_MANAGER_PATH)
    mgr = bus.get_proxy_object(LOGIND_SERVICE, LOGIND_MANAGER_PATH, mgr_intro)
    mgr_iface = mgr.get_interface(LOGIND_MANAGER_IFACE)
    session_path = await mgr_iface.call_get_session_by_pid(os.getpid())
    log.info("session path: %s", session_path)
    sess_intro = await bus.introspect(LOGIND_SERVICE, session_path)
    sess = bus.get_proxy_object(LOGIND_SERVICE, session_path, sess_intro)
    return sess.get_interface(LOGIND_SESSION_IFACE), sess.get_interface("org.freedesktop.DBus.Properties")


async def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s %(name)s %(message)s",
    )

    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    sess_iface, props_iface = await _session_iface(bus)
    watcher = FprintWatcher(bus, _username())

    def on_lock() -> None:
        asyncio.create_task(watcher.start())

    def on_unlock() -> None:
        asyncio.create_task(watcher.stop())

    sess_iface.on_lock(on_lock)
    sess_iface.on_unlock(on_unlock)
    log.info("subscribed to logind Session Lock/Unlock signals")

    # If the session is already locked at startup (e.g. daemon restart mid-lock),
    # prime the watcher once.
    try:
        variant = await props_iface.call_get(LOGIND_SESSION_IFACE, "LockedHint")
        if variant.value:
            log.info("session already locked at startup — priming watcher")
            on_lock()
    except DBusError as exc:
        log.warning("LockedHint probe failed: %s", exc)

    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        asyncio.get_event_loop().add_signal_handler(sig, stop.set)

    log.info("running")
    try:
        await stop.wait()
    finally:
        await watcher.stop()


if __name__ == "__main__":
    asyncio.run(main())
