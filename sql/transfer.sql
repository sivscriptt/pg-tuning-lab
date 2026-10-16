-- Two versions of a balance transfer, used by scripts/08-locks.sh.

-- The naive one: lock the payer, then the payee. Two opposite transfers running at the
-- same time each hold one row and wait for the other, and Postgres kills one of them.
create or replace function core.transfer_naive(p_from bigint, p_to bigint, p_amount numeric,
                                               p_pause float default 0)
returns void language plpgsql as $$
begin
  update core.accounts set balance = balance - p_amount where id = p_from;
  perform pg_sleep(p_pause);     -- widens the window so the drill is repeatable
  update core.accounts set balance = balance + p_amount where id = p_to;
end $$;

-- The fix: lock both rows up front, always lowest id first. Every transfer takes locks in
-- the same order, so two of them can make each other wait but never deadlock.
create or replace function core.transfer(p_from bigint, p_to bigint, p_amount numeric,
                                         p_pause float default 0)
returns void language plpgsql as $$
begin
  perform 1 from core.accounts where id in (p_from, p_to) order by id for update;
  update core.accounts set balance = balance - p_amount where id = p_from;
  perform pg_sleep(p_pause);
  update core.accounts set balance = balance + p_amount where id = p_to;
end $$;
