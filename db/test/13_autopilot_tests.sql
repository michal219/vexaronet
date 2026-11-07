-- Testy vynucování nákladového limitu Autopilota. Po 01_base_stub.sql, migraci profilu a migraci autopilot_limity.
-- Jedna transakce, na konci ROLLBACK. Žádné volání AI; spotřeba tokenů se simuluje.
\set ON_ERROR_STOP on
\pset tuples_only on
begin;
\i db/test/helpers.sql

create function pg_temp.rsv(uid uuid, cid uuid, mode text, i integer, o integer, k text, model text default 'gemini-3.5-flash-lite') returns jsonb language sql as
$$select pg_temp.call_as(uid, 'authenticated', format($q$select public.autopilot_reserve(%L, %L, %L, %s, %s, %L)$q$, cid, mode, model, i, o, k))$$;
create function pg_temp.stl(run text, i text, o text, ok boolean) returns jsonb language sql as
$$select pg_temp.call_as(null, 'service_role', format($q$select public.autopilot_settle(%L, %L, %L, %L)$q$, run, i, o, ok))$$;
create function pg_temp.status(uid uuid, cid uuid) returns jsonb language sql as
$$select pg_temp.call_as(uid, 'authenticated', format($q$select public.autopilot_status(%L)$q$, cid))$$;

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0000-0000-0000-0000000000e' || n)::uuid, 'ap' || n || '@example.invalid', now() from generate_series(1, 8) n;
insert into public.companies (id, owner_id, name, parent_company_id) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', 'Root PRO', null),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e1', 'Pobočka', '00000000-0000-0000-0000-0000000000f1'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e5', 'START firma', null),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e6', 'Prošlá zkouška', null),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000e7', 'Druhá PRO', null);
insert into public.company_members (company_id, user_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', 'owner'),
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e2', 'admin'),
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e3', 'employee'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e1', 'owner'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e4', 'admin'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e5', 'owner'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e6', 'owner'),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000e7', 'owner');
insert into public.subscriptions (company_id, plan, status, trial_end, paid_until) values
  ('00000000-0000-0000-0000-0000000000f1', 'pro', 'trial', now() + interval '20 days', null),
  ('00000000-0000-0000-0000-0000000000f2', 'pro', 'trial', now() + interval '20 days', null),
  ('00000000-0000-0000-0000-0000000000f3', 'start', 'active', null, null),
  ('00000000-0000-0000-0000-0000000000f4', 'pro', 'trial', now() - interval '1 day', null),
  ('00000000-0000-0000-0000-0000000000f5', 'pro', 'trial', now() + interval '20 days', null);
\set e1 '00000000-0000-0000-0000-0000000000e1'
\set e2 '00000000-0000-0000-0000-0000000000e2'
\set e3 '00000000-0000-0000-0000-0000000000e3'
\set e4 '00000000-0000-0000-0000-0000000000e4'
\set e5 '00000000-0000-0000-0000-0000000000e5'
\set e6 '00000000-0000-0000-0000-0000000000e6'
\set e7 '00000000-0000-0000-0000-0000000000e7'
\set e8 '00000000-0000-0000-0000-0000000000e8'
\set f1 '00000000-0000-0000-0000-0000000000f1'
\set f2 '00000000-0000-0000-0000-0000000000f2'
\set f3 '00000000-0000-0000-0000-0000000000f3'
\set f4 '00000000-0000-0000-0000-0000000000f4'
\set f5 '00000000-0000-0000-0000-0000000000f5'

-- 0) ceník a výchozí vypnutí ----------------------------------------------------------------------------
select pg_temp.ok((select input_nusd_per_token = 300 and output_nusd_per_token = 2500 and active and verified_on = date '2026-11-07' and source_url like 'https://ai.google.dev/%' from private.ai_model_prices where model = 'gemini-3.5-flash-lite'), 'ceník: gemini-3.5-flash-lite = 300/2500 nUSD za token (0,30/2,50 USD za 1 M), ověřeno 2026-11-07');
select pg_temp.ok((select not paid_runs_enabled from private.autopilot_platform), 'placené běhy jsou ve výchozím stavu platformně VYPNUTÉ');
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'paid_runs_possible') = 'false' and (pg_temp.status(:'e1', :'f1') ->> 'plan_allowed') = 'true' and (pg_temp.status(:'e1', :'f1') -> 'monthly_limit_nusd') = 'null'::jsonb, 'stav: tarif PRO ok, limit nenastaven, placené běhy nejsou možné');

