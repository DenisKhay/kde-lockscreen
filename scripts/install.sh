#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"
DAEMON_DIR="$HOME/.local/lib/kde-lockscreen"
UNIT_DIR="$HOME/.config/systemd/user"
VENV="$DAEMON_DIR/venv"

echo ">> Installing Look-and-Feel package"
rm -rf "$LNF_DIR"
mkdir -p "$(dirname "$LNF_DIR")"
cp -r "$REPO/package" "$LNF_DIR"

echo ">> Installing daemon + venv"
mkdir -p "$DAEMON_DIR"
python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q "$REPO/daemon"

echo ">> Installing systemd user units"
mkdir -p "$UNIT_DIR"
cp "$REPO/systemd/"*.service "$REPO/systemd/"*.timer "$UNIT_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now kde-lockscreen-fetcher.timer kde-lockscreen-inhibitd.service

echo ">> Seeding image cache"
systemctl --user start kde-lockscreen-fetcher.service || true

echo ">> Activating theme"
kwriteconfig5 --file kscreenlockerrc --group Greeter --key Theme com.denisk.lockscreen
kwriteconfig5 --file kscreenlockerrc --group Greeter --key LookAndFeelPackage com.denisk.lockscreen

echo ""
echo ">> PAM optimization (sudo required)"
read -rp "Install optimized /etc/pam.d/kde now? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  sudo "$REPO/scripts/install-pam.sh"
else
  echo ">> Skipped. Run scripts/install-pam.sh later."
fi

echo ">> Done. Test: loginctl lock-session"
