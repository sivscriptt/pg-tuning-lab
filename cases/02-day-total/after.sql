-- Same result, written as a range on the raw column.
select count(*), sum(amount)
from core.txns
where posted_at >= date '2026-03-14' and posted_at < date '2026-03-15';
