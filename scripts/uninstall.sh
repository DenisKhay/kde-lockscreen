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
# install-pam.sh writes BOTH /etc/pam.d/kde and /etc/pam.d/kscreenlocker (see
# scripts/install-pam.sh for the why). Restore each symmetrically.
for TARGET in /etc/pam.d/kde /etc/pam.d/kscreenlocker; do
  BACKUP="$(ls -t "${TARGET}".bak.* 2>/dev/null | head -n1 || true)"
  if [[ -n "$BACKUP" ]]; then
    sudo install -m644 "$BACKUP" "$TARGET"
    echo ">> Restored $TARGET from $BACKUP"
  elif [[ -f "$TARGET" ]]; then
    # No prior backup → we created it fresh. Remove it so PAM falls back to
    # /etc/pam.d/other (which is the pre-install state for both paths on
    # Kubuntu 24.04).
    sudo rm -f "$TARGET"
    echo ">> Removed $TARGET (no backup to restore from)"
  else
    echo ">> $TARGET absent and no backup — nothing to do."
  fi
done

echo ">> Done."
