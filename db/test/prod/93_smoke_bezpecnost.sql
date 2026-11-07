-- PRODUKČNÍ kontrola (jedna dávka, vždy skončí vrácením transakce, v databázi nezůstane nic).
-- Úspěch = chyba "SMOKE_OK ...". Selhání = chyba "TEST_FAIL ...". Bez příkazů psql, spouští se přes API.
-- Fáze 3: bezpečnostní opravy (po migraci 20261108100000_bezpecnostni_opravy)
create function pg_temp.call_as(uid uuid, r text, q text) returns jsonb language plpgsql as $$
declare res jsonb;
begin
  perform set_config('request.jwt.claims',
    case when uid is null then json_build_object('role', r)::text else json_build_object('sub', uid, 'role', r)::text end, true);
  execute format('set local role %I', r);
  execute q into res;
  execute 'reset role';
  return res;
end $$;

create function pg_temp.expect_as(uid uuid, r text, q text, state text, label text, must_detail text default null) returns void language plpgsql as $$
declare d text;
begin
  begin
    perform pg_temp.call_as(uid, r, q);
    raise exception 'TEST_FAIL %: očekávána chyba %, ale příkaz proběhl', label, state using errcode = 'XX999';
  exception when others then
    execute 'reset role';
    if sqlstate = 'XX999' then raise; end if;
    get stacked diagnostics d = pg_exception_detail;
    if sqlstate <> state then
      raise exception 'TEST_FAIL %: očekáván SQLSTATE %, je % (%)', label, state, sqlstate, sqlerrm using errcode = 'XX999';
    end if;
    if must_detail is not null and position(must_detail in coalesce(d, '') || ' ' || sqlerrm) = 0 then
      raise exception 'TEST_FAIL %: v detailu chybí "%", detail="%"', label, must_detail, d using errcode = 'XX999';
    end if;
  end;
  raise notice 'ok  %', label;
end $$;

