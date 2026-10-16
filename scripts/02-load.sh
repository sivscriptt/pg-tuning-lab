#!/usr/bin/env bash
# Build the schema and load it: 500k customers, 1M accounts, 10M transactions.
# Takes a few minutes on a laptop. Drops anything already there.
source "$(dirname "$0")/lib.sh"
need_up
CHUNK=1000000
t0=$(now_ms)

log "schema"
q -f "$LAB_ROOT/sql/schema.sql" >/dev/null
log "customers, accounts"
q -v customers="$CUSTOMERS" -v accounts="$ACCOUNTS" -f "$LAB_ROOT/sql/load.sql" >/dev/null

lo=1
while [ "$lo" -le "$TXNS" ]; do
  hi=$((lo + CHUNK - 1)); [ "$hi" -gt "$TXNS" ] && hi=$TXNS
  q -v lo=$lo -v hi=$hi -v txns="$TXNS" -v accounts="$ACCOUNTS" -f "$LAB_ROOT/sql/load-txns.sql" >/dev/null
  printf '\r     txns %s / %s' "$hi" "$TXNS"
  lo=$((hi + 1))
done
echo

log "balances, vacuum, analyze"
q -c "update core.accounts a set balance = s.total
      from (select account_id, sum(amount) total from core.txns where status <> 'reversed' group by account_id) s
      where s.account_id = a.id" >/dev/null
q -c "vacuum (analyze) core.branches, core.customers, core.accounts, core.txns"
q -c "select pg_stat_statements_reset()" >/dev/null

ok "loaded in $(secs_since "$t0")s"
q -c "select relname || ': ' || to_char(n_live_tup, 'FM999,999,999') || ' rows, ' || pg_size_pretty(pg_total_relation_size(relid))
      from pg_stat_user_tables where schemaname = 'core' order by relname"
