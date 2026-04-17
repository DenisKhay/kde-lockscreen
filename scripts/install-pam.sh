#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Run this with sudo: sudo $0"
  exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/pam/kde.optimized"
DST="/etc/pam.d/kde"
BAK="$DST.bak.$(date +%Y-%m-%d)"

if [[ ! -f "$SRC" ]]; then
  echo "Missing $SRC — derive it first from the diagnosis output."
  echo "See the plan Task 25 for the procedure."
  exit 1
fi

if [[ ! -f "$BAK" ]]; then
  echo ">> Backing up $DST -> $BAK"
  cp "$DST" "$BAK"
fi

echo ">> Installing optimized config"
install -m644 "$SRC" "$DST"

echo ">> Testing with pamtester (wrong password expected to fail quickly)"
time (echo "wrong-password" | pamtester kde "$(logname)" authenticate || true)
echo ""
echo ">> If the timing above is >200ms, re-run pam-diagnose.sh and iterate."
