-- Hranice oprávnění po migraci 20261109100000_zprisneni_prav.sql (po 01_base_stub.sql a 03_hardening_prestate.sql).
-- Každá kontrola běží pod skutečnou rolí anon/authenticated s JWT nárokem, jako přes PostgREST. Jedna transakce, na konci ROLLBACK.
\set ON_ERROR_STOP on
\pset tuples_only on
begin;
\i db/test/helpers.sql

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0000-0000-0000-0000000000c' || n)::uuid, 'hard' || n || '@example.invalid', now() from generate_series(1, 3) n;
insert into public.companies (id, owner_id, name) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Firma A'),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c3', 'Firma B');
insert into public.company_members (company_id, user_id, role) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'owner'),
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c2', 'employee'),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c3', 'owner');
insert into public.products (id, company_id, name) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', 'Zboží A'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e2', 'Zboží B');
insert into public.public_profiles (company_id, published, title) values ('00000000-0000-0000-0000-0000000000e1', true, 'Veřejný A'), ('00000000-0000-0000-0000-0000000000e2', false, 'Skrytý B');
\set c1 '00000000-0000-0000-0000-0000000000c1'
\set c2 '00000000-0000-0000-0000-0000000000c2'
\set c3 '00000000-0000-0000-0000-0000000000c3'

-- A) anon na firemních tabulkách nemá žádné právo (dřív arwdDxtm, chránilo jen RLS) --------------------------
select pg_temp.ok(not has_table_privilege('anon', 'public.products', 'select') and not has_table_privilege('anon', 'public.products', 'insert')
  and not has_table_privilege('anon', 'public.products', 'update') and not has_table_privilege('anon', 'public.products', 'delete')
  and not has_table_privilege('anon', 'public.products', 'truncate') and not has_table_privilege('anon', 'public.shifts', 'truncate'), 'A: anon nemá na products ani shifts žádné právo');
select pg_temp.expect_as(null, 'anon', $q$select to_jsonb(count(*)) from public.products$q$, '42501', 'A: anon nepřečte zboží');
select pg_temp.expect_as(null, 'anon', $q$with i as (insert into public.products (company_id, name) values ('00000000-0000-0000-0000-0000000000e1', 'x')) select '1'::jsonb$q$, '42501', 'A: anon nezapíše zboží');
select pg_temp.expect_as(null, 'anon', $q$with i as (insert into public.companies (owner_id, name) values ('00000000-0000-0000-0000-0000000000c1', 'xx')) select '1'::jsonb$q$, '42501', 'A: anon nezaloží firmu');

-- B) záměrně veřejné zůstává ---------------------------------------------------------------------------
select pg_temp.ok(pg_temp.call_as(null, 'anon', $q$with i as (insert into public.newsletter_subscribers (email, name, consent) values ('novy@example.invalid', 'Nový', true)) select '1'::jsonb$q$) = '1'::jsonb, 'B: anon se přihlásí k novinkám');
select pg_temp.ok(pg_temp.call_as(null, 'anon', $q$with i as (insert into public.custom_inquiries (email, name, message) values ('poptavka@example.invalid', 'Poptávka', 'Dobrý den')) select '1'::jsonb$q$) = '1'::jsonb, 'B: anon odešle poptávku');
select pg_temp.ok(pg_temp.call_as(null, 'anon', $q$select to_jsonb(array_agg(title)) from public.public_profiles$q$) = '["Veřejný A"]'::jsonb, 'B: anon vidí jen zveřejněný profil');
select pg_temp.ok(has_function_privilege('anon', 'public.public_book(text,uuid,timestamptz,text,text,text)', 'execute'), 'B: veřejná rezervace dál spustitelná pro anon');
select pg_temp.expect_as(null, 'anon', $q$select to_jsonb(count(*)) from public.newsletter_subscribers$q$, '42501', 'B: anon nepřečte seznam přihlášených');

-- C) limity formulářů ---------------------------------------------------------------------------------
select pg_temp.expect_as(null, 'anon', $q$with i as (insert into public.custom_inquiries (email, name, message) values ('x@example.invalid', 'X', repeat('a', 4001))) select '1'::jsonb$q$, '42501', 'C: příliš dlouhá poptávka se odmítne');
select pg_temp.expect_as(null, 'anon', $q$with i as (insert into public.custom_inquiries (email, name) values ('bez-zavinace', 'X')) select '1'::jsonb$q$, '42501', 'C: poptávka bez platného e-mailu se odmítne');
select pg_temp.expect_as(null, 'anon', $q$with i as (insert into public.newsletter_subscribers (email, consent) values ('x@example.invalid', false)) select '1'::jsonb$q$, '42501', 'C: novinky bez souhlasu se odmítnou');
select pg_temp.expect_as(null, 'anon', $q$with i as (insert into public.newsletter_subscribers (email, consent, company) values ('x@example.invalid', true, repeat('a', 201))) select '1'::jsonb$q$, '42501', 'C: příliš dlouhý název firmy se odmítne');

