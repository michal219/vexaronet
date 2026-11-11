-- AI tým: hranice oprávnění, fronta, schvalování akcí, limity, plány a AI Účetnictví (po migraci 20261115100000).
\set ON_ERROR_STOP on
\pset tuples_only on
begin;
\i db/test/helpers.sql
update private.autopilot_platform set paid_runs_enabled = true, pilot_root_ids = null;   -- jen v testu
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-00000000b001', 'owner@a.test', now()), ('00000000-0000-0000-0000-00000000b002', 'admin@a.test', now()),
  ('00000000-0000-0000-0000-00000000b003', 'emp@a.test', now()), ('00000000-0000-0000-0000-00000000b004', 'owner@b.test', now());
insert into public.companies (id, owner_id, name) values ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-00000000b001', 'Autoservis A'),
  ('00000000-0000-0000-0000-00000000cb01', '00000000-0000-0000-0000-00000000b004', 'Firma B');
insert into public.company_members (company_id, user_id, role) values ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-00000000b001', 'owner'),
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-00000000b002', 'admin'), ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-00000000b003', 'employee'),
  ('00000000-0000-0000-0000-00000000cb01', '00000000-0000-0000-0000-00000000b004', 'owner');
insert into public.subscriptions (company_id, plan, status, trial_end) values ('00000000-0000-0000-0000-00000000ca01', 'pro', 'trial', now() + interval '20 days'),
  ('00000000-0000-0000-0000-00000000cb01', 'pro', 'trial', now() + interval '20 days');
\set o '00000000-0000-0000-0000-00000000b001'
\set a '00000000-0000-0000-0000-00000000b002'
\set e '00000000-0000-0000-0000-00000000b003'
\set x '00000000-0000-0000-0000-00000000b004'
\set A '00000000-0000-0000-0000-00000000ca01'
\set B '00000000-0000-0000-0000-00000000cb01'
insert into public.customers (id, company_id, name) values ('00000000-0000-0000-0000-0000000c0a01', :'A', 'Zákazník A'), ('00000000-0000-0000-0000-0000000c0b01', :'B', 'Zákazník B');
insert into public.sites (company_id, slug, enabled, data) values (:'A', 'servis-a', true, '{"hero":{"title":"Starý titulek"}}');
insert into public.products (id, company_id, name) values ('00000000-0000-0000-0000-0000000d0a01', :'A', 'Olej 5W30');
insert into public.financial_entries (company_id, title, amount, kind, entry_date) values (:'A', 'Tržba', 5000, 'income', current_date), (:'B', 'Tajné B', 99999, 'income', current_date);
create temp table k (k text primary key, v text); grant all on k to public;
select pg_temp.call_as(:'o', 'authenticated', format('select public.autopilot_set_budget(%L, 250000000)', :'A'));

-- ===== limity =====
select pg_temp.expect_as(:'o', 'authenticated', format('select public.autopilot_set_budget(%L, 3000000000)', :'A'), 'PT422', 'limit firmy nad strop tarifu PRO (2 USD) je odmítnut', 'cap_nusd');
select pg_temp.expect_as(:'e', 'authenticated', format('select public.autopilot_set_limits(%L, 1000000, 1000000)', :'A'), '42501', 'zaměstnanec limity nenastaví');
select pg_temp.expect_as(:'o', 'authenticated', format($q$select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 8000, 4000, 'limit-run-0001')$q$, :'A'), 'PT402', 'operace dražší než výchozí limit na operaci (0,01 USD) neprojde', 'per_run_nusd');
select pg_temp.call_as(:'o', 'authenticated', format('select public.autopilot_set_limits(%L, 8000000, 6000000)', :'A'));
select pg_temp.expect_as(:'o', 'authenticated', format($q$select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 4000, 2400, 'limit-run-0002')$q$, :'A'), 'PT402', 'vlastní limit na operaci (0,006 USD) platí', 'per_run_nusd');
insert into k select 'r1', pg_temp.call_as(:'a', 'authenticated', format($q$select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 3000, 2000, 'limit-user-0001')$q$, :'A')) ->> 'run_id';
select pg_temp.expect_as(:'a', 'authenticated', format($q$select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 3000, 2000, 'limit-user-0002')$q$, :'A'), 'PT402', 'limit na uživatele: druhá rezervace správce přesáhne 0,008 USD', 'per_user_nusd');
select pg_temp.ok((pg_temp.call_as(:'o', 'authenticated', format($q$select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 3000, 2000, 'limit-user-0003')$q$, :'A')) ->> 'status') = 'reserved', 'limit na uživatele se počítá každému zvlášť (vlastník ještě může)');
select pg_temp.call_as(null, 'service_role', format('select public.autopilot_settle(%L, 100, 100, true)', (select v from k where k = 'r1')));
select pg_temp.call_as(null, 'service_role', format('select public.autopilot_settle(%L, 100, 100, true)', (select id from private.autopilot_runs where idempotency_key = 'limit-user-0003')));
select pg_temp.call_as(:'o', 'authenticated', format('select public.autopilot_set_limits(%L, null, null)', :'A'));

