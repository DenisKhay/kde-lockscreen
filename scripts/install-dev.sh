#!/usr/bin/env bash
#
# install-dev.sh — copy (not symlink — Plasma's LNF registry skips symlinks)
# the QML package to the user's LNF dir with @HOME@ substituted. Skips the
# venv/systemd/PAM steps. Useful for fast QML iteration:
#
#   vim package/contents/lockscreen/LockScreenUi.qml
#   ./scripts/install-dev.sh
#   ./scripts/test-greeter.sh
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"

echo ">> Copying package (@HOME@ -> $HOME)"
rm -rf "$LNF_DIR"
mkdir -p "$(dirname "$LNF_DIR")"
cp -r "$REPO/package" "$LNF_DIR"
find "$LNF_DIR/contents" -name '*.qml' -exec sed -i "s|@HOME@|$HOME|g" {} +

echo ">> Activating theme"
kwriteconfig5 --file kscreenlockerrc --group Greeter --key Theme com.denisk.lockscreen
kwriteconfig5 --file kscreenlockerrc --group Greeter --key LookAndFeelPackage com.denisk.lockscreen

echo ">> Done. Run scripts/test-greeter.sh to preview."
