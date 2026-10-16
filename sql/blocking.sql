-- Who is waiting on whom. The first query to run when the app says "the database is slow"
-- and CPU is idle.
select a.pid,
       pg_blocking_pids(a.pid)                       as blocked_by,
       a.state,
       a.wait_event_type || ':' || a.wait_event      as waiting_on,
       round(extract(epoch from now() - a.xact_start)::numeric, 1) as xact_secs,
       left(regexp_replace(a.query, '\s+', ' ', 'g'), 70) as query
from pg_stat_activity a
where a.datname = current_database()
  and a.pid <> pg_backend_pid()
  and (a.state <> 'idle' or a.xact_start is not null)
order by a.xact_start;