-- ===== úlohy: oprávnění a izolace =====
select pg_temp.expect_as(:'e', 'authenticated', format($q$select public.ai_job_create(%L, 'ceo', 'risks', '', '{}', 'job-key-0001')$q$, :'A'), '42501', 'zaměstnanec úlohu nezadá');
select pg_temp.expect_as(:'x', 'authenticated', format($q$select public.ai_job_create(%L, 'ceo', 'risks', '', '{}', 'job-key-0001')$q$, :'A'), '42501', 'cizí firma úlohu nezadá');
select pg_temp.expect_as(null, 'anon', format($q$select public.ai_job_create(%L, 'ceo', 'risks', '', '{}', 'job-key-0001')$q$, :'A'), '42501', 'anon úlohu nezadá');
select pg_temp.expect_as(null, 'service_role', format($q$select public.ai_job_create(%L, 'ceo', 'risks', '', '{}', 'job-key-0001')$q$, :'A'), '42501', 'service_role úlohu za člověka nezadá');
select pg_temp.expect_as(:'o', 'authenticated', format($q$select public.ai_job_create(%L, 'ceo', 'neexistuje', '', '{}', 'job-key-0001')$q$, :'A'), 'PT422', 'neznámý druh úlohy je odmítnut');
insert into k select 'j1', pg_temp.call_as(:'o', 'authenticated', format($q$select public.ai_job_create(%L, 'obchodnik', 'next_steps', 'Zaměř se na servis', '{}', 'job-key-0001')$q$, :'A')) ->> 'id';
select pg_temp.ok((pg_temp.call_as(:'o', 'authenticated', format($q$select public.ai_job_create(%L, 'obchodnik', 'next_steps', 'x', '{}', 'job-key-0001')$q$, :'A')) ->> 'reused')::boolean and (select count(*) from private.ai_jobs) = 1, 'stejný klíč nevytvoří druhou úlohu');
select pg_temp.expect_as(:'o', 'authenticated', format('select public.ai_job_claim(%L)', (select v from k where k = 'j1')), '42501', 'člověk nemůže úlohu převzít (jen server)');
select pg_temp.expect_as(:'o', 'authenticated', format($q$select public.ai_job_finish(%L, gen_random_uuid(), true, '{}', '[]', '[]', null)$q$, (select v from k where k = 'j1')), '42501', 'člověk nemůže podvrhnout výsledek AI');

