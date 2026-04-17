#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Run this with sudo: sudo $0"
  exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/pam/kscreenlocker.optimized"

# Plasma 5.27's kscreenlocker_greet hardcodes PAM service "kde" (see
# greeterapp.cpp:139 upstream). The library's "kscreenlocker" string is a
# different identifier — NOT the PAM service. Installing only to
# /etc/pam.d/kscreenlocker is a no-op for the real unlock path; PAM falls back
# to /etc/pam.d/other → common-auth → pam_fprintd (10s fingerprint timeout).
# We install to BOTH paths: "kde" is load-bearing, "kscreenlocker" keeps the
# pamtester sanity check meaningful and survives any future KDE rename.
TARGETS=(
  "/etc/pam.d/kde"
  "/etc/pam.d/kscreenlocker"
)
DATE_SUFFIX="$(date +%Y-%m-%d)"

if [[ ! -f "$SRC" ]]; then
  echo "Missing $SRC"
  echo "Nothing to install. Check the repo contents."
  exit 1
fi

for DST in "${TARGETS[@]}"; do
  BAK="$DST.bak.$DATE_SUFFIX"
  if [[ -f "$DST" && ! -f "$BAK" ]]; then
    echo ">> Backing up existing $DST -> $BAK"
    cp "$DST" "$BAK"
  fi
  echo ">> Installing $SRC -> $DST"
  install -m644 "$SRC" "$DST"
done

USER_NAME="$(logname)"
echo ""
echo ">> Smoke test 1/2 — wrong password against each service (DO NOT use fingerprint):"
for SVC in kde kscreenlocker; do
  echo ""
  echo "   --- service: $SVC ---"
  time (echo "wrong-password" | pamtester "$SVC" "$USER_NAME" authenticate || true)
done

echo ""
echo ">> Target: real time well under 200 ms for BOTH services."
echo ""
echo ">> Smoke test 2/2 — CORRECT password verification against service 'kde'."
echo "   This catches the case where the wrong-password path happens to fail"
echo "   correctly but the stack rejects valid passwords too (lockout bug)."
echo "   pamtester will prompt for your login password — type it."
echo ""
if pamtester kde "$USER_NAME" authenticate; then
  echo ">> Authentication successful. PAM stack accepts the real password."
  echo ">> Service 'kde' is the one kscreenlocker_greet actually opens at runtime."
  echo ">> Safe to lock the session now. If unlock is still slow, re-run pam-diagnose.sh."
else
  echo ""
  echo "!! AUTHENTICATION FAILED WITH CORRECT PASSWORD — ABORT."
  echo "!! This would lock you out of the real greeter. Reverting both PAM files."
  for DST in "${TARGETS[@]}"; do
    BAK="$DST.bak.$DATE_SUFFIX"
    if [[ -f "$BAK" ]]; then
      install -m644 "$BAK" "$DST"
      echo "   Restored $DST from $BAK"
    else
      rm -f "$DST"
      echo "   Removed $DST (no backup — was absent before install)"
    fi
  done
  echo ""
  echo "!! Reverted. Do NOT lock the session until pam/kscreenlocker.optimized is fixed."
  exit 1
fi
