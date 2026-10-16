-- The settlement job polls this every few seconds. Pending rows are well under 1% of the table.
select id, account_id, amount, posted_at
from core.txns
where status = 'pending'
order by posted_at
limit 100;