-- 1) vypnutí a chybějící limit -------------------------------------------------------------------------------
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 4000, 2000, 'klic-0001-aaaa') $q$, :'f1'), 'PT403', 'rezervace při vypnuté platformě = PT403', '"reason": "platform"');
select pg_temp.ok((select count(*) from private.autopilot_runs) = 0, 'odmítnutá rezervace nezanechala žádný záznam');
update private.autopilot_platform set paid_runs_enabled = true;      -- v testu zapíná postgres; žádná API role to neumí (viz níže)
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 4000, 2000, 'klic-0001-aaaa') $q$, :'f1'), 'PT402', 'bez nastaveného limitu se rezervace odmítne (PT402)', 'budget_not_set');

-- 2) nastavení limitu --------------------------------------------------------------------------------------------
select pg_temp.expect_as(:'e3', 'authenticated', format($q$ select public.autopilot_set_budget(%L, 250000000) $q$, :'f1'), '42501', 'zaměstnanec limit nenastaví');
select pg_temp.expect_as(:'e4', 'authenticated', format($q$ select public.autopilot_set_budget(%L, 250000000) $q$, :'f2'), 'PT403', 'pobočka limit nenastaví, patří hlavní firmě', 'only_root');
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_set_budget(%L, -1) $q$, :'f1'), 'PT422', 'záporný limit = PT422');
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_set_budget(%L, 60000000000) $q$, :'f1'), 'PT422', 'limit nad 50 USD = PT422 (ochrana před překlepem)');
select pg_temp.expect_as(:'e6', 'authenticated', format($q$ select public.autopilot_set_budget(%L, 1000) $q$, :'f4'), '42501', 'účet jen pro čtení limit nenastaví');
select pg_temp.call_as(:'e2', 'authenticated', format($q$ select public.autopilot_set_budget(%L, 250000000) $q$, :'f1')) as sb \gset
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'monthly_limit_nusd')::bigint = 250000000, 'správce nastavil limit 0,25 USD = 250 000 000 nUSD');

-- 3) neplatné požadavky -------------------------------------------------------------------------------------------
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'hacker', 'gemini-3.5-flash-lite', 100, 100, 'klic-0002-aaaa') $q$, :'f1'), 'PT422', 'neznámý režim');
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 100, 5000, 'klic-0002-aaaa') $q$, :'f1'), 'PT422', 'výstup nad 4 000 tokenů');
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 9000, 100, 'klic-0002-aaaa') $q$, :'f1'), 'PT422', 'vstup nad 8 000 tokenů');
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'krátký') $q$, :'f1'), 'PT422', 'příliš krátký klíč idempotence');
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-9-ultra', 100, 100, 'klic-0002-aaaa') $q$, :'f1'), 'PT422', 'model, který není v ceníku, se odmítne', 'unknown_model');
update private.ai_model_prices set active = false where model = 'gemini-3.5-flash-lite';
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'klic-0002-aaaa') $q$, :'f1'), 'PT422', 'neaktivní cena modelu = odmítnuto', 'unknown_model');
update private.ai_model_prices set active = true where model = 'gemini-3.5-flash-lite';

