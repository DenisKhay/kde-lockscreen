#!/usr/bin/env bash
set -euo pipefail

LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"
DAEMON_DIR="$HOME/.local/lib/kde-lockscreen"
UNIT_DIR="$HOME/.config/systemd/user"

echo ">> Disabling systemd units"
systemctl --user disable --now kde-lockscreen-fetcher.timer kde-lockscreen-inhibitd.service 2>/dev/null || true
rm -f "$UNIT_DIR/kde-lockscreen-fetcher.service" \
      "$UNIT_DIR/kde-lockscreen-fetcher.timer" \
      "$UNIT_DIR/kde-lockscreen-inhibitd.service"
systemctl --user daemon-reload

echo ">> Removing package + daemon"
rm -rf "$LNF_DIR" "$DAEMON_DIR"

echo ">> Reverting theme to Breeze"
kwriteconfig5 --file kscreenlockerrc --group Greeter --key Theme org.kde.breeze.desktop

echo ">> Restoring PAM (most recent backup)"
BACKUP="$(ls -t /etc/pam.d/kde.bak.* 2>/dev/null | head -n1 || true)"
if [[ -n "$BACKUP" ]]; then
  sudo install -m644 "$BACKUP" /etc/pam.d/kde
  echo ">> Restored from $BACKUP"
else
  echo ">> No PAM backup found. Skipping."
fi

echo ">> Done."
