-- PRODUKČNÍ kontrola (jedna dávka, vždy skončí vrácením transakce, v databázi nezůstane nic).
-- Úspěch = chyba "SMOKE_OK ...". Selhání = chyba "TEST_FAIL ...". Bez příkazů psql, spouští se přes API.
-- Fáze 1: profil firmy (po migraci 20261107120000_profil_firmy)
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

select pg_temp.ok(to_regprocedure('public.profile_get(uuid)') is not null and to_regclass('private.company_profile_versions') is not null, 'profil: objekty existují');
select pg_temp.ok((pg_temp.call_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select to_jsonb((public.profile_schema_info()->>'version')::int) $q$))::text = '1', 'profile_schema_info: verze schématu 1');
insert into smk select 'r', pg_temp.call_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.profile_save_draft('deadbeef-0000-4000-8000-0000000000c1', 0, 1, '{"shared":{"identity":{"displayName":"  SMOKE firma  ","activity":"test"},"audience":{"description":"test"},"financialContext":{"revenueMinor":14600000,"revenueCurrency":"CZK","revenuePeriod":"month"},"goals":[{"metric":"revenue","baselineMinor":14600000,"growthBp":3500,"dueDate":"2027-05-07"}]},"local":{"geography":{"city":"Praha"}}}'::jsonb) $q$);
select pg_temp.ok((select v ->> 'revision' = '1' and v #>> '{data,shared,identity,displayName}' = 'SMOKE firma' and v #>> '{data,shared,goals,0,targetMinor}' = '19710000' from smk where k = 'r'), 'uložení konceptu: revize 1, ořez textu, cíl 197 100 Kč = 19 710 000 haléřů');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.profile_save_draft('deadbeef-0000-4000-8000-0000000000c1', 0, 1, '{"shared":{},"local":{}}'::jsonb) $q$, 'PT409', 'zastaralá revize = PT409', 'current_revision');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.profile_save_draft('deadbeef-0000-4000-8000-0000000000c1', 1, 999, '{"shared":{},"local":{}}'::jsonb) $q$, 'PT412', 'jiná verze schématu = PT412');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000002', 'authenticated', $q$ select public.profile_get('deadbeef-0000-4000-8000-0000000000c1') $q$, '42501', 'zaměstnanec nesmí číst');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000002', 'authenticated', $q$ select public.profile_save_draft('deadbeef-0000-4000-8000-0000000000c1', 1, 1, '{"shared":{},"local":{}}'::jsonb) $q$, '42501', 'zaměstnanec nesmí ukládat');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000003', 'authenticated', $q$ select public.profile_get('deadbeef-0000-4000-8000-0000000000c1') $q$, '42501', 'cizí uživatel nesmí číst');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.profile_get('deadbeef-0000-4000-8000-0000000000c2') $q$, '42501', 'majitel A nesmí číst firmu B');
select pg_temp.expect_as(null, 'anon', $q$ select public.profile_get('deadbeef-0000-4000-8000-0000000000c1') $q$, '42501', 'anon nesmí volat profile_get');
select pg_temp.expect_as(null, 'service_role', $q$ select public.profile_confirm('deadbeef-0000-4000-8000-0000000000c1', 1, 'x') $q$, '42501', 'service_role nemůže potvrdit profil');
select pg_temp.expect_as(null, 'postgres', $q$ select public.profile_confirm('deadbeef-0000-4000-8000-0000000000c1', 1, 'x') $q$, '42501', 'bez lidské identity se nepotvrdí ani jako postgres');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select count(*)::text::jsonb from private.company_profile_drafts $q$, '42501', 'tabulka konceptů není přímo dostupná');
select pg_temp.expect_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.profile_confirm('deadbeef-0000-4000-8000-0000000000c1', 1, 'neplatny') $q$, 'PT409', 'potvrzení s jiným otiskem = PT409');
insert into smk select 'c', pg_temp.call_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', format($q$ select public.profile_confirm('deadbeef-0000-4000-8000-0000000000c1', 1, %L) $q$, (select v ->> 'hash' from smk where k = 'r')));
select pg_temp.ok((select v ->> 'version' = '1' and v ->> 'unchanged' = 'false' from smk where k = 'c'), 'potvrzení vytvoří verzi 1');
insert into smk select 'g', pg_temp.call_as('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.profile_get('deadbeef-0000-4000-8000-0000000000c1') $q$);
select pg_temp.ok((select v #>> '{active,version}' = '1' and jsonb_array_length(v -> 'versions') = 1 and (v ->> 'is_root') = 'true' from smk where k = 'g'), 'profile_get: aktivní verze 1, historie 1, hlavní firma');
select pg_temp.ok((select confirmed_by = 'deadbeef-0000-4000-8000-000000000001'::uuid from private.company_profile_versions where company_id = 'deadbeef-0000-4000-8000-0000000000c1' and version = 1), 'potvrdil člověk: confirmed_by = přihlášená identita');
select pg_temp.expect_as(null, 'postgres', $q$ update private.company_profile_versions set data = '{}'::jsonb returning to_jsonb(1) $q$, 'P0001', 'potvrzená verze je neměnná');
select pg_temp.ok((pg_temp.call_as('deadbeef-0000-4000-8000-000000000004', 'authenticated', $q$ select public.profile_save_draft('deadbeef-0000-4000-8000-0000000000c2', 0, 1, '{"shared":{"identity":{"displayName":"SMOKE start"}},"local":{}}'::jsonb) $q$) ->> 'revision') = '1', 'tarif START může profil ukládat (ruční profil je ve všech tarifech)');
select pg_temp.not_denied('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select public.dashboard_summary('deadbeef-0000-4000-8000-0000000000c1') $q$, 'stávající dashboard_summary dál funguje');
select pg_temp.not_denied('deadbeef-0000-4000-8000-000000000001', 'authenticated', $q$ select to_jsonb(count(*)) from public.company_team('deadbeef-0000-4000-8000-0000000000c1') $q$, 'stávající company_team dál funguje');
do $$ begin raise exception 'SMOKE_OK %'; end $$;