-- D) oddělení firem a role (politiky ve tvaru produkce) -------------------------------------------------
select pg_temp.ok(pg_temp.call_as(:'c1', 'authenticated', $q$select to_jsonb(array_agg(name)) from public.products$q$) = '["Zboží A"]'::jsonb, 'D: vlastník A vidí jen zboží své firmy');
select pg_temp.ok(pg_temp.call_as(:'c1', 'authenticated', $q$with u as (update public.products set name = 'změna' where id = '00000000-0000-0000-0000-0000000000f2' returning 1) select to_jsonb(count(*)) from u$q$) = '0'::jsonb, 'D: vlastník A nezmění zboží firmy B ani se znalostí ID');
select pg_temp.expect_as(:'c1', 'authenticated', $q$with i as (insert into public.products (company_id, name) values ('00000000-0000-0000-0000-0000000000e2', 'podstrčené')) select '1'::jsonb$q$, '42501', 'D: vlastník A nezapíše do firmy B změnou company_id');
select pg_temp.expect_as(:'c1', 'authenticated', $q$with u as (update public.products set company_id = '00000000-0000-0000-0000-0000000000e2' where id = '00000000-0000-0000-0000-0000000000f1' returning 1) select to_jsonb(count(*)) from u$q$, '42501', 'D: vlastník A nepřesune své zboží do firmy B');
select pg_temp.ok(pg_temp.call_as(:'c1', 'authenticated', $q$with d as (delete from public.products where id = '00000000-0000-0000-0000-0000000000f2' returning 1) select to_jsonb(count(*)) from d$q$) = '0'::jsonb, 'D: vlastník A nesmaže zboží firmy B');
select pg_temp.ok(pg_temp.call_as(:'c2', 'authenticated', $q$select to_jsonb(count(*)) from public.products$q$) = '1'::jsonb, 'D: zaměstnanec A zboží své firmy vidí');
select pg_temp.expect_as(:'c2', 'authenticated', $q$with i as (insert into public.products (company_id, name) values ('00000000-0000-0000-0000-0000000000e1', 'zaměstnanec')) select '1'::jsonb$q$, '42501', 'D: zaměstnanec zboží nepřidá (jen vlastník a správce)');
select pg_temp.ok(pg_temp.call_as(:'c1', 'authenticated', $q$with i as (insert into public.products (company_id, name) values ('00000000-0000-0000-0000-0000000000e1', 'nové') returning 1) select to_jsonb(count(*)) from i$q$) = '1'::jsonb, 'D: vlastník A dál přidává zboží do své firmy');
select pg_temp.ok(pg_temp.call_as(:'c3', 'authenticated', $q$select to_jsonb(count(*)) from public.company_team('00000000-0000-0000-0000-0000000000e1'::uuid)$q$) = '0'::jsonb, 'D: cizí uživatel nevidí tým firmy A přes RPC');
select pg_temp.expect_as(:'c1', 'authenticated', $q$truncate public.products$q$, '42501', 'D: přihlášený uživatel nemůže TRUNCATE (RLS by ho neomezilo)');

-- E) search_path funkcí SECURITY DEFINER ----------------------------------------------------------------
select pg_temp.ok((select x from pg_proc p, unnest(p.proconfig) x where p.oid = 'public.public_book(text,uuid,timestamptz,text,text,text)'::regprocedure and x like 'search_path=%') = 'search_path=public, pg_temp', 'E: public_book má pg_temp až na konci');
select pg_temp.ok((select x from pg_proc p, unnest(p.proconfig) x where p.oid = 'public.company_team(uuid)'::regprocedure and x like 'search_path=%') = 'search_path=public, auth, pg_temp', 'E: company_team má pg_temp až na konci');
select pg_temp.ok((select x from pg_proc p, unnest(p.proconfig) x where p.oid = 'public.shop_cancel_order(uuid)'::regprocedure and x like 'search_path=%') = 'search_path=""', 'E: funkce se search_path prázdným se nemění');
select pg_temp.ok(pg_temp.call_as(null, 'anon', $q$select public.public_book('x', null, now(), 'a', 'b', null)$q$) ->> 'ok' = 'true', 'E: veřejná funkce po změně dál funguje');

-- F) zálohy pro návrat ----------------------------------------------------------------------------------
select pg_temp.ok((select count(*) from private.deploy_backup_20261109_acl where grantee = 'anon') >= 20, 'F: záloha práv anon existuje');
select pg_temp.ok((select count(*) from private.deploy_backup_20261109_policy) = 2 and (select count(*) from private.deploy_backup_20261109_config) >= 3, 'F: záloha politik a search_path existuje');
select pg_temp.ok(not has_table_privilege('anon', 'private.deploy_backup_20261109_acl', 'select') and not has_table_privilege('authenticated', 'private.deploy_backup_20261109_acl', 'select'), 'F: zálohy nejsou čitelné přes API');

do $$ begin raise notice 'VŠECHNY KONTROLY PROŠLY'; end $$;
rollback;
