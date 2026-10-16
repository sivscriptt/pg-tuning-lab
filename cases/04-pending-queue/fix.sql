-- Partial index: only pending rows are in it, so it stays small no matter how big txns gets.
create index txns_pending_idx on core.txns (posted_at) where status = 'pending';
