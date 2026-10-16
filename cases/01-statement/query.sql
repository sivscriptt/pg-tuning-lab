-- The mobile app's statement screen. Runs every time a customer opens an account.
select id, posted_at, amount, kind, merchant, status
from core.txns
where account_id = 424242
order by posted_at desc
limit 50;