-- 4) rezervace, idempotence, pobočka -------------------------------------------------------------------------------
select pg_temp.rsv(:'e1', :'f1', 'ceo', 4000, 2000, 'klic-0010-aaaa') as a \gset
select pg_temp.ok((:'a'::jsonb ->> 'reserved_nusd')::bigint = 6200000, 'rezervace 4 000 vstup + 2 000 výstup = 6 200 000 nUSD (0,0062 USD)');
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = 6200000, 'rezervace se hned počítá do měsíční spotřeby');
select pg_temp.rsv(:'e1', :'f1', 'ceo', 4000, 2000, 'klic-0010-aaaa') as a2 \gset
select pg_temp.ok((:'a2'::jsonb ->> 'reused') = 'true' and (:'a2'::jsonb ->> 'run_id') = (:'a'::jsonb ->> 'run_id') and (pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = 6200000, 'opakované volání se stejným klíčem nevytvoří druhou rezervaci');
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'marketing', 'gemini-3.5-flash-lite', 4000, 2000, 'klic-0010-aaaa') $q$, :'f1'), 'PT409', 'stejný klíč pro jiný režim = PT409');
select pg_temp.rsv(:'e4', :'f2', 'marketing', 4000, 2000, 'klic-0011-aaaa') as b \gset
select pg_temp.ok((select root_company_id = :'f1'::uuid and company_id = :'f2'::uuid from private.autopilot_runs where id = (:'b'::jsonb ->> 'run_id')::uuid), 'rezervace z pobočky se účtuje hlavní firmě');
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = 12400000, 'hlavní firma a pobočka sdílejí jeden limit');
select pg_temp.rsv(:'e2', :'f1', 'ucetnictvi', 4000, 2000, 'klic-0012-aaaa') as c \gset
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 10, 10, 'klic-0013-aaaa') $q$, :'f1'), 'PT429', 'čtvrtý souběžný nedokončený běh = PT429', 'open');

-- 5) vypořádání: jen server, jen jednou ---------------------------------------------------------------------------
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_settle(%L, 1, 1, true) $q$, (:'a'::jsonb ->> 'run_id')), '42501', 'přihlášený uživatel vypořádat nemůže (jen service_role)');
select pg_temp.expect_as(null, 'anon', format($q$ select public.autopilot_settle(%L, 1, 1, true) $q$, (:'a'::jsonb ->> 'run_id')), '42501', 'anon vypořádat nemůže');
select pg_temp.expect_as(null, 'service_role', format($q$ select public.autopilot_settle('00000000-0000-0000-0000-00000000dead', 1, 1, true) $q$), 'PT404', 'neexistující běh = PT404');
select pg_temp.expect_as(null, 'service_role', format($q$ select public.autopilot_settle(%L, null, 5, true) $q$, (:'a'::jsonb ->> 'run_id')), 'PT422', 'úspěšný běh bez udané spotřeby se odmítne');
select pg_temp.stl((:'a'::jsonb ->> 'run_id'), '1000', '500', true) as s1 \gset
select pg_temp.ok((:'s1'::jsonb ->> 'actual_nusd')::bigint = 1550000, 'vypořádání: 1 000 vstup × 300 + 500 výstup × 2 500 = 1 550 000 nUSD');
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = 6200000 + 6200000 + 1550000, 'rezervace se nahradí skutečnou spotřebou (méně než rezervováno)');
select pg_temp.stl((:'a'::jsonb ->> 'run_id'), '4000', '2000', true) as s2 \gset
select pg_temp.ok((:'s2'::jsonb ->> 'already') = 'true' and (pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = 13950000, 'druhé vypořádání téhož běhu nic nepřičte');
select pg_temp.stl((:'b'::jsonb ->> 'run_id'), null, null, false) as s3 \gset
select pg_temp.ok((:'s3'::jsonb ->> 'actual_nusd')::bigint = 0 and (pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = 7750000, 'neúspěšný běh bez spotřeby uvolní celou rezervaci');
select pg_temp.stl((:'c'::jsonb ->> 'run_id'), '4000', '2000', true);

-- 6) vyčerpání limitu na nanodolar -----------------------------------------------------------------------------------
do $$ begin
  for i in 1 .. 39 loop
    perform pg_temp.stl((pg_temp.rsv('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000f1', 'ceo', 4000, 2000, 'smycka-' || lpad(i::text, 4, '0')) ->> 'run_id'), '4000', '2000', true);
  end loop;
end $$;
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = 1550000 + 6200000 + 39 * 6200000, 'po 39 dalších bězích je spotřeba 249 550 000 nUSD (1 550 000 + 6 200 000 + 39 × 6 200 000)');
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = (select sum(coalesce(actual_nusd, reserved_nusd)) from private.autopilot_runs where root_company_id = :'f1'::uuid), 'spotřeba z funkce = součet ze záznamů');
select (pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint as spent \gset
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 4000, 2000, 'klic-0100-aaaa') $q$, :'f1'), 'PT402', 'rezervace nad limit se odmítne (PT402), poskytovatel by se nevolal', 'budget_exceeded');
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = :spent, 'odmítnutá rezervace spotřebu nezměnila');
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'remaining_nusd')::bigint = 250000000 - :spent, 'zbývá limit minus spotřeba (' || (250000000 - :spent) || ' nUSD)');
-- zbývá přesně 450 000 nUSD: rezervace přesně na hranici projde (rovnost je povolená)
select (250000000 - :spent) as rem \gset
select pg_temp.ok(:rem = 450000, 'zbývá přesně 450 000 nUSD');
select pg_temp.rsv(:'e1', :'f1', 'ceo', 1000, 60, 'klic-0101-aaaa') as edge \gset
select pg_temp.ok((:'edge'::jsonb ->> 'reserved_nusd')::bigint = 450000 and (pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = 250000000 and (pg_temp.status(:'e1', :'f1') ->> 'remaining_nusd')::bigint = 0, 'rezervace přesně do zbytku limitu projde a spotřeba je přesně na limitu (250 000 000 nUSD)');
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 1, 1, 'klic-0103-aaaa') $q$, :'f1'), 'PT402', 'o 2 800 nUSD navíc už ne', 'budget_exceeded');
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 1000, 10, 'klic-0102-aaaa') $q$, :'f1'), 'PT402', 'další rezervace po vyčerpání se odmítne', 'budget_exceeded');
select pg_temp.stl((:'edge'::jsonb ->> 'run_id'), '0', '0', true) as rel \gset
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = :spent, 'vypořádání s nulovou spotřebou vrátí rezervaci do limitu');

