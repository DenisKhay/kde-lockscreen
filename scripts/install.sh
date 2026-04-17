#!/usr/bin/env bash
#
# install.sh — deploy the KDE lockscreen onto a user account.
# Idempotent: safe to re-run. Detects existing install and skips done steps.
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"
DAEMON_DIR="$HOME/.local/lib/kde-lockscreen"
UNIT_DIR="$HOME/.config/systemd/user"
VENV="$DAEMON_DIR/venv"
SAVE_DIR="$HOME/Pictures/kde-lockscreen-saves"

# ---- prereq checks ----
_have() { command -v "$1" >/dev/null 2>&1; }

missing=()
_have python3         || missing+=("python3 (install: sudo apt install python3 python3-venv)")
_have kwriteconfig5   || missing+=("kwriteconfig5 (install: sudo apt install plasma-workspace)")
_have kpackagetool5   || missing+=("kpackagetool5 (install: sudo apt install kpackage-tools)")

if ! python3 -c 'import sys; assert sys.version_info >= (3, 11)' 2>/dev/null; then
    missing+=("python3 >= 3.11 (found: $(python3 --version 2>&1))")
fi

if ! python3 -c 'from PIL import Image' 2>/dev/null; then
    echo ">> Pillow not found — installing into --user site for fallback.jpg generation"
    pip3 install --user --quiet Pillow || missing+=("Pillow (install: pip3 install --user Pillow)")
fi

if ((${#missing[@]})); then
    echo "ERROR: missing prerequisites:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
fi

# Plasma version sanity (warn, don't block — user may know what they're doing)
if _have plasmashell; then
    plasma_ver="$(plasmashell --version 2>/dev/null | awk '{print $2}')"
    case "$plasma_ver" in
        5.27.*) ;;
        5.*)    echo "WARN: Plasma $plasma_ver detected; tested on 5.27.x. May work." >&2 ;;
        6.*)    echo "ERROR: Plasma 6 is not supported (QML API version mismatch)." >&2; exit 1 ;;
        *)      echo "WARN: Could not detect Plasma version. Continuing." >&2 ;;
    esac
fi

# ---- generate fallback.jpg if missing ----
if [[ ! -f "$REPO/package/contents/lockscreen/fallback.jpg" ]]; then
    echo ">> Generating fallback gradient"
    python3 -c "
from PIL import Image
img = Image.new('RGB', (1920, 1080))
px = img.load()
for y in range(1080):
    t = y / 1079
    r = int(16 + (8-16)*t); g = int(32 + (20-32)*t); b = int(48 + (32-48)*t)
    for x in range(1920): px[x,y] = (r,g,b)
img.save('$REPO/package/contents/lockscreen/fallback.jpg', quality=85)
"
fi

# ---- install LNF package ----
echo ">> Installing Look-and-Feel package to $LNF_DIR"
mkdir -p "$(dirname "$LNF_DIR")"
rm -rf "$LNF_DIR"
cp -r "$REPO/package" "$LNF_DIR"

# Substitute @HOME@ placeholder in QML files (portable across users)
find "$LNF_DIR/contents" -name '*.qml' -exec sed -i "s|@HOME@|$HOME|g" {} +
echo "   (substituted HOME=$HOME into QML files)"

# ---- daemon venv ----
echo ">> Installing daemon venv at $VENV"
mkdir -p "$DAEMON_DIR"
if [[ ! -x "$VENV/bin/python" ]]; then
    python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet --force-reinstall --no-deps "$REPO/daemon"
"$VENV/bin/pip" install --quiet "$REPO/daemon" >/dev/null  # resolve deps

# ---- systemd --user units ----
echo ">> Installing systemd user units"
mkdir -p "$UNIT_DIR"
cp "$REPO/systemd/"*.service "$REPO/systemd/"*.timer "$UNIT_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now \
    kde-lockscreen-fetcher.timer \
    kde-lockscreen-inhibitd.service \
    kde-lockscreen-refill.timer \
    kde-lockscreen-fprintd-watcher.service

# ---- save dir ----
echo ">> Ensuring save directory exists at $SAVE_DIR"
mkdir -p "$SAVE_DIR"

# ---- seed cache ----
echo ">> Seeding image cache (first run fetches a daily batch)"
systemctl --user start kde-lockscreen-fetcher.service || true

# ---- activate theme ----
echo ">> Activating theme in kscreenlockerrc"
kwriteconfig5 --file kscreenlockerrc --group Greeter --key Theme com.denisk.lockscreen
kwriteconfig5 --file kscreenlockerrc --group Greeter --key LookAndFeelPackage com.denisk.lockscreen

# ---- PAM (optional) ----
echo ""
if [[ -f /etc/pam.d/kscreenlocker ]] && ! diff -q /etc/pam.d/kscreenlocker "$REPO/pam/kscreenlocker.optimized" >/dev/null 2>&1; then
    echo ">> /etc/pam.d/kscreenlocker already exists and differs from our version."
    read -rp "   Overwrite with the optimized version? [y/N] " ans
elif [[ -f /etc/pam.d/kscreenlocker ]]; then
    echo ">> /etc/pam.d/kscreenlocker already installed with our version. Skipping."
    ans=n
else
    echo ">> PAM optimization (recommended — removes the fingerprint-timeout delay)"
    read -rp "   Install /etc/pam.d/kscreenlocker now? (sudo required) [y/N] " ans
fi
if [[ "$ans" =~ ^[Yy]$ ]]; then
    sudo "$REPO/scripts/install-pam.sh"
else
    echo ">> Skipped. Run scripts/install-pam.sh later if you want the speed fix."
fi

echo ""
echo ">> Done. Test with: loginctl lock-session"
