#!/usr/bin/env bash
#
# screen-off.sh — force the display into DPMS off NOW.
#
# Useful when the screen is locked and PowerDevil's "Turn off screen"
# button action is suppressed by KWin (kscreenlocker greeter is fullscreen
# and animating, so KWin won't transition the display to DPMS off via the
# normal D-Bus path).
#
# This bypasses PowerDevil/KWin and tells X11 directly. Wakes back on the
# next keypress / mouse move / touchpad touch — system stays fully awake,
# only the display is powered down.
#
# Bind to any keyboard shortcut via System Settings → Shortcuts → Custom
# Shortcuts, OR run from a TTY (Ctrl+Alt+F4) when troubleshooting.

set -euo pipefail

DISPLAY="${DISPLAY:-:0}" exec xset dpms force off
