-- The starting point is a schema the way many older systems ship it: primary keys and
-- foreign keys, and no other indexes. Every index in this lab is added by a case, with a
-- measured reason.
drop schema if exists core cascade;
create schema core;

create table core.branches (
  id    int primary key,
  name  text not null,
  atoll text not null
);

create table core.customers (
  id          bigint primary key,
  national_id text   not null unique,          -- A + 6 digits
  full_name   text   not null,
  email       text   not null,                  -- stored as typed, mixed case
  phone       text   not null,
  branch_id   int    not null references core.branches,
  created_at  timestamptz not null
);

create table core.accounts (
  id          bigint primary key,
  customer_id bigint not null references core.customers,
  branch_id   int    not null references core.branches,
  currency    char(3) not null check (currency in ('MVR', 'USD')),
  status      text   not null check (status in ('active', 'dormant', 'closed')),
  opened_at   timestamptz not null,
  balance     numeric(14,2) not null default 0
);

create table core.txns (
  id         bigint primary key,
  account_id bigint not null references core.accounts,
  posted_at  timestamptz not null,
  amount     numeric(14,2) not null,            -- negative = money out
  kind       text not null,                     -- card, transfer, atm, fee, salary
  channel    text not null,                     -- branch, mobile, pos, atm, internet
  status     text not null,                     -- posted, pending, reversed
  ref        text not null,
  merchant   text
);
