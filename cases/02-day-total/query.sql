-- End of day report. The cast on the column means no index on posted_at can be used.
select count(*), sum(amount)
from core.txns
where posted_at::date = date '2026-03-14';