-- 7) přečerpání proti rezervaci se zaznamená ---------------------------------------------------------------------------
select pg_temp.rsv(:'e1', :'f1', 'ceo', 100, 10, 'klic-0200-aaaa') as ov \gset
select pg_temp.stl((:'ov'::jsonb ->> 'run_id'), '1000', '500', true) as ovs \gset
select pg_temp.ok((:'ovs'::jsonb ->> 'overrun') = 'true' and (select overrun from private.autopilot_runs where id = (:'ov'::jsonb ->> 'run_id')::uuid), 'skutečná spotřeba nad rezervací se označí jako přečerpání');
select pg_temp.ok((pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint = :spent + 1550000, 'přečerpání se započítá ve skutečné výši (neskrývá se)');

-- 8) prošlé rezervace, přelom měsíce -----------------------------------------------------------------------------------
select pg_temp.call_as(:'e7', 'authenticated', format($q$ select public.autopilot_set_budget(%L, 100000000) $q$, :'f5')) as sb2 \gset
select pg_temp.rsv(:'e7', :'f5', 'marketing', 4000, 2000, 'stale-0001-aaaa') as st1 \gset
select pg_temp.rsv(:'e7', :'f5', 'marketing', 4000, 2000, 'stale-0002-aaaa') as st2 \gset
select pg_temp.rsv(:'e7', :'f5', 'marketing', 4000, 2000, 'stale-0003-aaaa') as st3 \gset
update private.autopilot_runs set created_at = now() - interval '20 minutes' where root_company_id = :'f5'::uuid;
select pg_temp.rsv(:'e7', :'f5', 'marketing', 1000, 100, 'stale-0004-aaaa') as st4 \gset
select pg_temp.ok((select count(*) from private.autopilot_runs where root_company_id = :'f5'::uuid and status = 'expired') = 3, 'rezervace starší 15 minut se při další rezervaci označí „expired“ a neblokují nové běhy');
select pg_temp.ok((pg_temp.status(:'e7', :'f5') ->> 'spent_nusd')::bigint = 3 * 6200000 + 550000, 'prošlé rezervace se dál počítají v plné výši (bezpečná strana)');
select pg_temp.stl((:'st1'::jsonb ->> 'run_id'), '10', '10', true);
select pg_temp.ok((pg_temp.status(:'e7', :'f5') ->> 'spent_nusd')::bigint = 2 * 6200000 + 550000 + 3000 + 25000, 'pozdní dokončení prošlé rezervace upraví spotřebu na skutečnou');
select pg_temp.ok((pg_temp.call_as(null, 'service_role', $q$ select to_jsonb(public.autopilot_expire_stale()) $q$))::text::int >= 0, 'autopilot_expire_stale smí volat service_role');
select pg_temp.expect_as(:'e7', 'authenticated', $q$ select to_jsonb(public.autopilot_expire_stale()) $q$, '42501', 'autopilot_expire_stale nesmí volat přihlášený uživatel');
select (pg_temp.status(:'e7', :'f5') ->> 'spent_nusd')::bigint as before_old \gset
insert into private.autopilot_runs (root_company_id, company_id, mode, model, in_price, out_price, max_in_tokens, max_out_tokens, reserved_nusd, actual_nusd, status, idempotency_key, created_at)
  values (:'f5', :'f5', 'ceo', 'gemini-3.5-flash-lite', 300, 2500, 4000, 2000, 99000000, 99000000, 'succeeded', 'stary-mesic-001', private.ap_month_start() - interval '1 day');
