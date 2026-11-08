-- AI Marketing: hranice a průchod strategie → příspěvky → schválení → publikace → výsledky (po migracích profilu, Autopilota a 20261112100000).
\set ON_ERROR_STOP on
\pset tuples_only on
begin;
\i db/test/helpers.sql
update private.autopilot_platform set paid_runs_enabled = true;   -- jen v testu
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
-- potvrzený profil jen u firmy A
insert into private.company_profile_versions (id, company_id, version, schema_version, data, content_hash, source_revision, confirmed_by)
  values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000ca01', 1, 1, '{"shared":{}}', repeat('a', 64), 1, '00000000-0000-0000-0000-00000000b001');
insert into private.company_active_profile values ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000f1');
\set o '00000000-0000-0000-0000-00000000b001'
\set a '00000000-0000-0000-0000-00000000b002'
\set e '00000000-0000-0000-0000-00000000b003'
\set x '00000000-0000-0000-0000-00000000b004'
\set A '00000000-0000-0000-0000-00000000ca01'
\set B '00000000-0000-0000-0000-00000000cb01'
create temp table k (k text primary key, v text); grant all on k to public;
select pg_temp.call_as(:'o', 'authenticated', format('select public.autopilot_set_budget(%L, 250000000)', :'A'));
select pg_temp.call_as(:'x', 'authenticated', format('select public.autopilot_set_budget(%L, 250000000)', :'B'));
insert into k select 'run1', pg_temp.call_as(:'o', 'authenticated', format($q$select public.autopilot_reserve(%L, 'marketing', 'gemini-3.5-flash-lite', 3000, 2000, 'test-strategie-0001')$q$, :'A')) ->> 'run_id';
insert into k select 'runB', pg_temp.call_as(:'x', 'authenticated', format($q$select public.autopilot_reserve(%L, 'marketing', 'gemini-3.5-flash-lite', 3000, 2000, 'test-strategie-b001')$q$, :'B')) ->> 'run_id';
insert into k values ('doc', '{"goal":{"metric":"poptavky","target":20,"days":30},"audience":"Majitelé aut v Konině a okolí","positioning":"Rychlý a férový autoservis s online rezervací","tone":"přátelský","channels":[{"channel":"Facebook","why":"místní komunita"},{"channel":"Web nebo blog","why":"vlastní web firmy"}],"themes":[{"title":"Přezutí pneumatik","angle":"sezóna"},{"title":"Výměna výfuku","angle":"bezpečnost a hluk"}],"cadence_per_week":2}');

