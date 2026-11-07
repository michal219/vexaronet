-- PRODUKČNÍ kontrola (jedna dávka, vždy skončí vrácením transakce, v databázi nezůstane nic).
-- Úspěch = chyba "SMOKE_OK ...". Selhání = chyba "TEST_FAIL ...". Bez příkazů psql, spouští se přes API.
-- Fáze 2: Autopilot (po migraci 20261108110000_autopilot_limity). Platformní vypínač se NEZAPÍNÁ ani v transakci.
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

select pg_temp.ok(to_regprocedure('public.autopilot_reserve(uuid,text,text,integer,integer,text)') is not null, 'autopilot: objekty existují');
select pg_temp.ok((select input_nusd_per_token = 300 and output_nusd_per_token = 2500 and active from private.ai_model_prices where model = 'gemini-3.5-flash-lite'), 'ceník: 300/2500 nUSD za token, aktivní');
select pg_temp.ok((select paid_runs_enabled = false from private.autopilot_platform), 'PLATFORMNÍ VYPÍNAČ PLACENÝCH BĚHŮ JE VYPNUTÝ');
insert into smk select 's', pg_temp.call_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.autopilot_status('deadbeef-0000-4000-8000-0000000000c1') $q$);
select pg_temp.ok((select v ->> 'platform_paid_runs_enabled' = 'false' and v ->> 'paid_runs_possible' = 'false' and v ->> 'plan_allowed' = 'true' and v -> 'monthly_limit_nusd' = 'null'::jsonb from smk where k = 's'), 'status: vypnuto, bez limitu, tarif PRO ok');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000002', 'authenticated', $q$ select public.autopilot_set_budget('deadbeef-0000-4000-8000-0000000000c1', 250000000) $q$, '42501', 'zaměstnanec limit nenastaví');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.autopilot_set_budget('deadbeef-0000-4000-8000-0000000000c1', 60000000000) $q$, 'PT422', 'limit nad 50 USD = PT422');
select pg_temp.ok((pg_temp.call_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.autopilot_set_budget('deadbeef-0000-4000-8000-0000000000c1', 250000000) $q$) ->> 'monthly_limit_nusd') = '250000000', 'majitel nastaví limit 0,25 USD (250 000 000 nUSD)');
select pg_temp.ok((pg_temp.call_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.autopilot_status('deadbeef-0000-4000-8000-0000000000c1') $q$) ->> 'monthly_limit_nusd') = '250000000', 'status ukazuje nastavený limit');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.autopilot_reserve('deadbeef-0000-4000-8000-0000000000c1', 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'smoke-klic-0001') $q$, 'PT403', 'rezervace při vypnuté platformě = PT403 (i s limitem a tarifem PRO)', 'paid_runs_disabled');
select pg_temp.ok((select count(*) from private.autopilot_runs) = 0, 'odmítnutá rezervace nezanechala záznam, žádný běh nevznikl');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000004', 'authenticated', $q$ select public.autopilot_reserve('deadbeef-0000-4000-8000-0000000000c2', 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'smoke-klic-0002') $q$, 'PT403', 'tarif START: odmítnuto', 'plan_not_allowed');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000002', 'authenticated', $q$ select public.autopilot_reserve('deadbeef-0000-4000-8000-0000000000c1', 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'smoke-klic-0003') $q$, '42501', 'zaměstnanec nerezervuje');
select pg_temp.expect_as(null, 'service_role', $q$ select public.autopilot_reserve('deadbeef-0000-4000-8000-0000000000c1', 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'smoke-klic-0004') $q$, '42501', 'service_role nemůže rezervovat');
select pg_temp.expect_as(null, 'anon', $q$ select public.autopilot_status('deadbeef-0000-4000-8000-0000000000c1') $q$, '42501', 'anon nevidí stav');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.autopilot_settle('00000000-0000-0000-0000-00000000dead', 1, 1, true) $q$, '42501', 'přihlášený uživatel nemůže vypořádávat');
select pg_temp.expect_as(null, 'service_role', $q$ select public.autopilot_settle('00000000-0000-0000-0000-00000000dead', 1, 1, true) $q$, 'PT404', 'service_role smí vypořádávat (neexistující běh = PT404)');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ update private.autopilot_platform set paid_runs_enabled = true returning to_jsonb(1) $q$, '42501', 'žádná API role nezapne placené běhy přímým zápisem');
select pg_temp.ok((select paid_runs_enabled = false from private.autopilot_platform), 'vypínač je po testech stále vypnutý');
do $$ begin raise exception 'SMOKE_OK'; end $$;