select pg_temp.ok((pg_temp.status(:'e7', :'f5') ->> 'spent_nusd')::bigint = :before_old, 'spotřeba z minulého měsíce se do aktuálního měsíce nepočítá (limit se obnoví)');

-- 9) tarif, role, účet jen pro čtení -------------------------------------------------------------------------------------
select pg_temp.call_as(:'e5', 'authenticated', format($q$ select public.autopilot_set_budget(%L, 250000000) $q$, :'f3')) as sb3 \gset
select pg_temp.expect_as(:'e5', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'start-0001-aaaa') $q$, :'f3'), 'PT403', 'tarif START nemá placené AI běhy, i když je limit nastaven', 'plan_not_allowed');
select pg_temp.expect_as(:'e6', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'expir-0001-aaaa') $q$, :'f4'), '42501', 'prošlá zkouška (jen pro čtení): rezervace zakázána');
select pg_temp.expect_as(:'e3', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'emp-00001-aaaa') $q$, :'f1'), '42501', 'zaměstnanec nerezervuje');
select pg_temp.expect_as(:'e8', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'out-00001-aaaa') $q$, :'f1'), '42501', 'uživatel bez členství nerezervuje');
select pg_temp.expect_as(:'e1', 'authenticated', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'cross-0001-aaaa') $q$, :'f5'), '42501', 'majitel A nerezervuje na účet firmy B');
select pg_temp.expect_as(null, 'service_role', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'svc-000001-aaaa') $q$, :'f1'), '42501', 'service_role nemůže rezervovat ani se pokusit „obejít“ limit vlastním voláním');
select pg_temp.expect_as(null, 'anon', format($q$ select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 100, 100, 'anon-00001-aaaa') $q$, :'f1'), '42501', 'anon nerezervuje');
select pg_temp.expect_as(:'e3', 'authenticated', format($q$ select public.autopilot_status(%L) $q$, :'f1'), '42501', 'zaměstnanec nevidí stav limitu');

-- 10) práva, RLS, neměnnost, audit ----------------------------------------------------------------------------------------------
select pg_temp.expect_as(:'e1', 'authenticated', $q$ update private.autopilot_platform set paid_runs_enabled = true returning to_jsonb(1) $q$, '42501', 'žádná API role nezapne placené běhy přímým zápisem');
select pg_temp.expect_as(:'e1', 'authenticated', $q$ update private.autopilot_budgets set monthly_limit_nusd = 50000000000 returning to_jsonb(1) $q$, '42501', 'limit nejde změnit přímo, jen přes funkci');
select pg_temp.expect_as(null, 'service_role', $q$ update private.autopilot_budgets set monthly_limit_nusd = 50000000000 returning to_jsonb(1) $q$, '42501', 'ani service_role nemůže limit změnit přímým zápisem');
select pg_temp.expect_as(null, 'service_role', $q$ update private.ai_model_prices set output_nusd_per_token = 1 returning to_jsonb(1) $q$, '42501', 'ani service_role nemůže změnit ceník');
select pg_temp.ok((select bool_and(not has_table_privilege(r, t, p)) from unnest(array['anon', 'authenticated', 'service_role']) r,
                   unnest(array['private.ai_model_prices', 'private.autopilot_platform', 'private.autopilot_budgets', 'private.autopilot_runs', 'private.autopilot_events']) t,
                   unnest(array['select', 'insert', 'update', 'delete']) p), 'žádná API role nemá práva na tabulky Autopilota');
