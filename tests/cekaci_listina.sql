-- Test čekací listiny na prázdné lokální PostgreSQL (nedotýká se žádné živé databáze).
-- Spuštění: createdb t && psql -v ON_ERROR_STOP=1 -d t -f tests/cekaci_listina.sql   (z kořene repozitáře)

do $$ declare r text; begin foreach r in array array['anon','authenticated','service_role'] loop
  if not exists (select 1 from pg_roles where rolname = r) then execute format('create role %I nologin', r); end if; end loop; end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create schema private;
create table public.companies (id uuid primary key default gen_random_uuid(), name text);
create table public.company_members (company_id uuid references public.companies(id), user_id uuid, role text, primary key (company_id, user_id));
create table public.subscriptions (company_id uuid, plan text, status text, trial_end timestamptz, paid_until timestamptz);
create table public.customers (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id), name text, email text, phone text, notes text,
  archived boolean not null default false, created_at timestamptz default now(), billing_address text, ico text, dic text, unique (company_id, id));
create function private.member_role(cid uuid) returns text language sql stable security definer set search_path to '' as $$ select m.role from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and auth.uid() is not null $$;
create function private.writable(cid uuid) returns boolean language sql stable security definer set search_path to '' as $$select auth.uid() is not null and exists(select 1 from public.subscriptions s where s.company_id=cid and ((s.status='trial' and s.trial_end>now()) or (s.status='active' and (s.paid_until>now() or s.plan='start'))))$$;
alter table public.customers enable row level security;
create policy tenant_read on public.customers for select to authenticated using (private.member_role(company_id) is not null);
grant usage on schema public, private, auth to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema private to authenticated;
grant execute on function auth.uid() to anon, authenticated;
create table public.booking_services (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id), name text, duration_minutes int, price numeric, active boolean default true);

\i schema_cekaci_listina.sql
\i schema_cekaci_listina.sql

insert into public.companies (id, name) values ('aaaaaaaa-0000-0000-0000-000000000001','A'), ('bbbbbbbb-0000-0000-0000-000000000001','B'), ('cccccccc-0000-0000-0000-000000000001','C');
insert into public.company_members values
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','owner'),
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a2','employee'),
 ('bbbbbbbb-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b1','owner'),
 ('cccccccc-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c1','owner');
insert into public.subscriptions values ('aaaaaaaa-0000-0000-0000-000000000001','pro','active',null,now()+interval '30 days'),
 ('bbbbbbbb-0000-0000-0000-000000000001','pro','active',null,now()+interval '30 days'),
 ('cccccccc-0000-0000-0000-000000000001','pro','active',null,now()-interval '1 day');
insert into public.customers (id, company_id, name) values
 ('c0000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Zákazník A'),
 ('c0000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000001','Zákazník B');
insert into public.booking_services (id, company_id, name) values
 ('50000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Střih'),
 ('50000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000001','Cizí služba');

create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', u, false); end $$;
create or replace function pg_temp.expect_fail(q text, tag text) returns void language plpgsql as $$ begin
  begin execute q; raise exception 'CHYBA: % mělo selhat', tag; exception when others then if sqlerrm like 'CHYBA:%' then raise; end if; end; end $$;

-- 1) vlastník firmy A přidá čekajícího a vidí ho
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into public.waitlist (company_id, name, email, service_id, wanted) values ('aaaaaaaa-0000-0000-0000-000000000001','Jana','jana@x.cz','50000000-0000-0000-0000-000000000001','po 15:00');
insert into public.waitlist (company_id, name, phone, customer_id) values ('aaaaaaaa-0000-0000-0000-000000000001','Petr','777111222','c0000000-0000-0000-0000-000000000001');
do $$ begin assert (select count(*) from public.waitlist)=2, 'vlastník vidí 2'; assert (select status from public.waitlist where name='Jana')='waiting', 'výchozí stav'; end $$;
-- 2) záznam bez jakéhokoli kontaktu, špatný stav a cizí zákazník/služba se odmítnou
select pg_temp.expect_fail($$insert into public.waitlist (company_id, name) values ('aaaaaaaa-0000-0000-0000-000000000001','Bez kontaktu')$$, 'bez kontaktu');
select pg_temp.expect_fail($$insert into public.waitlist (company_id, name, email, status) values ('aaaaaaaa-0000-0000-0000-000000000001','X','x@x.cz','nic')$$, 'špatný stav');
select pg_temp.expect_fail($$insert into public.waitlist (company_id, name, email, customer_id) values ('aaaaaaaa-0000-0000-0000-000000000001','X','x@x.cz','c0000000-0000-0000-0000-0000000000b1')$$, 'cizí zákazník');
select pg_temp.expect_fail($$insert into public.waitlist (company_id, name, email, service_id) values ('aaaaaaaa-0000-0000-0000-000000000001','X','x@x.cz','50000000-0000-0000-0000-0000000000b1')$$, 'cizí služba');
-- 3) změna stavu
update public.waitlist set status='offered', updated_at=now() where name='Jana';
do $$ begin assert (select status from public.waitlist where name='Jana')='offered', 'stav se změnil'; end $$;
-- 4) zaměstnanec smí číst i zapisovat (pracuje s kalendářem), cizí firma nic nevidí a nezapíše
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
do $$ begin assert (select count(*) from public.waitlist)=2, 'zaměstnanec vidí 2'; end $$;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
do $$ begin assert (select count(*) from public.waitlist)=0, 'cizí firma nevidí nic'; end $$;
select pg_temp.expect_fail($$insert into public.waitlist (company_id, name, email) values ('aaaaaaaa-0000-0000-0000-000000000001','Útok','a@a.cz')$$, 'zápis do cizí firmy');
update public.waitlist set status='dropped';
do $$ begin assert (select count(*) from public.waitlist)=0, 'update cizí firmy nic neudělal'; end $$;
delete from public.waitlist;
-- 5) propadlé předplatné: čtení ano, zápis ne
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.expect_fail($$insert into public.waitlist (company_id, name, email) values ('cccccccc-0000-0000-0000-000000000001','X','x@x.cz')$$, 'zápis s propadlým předplatným');
-- 6) anon nemá přístup; mazání vlastníkem
reset role; set role anon;
select pg_temp.expect_fail($$select * from public.waitlist$$, 'anon čte');
reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
delete from public.waitlist where name='Petr';
do $$ begin assert (select count(*) from public.waitlist)=1, 'smazán jeden'; end $$;
reset role;
-- 7) smazání služby nesmaže čekajícího
delete from public.booking_services where id='50000000-0000-0000-0000-000000000001';
do $$ begin assert (select count(*) from public.waitlist where service_id is null)=1, 'čekající zůstal'; end $$;
\echo OK cekaci_listina
