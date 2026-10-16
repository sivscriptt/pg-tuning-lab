-- The queries using the most database time, from pg_stat_statements.
select round(total_exec_time)                          as total_ms,
       calls,
       round(mean_exec_time::numeric, 2)               as mean_ms,
       round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 1) as pct,
       round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 1) as cache_hit_pct,
       left(regexp_replace(query, '\s+', ' ', 'g'), 80) as query
from pg_stat_statements
where dbid = (select oid from pg_database where datname = current_database())
  and query !~* '^(begin|commit|rollback|set|select pg_stat)'
order by total_exec_time desc
limit 6;
