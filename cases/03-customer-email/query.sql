-- Support desk search. Emails are stored the way customers typed them, so the app
-- compares in lower case, and a plain index on email can't help.
select id, full_name, national_id, phone
from core.customers
where lower(email) = lower('ali.naseem271828@example.mv');