-- ===== strategie =====
select pg_temp.expect_as(:'o', 'authenticated', format('select public.mkt_strategy_store(%L, %L, %L::jsonb)', :'A', (select v from k where k = 'run1'), (select v from k where k = 'doc')), '42501', 'S: výsledek AI nemůže uložit uživatel z prohlížeče (jen server)');
select pg_temp.expect_as(null, 'service_role', format('select public.mkt_strategy_store(%L, %L, %L::jsonb)', :'A', (select v from k where k = 'runB'), (select v from k where k = 'doc')), 'PT404', 'S: běh jiné firmy nelze použít');
select pg_temp.expect_as(null, 'service_role', format('select public.mkt_strategy_store(%L, %L, %L::jsonb)', :'A', (select v from k where k = 'run1'), '{"goal":{"metric":"lajky","target":5,"days":30}}'), 'PT422', 'S: neplatný návrh AI se neuloží');
select pg_temp.expect_as(null, 'service_role', format('select public.mkt_strategy_store(%L, %L, %L::jsonb)', :'B', (select v from k where k = 'runB'), (select v from k where k = 'doc')), 'PT412', 'S: bez potvrzeného profilu se strategie neuloží');
insert into k select 's1', pg_temp.call_as(null, 'service_role', format('select public.mkt_strategy_store(%L, %L, %L::jsonb)', :'A', (select v from k where k = 'run1'), (select v from k where k = 'doc'))) ->> 'id';
select pg_temp.ok((pg_temp.call_as(null, 'service_role', format('select public.mkt_strategy_store(%L, %L, %L::jsonb)', :'A', (select v from k where k = 'run1'), (select v from k where k = 'doc'))) ->> 'reused') = 'true', 'S: opakované uložení téhož běhu nevytvoří druhou strategii');
select pg_temp.expect_as(:'e', 'authenticated', format('select public.mkt_state(%L)', :'A'), '42501', 'S: zaměstnanec stav Autopilota nevidí');
select pg_temp.expect_as(:'x', 'authenticated', format('select public.mkt_state(%L)', :'A'), '42501', 'S: cizí firma stav nevidí');
select pg_temp.ok((pg_temp.call_as(:'a', 'authenticated', format('select public.mkt_state(%L)', :'A')) #>> '{strategy,status}') = 'draft'
  and (pg_temp.call_as(:'a', 'authenticated', format('select public.mkt_state(%L)', :'A')) #>> '{profile,confirmed}') = 'true', 'S: správce vidí koncept strategie a potvrzený profil');
insert into k select 'h1', pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_state(%L)', :'A')) #>> '{strategy,hash}';
select pg_temp.expect_as(:'o', 'authenticated', format('select public.mkt_strategy_approve(%L, %L, %L)', :'A', (select v from k where k = 's1'), repeat('0', 64)), 'PT409', 'S: schválit jde jen obsah, který člověk viděl (otisk)');
select pg_temp.expect_as(null, 'service_role', format('select public.mkt_strategy_approve(%L, %L, %L)', :'A', (select v from k where k = 's1'), (select v from k where k = 'h1')), '42501', 'S: server (service_role) strategii neschválí, jen člověk');
select pg_temp.expect_as(:'e', 'authenticated', format('select public.mkt_strategy_approve(%L, %L, %L)', :'A', (select v from k where k = 's1'), (select v from k where k = 'h1')), '42501', 'S: zaměstnanec neschvaluje');
select pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_strategy_approve(%L, %L, %L)', :'A', (select v from k where k = 's1'), (select v from k where k = 'h1')));
select pg_temp.ok((pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_state(%L)', :'A')) #>> '{approved,id}') = (select v from k where k = 's1'), 'S: vlastník schválil strategii');
-- úprava schválené vytvoří nový koncept, schválená platí dál
insert into k select 's2', pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_strategy_edit(%L, %L, %L, %L::jsonb)', :'A', (select v from k where k = 's1'), (select v from k where k = 'h1'),
  jsonb_set((select v from k where k = 'doc')::jsonb, '{goal,target}', '25')::text)) ->> 'id';
select pg_temp.ok((select v from k where k = 's2') <> (select v from k where k = 's1') and (pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_state(%L)', :'A')) #>> '{approved,id}') = (select v from k where k = 's1'),
  'S: úprava schválené strategie vznikne jako nový koncept, schválená platí dál');

-- ===== návrhy příspěvků =====
insert into k select 'run2', pg_temp.call_as(:'o', 'authenticated', format($q$select public.autopilot_reserve(%L, 'marketing', 'gemini-3.5-flash-lite', 3000, 2000, 'test-prispevky-0001')$q$, :'A')) ->> 'run_id';
insert into k values ('posts', format('[{"title":"Přezujte včas","channel":"Facebook","planned_on":"%s","body":"Zimní pneumatiky přezujeme do 30 minut. Rezervujte si termín online."},{"title":"Tichý výfuk","channel":"Web nebo blog","planned_on":"%s","body":"Hlučný výfuk? Vyměníme ho rychle a za férovou cenu, rezervace online."}]', current_date, current_date + 3));
select pg_temp.expect_as(null, 'service_role', format('select public.mkt_posts_store(%L, %L, %L, %L::jsonb)', :'A', (select v from k where k = 'run2'), (select v from k where k = 's2'), (select v from k where k = 'posts')), 'PT412', 'P: příspěvky jen ze SCHVÁLENÉ strategie');
select pg_temp.expect_as(null, 'service_role', format('select public.mkt_posts_store(%L, %L, %L, %L::jsonb)', :'A', (select v from k where k = 'run2'), (select v from k where k = 's1'), '[{"title":"X","channel":"TikTok","planned_on":"2026-12-01","body":"krátké"}]'), 'PT422', 'P: neplatný návrh se neuloží');
insert into k select 'ps', pg_temp.call_as(null, 'service_role', format('select public.mkt_posts_store(%L, %L, %L, %L::jsonb)', :'A', (select v from k where k = 'run2'), (select v from k where k = 's1'), (select v from k where k = 'posts')))::text;
select pg_temp.ok((pg_temp.call_as(null, 'service_role', format('select public.mkt_posts_store(%L, %L, %L, %L::jsonb)', :'A', (select v from k where k = 'run2'), (select v from k where k = 's1'), (select v from k where k = 'posts'))) ->> 'reused') = 'true'
  and (select count(*) from public.marketing_posts where company_id = :'A') = 2, 'P: opakovaný požadavek nevytvoří duplicitní koncepty');
insert into k select 'p1', (select v from k where k = 'ps')::jsonb #>> '{post_ids,0}';
insert into k select 'p2', (select v from k where k = 'ps')::jsonb #>> '{post_ids,1}';
select pg_temp.ok((select status from public.marketing_posts where id = (select v from k where k = 'p1')::uuid) = 'draft' and (select created_by from public.marketing_posts where id = (select v from k where k = 'p1')::uuid) = :'o',
  'P: návrhy jsou koncepty, autor je člověk, který běh spustil');
select pg_temp.ok(pg_temp.call_as(:'e', 'authenticated', $q$select to_jsonb(count(*)) from public.marketing_posts$q$) = '2'::jsonb, 'P: zaměstnanec koncepty vidí (čtení podle členství)');

-- ===== schválení =====
insert into k select 'hp1', private.mkt_hash(title, body, channel) from public.marketing_posts where id = (select v from k where k = 'p1')::uuid;
insert into k select 'hp2', private.mkt_hash(title, body, channel) from public.marketing_posts where id = (select v from k where k = 'p2')::uuid;
select pg_temp.expect_as(:'o', 'authenticated', format('select public.mkt_publish(%L, %L, %L)', :'A', (select v from k where k = 'p1'), 'Facebook'), 'PT412', 'A: neschválený příspěvek nelze zveřejnit');
select pg_temp.expect_as(:'o', 'authenticated', format('select public.mkt_post_approve(%L, %L, %L)', :'A', (select v from k where k = 'p1'), repeat('0', 64)), 'PT409', 'A: schvaluje se konkrétní obsah (otisk)');
select pg_temp.expect_as(:'e', 'authenticated', format('select public.mkt_post_approve(%L, %L, %L)', :'A', (select v from k where k = 'p1'), (select v from k where k = 'hp1')), '42501', 'A: zaměstnanec neschvaluje');
select pg_temp.expect_as(:'x', 'authenticated', format('select public.mkt_post_approve(%L, %L, %L)', :'B', (select v from k where k = 'p1'), (select v from k where k = 'hp1')), 'PT404', 'A: cizí firma příspěvek nenajde ani se znalostí ID');
select pg_temp.call_as(:'a', 'authenticated', format('select public.mkt_post_approve(%L, %L, %L)', :'A', (select v from k where k = 'p1'), (select v from k where k = 'hp1')));
select pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_post_approve(%L, %L, %L)', :'A', (select v from k where k = 'p2'), (select v from k where k = 'hp2')));
select pg_temp.ok((select status from public.marketing_posts where id = (select v from k where k = 'p1')::uuid) = 'planned', 'A: schválený příspěvek je naplánovaný');
-- úprava po schválení zruší schválení
select pg_temp.call_as(:'o', 'authenticated', format($q$with u as (update public.marketing_posts set body = body || ' Upraveno.' where id = %L returning 1) select to_jsonb(count(*)) from u$q$, (select v from k where k = 'p1')));
select pg_temp.ok((select status from public.marketing_posts where id = (select v from k where k = 'p1')::uuid) = 'draft'
  and (select approved_hash is null from private.mkt_items where post_id = (select v from k where k = 'p1')::uuid), 'A: změna schváleného obsahu vrátí příspěvek do konceptu');
select pg_temp.expect_as(:'o', 'authenticated', format('select public.mkt_publish(%L, %L, %L)', :'A', (select v from k where k = 'p1'), 'Facebook'), 'PT412', 'A: změněný obsah nelze zveřejnit bez nového schválení');

-- ===== publikace na web firmy =====
select pg_temp.expect_as(:'o', 'authenticated', format('select public.mkt_publish(%L, %L, %L)', :'A', (select v from k where k = 'p2'), 'web'), 'PT412', 'W: bez webu firmy nelze publikovat na web');
insert into public.sites (company_id, slug, enabled, data) values (:'A', 'autoservis-a', true, '{}');
select pg_temp.ok((pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_publish(%L, %L, %L)', :'A', (select v from k where k = 'p2'), 'web')) ->> 'live') = 'false', 'W: příspěvek s budoucím datem je naplánovaný, ne zveřejněný');
select pg_temp.ok(pg_temp.call_as(null, 'anon', $q$select public.public_site_news('autoservis-a')$q$) = '[]'::jsonb, 'W: veřejný web budoucí příspěvek neukáže');
update private.mkt_items set web_publish_on = current_date where post_id = (select v from k where k = 'p2')::uuid;   -- přišel den publikace
select pg_temp.ok(pg_temp.call_as(null, 'anon', $q$select public.public_site_news('autoservis-a')$q$) -> 0 ->> 'title' = 'Tichý výfuk', 'W: v den publikace je příspěvek na veřejném webu (bez plánovače)');
select pg_temp.ok(pg_temp.call_as(null, 'anon', $q$select public.public_site_news('neexistuje')$q$) = '[]'::jsonb, 'W: jiný web příspěvky firmy neukáže');
select pg_temp.call_as(:'o', 'authenticated', format($q$with u as (update public.marketing_posts set title = 'Tichý výfuk!' where id = %L returning 1) select to_jsonb(count(*)) from u$q$, (select v from k where k = 'p2')));
select pg_temp.ok(pg_temp.call_as(null, 'anon', $q$select public.public_site_news('autoservis-a')$q$) = '[]'::jsonb, 'W: změněný (neschválený) obsah z webu zmizí');
-- ruční zveřejnění s odkazem
insert into k select 'hp2b', private.mkt_hash(title, body, channel) from public.marketing_posts where id = (select v from k where k = 'p2')::uuid;
select pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_post_approve(%L, %L, %L)', :'A', (select v from k where k = 'p2'), (select v from k where k = 'hp2b')));
select pg_temp.expect_as(:'o', 'authenticated', format('select public.mkt_publish(%L, %L, %L, %L)', :'A', (select v from k where k = 'p2'), 'Facebook', 'http://nezabezpeceny.test'), 'PT422', 'M: odkaz na ručně zveřejněný příspěvek musí být https');
select pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_publish(%L, %L, %L, %L)', :'A', (select v from k where k = 'p2'), 'Facebook', 'https://facebook.com/autoservis/posts/1'));
select pg_temp.ok((select status from public.marketing_posts where id = (select v from k where k = 'p2')::uuid) = 'done', 'M: ruční zveřejnění se zaznamená');

-- ===== výsledky =====
select pg_temp.expect_as(:'o', 'authenticated', format($q$select public.mkt_result_add(%L, %L, 'dosah', 120, current_date, current_date, 'Facebook přehled')$q$, :'A', (select v from k where k = 'p1')), 'PT412', 'R: výsledky jen u zveřejněného příspěvku');
select pg_temp.expect_as(:'e', 'authenticated', format($q$select public.mkt_result_add(%L, %L, 'dosah', 120, current_date, current_date, 'Facebook přehled')$q$, :'A', (select v from k where k = 'p2')), '42501', 'R: zaměstnanec výsledky nezadává');
select pg_temp.call_as(:'o', 'authenticated', format($q$select public.mkt_result_add(%L, %L, 'dosah', 120, current_date, current_date, 'Facebook přehled')$q$, :'A', (select v from k where k = 'p2')));
insert into public.deals (company_id, title, created_at) values (:'A', 'poptávka po zveřejnění', now() + interval '1 minute'), (:'A', 'starší poptávka', now() - interval '3 days'), (:'B', 'cizí', now() + interval '1 minute');
select pg_temp.ok((pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_results(%L)', :'A')) -> 0 #>> '{system,poptavky,after}') = '1'
  and (pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_results(%L)', :'A')) -> 0 #>> '{system,poptavky,before}') = '1'
  and (pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_results(%L)', :'A')) -> 0 #>> '{manual,0,source}') = 'Facebook přehled',
  'R: výsledky z DB téže firmy (7 dní po vs. před) a ručně zadané metriky se zdrojem');
select pg_temp.ok((pg_temp.call_as(:'o', 'authenticated', format('select public.mkt_state(%L)', :'A')) #>> '{progress,value}')::int >= 1, 'R: plnění cíle strategie se počítá ze skutečných poptávek');

do $$ begin raise notice 'VŠECHNY KONTROLY PROŠLY'; end $$;
rollback;