create function pg_temp.ok(cond boolean, label text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'TEST_FAIL %', label using errcode = 'XX999'; end if;
  raise notice 'ok  %', label;
end $$;


create function pg_temp.not_denied(uid uuid, r text, q text, label text) returns void language plpgsql as $$
begin
  begin perform pg_temp.call_as(uid, r, q);
  exception when others then
    execute 'reset role';
    if sqlstate = '42501' then raise exception 'TEST_FAIL %: neočekávané odepření práva (%)', label, sqlerrm using errcode = 'XX999'; end if;
  end;
  raise notice 'ok  %', label;
end $$;
create temp table smk (k text primary key, v jsonb);

insert into auth.users (id, email, email_confirmed_at) values
  ('deadbeef-0000-4000-8000-000000000001', 'vx-smoke-1@example.invalid', now()),
  ('deadbeef-0000-4000-8000-000000000002', 'vx-smoke-2@example.invalid', now()),
  ('deadbeef-0000-4000-8000-000000000003', 'vx-smoke-3@example.invalid', now()),
  ('deadbeef-0000-4000-8000-000000000004', 'vx-smoke-4@example.invalid', now());
insert into public.companies (id, owner_id, name) values
  ('deadbeef-0000-4000-8000-0000000000c1', 'deadbeef-0000-4000-8000-000000000001', 'SMOKE TEST firma'),
  ('deadbeef-0000-4000-8000-0000000000c2', 'deadbeef-0000-4000-8000-000000000004', 'SMOKE TEST start');
insert into public.company_members (company_id, user_id, role) values
  ('deadbeef-0000-4000-8000-0000000000c1', 'deadbeef-0000-4000-8000-000000000001', 'owner'),
  ('deadbeef-0000-4000-8000-0000000000c1', 'deadbeef-0000-4000-8000-000000000002', 'employee'),
  ('deadbeef-0000-4000-8000-0000000000c2', 'deadbeef-0000-4000-8000-000000000004', 'owner');
insert into public.subscriptions (company_id, plan, status, trial_end) values ('deadbeef-0000-4000-8000-0000000000c1', 'pro', 'trial', now() + interval '20 days');
insert into public.subscriptions (company_id, plan, status) values ('deadbeef-0000-4000-8000-0000000000c2', 'start', 'active');

select pg_temp.ok((select bool_and(relrowsecurity) from pg_class where oid in ('private.platform_admins'::regclass,'private.ai_requests'::regclass,'private.feedback_mail_delivery'::regclass,'private.push_deliveries'::regclass)), 'RLS zapnuté na 4 tabulkách private');
select pg_temp.ok((select bool_and(not has_table_privilege('anon', t, p)) from unnest(array['public.ai_usage','public.company_invites','public.plan_requests']) t, unnest(array['select','insert','update','delete','truncate','references','trigger']) p), 'anon nemá práva na ai_usage, company_invites, plan_requests');
select pg_temp.ok(has_table_privilege('authenticated','public.ai_usage','select') and has_table_privilege('authenticated','public.ai_usage','insert') and has_table_privilege('authenticated','public.company_invites','select') and has_table_privilege('authenticated','public.plan_requests','insert') and not has_table_privilege('authenticated','public.plan_requests','update') and not has_table_privilege('authenticated','public.ai_usage','truncate'), 'authenticated má jen potřebná práva');
select pg_temp.ok((select bool_and(not has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute') and has_function_privilege('service_role', f, 'execute')) from unnest(array['public.clock_in(uuid,uuid)','public.clock_out(uuid,uuid)','public.shop_cancel_order(uuid)']) f) and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where a.grantee = 0 and p.oid in ('public.clock_in(uuid,uuid)'::regprocedure,'public.clock_out(uuid,uuid)'::regprocedure,'public.shop_cancel_order(uuid)'::regprocedure)), 'clock_in, clock_out, shop_cancel_order: bez anon a PUBLIC, authenticated a service_role zachovány');
select pg_temp.ok((select bool_and(has_function_privilege('anon', f, 'execute')) from unnest(array['public.public_shop(text)','public.public_shop_order(text,jsonb,jsonb,text,text)','public.public_site(text)','public.public_book(text,uuid,timestamptz,text,text,text)','public.public_booking_info(text)','public.public_slots(text,uuid,date)']) f), 'záměrně veřejné funkce (e-shop, rezervace, web) zůstaly dostupné pro anon');
select pg_temp.ok((select count(*) from private.deploy_backup_20261107_acl) = 15, 'záloha původního stavu práv je na místě (15 záznamů)');
select pg_temp.ok((pg_temp.call_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ with i as (insert into public.ai_usage (company_id) values ('deadbeef-0000-4000-8000-0000000000c1') returning 1) select to_jsonb(count(*)) from i $q$))::text = '1', 'AI Účetní: člen firmy zapíše počítadlo');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ with i as (insert into public.ai_usage (company_id) values ('deadbeef-0000-4000-8000-0000000000c2') returning 1) select to_jsonb(count(*)) from i $q$, '42501', 'do cizí firmy zapsat nejde (RLS)');
select pg_temp.ok((pg_temp.call_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ with i as (insert into public.plan_requests (company_id, requested_plan) values ('deadbeef-0000-4000-8000-0000000000c1', 'pro') returning 1) select to_jsonb(count(*)) from i $q$))::text = '1', 'žádost o změnu tarifu funguje');
select pg_temp.not_denied('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select to_jsonb(count(*)) from public.company_invites $q$, 'majitel čte pozvánky své firmy');
select pg_temp.expect_as(null, 'anon', $q$ select to_jsonb(count(*)) from public.ai_usage $q$, '42501', 'anon nečte ai_usage');
select pg_temp.expect_as(null, 'anon', $q$ select public.clock_in('deadbeef-0000-4000-8000-0000000000c1', null)::text::jsonb $q$, '42501', 'anon nevolá clock_in');
select pg_temp.expect_as(null, 'anon', $q$ select public.shop_cancel_order('00000000-0000-0000-0000-000000000001') $q$, '42501', 'anon nevolá shop_cancel_order');
select pg_temp.ok((pg_temp.call_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select to_jsonb(public.clock_in('deadbeef-0000-4000-8000-0000000000c1', null)::text) $q$)) is not null, 'přihlášený člen dál zapíše příchod (docházka)');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000003', 'authenticated', $q$ select to_jsonb(public.clock_in('deadbeef-0000-4000-8000-0000000000c1', null)::text) $q$, 'P0001', 'cizí člen dál dostane „Nemate pristup“');
select pg_temp.not_denied(null, 'anon', $q$ select public.public_shop('neexistujici-smoke-slug') $q$, 'veřejný e-shop pro anon dál funguje');
select pg_temp.not_denied(null, 'anon', $q$ select public.public_site('neexistujici-smoke-slug') $q$, 'veřejný web pro anon dál funguje');
select pg_temp.ok(has_function_privilege('service_role', 'public.claim_push_reminders(text)', 'execute') and has_function_privilege('service_role', 'public.claim_welcome_mail(text)', 'execute') and has_function_privilege('service_role', 'public.claim_care_mail(text)', 'execute'), 'plánovače (service_role) mají dál právo na claim_* funkce');
do $$ begin raise exception 'SMOKE_OK'; end $$;
