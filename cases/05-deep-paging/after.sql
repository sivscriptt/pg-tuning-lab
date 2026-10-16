-- Keyset paging: remember the last id from the previous page and start from there.
select id, posted_at, amount, ref
from core.txns
where id > 5000000
order by id
limit 100;
