#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LNF_DIR="$HOME/.local/share/plasma/look-and-feel/com.denisk.lockscreen"

if [[ ! -e "$LNF_DIR" ]]; then
  echo "Installing dev symlink first"
  "$REPO/scripts/install-dev.sh"
fi

# kscreenlocker_greet isn't on PATH on Kubuntu — use libexec
GREETER_BIN=""
for candidate in \
    "$(command -v kscreenlocker_greet 2>/dev/null || true)" \
    /usr/lib/x86_64-linux-gnu/libexec/kscreenlocker_greet \
    /usr/libexec/kscreenlocker_greet; do
    if [[ -x "$candidate" ]]; then GREETER_BIN="$candidate"; break; fi
done

if [[ -z "$GREETER_BIN" ]]; then
  echo "kscreenlocker_greet not found" >&2
  exit 1
fi

echo ">> Running $GREETER_BIN in testing mode"
QT_QPA_PLATFORM=xcb "$GREETER_BIN" --testing --theme com.denisk.lockscreen
