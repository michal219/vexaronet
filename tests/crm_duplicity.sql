-- Test duplicit a slučování zákazníků na prázdné lokální PostgreSQL (nedotýká se žádné živé databáze).
-- Spuštění: createdb t && psql -v ON_ERROR_STOP=1 -d t -f tests/crm_duplicity.sql   (z kořene repozitáře)
-- Tabulky níže jsou zjednodušené náhrady skutečných (stejné sloupce a vazby, které migrace používá). Skutečné triggery
-- (kapacita, audit, odvolání souhlasu) se zde nespouští, ověřte je jednou na vlastním testovacím projektu.

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
create table public.invoices (id uuid primary key default gen_random_uuid());
create table public.jobs (id uuid primary key default gen_random_uuid(), company_id uuid not null, customer_id uuid, title text, foreign key (company_id, customer_id) references public.customers(company_id, id));
create table public.reservations (id uuid primary key default gen_random_uuid(), company_id uuid not null, customer_id uuid, title text, foreign key (company_id, customer_id) references public.customers(company_id, id));
create table public.customer_reviews (id uuid primary key default gen_random_uuid(), company_id uuid not null, customer_id uuid references public.customers(id));
create table public.shop_orders (id uuid primary key default gen_random_uuid(), company_id uuid not null, customer_id uuid references public.customers(id) on delete set null);
create table public.ai_saved_actions (request_id uuid primary key default gen_random_uuid(), company_id uuid not null, customer_id uuid references public.customers(id));
create function private.member_role(cid uuid) returns text language sql stable security definer set search_path to '' as $$ select m.role from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and auth.uid() is not null $$;
create function private.writable(cid uuid) returns boolean language sql stable security definer set search_path to '' as $$select auth.uid() is not null and exists(select 1 from public.subscriptions s where s.company_id=cid and ((s.status='trial' and s.trial_end>now()) or (s.status='active' and (s.paid_until>now() or s.plan='start'))))$$;
alter table public.customers enable row level security;
create policy tenant_read on public.customers for select to authenticated using (private.member_role(company_id) is not null);
grant usage on schema public, private, auth to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema private to authenticated;
grant execute on function auth.uid() to anon, authenticated;

\i schema_crm.sql
\i schema_crm_duplicity.sql
\i schema_crm_duplicity.sql

-- data: firma A (owner oa, zaměstnanec ea), firma B (owner ob)
insert into public.companies (id, name) values ('aaaaaaaa-0000-0000-0000-000000000001','A'), ('bbbbbbbb-0000-0000-0000-000000000001','B');
insert into public.company_members values
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','owner'),
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a2','employee'),
 ('bbbbbbbb-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b1','owner');
insert into public.subscriptions values ('aaaaaaaa-0000-0000-0000-000000000001','pro','active',null,now()+interval '30 days'), ('bbbbbbbb-0000-0000-0000-000000000001','pro','active',null,now()+interval '30 days');
insert into public.customers (id, company_id, name, email, phone, ico, archived, notes) values
 ('c0000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Novák Auto s.r.o.','Info@NovakAuto.cz','+420 602 111 222','12345678',false,'VIP'),
 ('c0000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','Novak Auto','info@novakauto.cz ','602111222','12345678',false,'Platí vždy včas'),
 ('c0000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001','Stavby Dvořák',null,null,'1234567',false,null),
 ('c0000000-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000001','Dvořák stavby',null,null,'01234567',false,null),
 ('c0000000-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000001','Eva',null,'12345',null,false,null),
 ('c0000000-0000-0000-0000-000000000006','aaaaaaaa-0000-0000-0000-000000000001','Eva H.',null,'12345',null,false,null),
 ('c0000000-0000-0000-0000-000000000007','aaaaaaaa-0000-0000-0000-000000000001','Archivovaný','x@y.cz',null,'12345678',true,null),
 ('c0000000-0000-0000-0000-000000000008','aaaaaaaa-0000-0000-0000-000000000001','Samostatný','solo@x.cz','777 000 111','99999999',false,null),
 ('c0000000-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000001','Prázdný 1','', '', '',false,null),
 ('c0000000-0000-0000-0000-00000000000a','aaaaaaaa-0000-0000-0000-000000000001','Prázdný 2','', '', '',false,null),
 ('c0000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000001','Cizí firma','info@novakauto.cz','602111222','12345678',false,null);
