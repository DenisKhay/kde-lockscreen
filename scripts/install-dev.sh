#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"

echo ">> Symlinking package for live edits"
rm -rf "$LNF_DIR"
mkdir -p "$(dirname "$LNF_DIR")"
ln -s "$REPO/package" "$LNF_DIR"

echo ">> Activating theme"
kwriteconfig5 --file kscreenlockerrc --group Greeter --key Theme com.denisk.lockscreen
kwriteconfig5 --file kscreenlockerrc --group Greeter --key LookAndFeelPackage com.denisk.lockscreen

echo ">> Done. QML edits apply on next lock."
