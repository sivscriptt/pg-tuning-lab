-- One chunk of transactions, ids :lo to :hi. Run in chunks so the load shows progress
-- and no single statement holds gigabytes of WAL.
set synchronous_commit = off;
select setseed(:lo::float / :txns / 2);
insert into core.txns
select i,
       1 + (random() * (:accounts - 1))::bigint,
       ts,
       case k when 'salary' then round((8000 + random() * 30000)::numeric, 2)
              when 'fee'    then -round((5 + random() * 50)::numeric, 2)
              else round(((random() - 0.6) * 4000)::numeric, 2) end,
       k,
       (array['branch','mobile','pos','atm','internet'])[1 + (random() * 4)::int],
       case when ts > timestamptz '2026-09-29' and random() < 0.3 then 'pending'
            when random() < 0.005 then 'reversed'
            else 'posted' end,
       'TX' || lpad(i::text, 10, '0'),
       case when k = 'card' then (array['STO','Sonee','Agora','Coffee Club','Ooredoo','Dhiraagu','Fenaka','MWSC'])[1 + (random() * 7)::int] end
from (
  select i,
         timestamptz '2024-10-01' + (i::float / :txns) * interval '730 days' + random() * interval '10 minutes' ts,
         (array['card','card','card','transfer','transfer','atm','fee','salary'])[1 + (random() * 7)::int] k
  from generate_series(:lo, :hi) i
) s;
