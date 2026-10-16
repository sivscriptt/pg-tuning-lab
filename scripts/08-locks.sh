#!/usr/bin/env bash
# Locking drill.
#   1. Two opposite transfers with the naive function: one is killed by the deadlock detector.
#   2. The same two with the fixed function: one waits for the other, both commit.
#   3. A long open transaction blocking a queue of updates, and the query that shows it.
source "$(dirname "$0")/lib.sh"
need_up
OUT="$RESULTS/08-locks"; mkdir -p "$OUT"
q -f "$LAB_ROOT/sql/transfer.sql" >/dev/null
A=1001; B=2002

# pair <function>: run A->B and B->A at the same time, print how each one ended
pair() {
  local fn=$1 t0
  t0=$(now_ms)
  psql -X -q -c "select core.$fn($A, $B, 10, 1.5)" > "$OUT/$fn-1.txt" 2>&1 & p1=$!
  sleep 0.2
  psql -X -q -c "select core.$fn($B, $A, 10, 1.5)" > "$OUT/$fn-2.txt" 2>&1 & p2=$!
  wait $p1 || true; wait $p2 || true
  for f in "$OUT/$fn-1.txt" "$OUT/$fn-2.txt"; do
    if grep -q 'deadlock detected' "$f"; then echo "killed (deadlock detected)"; else echo "committed"; fi
  done | paste -sd ',' - | sed 's/,/, /'
  echo "     both finished after $(secs_since "$t0")s"
}

log "two opposite transfers, naive lock order"
LOGSTART=$(wc -l < "$LOGS/postgres.log")
echo "     $(pair transfer_naive)"
tail -n +"$((LOGSTART + 1))" "$LOGS/postgres.log" | grep -A4 'deadlock detected' | head -8 > "$OUT/deadlock-log.txt" || true
grep -q 'deadlock detected' "$OUT/deadlock-log.txt" && ok "server log has both sides of the deadlock (results/08-locks/deadlock-log.txt)" \
  || warn "no deadlock this run"

log "the same two transfers, locks taken in id order"
echo "     $(pair transfer)"

log "a forgotten open transaction blocking three updates"
psql -X -q -c "begin" -c "update core.accounts set status = status where id = $A" -c "select pg_sleep(6)" -c "commit" >/dev/null 2>&1 & holder=$!
sleep 0.5
for i in 1 2 3; do
  psql -X -q -c "update core.accounts set balance = balance + $i where id = $A" >/dev/null 2>&1 & sleep 0.3
done
sleep 1.5
psql -X -c "\\pset footer off" -f "$LAB_ROOT/sql/blocking.sql" | tee "$OUT/blocking.txt"
ok "the chain is in blocked_by. The fix in real life: find who owns pid $(awk -F'|' 'NR==3 { gsub(/ /, "", $1); print $1 }' "$OUT/blocking.txt"), then pg_terminate_backend() if they can't commit"
wait
ok "holder committed, queue drained"
