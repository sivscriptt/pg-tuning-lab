#!/usr/bin/env bash
# The size argument behind cases 02 and 04: build the "obvious" index next to the one the
# case uses, print both sizes, drop the obvious one.
source "$(dirname "$0")/lib.sh"
need_up
OUT="$RESULTS/10-index-sizes.tsv"; : > "$OUT"
size() { q -c "select pg_size_pretty(pg_relation_size('core.$1'))"; }
cmp() { # cmp <label> <obvious index name> <obvious ddl> <case index name> <case ddl>
  q -c "$3" -c "$5"
  printf '%s\t%s\t%s\n' "$1" "$(size "$2")" "$(size "$4")" | tee -a "$OUT"
  q -c "drop index core.$2" -c "drop index core.$4"
}
log "obvious index vs the one the case uses"
cmp "posted_at: btree vs BRIN" txns_posted_btree "create index txns_posted_btree on core.txns (posted_at)" \
    txns_posted_brin "create index if not exists txns_posted_brin on core.txns using brin (posted_at) with (pages_per_range = 32)"
cmp "pending: full (status, posted_at) vs partial" txns_status_posted "create index txns_status_posted on core.txns (status, posted_at)" \
    txns_pending_idx "create index if not exists txns_pending_idx on core.txns (posted_at) where status = 'pending'"
