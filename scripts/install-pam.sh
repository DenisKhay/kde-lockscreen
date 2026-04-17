#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Run this with sudo: sudo $0"
  exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/pam/kscreenlocker.optimized"
DST="/etc/pam.d/kscreenlocker"
BAK="$DST.bak.$(date +%Y-%m-%d)"

if [[ ! -f "$SRC" ]]; then
  echo "Missing $SRC"
  echo "Nothing to install. Check the repo contents."
  exit 1
fi

if [[ -f "$DST" && ! -f "$BAK" ]]; then
  echo ">> Backing up existing $DST -> $BAK"
  cp "$DST" "$BAK"
fi

echo ">> Installing $SRC -> $DST"
install -m644 "$SRC" "$DST"

echo ">> Testing with pamtester (wrong password; DO NOT use fingerprint)"
time (echo "wrong-password" | pamtester kscreenlocker "$(logname)" authenticate || true)
echo ""
echo ">> Target: real time well under 200 ms. If still slow, re-run pam-diagnose.sh."
