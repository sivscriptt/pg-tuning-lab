# pg-tuning-lab

I wanted to practise query tuning on a table big enough for mistakes to hurt. This is a
banking database with 10 million transactions, loaded with nothing but primary keys, the
way a lot of older systems ship. Each fix is a script: measure the slow query, apply the
fix, measure again.

It runs PostgreSQL 17 on my laptop (M1 MacBook Air, 8 GB). No Docker.

## The data

500,000 customers, 1,000,000 accounts and 10,000,000 transactions over two years. The
transactions table is 1.2 GB. Loading it takes about 90 seconds.

## Find the problem first

Before changing anything, I ran an app-like mix with pgbench for 30 seconds: statements,
customer search, the settlement poll and transfers. Then I checked pg_stat_statements.
Two queries used 98% of the database time: the statement screen (82%) and the pending
poll (16%). So those came first.

|                 | Before   | After fixes |
|-----------------|----------|-------------|
| Throughput      | 4 TPS    | 5,669 TPS   |
| Average latency | 1,035 ms | 0.7 ms      |

## The cases

| Case | Before | After | Fix |
|---|---|---|---|
| Customer statement, last 50 | 428 ms | 0.05 ms | Index on (account_id, posted_at desc) |
| Total for one day | 577 ms | 2.6 ms | Rewrite as a range, BRIN index (144 kB) |
| Customer search by email | 43 ms | 0.03 ms | Index on lower(email) |
| Oldest 100 pending | 487 ms | 0.05 ms | Partial index (200 kB) |
| Page 50,001 with OFFSET | 959 ms | 0.05 ms | Keyset paging, no new index |
| Delete a closed account | 503 ms | 0.3 ms | Index on the foreign key |

What I learned from them:

- **The index alone didn't help the day total.** The query had `posted_at::date = ...`,
  and with the BRIN index added it still took 545 ms. It only used the index after I
  rewrote it as a range. The BRIN index is 144 kB. A normal btree on the same column is
  214 MB.
- **Partial indexes are tiny.** A full index on (status, posted_at) is 301 MB. One that
  only holds pending rows is 200 kB and does the same job.
- **The delete plan looked fine.** All the time was in the foreign key check:
  `Trigger for constraint txns_account_id_fkey: time=502.956`. Postgres doesn't index
  foreign keys for you. The index from the first case fixes this too.

## Partitioning

`07-partitioning.sh` copies the table into 24 monthly partitions and compares.

| Job | Plain table | Partitioned |
|---|---|---|
| Month-end report | 1,132 ms | 32 ms |
| Archive the oldest month (424,611 rows) | DELETE: 1,145 ms, 22.7 MB of WAL, all rows left for vacuum | DETACH + DROP: 96 ms, 41 kB of WAL |

The report gain is partly just reading one month instead of all of them. The BRIN
index from the day total case would help the plain table too. The archive gain is the
one only partitioning gives you.

## Locks and deadlocks

`08-locks.sh` runs two transfers in opposite directions at the same time. Each one locks
its first account and waits for the other, and Postgres kills one after a second. The
server log shows both sides. The fixed function locks both accounts up front, lowest id
first. Then the same two transfers both commit, and one just waits a moment.

It also leaves a transaction open and queues three updates behind it, then runs
`sql/blocking.sql`:

     pid  | blocked_by    | waiting_on         | query
    38494 | {}            | Timeout:PgSleep    | select pg_sleep(6)
    38497 | {38494}       | Lock:transactionid | update core.accounts ...
    38504 | {38497}       | Lock:tuple         | update core.accounts ...
    38509 | {38497,38504} | Lock:tuple         | update core.accounts ...

## Running it

    ./scripts/01-init.sh                 # instance with pg_stat_statements
    ./scripts/02-load.sh                 # 10M transactions
    ./scripts/run-case.sh cases/01-statement
    ./scripts/07-partitioning.sh
    ./scripts/08-locks.sh
    ./scripts/09-workload.sh             # before and after, with pg_stat_statements
    ./scripts/10-index-sizes.sh
    ./scripts/teardown.sh

Plans for every run are saved in `results/`.

## What's next

After the fixes, the statement query still takes 91% of the time. Each account's rows sit
on different pages, so one statement reads about 50 scattered pages. A covering index
would make it an index-only scan, but the index would be much bigger. I haven't decided
if that's worth it.
