#!/bin/zsh
# Polls cswap every 2 minutes; exits (which notifies the coordinator) once the
# active account's 5-hour session usage goes above the limit.
LIMIT=${1:-50}
while true; do
  out=$(cswap status 2>/dev/null)
  acct=$(printf '%s\n' "$out" | sed -n 's/^Status: //p' | head -1)
  pct=$(printf '%s\n' "$out" | sed -n 's/.*5h:[^0-9]*\([0-9][0-9]*\)%.*/\1/p' | head -1)
  echo "$(date +%H:%M) ${pct:-?}% $acct"
  if [ -n "$pct" ] && [ "$pct" -gt "$LIMIT" ]; then
    echo "LIMIT REACHED: 5h session usage ${pct}% > ${LIMIT}% on $acct"
    exit 0
  fi
  sleep 120
done