select pg_temp.ok((select bool_and(relrowsecurity) from pg_class where oid in ('private.ai_model_prices'::regclass, 'private.autopilot_platform'::regclass, 'private.autopilot_budgets'::regclass, 'private.autopilot_runs'::regclass, 'private.autopilot_events'::regclass)), 'RLS je na všech tabulkách Autopilota zapnuté');
select pg_temp.ok(
  has_function_privilege('authenticated', 'public.autopilot_reserve(uuid,text,text,integer,integer,text)', 'execute') and has_function_privilege('authenticated', 'public.autopilot_status(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.autopilot_set_budget(uuid,bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.autopilot_settle(uuid,integer,integer,boolean)', 'execute') and not has_function_privilege('authenticated', 'public.autopilot_expire_stale()', 'execute')
  and has_function_privilege('service_role', 'public.autopilot_settle(uuid,integer,integer,boolean)', 'execute') and has_function_privilege('service_role', 'public.autopilot_expire_stale()', 'execute')
  and not has_function_privilege('service_role', 'public.autopilot_reserve(uuid,text,text,integer,integer,text)', 'execute') and not has_function_privilege('service_role', 'public.autopilot_set_budget(uuid,bigint)', 'execute')
  and not has_function_privilege('anon', 'public.autopilot_reserve(uuid,text,text,integer,integer,text)', 'execute') and not has_function_privilege('anon', 'public.autopilot_settle(uuid,integer,integer,boolean)', 'execute')
  and not has_function_privilege('authenticated', 'private.autopilot_settle_core(uuid,integer,integer,boolean)', 'execute') and not has_function_privilege('authenticated', 'private.ap_spent(uuid)', 'execute'),
  'matice práv: rezervovat a nastavovat smí jen přihlášený, vypořádávat jen service_role, anon nic');
select pg_temp.expect_as(null, 'postgres', $q$ update private.autopilot_events set operation = 'reserve' returning to_jsonb(1) $q$, 'P0001', 'auditní události nejdou upravit');
select pg_temp.ok((select count(*) from private.autopilot_events where operation = 'set_budget' and actor is not null) >= 3
              and (select count(*) from private.autopilot_events where operation = 'reserve' and actor is not null) >= 5
              and (select count(*) from private.autopilot_events where operation = 'settle' and actor is null) >= 5, 'audit: nastavení limitu a rezervace nesou identitu člověka, vypořádání je z backendu');
select pg_temp.ok((select (details ->> 'old_nusd') is null and (details ->> 'new_nusd')::bigint = 250000000 from private.autopilot_events where operation = 'set_budget' and root_company_id = :'f1'::uuid order by id limit 1), 'audit nastavení limitu uchovává starou i novou hodnotu');

-- 11) invariant a kaskáda ----------------------------------------------------------------------------------------------------------------
select pg_temp.ok((select coalesce(sum(case when overrun then actual_nusd - reserved_nusd else 0 end), 0) from private.autopilot_runs where root_company_id = :'f1'::uuid) >= (pg_temp.status(:'e1', :'f1') ->> 'spent_nusd')::bigint - 250000000,
  'invariant: spotřeba nikdy nepřekročí limit jinak než zaznamenaným přečerpáním');
delete from public.companies where id = :'f5';
select pg_temp.ok((select count(*) from private.autopilot_runs where root_company_id = :'f5'::uuid) + (select count(*) from private.autopilot_budgets where root_company_id = :'f5'::uuid) + (select count(*) from private.autopilot_events where root_company_id = :'f5'::uuid) = 0, 'smazání firmy odstraní data Autopilota (výmaz)');

rollback;
\echo VŠECHNY TESTY AUTOPILOTA PROŠLY (transakce vrácena)