insert into public.jobs (company_id, customer_id, title) values
 ('aaaaaaaa-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','Servis 1'), ('aaaaaaaa-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','Servis 2');
insert into public.reservations (company_id, customer_id, title) values ('aaaaaaaa-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','Rezervace');
insert into public.customer_reviews (company_id, customer_id) values ('aaaaaaaa-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002');
insert into public.shop_orders (company_id, customer_id) values ('aaaaaaaa-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002');
insert into public.ai_saved_actions (company_id, customer_id) values ('aaaaaaaa-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002');
insert into public.deals (company_id, customer_id, title) values ('aaaaaaaa-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','Obchod');
insert into public.quotes (company_id, customer_id, title) values ('aaaaaaaa-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','Nabídka');
insert into public.client_notes (company_id, customer_id, body) values ('aaaaaaaa-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','Staré volání');

-- 1) vyhledání duplicit jako vlastník A
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',false);
do $$ declare r record; n int; begin
  select count(*) into n from public.crm_find_duplicates('aaaaaaaa-0000-0000-0000-000000000001');
  raise notice 'skupin duplicit: %', n;
  assert n = 4, 'očekávány 4 skupiny (ico 12345678, ico 01234567, email, telefon), je ' || n;
  assert exists (select 1 from public.crm_find_duplicates('aaaaaaaa-0000-0000-0000-000000000001') where reason='ico' and match_key='12345678' and array_length(customer_ids,1)=2), 'IČO 12345678 má mít 2 zákazníky (bez archivovaného a cizí firmy)';
  assert exists (select 1 from public.crm_find_duplicates('aaaaaaaa-0000-0000-0000-000000000001') where reason='ico' and match_key='01234567'), 'IČO s chybějící nulou se má spárovat';
  assert exists (select 1 from public.crm_find_duplicates('aaaaaaaa-0000-0000-0000-000000000001') where reason='email' and match_key='info@novakauto.cz'), 'e-mail bez ohledu na velikost písmen a mezery';
  assert exists (select 1 from public.crm_find_duplicates('aaaaaaaa-0000-0000-0000-000000000001') where reason='phone' and match_key='602111222'), 'telefon s předvolbou a bez';
  assert not exists (select 1 from public.crm_find_duplicates('aaaaaaaa-0000-0000-0000-000000000001') where 'c0000000-0000-0000-0000-000000000009'::uuid = any(customer_ids)), 'prázdné údaje nejsou duplicita';
  assert not exists (select 1 from public.crm_find_duplicates('aaaaaaaa-0000-0000-0000-000000000001') where 'c0000000-0000-0000-0000-000000000005'::uuid = any(customer_ids)), 'krátký telefon není duplicita';
  assert not exists (select 1 from public.crm_find_duplicates('aaaaaaaa-0000-0000-0000-000000000001') where 'c0000000-0000-0000-0000-0000000000b1'::uuid = any(customer_ids)), 'cizí firma se nesmí objevit';
end $$;

-- 2) oprávnění
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false);
do $$ begin
  begin perform * from public.crm_find_duplicates('aaaaaaaa-0000-0000-0000-000000000001'); raise exception 'MELO_SELHAT';
  exception when insufficient_privilege then null; end;
  begin perform public.crm_merge_customers('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002'); raise exception 'MELO_SELHAT';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',false);
do $$ begin
  begin perform public.crm_merge_customers('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002'); raise exception 'MELO_SELHAT';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set role anon;
do $$ begin
  begin perform public.crm_merge_customers('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002'); raise exception 'MELO_SELHAT';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- 3) sloučení jako vlastník A
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',false);
do $$ begin
  begin perform public.crm_merge_customers('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001'); raise exception 'MELO_SELHAT';
  exception when invalid_parameter_value then null; end;
  begin perform public.crm_merge_customers('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-0000000000b1'); raise exception 'MELO_SELHAT';
  exception when insufficient_privilege then null; end;
  begin perform public.crm_merge_customers('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000007'); raise exception 'MELO_SELHAT';
  exception when invalid_parameter_value then null; end;
