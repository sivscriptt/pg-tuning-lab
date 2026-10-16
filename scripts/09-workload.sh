#!/usr/bin/env bash
# The story the cases tell, end to end: run an app-like mix with only the original keys,
# find the worst queries in pg_stat_statements, apply every fix, run the same mix again.
#   statement 50%, email search 20%, settlement poll 10%, transfers 20%
source "$(dirname "$0")/lib.sh"
need_up
SECS=${SECS:-30}; CLIENTS=${CLIENTS:-4}
OUT="$RESULTS/09-workload"; mkdir -p "$OUT"
W="$LAB_ROOT/workload"
FIXES="01-statement 03-customer-email 04-pending-queue"
q -f "$LAB_ROOT/sql/transfer.sql" >/dev/null

run() { # run <label>
  q -c "select pg_stat_statements_reset()" >/dev/null
  pgbench -n -c "$CLIENTS" -j "$CLIENTS" -T "$SECS" \
    -f "$W/statement.pgbench@5" -f "$W/email.pgbench@2" -f "$W/pending.pgbench@1" -f "$W/transfer.pgbench@2" \
    > "$OUT/$1-pgbench.txt" 2>&1
  psql -X -v ON_ERROR_STOP=1 -f "$LAB_ROOT/sql/top-queries.sql" > "$OUT/$1-top.txt"
  ok "$1: $(awk '/^tps/ { printf "%.0f TPS", $3 }' "$OUT/$1-pgbench.txt"), $(awk '/^latency average/ { print $4 " ms"; exit }' "$OUT/$1-pgbench.txt") average latency"
}

log "workload with only the original keys (${SECS}s, $CLIENTS clients)"
for c in $FIXES; do q -f "$LAB_ROOT/cases/$c/undo.sql"; done
run before
cat "$OUT/before-top.txt"

log "apply the fixes from cases $FIXES"
for c in $FIXES; do q -f "$LAB_ROOT/cases/$c/fix.sql"; done
q -c "analyze core.txns"
run after
cat "$OUT/after-top.txt"
