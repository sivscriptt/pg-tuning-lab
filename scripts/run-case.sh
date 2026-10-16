#!/usr/bin/env bash
# Run one tuning case: measure the slow query, apply the fix, measure again.
#
#   scripts/run-case.sh cases/01-statement        (KEEP=1 to leave the fix in place)
#
# A case folder holds:
#   title      one line for the results table
#   query.sql  the slow query, one statement
#   after.sql  the rewritten query, if the fix is a rewrite (optional)
#   fix.sql    DDL that fixes it (optional)
#   undo.sql   puts things back so the case can run again (optional)
#   setup.sql  run once before measuring (optional)
#
# Each query runs once to warm the cache, then RUNS times under EXPLAIN (ANALYZE, BUFFERS)
# inside a transaction that is rolled back, so a DELETE is safe to measure. The median
# execution time is reported and the last plan is saved under results/<case>/.
source "$(dirname "$0")/lib.sh"
need_up
CASE_DIR=$(cd "${1:?usage: run-case.sh cases/<name>}" && pwd)
NAME=$(basename "$CASE_DIR")
OUT="$RESULTS/$NAME"; mkdir -p "$OUT"
RUNS=${RUNS:-5}

sql_of() { grep -v '^--' "$1" | sed -e 's/;[[:space:]]*$//'; }

# measure <sqlfile> <label>: prints the median execution time in ms
measure() {
  local stmt plan times=""
  stmt=$(sql_of "$1")
  q -c "begin" -c "$stmt" -c "rollback" >/dev/null
  for _ in $(seq 1 "$RUNS"); do
    plan=$(psql -X -q -A -t -v ON_ERROR_STOP=1 -c "begin" \
             -c "explain (analyze, buffers, settings) $stmt" -c "rollback")
    times="$times $(echo "$plan" | awk '/Execution Time/ { print $3 }')"
  done
  printf '%s\n' "$stmt" "" "$plan" > "$OUT/$2.txt"
  echo $times | tr ' ' '\n' | sort -n | awk '{ a[NR] = $1 } END { printf "%.2f", a[int((NR + 1) / 2)] }'
}

index_list() { q -c "select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where n.nspname = 'core' and c.relkind = 'i' order by 1"; }

TITLE=$(cat "$CASE_DIR/title")
log "$NAME: $TITLE"
[ -f "$CASE_DIR/undo.sql" ] && q -f "$CASE_DIR/undo.sql" >/dev/null
[ -f "$CASE_DIR/setup.sql" ] && q -f "$CASE_DIR/setup.sql" >/dev/null

BEFORE=$(measure "$CASE_DIR/query.sql" before)
ok "before: ${BEFORE} ms  ($(grep -m1 -oE '(Parallel )?(Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan)' "$OUT/before.txt"))"

FIX_TIME="-"; NEW_INDEXES="-"
if [ -f "$CASE_DIR/fix.sql" ]; then
  idx0=$(index_list)
  t0=$(now_ms); q -f "$CASE_DIR/fix.sql" >/dev/null; FIX_TIME="$(secs_since "$t0")s"
  NEW_INDEXES=$(comm -13 <(echo "$idx0") <(index_list) | while read -r i; do
    printf '%s (%s) ' "$i" "$(q -c "select pg_size_pretty(pg_relation_size('core.$i'))")"; done)
  ok "fix applied in $FIX_TIME: ${NEW_INDEXES:-no new index}"
fi

AFTER_SQL="$CASE_DIR/query.sql"
if [ -f "$CASE_DIR/after.sql" ]; then
  AFTER_SQL="$CASE_DIR/after.sql"
  if [ -f "$CASE_DIR/fix.sql" ]; then
    SAME=$(measure "$CASE_DIR/query.sql" fix-old-query)
    ok "fix with the old query unchanged: ${SAME} ms"
  fi
fi
AFTER=$(measure "$AFTER_SQL" after)
SPEEDUP=$(awk -v a="$BEFORE" -v b="$AFTER" 'BEGIN { if (b > 0) printf "%.0fx", a / b; else print "-" }')
ok "after:  ${AFTER} ms  ($(grep -m1 -oE '(Parallel )?(Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan)' "$OUT/after.txt"))  ${SPEEDUP} faster"

if [ "${KEEP:-0}" != 1 ] && [ -f "$CASE_DIR/undo.sql" ]; then q -f "$CASE_DIR/undo.sql" >/dev/null; fi

# One line per case in results/summary.tsv, newest run wins.
SUMMARY="$RESULTS/summary.tsv"; touch "$SUMMARY"
grep -v "^$NAME	" "$SUMMARY" > "$SUMMARY.tmp" || true
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$NAME" "$TITLE" "$BEFORE" "$AFTER" "$SPEEDUP" "${NEW_INDEXES% }" "$FIX_TIME" >> "$SUMMARY.tmp"
sort "$SUMMARY.tmp" > "$SUMMARY"; rm "$SUMMARY.tmp"
