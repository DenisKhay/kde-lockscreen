#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Run this with sudo: sudo $0"
  exit 1
fi

PAM_LIVE="/etc/pam.d/kde"
PAM_TIMED="/etc/pam.d/kde-timed"
LOG="/tmp/pam-time.log"
PROBE="/tmp/pam-time.sh"

if [[ ! -f "$PAM_LIVE" ]]; then
  echo "No $PAM_LIVE — is this Kubuntu with Plasma?"
  exit 1
fi

echo ">> Writing probe to $PROBE"
cat > "$PROBE" <<'EOF'
#!/bin/sh
echo "$(date +%s%N) $PAM_TYPE $PAM_SERVICE $1" >> /tmp/pam-time.log
exit 0
EOF
chmod +x "$PROBE"

echo ">> Building $PAM_TIMED from $PAM_LIVE"
rm -f "$LOG"
awk -v probe="$PROBE" '
BEGIN { i = 0 }
/^#/ || /^\s*$/ { print; next }
{
  i++
  printf "auth  optional  pam_exec.so quiet seteuid %s BEFORE_%d\n", probe, i
  print
  printf "auth  optional  pam_exec.so quiet seteuid %s AFTER_%d\n", probe, i
}
' "$PAM_LIVE" > "$PAM_TIMED"

echo ">> Running pamtester x3 with wrong password (expects failures)"
for i in 1 2 3; do
  echo "wrong-password" | pamtester kde-timed "$(logname)" authenticate 2>/dev/null || true
done

echo ""
echo ">> Per-module elapsed times (median of 3 runs):"
python3 - <<'PY'
import collections, statistics
from pathlib import Path

log = Path("/tmp/pam-time.log")
if not log.exists():
    print("No log. Probe did not fire.")
    raise SystemExit(0)

events = [line.split() for line in log.read_text().splitlines() if line.strip()]
deltas = collections.defaultdict(list)
run = {}
for ts_s, _type, _svc, tag in events:
    ts = int(ts_s)
    if tag.startswith("BEFORE_"):
        run[tag[7:]] = ts
    elif tag.startswith("AFTER_"):
        i = tag[6:]
        before = run.pop(i, None)
        if before:
            deltas[i].append((ts - before) / 1e6)  # ns -> ms

rows = [(int(i), statistics.median(v)) for i, v in deltas.items()]
rows.sort(key=lambda r: -r[1])
for i, ms in rows:
    print(f"  module #{i:>2}: {ms:7.2f} ms")

print("")
print(">> Map module numbers to actual lines:")
import subprocess
pam_live = Path("/etc/pam.d/kde").read_text().splitlines()
i = 0
for line in pam_live:
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    i += 1
    print(f"  #{i:>2}: {line}")
PY

echo ""
echo ">> Done. Cleanup: sudo rm $PAM_TIMED $PROBE $LOG"
