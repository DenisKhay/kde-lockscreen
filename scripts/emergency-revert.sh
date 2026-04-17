#!/usr/bin/env bash
#
# emergency-revert.sh — escape hatch when our custom theme breaks unlock.
#
# How to use if you're locked out:
#   1. Press Ctrl+Alt+F4 to drop to a TTY (Ctrl+Alt+F1 returns to GUI).
#   2. Log in with username + password (this uses /etc/pam.d/login, NOT
#      /etc/pam.d/kde, so it works even if the lockscreen PAM is wedged).
#   3. Run:  bash ~/Projects/kde-lockscreen/scripts/emergency-revert.sh
#      (or wherever you cloned the repo).
#   4. Press Ctrl+Alt+F1 to return to the locked GUI session, then unlock
#      via the standard Breeze password prompt.
#
# This script ONLY reverts the look-and-feel theme back to Breeze. It does
# NOT touch PAM (install-pam.sh has its own auto-revert if a bad PAM stack
# rejected your password). It does NOT remove the LNF package, so your
# theme files stay installed and you can re-activate later via:
#   kwriteconfig5 --file kscreenlockerrc --group Greeter \
#     --key Theme com.denisk.lockscreen
#   kwriteconfig5 --file kscreenlockerrc --group Greeter \
#     --key LookAndFeelPackage com.denisk.lockscreen

set -euo pipefail

if ! command -v kwriteconfig5 >/dev/null 2>&1; then
  echo "ERROR: kwriteconfig5 not found. Install plasma-workspace." >&2
  exit 1
fi

echo ">> Reverting kscreenlockerrc theme to Breeze"
kwriteconfig5 --file kscreenlockerrc --group Greeter \
  --key Theme org.kde.breeze.desktop
kwriteconfig5 --file kscreenlockerrc --group Greeter \
  --key LookAndFeelPackage org.kde.breeze.desktop

# Try to restart kscreenlockerd so the change takes effect on the NEXT lock
# rather than after a logout. Best-effort — if it's not running we don't
# care, and if the restart fails the next manual lock still picks up the
# new config from disk.
if pgrep -x ksmserver >/dev/null 2>&1; then
  echo ">> Asking kscreenlockerd to re-read its config"
  kquitapp5 kscreenlocker_greet 2>/dev/null || true
  # kscreenlockerd auto-respawns on next lock request; no need to start it.
fi

echo ""
echo ">> Done. Theme is now Breeze."
echo ">> Test: loginctl lock-session"
echo ""
echo ">> To re-enable the custom theme later:"
echo "   kwriteconfig5 --file kscreenlockerrc --group Greeter \\"
echo "     --key Theme com.denisk.lockscreen"
echo "   kwriteconfig5 --file kscreenlockerrc --group Greeter \\"
echo "     --key LookAndFeelPackage com.denisk.lockscreen"
