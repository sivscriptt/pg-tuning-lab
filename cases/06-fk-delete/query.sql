-- Deleting one account makes Postgres check that no txns row points at it.
-- With no index on txns.account_id that check reads the whole table.
delete from core.accounts where id = 9999999;
