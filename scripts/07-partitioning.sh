#!/usr/bin/env bash
# Copy txns into a table partitioned by month, then compare the two on the jobs where
# partitioning matters: a month-end report and archiving the oldest month.
# The partitioned copy is dropped at the end (KEEP=1 to leave it).
source "$(dirname "$0")/lib.sh"
need_up
OUT="$RESULTS/07-partitioning"; mkdir -p "$OUT"
report() { echo "select kind, count(*), sum(amount) from $1
  where posted_at >= '2026-09-01' and posted_at < '2026-10-01' group by kind"; }

exec_ms() { # exec_ms <sql> : median of 3 under EXPLAIN ANALYZE, rolled back
  local t="" i
  q -c "begin" -c "$1" -c "rollback" >/dev/null
  for i in 1 2 3; do
    t="$t $(psql -X -q -A -t -c begin -c "explain (analyze, buffers) $1" -c rollback | awk '/Execution Time/ { print $3 }')"
  done
  echo $t | tr ' ' '\n' | sort -n | sed -n 2p
}
wal_mb() { # wal_mb <sql> : MB of WAL written by the statement (run, then rolled back)
  psql -X -q -A -t -v ON_ERROR_STOP=1 <<EOF | tail -1
select pg_current_wal_insert_lsn() as a \gset
begin;
$1;
rollback;
select round(pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'a') / 1048576.0, 1);
EOF
}

log "build core.txns_p: one partition per month, Oct 2024 to Sep 2026"
q <<'EOF'
drop table if exists core.txns_p;
create table core.txns_p (like core.txns including defaults) partition by range (posted_at);
do $$
declare m date := '2024-10-01';
begin
  while m < '2026-10-01' loop
    execute format('create table core.txns_p_%s partition of core.txns_p for values from (%L) to (%L)',
                   to_char(m, 'YYYYMM'), m, m + interval '1 month');
    m := m + interval '1 month';
  end loop;
  create table core.txns_p_default partition of core.txns_p default;
end $$;
EOF
t0=$(now_ms)
q -c "set synchronous_commit = off" -c "insert into core.txns_p select * from core.txns"
q -c "alter table core.txns_p add primary key (id, posted_at)" -c "vacuum (analyze) core.txns_p"
ok "copied $(q -c "select to_char(count(*), 'FM99,999,999') from core.txns_p") rows into $(q -c "select count(*) from pg_inherits where inhparent = 'core.txns_p'::regclass") partitions in $(secs_since "$t0")s"

log "month-end report for Sep 2026"
psql -X -q -c "explain (analyze, buffers) $(report core.txns)" > "$OUT/report-plain.txt"
psql -X -q -c "explain (analyze, buffers) $(report core.txns_p)" > "$OUT/report-partitioned.txt"
R1=$(exec_ms "$(report core.txns)"); R2=$(exec_ms "$(report core.txns_p)")
ok "plain table ${R1} ms, partitioned ${R2} ms (partitions scanned: $(grep -oE 'txns_p_[0-9a-z]+' "$OUT/report-partitioned.txt" | sort -u | tr '\n' ' '))"

log "archive the oldest month (Oct 2024)"
OLD="posted_at < '2024-11-01'"
ROWS=$(q -c "select to_char(count(*), 'FM999,999') from core.txns where $OLD")
D_MS=$(exec_ms "delete from core.txns where $OLD")
D_WAL=$(wal_mb "delete from core.txns where $OLD")
ok "DELETE of $ROWS rows: ${D_MS} ms, ${D_WAL} MB of WAL, and every row is left dead for vacuum (rolled back here)"

t0=$(now_ms)
a=$(q -c "select pg_current_wal_insert_lsn()")
q -c "alter table core.txns_p detach partition core.txns_p_202410" -c "drop table core.txns_p_202410"
P_MS=$(awk -v a="$t0" -v b="$(now_ms)" 'BEGIN { print b - a }')
P_KB=$(q -c "select round(pg_wal_lsn_diff(pg_current_wal_insert_lsn(), '$a') / 1024.0, 1)")
ok "DETACH + DROP partition: ${P_MS} ms wall clock, ${P_KB} kB of WAL, nothing left to vacuum"

[ "${KEEP:-0}" = 1 ] || { q -c "drop table core.txns_p"; ok "dropped core.txns_p"; }

cat > "$OUT/summary.tsv" <<EOF
Month-end report, plain table	${R1} ms
Month-end report, partitioned	${R2} ms
Archive 1 month with DELETE ($ROWS rows)	${D_MS} ms, ${D_WAL} MB WAL
Archive 1 month with DETACH + DROP	${P_MS} ms, ${P_KB} kB WAL
EOF
