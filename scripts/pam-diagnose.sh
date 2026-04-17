#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Run this with sudo: sudo $0"
  exit 1
fi

# Plasma 5.27's kscreenlocker_greet opens PAM service "kde" (hardcoded in
# upstream greeterapp.cpp:139). On Kubuntu 24.04 /etc/pam.d/kde doesn't exist
# by default — PAM falls back to /etc/pam.d/other → common-auth, which
# includes pam_fprintd with a 10s timeout. That fingerprint wait is almost
# certainly the 3+s unlock delay.
#
# Before trusting this assumption on a different machine, verify the real
# service name the greeter is using:
#   journalctl --since '30 min ago' | grep -oE 'kscreenlocker_greet.*pam_unix\([^:]+:auth\)' | head
# The token in parens is what pam_start() was actually called with.

echo ">> Probing journalctl for the real PAM service the greeter opens..."
REAL_SVC="$(journalctl --since '30 min ago' 2>/dev/null \
  | grep -oE 'kscreenlocker_greet.*pam_unix\([^:]+:auth\)' \
  | grep -oE 'pam_unix\([^:]+' | sed 's/pam_unix(//' | sort -u | head -n1 || true)"
if [[ -n "$REAL_SVC" ]]; then
  echo "   journalctl says greeter opened: $REAL_SVC"
  if [[ "$REAL_SVC" != "kde" ]]; then
    echo "   !!! Expected 'kde' on Plasma 5.27. Your KDE build may differ — update SERVICE below."
  fi
else
  echo "   No recent greeter attempt in journal. Trigger a failed unlock, then re-run."
fi

SERVICE="kde"
PAM_LIVE="/etc/pam.d/$SERVICE"
PAM_OTHER="/etc/pam.d/other"
PAM_TIMED="/etc/pam.d/${SERVICE}-timed"
LOG="/tmp/pam-time.log"
PROBE="/tmp/pam-time.sh"

if [[ -f "$PAM_LIVE" ]]; then
  SOURCE_FOR_PROBE="$PAM_LIVE"
  echo ">> Using $PAM_LIVE as the source to profile"
else
  SOURCE_FOR_PROBE="$PAM_OTHER"
  echo ">> $PAM_LIVE does not exist — PAM falls back to $PAM_OTHER"
  echo ">> Profiling $PAM_OTHER instead (plus its @include targets)"
fi

echo ">> Writing probe to $PROBE"
cat > "$PROBE" <<'EOF'
#!/bin/sh
echo "$(date +%s%N) $PAM_TYPE $PAM_SERVICE $1" >> /tmp/pam-time.log
exit 0
EOF
chmod +x "$PROBE"

echo ">> Building $PAM_TIMED"
rm -f "$LOG"

# Inline-expand @include directives so we see per-line timings of the real chain
expand_pam() {
  local file="$1"
  local line name inc
  while IFS= read -r line; do
    case "$line" in
      @include\ *|"@include	"*)
        name="${line#@include }"
        name="${name#"${name%%[![:space:]]*}"}"  # ltrim
        name="${name%% *}"
        inc="/etc/pam.d/${name}"
        if [[ -f "$inc" ]]; then
          echo "# ---- BEGIN @include ${name} ----"
          expand_pam "$inc"
          echo "# ---- END @include ${name} ----"
        else
          echo "$line"
        fi
        ;;
      *)
        echo "$line"
        ;;
    esac
  done < "$file"
}

expand_pam "$SOURCE_FOR_PROBE" | awk -v probe="$PROBE" '
BEGIN { i = 0 }
/^#/ || /^\s*$/ { print; next }
{
  i++
  printf "auth  optional  pam_exec.so quiet seteuid %s BEFORE_%d\n", probe, i
  print
  printf "auth  optional  pam_exec.so quiet seteuid %s AFTER_%d\n", probe, i
}
' > "$PAM_TIMED"

echo ">> Running pamtester x3 with wrong password (expects failures; NO FINGER on reader)"
for i in 1 2 3; do
  echo "wrong-password" | pamtester "${SERVICE}-timed" "$(logname)" authenticate 2>/dev/null || true
done

echo ""
echo ">> Per-module elapsed times (median of 3 runs, longest first):"
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
            deltas[i].append((ts - before) / 1e6)

rows = [(int(i), statistics.median(v)) for i, v in deltas.items()]
rows.sort(key=lambda r: -r[1])
for i, ms in rows[:10]:
    print(f"  module #{i:>2}: {ms:7.2f} ms")

print("")
print(">> Map the top-timing module numbers to their PAM lines:")
import subprocess
expanded = subprocess.run(["bash","-c",
    'source_file=/etc/pam.d/kde; [[ -f "$source_file" ]] || source_file=/etc/pam.d/kscreenlocker; [[ -f "$source_file" ]] || source_file=/etc/pam.d/other;'
    'expand() { while IFS= read -r line; do if [[ "$line" =~ ^@include[[:space:]]+([a-zA-Z0-9_-]+)$ ]]; then expand "/etc/pam.d/${BASH_REMATCH[1]}"; else echo "$line"; fi; done < "$1"; };'
    'expand "$source_file"'
], capture_output=True, text=True).stdout.splitlines()
i = 0
for line in expanded:
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    i += 1
    print(f"  #{i:>2}: {line}")
PY

echo ""
echo ">> Done. Cleanup:"
echo "   sudo rm $PAM_TIMED $PROBE $LOG"
