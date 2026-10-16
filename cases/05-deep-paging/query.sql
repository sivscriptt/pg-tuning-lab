-- An export screen that pages with OFFSET. Page 50,001 makes Postgres walk past 5M rows.
select id, posted_at, amount, ref
from core.txns
order by id
offset 5000000 limit 100;
