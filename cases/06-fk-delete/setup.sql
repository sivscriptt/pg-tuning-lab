-- An account that never had a transaction, so the delete is allowed.
insert into core.accounts (id, customer_id, branch_id, currency, status, opened_at)
values (9999999, 1, 1, 'MVR', 'closed', now())
on conflict (id) do nothing;
