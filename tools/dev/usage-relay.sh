#!/bin/zsh
# Two-stage usage guard: watch the active account's 5-hour usage until it passes
# FIRST_LIMIT, switch to account TARGET with cswap, then exit so the coordinator
# can start `tools/dev/usage-watch.sh SECOND_LIMIT` on the new account.
#   tools/dev/usage-relay.sh 95 2
FIRST_LIMIT=${1:-95}
TARGET=${2:-2}
while true; do
  out=$(cswap status 2>/dev/null)
  acct=$(printf '%s\n' "$out" | sed -n 's/^Status: //p' | head -1)
  pct=$(printf '%s\n' "$out" | sed -n 's/.*5h:[^0-9]*\([0-9][0-9]*\)%.*/\1/p' | head -1)
  echo "$(date +%H:%M) ${pct:-?}% $acct"
  if [ -n "$pct" ] && [ "$pct" -gt "$FIRST_LIMIT" ]; then
    echo "LIMIT REACHED: ${pct}% > ${FIRST_LIMIT}% on $acct; switching to account $TARGET"
    cswap switch "$TARGET" 2>&1 | grep -v "newer version" | tail -3
    cswap status 2>/dev/null | sed -n 's/^Status: //p; /5h:/p' | head -2
    exit 0
  fi
  sleep 60
done