-- ===== fronta: zámek, kontext, výsledek =====
create temp table c1 as select pg_temp.call_as(null, 'service_role', format('select public.ai_job_claim(%L)', (select v from k where k = 'j1'))) j; grant all on c1 to public;
select pg_temp.ok((select j->>'lock_token' from c1) is not null and (select j#>>'{context,firma,nazev}' from c1) = 'Autoservis A', 'server úlohu převezme a dostane kontext firmy A');
select pg_temp.ok((select j::text from c1) not like '%Tajné B%' and (select j::text from c1) not like '%Zákazník B%', 'kontext neobsahuje data firmy B');
select pg_temp.ok(pg_temp.call_as(null, 'service_role', format('select public.ai_job_claim(%L)', (select v from k where k = 'j1'))) is null, 'běžící úlohu nejde převzít podruhé (zámek)');
select pg_temp.expect_as(null, 'service_role', format($q$select public.ai_job_finish(%L, gen_random_uuid(), true, '{"summary":"x"}', '[]', '[]', null)$q$, (select v from k where k = 'j1')), 'PT409', 'výsledek se špatným zámkem je odmítnut');
select pg_temp.ok((pg_temp.call_as(null, 'service_role', format($q$select public.ai_job_reserve(%L, %L, 'gemini-3.5-flash-lite', 3000, 1500)$q$, (select v from k where k = 'j1'), (select j->>'lock_token' from c1))) ->> 'status') = 'reserved', 'rezervace peněz k úloze na účet zadavatele');
select pg_temp.ok((select r.created_by from private.autopilot_runs r join private.ai_jobs j on j.run_id = r.id where j.id = (select v::uuid from k where k = 'j1')) = :'o', 'běh je připsaný člověku, který úlohu zadal');
create temp table f1 as select pg_temp.call_as(null, 'service_role', format($q$select public.ai_job_finish(%L, %L, true, '{"summary":"Tři kroky"}',
  '[{"type":"task","payload":{"title":"Zavolat zákazníkovi A","due_in_days":2}},
    {"type":"customer_note","payload":{"customer_id":"00000000-0000-0000-0000-0000000c0a01","body":"Nabídnout servisní balíček"}},
    {"type":"customer_note","payload":{"customer_id":"00000000-0000-0000-0000-0000000c0b01","body":"Poznámka k cizímu zákazníkovi"}},
    {"type":"site_text","payload":{"field":"hero.title","value":"Nový titulek"}},
    {"type":"finance_entry","payload":{"title":"Podvod","amount":-5,"kind":"income","entry_date":"2026-11-01"}},
    {"type":"quote_draft","payload":{"customer_id":"00000000-0000-0000-0000-0000000c0a01","title":"Servisní balíček","items":[{"name":"Výměna oleje","qty":1,"price":1500},{"name":"Filtr","qty":2,"price":250.5}]}},
    {"type":"goal","payload":{"title":"Tržby 20 tisíc","metric":"trzby","target":20000,"days":30}},
    {"type":"schedule","payload":{"module":"ceo","kind":"weekly_report","cadence":"weekly"}},
    {"type":"product_description","payload":{"product_id":"00000000-0000-0000-0000-0000000d0a01","description":"Plně syntetický motorový olej."}},
    {"type":"sql","payload":{"q":"drop table"}}]', '[]', null)$q$, (select v from k where k = 'j1'), (select j->>'lock_token' from c1))) r; grant all on f1 to public;
select pg_temp.ok((select (r->>'actions')::int from f1) = 7 and (select (r->>'dropped')::int from f1) = 3 and (select r->>'status' from f1) = 'awaiting_approval', 'uloží se 7 platných návrhů; cizí zákazník, záporná částka a neznámý typ se zahodí');
select pg_temp.ok((select count(*) from public.tasks) = 0 and (select data#>>'{hero,title}' from public.sites where company_id = :'A') = 'Starý titulek' and (select count(*) from public.quotes) = 0, 'návrhy AI samy nic nezmění (úkol, web ani nabídka neexistují)');

-- ===== schvalování: jen člověk, konkrétní obsah =====
insert into k select 'a_' || type, id::text from private.ai_actions;
insert into k select 'h_' || type, payload_hash from private.ai_actions;
select pg_temp.expect_as(null, 'service_role', format('select public.ai_action_decide(%L, %L, %L, true)', :'A', (select v from k where k = 'a_task'), (select v from k where k = 'h_task')), '42501', 'service_role nemůže schválit akci za člověka');
select pg_temp.expect_as(:'e', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, true)', :'A', (select v from k where k = 'a_task'), (select v from k where k = 'h_task')), '42501', 'zaměstnanec akci neschválí');
select pg_temp.expect_as(:'x', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, true)', :'B', (select v from k where k = 'a_task'), (select v from k where k = 'h_task')), 'PT404', 'cizí firma akci nevidí');
select pg_temp.expect_as(:'o', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, true)', :'A', (select v from k where k = 'a_task'), repeat('0', 64)), 'PT409', 'schválení s jiným otiskem obsahu je odmítnuto');
select pg_temp.call_as(:'a', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, true)', :'A', (select v from k where k = 'a_task'), (select v from k where k = 'h_task')));
select pg_temp.ok((select count(*) from public.tasks where company_id = :'A' and title = 'Zavolat zákazníkovi A' and due_at > now()) = 1, 'schválený úkol vznikl s termínem');
select pg_temp.ok((pg_temp.call_as(:'a', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, true)', :'A', (select v from k where k = 'a_task'), (select v from k where k = 'h_task'))) ->> 'already')::boolean and (select count(*) from public.tasks) = 1, 'opakované schválení nic nezdvojí');
select pg_temp.call_as(:'o', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, true)', :'A', (select v from k where k = 'a_site_text'), (select v from k where k = 'h_site_text')));
select pg_temp.ok((select data#>>'{hero,title}' from public.sites where company_id = :'A') = 'Nový titulek' and (select result->>'previous' from private.ai_actions where type = 'site_text') = 'Starý titulek', 'text webu se změní až po schválení a původní znění se uloží');
select pg_temp.call_as(:'o', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, true)', :'A', (select v from k where k = 'a_quote_draft'), (select v from k where k = 'h_quote_draft')));
select pg_temp.ok((select total from public.quotes where company_id = :'A' and status = 'draft') = 2001, 'nabídka vznikne jako koncept se spočtenou cenou (1500 + 2×250,50)');
select pg_temp.call_as(:'o', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, true)', :'A', (select v from k where k = 'a_goal'), (select v from k where k = 'h_goal')));
select pg_temp.call_as(:'o', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, true)', :'A', (select v from k where k = 'a_schedule'), (select v from k where k = 'h_schedule')));
select pg_temp.call_as(:'o', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, true)', :'A', (select v from k where k = 'a_product_description'), (select v from k where k = 'h_product_description')));
select pg_temp.call_as(:'o', 'authenticated', format('select public.ai_action_decide(%L, %L, %L, false)', :'A', (select v from k where k = 'a_customer_note'), (select v from k where k = 'h_customer_note')));
select pg_temp.ok((select count(*) from public.client_notes) = 0 and (select status from private.ai_actions where type = 'customer_note') = 'rejected', 'zamítnutá akce se neprovede');
select pg_temp.ok((select status from private.ai_jobs where id = (select v::uuid from k where k = 'j1')) = 'done', 'po rozhodnutí všech akcí je úloha hotová');
create temp table s1 as select pg_temp.call_as(:'o', 'authenticated', format('select public.ai_team_state(%L)', :'A')) s; grant all on s1 to public;
select pg_temp.ok((select (s#>>'{goals,0,value}')::numeric from s1) = 5000 and (select s#>>'{schedules,0,kind}' from s1) = 'weekly_report' and (select jsonb_array_length(s->'actions') from s1) = 7, 'stav pro rozhraní: cíl s plněním ze skutečných tržeb, plán a akce');
select pg_temp.expect_as(:'e', 'authenticated', format('select public.ai_team_state(%L)', :'A'), '42501', 'zaměstnanec stav AI týmu nečte');
select pg_temp.ok((pg_temp.call_as(:'x', 'authenticated', format('select public.ai_team_state(%L)', :'B')))::text not like '%Zavolat zákazníkovi A%', 'firma B nevidí úlohy ani akce firmy A');

-- ===== delegace AI CEO =====
insert into k select 'j2', pg_temp.call_as(:'o', 'authenticated', format($q$select public.ai_job_create(%L, 'ceo', 'orchestrate', 'Chci zvýšit tržby o 20 %%', '{}', 'job-key-0002')$q$, :'A')) ->> 'id';
create temp table c2 as select pg_temp.call_as(null, 'service_role', format('select public.ai_job_claim(%L)', (select v from k where k = 'j2'))) j; grant all on c2 to public;
select pg_temp.call_as(null, 'service_role', format($q$select public.ai_job_finish(%L, %L, true, '{"summary":"Plán"}', '[]',
  '[{"module":"marketing","kind":"plan_30","brief":"Kampaň na servisní balíčky"},{"module":"obchodnik","kind":"opportunities","brief":"Oslovit stávající zákazníky"},
    {"module":"ceo","kind":"orchestrate","brief":"rekurze nesmí projít"},{"module":"hack","kind":"x","brief":"neplatný modul"}]', null)$q$, (select v from k where k = 'j2'), (select j->>'lock_token' from c2)));
select pg_temp.ok((select count(*) from private.ai_jobs where parent_id = (select v::uuid from k where k = 'j2') and status = 'queued' and source = 'ceo' and created_by = :'o') = 2, 'AI CEO rozdělí zadání na 2 platné dílčí úlohy (rekurze a neznámý modul se zahodí)');

-- ===== plány a běh na pozadí =====
select pg_temp.expect_as(:'o', 'authenticated', format($q$select public.ai_schedule_save(%L, 'ceo', 'risks', 'weekly', '', true)$q$, :'A'), 'PT422', 'úlohu, která není určená k plánování, naplánovat nelze');
select pg_temp.expect_as(null, 'service_role', format($q$select public.ai_schedule_save(%L, 'ceo', 'monthly_report', 'monthly', '', true)$q$, :'A'), '42501', 'plán může schválit jen člověk, ne service_role');
select pg_temp.call_as(:'a', 'authenticated', format($q$select public.ai_schedule_save(%L, 'ucetnictvi', 'unpaid_followup', 'daily', 'Hlídej splatnost', true)$q$, :'A'));
select pg_temp.expect_as(:'o', 'authenticated', 'select public.ai_schedule_tick(5)', '42501', 'tik plánovače spouští jen server');
update private.ai_schedules set next_run_at = now() - interval '1 minute' where kind = 'unpaid_followup';
create temp table t1 as select pg_temp.call_as(null, 'service_role', 'select public.ai_schedule_tick(5)') t; grant all on t1 to public;
select pg_temp.ok((select (t->>'created')::int from t1) = 1 and (select jsonb_array_length(t->'jobs') from t1) = 1, 'splatný plán založí jednu úlohu');
select pg_temp.ok((pg_temp.call_as(null, 'service_role', 'select public.ai_schedule_tick(5)') ->> 'created')::int = 0 and (select count(*) from private.ai_jobs where source = 'schedule') = 1, 'druhý tik týž den nezaloží duplicitní úlohu');
insert into k select 'j3', (select t#>>'{jobs,0}' from t1);
create temp table c3 as select pg_temp.call_as(null, 'service_role', format('select public.ai_job_claim(%L)', (select v from k where k = 'j3'))) j; grant all on c3 to public;
select pg_temp.ok((select j->>'created_by' from c3) = :'a', 'úloha z plánu běží na účet toho, kdo plán schválil');
select pg_temp.call_as(null, 'service_role', format($q$select public.ai_job_finish(%L, %L, false, null, null, null, 'upstream')$q$, (select v from k where k = 'j3'), (select j->>'lock_token' from c3)));
select pg_temp.ok((select status = 'queued' and next_attempt_at > now() and attempts = 1 from private.ai_jobs where id = (select v::uuid from k where k = 'j3')), 'neúspěšná úloha z plánu se zařadí k opakování s odstupem');
update private.ai_jobs set next_attempt_at = now(), attempts = 3 where id = (select v::uuid from k where k = 'j3');
select pg_temp.ok(pg_temp.call_as(null, 'service_role', format('select public.ai_job_claim(%L)', (select v from k where k = 'j3'))) is null, 'úlohu s vyčerpanými pokusy už nejde převzít');
select pg_temp.ok((select status from private.ai_jobs where id = (select v::uuid from k where k = 'j3')) = 'failed', 'po vyčerpání pokusů úloha skončí jako neúspěšná');
-- ten, kdo plán schválil, přestane být správcem: úloha se nespustí
update private.ai_schedules set next_run_at = now() - interval '1 minute' where kind = 'unpaid_followup';
update private.ai_jobs set idempotency_key = idempotency_key || '-old' where source = 'schedule';
select pg_temp.call_as(null, 'service_role', 'select public.ai_schedule_tick(5)');
update public.company_members set role = 'employee' where user_id = :'a';
select pg_temp.ok(pg_temp.call_as(null, 'service_role', format('select public.ai_job_claim(%L)', (select id from private.ai_jobs where source = 'schedule' and status = 'queued'))) is null, 'úlohu plánu schváleného bývalým správcem nejde převzít');
select pg_temp.ok(exists (select 1 from private.ai_jobs where error = 'requester_not_allowed' and status = 'failed'), 'plán schválený bývalým správcem se už nespustí');
update public.company_members set role = 'admin' where user_id = :'a';
select pg_temp.ok((pg_temp.call_as(:'o', 'authenticated', format('select public.ai_schedule_stop_all(%L)', :'A')) ->> 'schedules_stopped')::int = 2, 'zastavení automatizace vypne oba plány');
select pg_temp.ok((select count(*) from private.ai_schedules where enabled) = 0 and (select count(*) from private.ai_jobs where status = 'queued') = 0, 'po zastavení nezůstane zapnutý plán ani čekající úloha');

-- ===== chat =====
insert into k select 'rc', pg_temp.call_as(:'o', 'authenticated', format($q$select public.autopilot_reserve(%L, 'ceo', 'gemini-3.5-flash-lite', 2000, 700, 'chat-key-0001')$q$, :'A')) ->> 'run_id';
select pg_temp.expect_as(:'o', 'authenticated', format($q$select public.ai_chat_store(%L, 'ceo', %L, 'Ahoj', 'Dobrý den')$q$, :'A', (select v from k where k = 'rc')), '42501', 'historii chatu zapisuje jen server');
select pg_temp.call_as(null, 'service_role', format($q$select public.ai_chat_store(%L, 'ceo', %L, 'Jak jsme na tom?', 'Tržby 5 000 Kč.')$q$, :'A', (select v from k where k = 'rc')));
select pg_temp.call_as(null, 'service_role', format($q$select public.ai_chat_store(%L, 'ceo', %L, 'Jak jsme na tom?', 'Tržby 5 000 Kč.')$q$, :'A', (select v from k where k = 'rc')));
select pg_temp.ok(jsonb_array_length(pg_temp.call_as(:'o', 'authenticated', format($q$select public.ai_chat_history(%L, 'ceo')$q$, :'A'))) = 2 and jsonb_array_length(pg_temp.call_as(:'a', 'authenticated', format($q$select public.ai_chat_history(%L, 'ceo')$q$, :'A'))) = 0, 'historie chatu: bez zdvojení a každý uživatel jen svou');
select pg_temp.expect_as(null, 'service_role', format($q$select public.ai_chat_store(%L, 'ceo', %L, 'x', 'y')$q$, :'B', (select v from k where k = 'rc')), 'PT404', 'chat nejde připsat jiné firmě než běh');
select pg_temp.ok((pg_temp.call_as(:'o', 'authenticated', format($q$select public.ai_context(%L, 'ceo')$q$, :'A')) #>> '{finance,mesice,5,prijmy}')::numeric = 5000, 'kontext pro AI CEO počítá server ze skutečných záznamů');
select pg_temp.expect_as(:'x', 'authenticated', format($q$select public.ai_context(%L, 'ceo')$q$, :'A'), '42501', 'cizí firma kontext nezíská');

-- ===== AI Účetnictví =====
select pg_temp.expect_as(:'e', 'authenticated', format($q$select public.acc_document_store(%L, %L, 'application/pdf', '{"total_amount":100}')$q$, :'A', repeat('a', 64)), '42501', 'zaměstnanec doklad neuloží');
insert into k select 'd1', pg_temp.call_as(:'o', 'authenticated', format($q$select public.acc_document_store(%L, %L, 'application/pdf',
  '{"document_type":"received_invoice","supplier_name":"Dodavatel s.r.o.","supplier_ico":"12 345 678","document_number":"FV-2026-15","issue_date":"2026-11-03","total_amount":1210,"vat_amount":210,"vat_rate":21,"category":"material","hack":"<script>"}')$q$, :'A', repeat('a', 64))) ->> 'id';
select pg_temp.ok((select doc->>'supplier_ico' = '12345678' and not doc ? 'hack' and duplicate_of is null from private.acc_documents where id = (select v::uuid from k where k = 'd1')), 'doklad se uloží očištěný (IČO bez mezer, neznámá pole pryč)');
select pg_temp.ok((pg_temp.call_as(:'o', 'authenticated', format($q$select public.acc_document_store(%L, %L, 'application/pdf', '{"supplier_name":"Jiný","document_number":"1","total_amount":5,"issue_date":"2026-11-03"}')$q$, :'A', repeat('a', 64))) ->> 'duplicate_reason') = 'same_file', 'duplicita: stejný soubor');
insert into k select 'd3', pg_temp.call_as(:'o', 'authenticated', format($q$select public.acc_document_store(%L, %L, 'image/jpeg', '{"document_type":"received_invoice","supplier_ico":"12345678","document_number":"fv-2026-15","total_amount":1210,"issue_date":"2026-11-03"}')$q$, :'A', repeat('b', 64))) ->> 'id';
select pg_temp.ok((select duplicate_of from private.acc_documents where id = (select v::uuid from k where k = 'd3')) = (select v::uuid from k where k = 'd1'), 'duplicita: stejný dodavatel, číslo a částka z jiného souboru');
select pg_temp.expect_as(null, 'service_role', format('select public.acc_document_decide(%L, %L, %L, true, false)', :'A', (select v from k where k = 'd1'), (select doc_hash from private.acc_documents where id = (select v::uuid from k where k = 'd1'))), '42501', 'doklad neschválí service_role');
select pg_temp.expect_as(:'o', 'authenticated', format('select public.acc_document_decide(%L, %L, %L, true, false)', :'A', (select v from k where k = 'd1'), repeat('0', 64)), 'PT409', 'schválení dokladu s jiným otiskem je odmítnuto');
select pg_temp.call_as(:'o', 'authenticated', format('select public.acc_document_decide(%L, %L, %L, true, false)', :'A', (select v from k where k = 'd1'), (select doc_hash from private.acc_documents where id = (select v::uuid from k where k = 'd1'))));
select pg_temp.ok((select count(*) from public.financial_entries where company_id = :'A' and kind = 'expense' and amount = 1210 and entry_date = date '2026-11-03') = 1, 'schválený doklad vytvoří výdaj v evidenci');
select pg_temp.expect_as(:'o', 'authenticated', format('select public.acc_document_decide(%L, %L, %L, true, false)', :'A', (select v from k where k = 'd3'), (select doc_hash from private.acc_documents where id = (select v::uuid from k where k = 'd3'))), 'PT409', 'duplicitní doklad nejde schválit bez výslovného potvrzení', 'duplicate');
select pg_temp.ok((select count(*) from public.financial_entries where company_id = :'A' and kind = 'expense') = 1, 'duplicitní doklad nevytvořil druhý výdaj');
select pg_temp.call_as(:'o', 'authenticated', format($q$select public.acc_document_update(%L, %L, %L, '{"document_type":"received_invoice","supplier_ico":"12345678","document_number":"FV-2026-16","total_amount":605,"vat_amount":105,"vat_rate":21,"issue_date":"2026-11-04"}')$q$, :'A', (select v from k where k = 'd3'), (select doc_hash from private.acc_documents where id = (select v::uuid from k where k = 'd3'))));
select pg_temp.ok((select duplicate_of is null and ai_doc->>'document_number' = 'fv-2026-15' from private.acc_documents where id = (select v::uuid from k where k = 'd3')), 'oprava člověkem zruší příznak duplicity a původní návrh AI zůstane uložený');
select pg_temp.call_as(:'o', 'authenticated', format('select public.acc_document_decide(%L, %L, %L, true, false)', :'A', (select v from k where k = 'd3'), (select doc_hash from private.acc_documents where id = (select v::uuid from k where k = 'd3'))));
insert into public.invoices (id, company_id, lifecycle, number, issued_on, taxable_supply_on, due_on, vat_payer, total) values ('00000000-0000-0000-0000-0000000f0a01', :'A', 'issued', '20260001', '2026-11-05', '2026-11-05', '2026-11-19', true, 2420);
insert into public.invoice_items (company_id, invoice_id, vat_rate, gross, net, tax) values (:'A', '00000000-0000-0000-0000-0000000f0a01', 21, 2420, 2000, 420);
create temp table v1 as select pg_temp.call_as(:'o', 'authenticated', format($q$select public.acc_vat_summary(%L, '2026-11-01', '2026-11-30')$q$, :'A')) v; grant all on v1 to public;
select pg_temp.ok((select (v#>>'{output,0,vat}')::numeric from v1) = 420 and (select (v#>>'{input,0,vat}')::numeric from v1) = 315 and (select v->>'note' from v1) like 'Orientační%', 'přehled DPH: výstup 420 z faktur, vstup 315 ze schválených dokladů, s upozorněním');
select pg_temp.ok((select jsonb_array_length(e->'entries') = 3 and jsonb_array_length(e->'documents') = 2 and jsonb_array_length(e->'invoices') = 1 from (select pg_temp.call_as(:'a', 'authenticated', format($q$select public.acc_export(%L, '2026-11-01', '2026-11-30')$q$, :'A')) e) q), 'export: záznamy, doklady a faktury za období');
select pg_temp.expect_as(:'x', 'authenticated', format($q$select public.acc_export(%L, '2026-11-01', '2026-11-30')$q$, :'A'), '42501', 'cizí firma export nezíská');
select pg_temp.call_as(:'o', 'authenticated', format($q$select public.acc_settings_save(%L, 'danova_evidence', true)$q$, :'A'));
select pg_temp.ok((pg_temp.call_as(:'o', 'authenticated', format('select public.acc_state(%L)', :'A')) #>> '{settings,regime}') = 'danova_evidence', 'režim (daňová evidence / účetnictví) se uloží');
select pg_temp.ok((pg_temp.call_as(:'x', 'authenticated', format('select public.acc_state(%L)', :'B')))::text not like '%Dodavatel s.r.o.%', 'firma B nevidí doklady firmy A');
-- přímý přístup k tabulkám
select pg_temp.expect_as(:'o', 'authenticated', 'select to_jsonb(count(*)) from private.ai_jobs', '42501', 'tabulky AI týmu nejsou přes API přímo čitelné');
select pg_temp.ok(not has_function_privilege('anon', 'public.ai_team_state(uuid)', 'execute') and not has_function_privilege('authenticated', 'public.ai_job_finish(uuid,uuid,boolean,jsonb,jsonb,jsonb,text)', 'execute')
  and not has_function_privilege('service_role', 'public.ai_action_decide(uuid,uuid,text,boolean)', 'execute') and not has_function_privilege('service_role', 'public.acc_document_decide(uuid,uuid,text,boolean,boolean)', 'execute'), 'práva funkcí: anon nic, člověk nezapisuje výsledky AI, server neschvaluje');
do $$ begin raise notice 'VŠECHNY TESTY AI TÝMU PROŠLY'; end $$;
rollback;
