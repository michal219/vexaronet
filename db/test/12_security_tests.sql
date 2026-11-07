-- Dopady bezpečnostních oprav (po 02_security_prestate.sql a migraci 20261108100000_bezpecnostni_opravy.sql).
-- Jedna transakce, na konci ROLLBACK.
\set ON_ERROR_STOP on
\pset tuples_only on
begin;
\i db/test/helpers.sql

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0000-0000-0000-0000000000b' || n)::uuid, 'sec' || n || '@example.invalid', now() from generate_series(1, 3) n;
insert into public.companies (id, owner_id, name) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1', 'Firma A'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000b3', 'Firma B');
insert into public.company_members (company_id, user_id, role) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1', 'owner'),
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b2', 'employee'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000b3', 'owner');
insert into public.company_invites (company_id, email) values ('00000000-0000-0000-0000-0000000000d1', 'pozvany@example.invalid');
\set b1 '00000000-0000-0000-0000-0000000000b1'
\set b2 '00000000-0000-0000-0000-0000000000b2'
\set b3 '00000000-0000-0000-0000-0000000000b3'
\set d1 '00000000-0000-0000-0000-0000000000d1'
\set d2 '00000000-0000-0000-0000-0000000000d2'

-- A) RLS na čtyřech tabulkách private ---------------------------------------------------------------
select pg_temp.ok((select bool_and(relrowsecurity) from pg_class where oid in ('private.platform_admins'::regclass, 'private.ai_requests'::regclass, 'private.feedback_mail_delivery'::regclass, 'private.push_deliveries'::regclass)), 'A: RLS zapnuté na všech čtyřech tabulkách private');
select pg_temp.ok(not exists (select 1 from pg_policies where schemaname = 'private' and tablename in ('platform_admins', 'ai_requests', 'feedback_mail_delivery', 'push_deliveries')), 'A: žádné politiky (tedy nikdo kromě vlastníka a rolí s BYPASSRLS)');
-- funkce SECURITY DEFINER vlastněné postgres musí dál fungovat (jako reserve_ai_core, claim_push_core…)
create function public.vxtest_definer() returns bigint language plpgsql security definer set search_path = '' as $$
begin
  insert into private.ai_requests (company_id, user_id) values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1');
  insert into private.push_deliveries default values; insert into private.feedback_mail_delivery default values;
  insert into private.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000000b1');
  return (select count(*) from private.ai_requests) + (select count(*) from private.push_deliveries) + (select count(*) from private.feedback_mail_delivery) + (select count(*) from private.platform_admins);
end $$;
grant execute on function public.vxtest_definer() to authenticated;
select pg_temp.ok((pg_temp.call_as(:'b1', 'authenticated', $q$ select to_jsonb(public.vxtest_definer()) $q$))::text::int = 4, 'A: funkce SECURITY DEFINER dál čtou i zapisují do tabulek s RLS (dopad na reserve_ai, push, platform_admin)');
select pg_temp.expect_as(:'b1', 'authenticated', $q$ select to_jsonb(count(*)) from private.ai_requests $q$, '42501', 'A: authenticated přímo čte jen s právem; bez práva dál nic');
select pg_temp.expect_as(null, 'anon', $q$ select to_jsonb(count(*)) from private.platform_admins $q$, '42501', 'A: anon nečte private.platform_admins');

-- B) práva na tři veřejné tabulky ----------------------------------------------------------------------
select pg_temp.ok((select bool_and(not has_table_privilege('anon', t, p)) from unnest(array['public.ai_usage', 'public.company_invites', 'public.plan_requests']) t,
                    unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) p), 'B: anon nemá žádné právo na ai_usage, company_invites, plan_requests');
select pg_temp.ok(has_table_privilege('authenticated', 'public.ai_usage', 'select') and has_table_privilege('authenticated', 'public.ai_usage', 'insert')
  and has_table_privilege('authenticated', 'public.company_invites', 'select') and has_table_privilege('authenticated', 'public.plan_requests', 'select')
  and has_table_privilege('authenticated', 'public.plan_requests', 'insert'), 'B: authenticated si ponechal práva, která aplikace používá (ai_usage S+I, company_invites S, plan_requests S+I)');
select pg_temp.ok((select bool_and(not has_table_privilege('authenticated', t, p)) from (values ('public.ai_usage'), ('public.company_invites'), ('public.plan_requests')) x(t),
                    unnest(array['update', 'delete', 'truncate', 'references', 'trigger']) p)
                  and not has_table_privilege('authenticated', 'public.company_invites', 'insert'), 'B: authenticated nemá UPDATE, DELETE, TRUNCATE, REFERENCES ani TRIGGER a do company_invites nemůže zapisovat přímo');
