-- Fills the schema with repeatable fake data. Run by scripts/02-load.sh with
-- -v customers=.. -v accounts=.. -v txns=.. -v chunk=<n> -v chunks=<n>.
-- Transactions run from 1 Oct 2024 to 1 Oct 2026 in id order, like a real ledger.
set synchronous_commit = off;
select setseed(0.42);

insert into core.branches
select i, 'Branch ' || i,
       (array['Male','Hulhumale','Addu','Fuvahmulah','Kulhudhuffushi','Thinadhoo','Naifaru'])[1 + i % 7]
from generate_series(1, 20) i;

insert into core.customers
select i,
       'A' || lpad((100000 + i)::text, 6, '0'),
       fn || ' ' || ln,
       initcap(fn) || '.' || initcap(ln) || i || '@Example.mv',
       '7' || lpad((i % 1000000)::text, 6, '0'),
       1 + i % 20,
       timestamptz '2015-01-01' + (i::float / :customers) * interval '3500 days'
from (
  select i,
         (array['ahmed','mohamed','aishath','fathimath','ibrahim','hassan','mariyam','ali','hawwa','yoosuf'])[1 + (random() * 9)::int] fn,
         (array['shareef','naseem','rasheed','waheed','saeed','zahir','latheef','hameed','fulhu','manik'])[1 + (random() * 9)::int] ln
  from generate_series(1, :customers) i
) s;

insert into core.accounts
select i,
       1 + (i - 1) % :customers,
       1 + i % 20,
       case when random() < 0.8 then 'MVR' else 'USD' end,
       case when random() < 0.9 then 'active' when random() < 0.7 then 'dormant' else 'closed' end,
       timestamptz '2015-01-01' + random() * interval '3500 days',
       0
from generate_series(1, :accounts) i;
