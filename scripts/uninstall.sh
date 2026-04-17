#!/usr/bin/env bash
set -euo pipefail

LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"
DAEMON_DIR="$HOME/.local/lib/kde-lockscreen"
UNIT_DIR="$HOME/.config/systemd/user"

echo ">> Disabling systemd units"
systemctl --user disable --now \
  kde-lockscreen-fetcher.timer \
  kde-lockscreen-inhibitd.service \
  kde-lockscreen-refill.timer 2>/dev/null || true
rm -f "$UNIT_DIR/kde-lockscreen-fetcher.service" \
      "$UNIT_DIR/kde-lockscreen-fetcher.timer" \
      "$UNIT_DIR/kde-lockscreen-inhibitd.service" \
      "$UNIT_DIR/kde-lockscreen-refill.service" \
      "$UNIT_DIR/kde-lockscreen-refill.timer"
systemctl --user daemon-reload

echo ">> Removing package + daemon"
rm -rf "$LNF_DIR" "$DAEMON_DIR"

echo ">> Reverting theme to Breeze"
kwriteconfig5 --file kscreenlockerrc --group Greeter --key Theme org.kde.breeze.desktop
kwriteconfig5 --file kscreenlockerrc --group Greeter --key LookAndFeelPackage org.kde.breeze.desktop

echo ">> Restoring PAM"
# install-pam.sh writes /etc/pam.d/kscreenlocker and backs up to kscreenlocker.bak.YYYY-MM-DD
BACKUP="$(ls -t /etc/pam.d/kscreenlocker.bak.* 2>/dev/null | head -n1 || true)"
if [[ -n "$BACKUP" ]]; then
  sudo install -m644 "$BACKUP" /etc/pam.d/kscreenlocker
  echo ">> Restored /etc/pam.d/kscreenlocker from $BACKUP"
elif [[ -f /etc/pam.d/kscreenlocker ]]; then
  # No prior backup means the file was created fresh — safer to remove it so
  # PAM falls back to /etc/pam.d/other.
  sudo rm -f /etc/pam.d/kscreenlocker
  echo ">> Removed /etc/pam.d/kscreenlocker (no backup to restore from)"
else
  echo ">> No PAM file to revert. Skipping."
fi

echo ">> Done."