end $$;
select public.crm_merge_customers('c0000000-0000-0000-0000-000000000003','c0000000-0000-0000-0000-000000000004') as merge_dvorak \gset
select public.crm_merge_customers('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002') as merge_novak \gset
reset role;
do $$ declare k record; m record; begin
  select * into k from public.customers where id='c0000000-0000-0000-0000-000000000001';
  select * into m from public.customers where id='c0000000-0000-0000-0000-000000000002';
  assert k.name = 'Novák Auto s.r.o.' and k.email = 'Info@NovakAuto.cz', 'ponechaný záznam se nesmí přepsat';
  assert k.notes like 'VIP%Platí vždy včas%', 'poznámky se spojí: ' || k.notes;
  assert m.archived and m.merged_into = k.id, 'sloučený záznam je archivovaný a odkazuje na zachovaný';
  assert (select count(*) from public.jobs where customer_id = k.id) = 2 and (select count(*) from public.jobs where customer_id = m.id) = 0, 'zakázky přesunuty';
  assert (select count(*) from public.reservations where customer_id = k.id) = 1, 'rezervace přesunuty';
  assert (select count(*) from public.customer_reviews where customer_id = k.id) = 1, 'recenze přesunuty';
  assert (select count(*) from public.shop_orders where customer_id = k.id) = 1, 'objednávky e-shopu přesunuty';
  assert (select count(*) from public.ai_saved_actions where customer_id = k.id) = 1, 'AI akce přesunuty';
  assert (select count(*) from public.deals where customer_id = k.id) = 1, 'obchody přesunuty';
  assert (select count(*) from public.quotes where customer_id = k.id) = 1, 'nabídky přesunuty';
  assert (select count(*) from public.client_notes where customer_id = k.id) = 2, 'staré volání + záznam o sloučení';
  assert (select count(*) from public.client_notes where customer_id = k.id and body like 'Sloučeno se záznamem „Novak Auto“%') = 1, 'záznam o sloučení v historii klienta';
  assert (select count(*) from public.customer_merges where kept_id = k.id and merged_id = m.id and merged_snapshot->>'name' = 'Novak Auto') = 1, 'záloha smazaného záznamu';
  assert (select ico from public.customers where id='c0000000-0000-0000-0000-000000000003') = '1234567', 'IČO se nemění';
end $$;
select :'merge_novak'::jsonb -> 'moved' as moved;

-- 4) po sloučení už skupina není, druhé sloučení téhož záznamu selže
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',false);
do $$ declare n int; begin
  select count(*) into n from public.crm_find_duplicates('aaaaaaaa-0000-0000-0000-000000000001');
  assert n = 0, 'po sloučení nemají zůstat žádné duplicity, zbývá ' || n;
  begin perform public.crm_merge_customers('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002'); raise exception 'MELO_SELHAT';
  exception when invalid_parameter_value then null; end;
  assert (select count(*) from public.customer_merges) = 2, 'zaměstnanec/vlastník vidí jen svoje zálohy';
end $$;
reset role;

-- 5) zaměstnanec záloh sloučení nevidí; přímý zápis do customer_merges je zakázán
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',false);
do $$ begin
  assert (select count(*) from public.customer_merges) = 0, 'zaměstnanec nesmí vidět zálohy';
  begin insert into public.customer_merges (company_id,kept_id,merged_id,merged_snapshot) values ('aaaaaaaa-0000-0000-0000-000000000001',gen_random_uuid(),gen_random_uuid(),'{}'); raise exception 'MELO_SELHAT';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- 6) vypršené předplatné: slučování zamítnuto
update public.subscriptions set status='expired', paid_until=now()-interval '1 day' where company_id='aaaaaaaa-0000-0000-0000-000000000001';
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',false);
do $$ begin
  begin perform public.crm_merge_customers('c0000000-0000-0000-0000-000000000005','c0000000-0000-0000-0000-000000000006'); raise exception 'MELO_SELHAT';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
\echo VSECHNY TESTY PROSLY
