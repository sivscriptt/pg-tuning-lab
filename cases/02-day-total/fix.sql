-- Rows arrive in time order, so a BRIN index (one summary per block range) is enough
-- and is a tiny fraction of the size of a btree.
create index txns_posted_brin on core.txns using brin (posted_at) with (pages_per_range = 32);
