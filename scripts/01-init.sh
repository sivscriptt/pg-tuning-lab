#!/usr/bin/env bash
# Create and start the instance. Safe to run again: it starts an existing one instead.
source "$(dirname "$0")/lib.sh"
mkdir -p "$LAB_DIR/sock" "$LOGS"

if [ ! -f "$DATA/PG_VERSION" ]; then
  log "initdb at $DATA"
  initdb -D "$DATA" -U postgres --auth=trust --data-checksums >/dev/null
  cat >> "$DATA/postgresql.conf" <<EOF

# ---- pg-tuning-lab ----
port = $PORT
listen_addresses = ''
unix_socket_directories = '$LAB_DIR/sock'
shared_buffers = $SHARED_BUFFERS
work_mem = 16MB
maintenance_work_mem = 256MB
effective_cache_size = 2GB
random_page_cost = 1.1                     # SSD
max_wal_size = 4GB
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = top
track_io_timing = on
compute_query_id = on
log_min_duration_statement = 250           # anything slower than 250 ms goes to the log
log_lock_waits = on
deadlock_timeout = 1s
log_line_prefix = '%m [%p] %q%u@%d '
EOF
fi

if is_up; then ok "already running on port $PORT"
else
  pg_ctl -D "$DATA" -l "$LOGS/postgres.log" -w start >/dev/null
  ok "running on port $PORT"
fi
q -d postgres -c "select 1 from pg_database where datname = 'bank'" | grep -q 1 \
  || q -d postgres -c "create database bank"
q -c "create extension if not exists pg_stat_statements"
ok "database bank ready"