select pg_temp.ok(has_table_privilege('service_role', 'public.ai_usage', 'insert') and has_table_privilege('service_role', 'public.company_invites', 'delete'), 'B: service_role beze změny (používají ho serverové funkce)');
-- chování aplikace pod RLS dál funguje
select pg_temp.ok((pg_temp.call_as(:'b1', 'authenticated', format($q$ with i as (insert into public.ai_usage (company_id) values (%L) returning 1) select to_jsonb(count(*)) from i $q$, :'d1')))::text::int = 1, 'B: člen firmy zapíše zpracovaný doklad (AI Účetní)');
select pg_temp.ok((pg_temp.call_as(:'b2', 'authenticated', format($q$ select to_jsonb(count(*)) from public.ai_usage where company_id = %L $q$, :'d1')))::text::int = 1, 'B: zaměstnanec vidí počítadlo své firmy');
select pg_temp.expect_as(:'b1', 'authenticated', format($q$ with i as (insert into public.ai_usage (company_id) values (%L) returning 1) select to_jsonb(count(*)) from i $q$, :'d2'), '42501', 'B: do cizí firmy zapsat nejde (RLS)');
select pg_temp.ok((pg_temp.call_as(:'b1', 'authenticated', format($q$ with i as (insert into public.plan_requests (company_id, requested_plan) values (%L, 'pro') returning 1) select to_jsonb(count(*)) from i $q$, :'d1')))::text::int = 1, 'B: člen odešle žádost o změnu tarifu');
select pg_temp.ok((pg_temp.call_as(:'b1', 'authenticated', $q$ select to_jsonb(count(*)) from public.company_invites $q$))::text::int = 1, 'B: majitel vidí pozvánky své firmy');
select pg_temp.ok((pg_temp.call_as(:'b2', 'authenticated', $q$ select to_jsonb(count(*)) from public.company_invites $q$))::text::int = 0, 'B: zaměstnanec pozvánky nevidí');
select pg_temp.expect_as(:'b1', 'authenticated', format($q$ with u as (update public.plan_requests set status = 'x' where company_id = %L returning 1) select to_jsonb(count(*)) from u $q$, :'d1'), '42501', 'B: žádost o tarif nejde přímo upravit');
select pg_temp.expect_as(null, 'anon', $q$ select to_jsonb(count(*)) from public.ai_usage $q$, '42501', 'B: anon nečte ai_usage');
select pg_temp.expect_as(null, 'anon', format($q$ with i as (insert into public.company_invites (company_id, email) values (%L, 'x@example.invalid') returning 1) select to_jsonb(count(*)) from i $q$, :'d1'), '42501', 'B: anon nezapíše pozvánku');

-- C) funkce -----------------------------------------------------------------------------------------------
select pg_temp.ok((select bool_and(not has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute') and has_function_privilege('service_role', f, 'execute'))
                     from unnest(array['public.clock_in(uuid,uuid)', 'public.clock_out(uuid,uuid)', 'public.shop_cancel_order(uuid)']) f), 'C: anon už funkce nespustí, authenticated a service_role ano');
select pg_temp.ok(not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('public.clock_in(uuid,uuid)'::regprocedure, 'public.clock_out(uuid,uuid)'::regprocedure, 'public.shop_cancel_order(uuid)'::regprocedure) and a.grantee = 0), 'C: PUBLIC už nemá EXECUTE (jinak by ho anon dědil)');
select pg_temp.expect_as(null, 'anon', format($q$ select public.clock_in(%L, null)::text::jsonb $q$, :'d1'), '42501', 'C: anon dostane „permission denied“ už při volání clock_in');
select pg_temp.expect_as(null, 'anon', $q$ select public.shop_cancel_order('00000000-0000-0000-0000-000000000001') $q$, '42501', 'C: anon dostane „permission denied“ i u shop_cancel_order (už nezjistí, zda objednávka existuje)');
select pg_temp.ok((pg_temp.call_as(:'b1', 'authenticated', format($q$ select to_jsonb(public.clock_in(%L, null)::text) $q$, :'d1'))) is not null, 'C: přihlášený člen firmy dál zapíše příchod');
select pg_temp.expect_as(:'b3', 'authenticated', format($q$ select to_jsonb(public.clock_in(%L, null)::text) $q$, :'d1'), 'P0001', 'C: cizí člen dál dostane „Nemate pristup“ (logika funkce nezměněna)');
select pg_temp.ok(has_function_privilege('anon', 'public.public_shop(text)', 'execute'), 'C: záměrně veřejné funkce (e-shop, rezervace) zůstaly dostupné pro anon');

rollback;
\echo VŠECHNY BEZPEČNOSTNÍ TESTY PROŠLY (transakce vrácena)
