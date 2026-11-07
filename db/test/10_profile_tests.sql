-- Testy profilu firmy. Spouštět po 01_base_stub.sql a migraci 20261107120000_profil_firmy.sql.
-- Celé běží v jedné transakci a končí ROLLBACKem, takže po sobě nezanechají žádná data.
-- Funguje v lokálním PostgreSQL (po 00_local_supabase_shim.sql) i v bezplatném Supabase projektu
-- (SQL Editor nebo psql jako uživatel postgres). Při první chybě skončí (ON_ERROR_STOP).
\set ON_ERROR_STOP on
\pset tuples_only on
begin;

-- ---- pomocné funkce (existují jen v této relaci) ------------------------------------------------
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
    if must_detail is not null and position(must_detail in coalesce(d, '')) = 0 then
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

-- ---- fixtury ------------------------------------------------------------------------------------
-- u1 majitel hlavní firmy, u2 správce hlavní firmy, u3 zaměstnanec, u4 majitel cizí firmy,
-- u5 správce jen v pobočce, u6 bez členství, u7 majitel firmy s prošlou zkušební dobou
insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0000-0000-0000-0000000000a' || n)::uuid, 'test' || n || '@example.invalid', now() from generate_series(1, 7) n;
insert into public.companies (id, owner_id, name, parent_company_id, created_at) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1', 'Autoservis Konina', null, now() - interval '3 days'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000a1', 'Konina Beroun', '00000000-0000-0000-0000-0000000000c1', now() - interval '2 days'),
  ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000a4', 'Cizí firma', null, now()),
  ('00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000a7', 'Prošlá zkouška', null, now());
insert into public.company_members (company_id, user_id, role) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1', 'owner'),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a2', 'admin'),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a3', 'employee'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000a1', 'owner'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000a5', 'admin'),
  ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000a4', 'owner'),
  ('00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000a7', 'owner');
insert into public.subscriptions (company_id, plan, status, trial_end) values
  ('00000000-0000-0000-0000-0000000000c1', 'pro', 'trial', now() + interval '20 days'),
  ('00000000-0000-0000-0000-0000000000c2', 'pro', 'trial', now() + interval '20 days'),
  ('00000000-0000-0000-0000-0000000000c3', 'start', 'active', null),
  ('00000000-0000-0000-0000-0000000000c4', 'pro', 'trial', now() - interval '1 day');

\set u1 '00000000-0000-0000-0000-0000000000a1'
\set u2 '00000000-0000-0000-0000-0000000000a2'
\set u3 '00000000-0000-0000-0000-0000000000a3'
\set u4 '00000000-0000-0000-0000-0000000000a4'
\set u5 '00000000-0000-0000-0000-0000000000a5'
\set u6 '00000000-0000-0000-0000-0000000000a6'
\set u7 '00000000-0000-0000-0000-0000000000a7'
\set c1 '00000000-0000-0000-0000-0000000000c1'
\set c2 '00000000-0000-0000-0000-0000000000c2'
\set c3 '00000000-0000-0000-0000-0000000000c3'
\set c4 '00000000-0000-0000-0000-0000000000c4'

select (pg_temp.call_as(:'u1', 'authenticated', $q$ select to_jsonb((public.profile_schema_info()->>'version')::int) $q$))::text as ver \gset

-- ---- 1) konceptu: první uložení, konflikt revize --------------------------------------------------
select pg_temp.call_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 0, %s, %L::jsonb) $q$, :'c1', :ver,
  '{"shared":{"identity":{"displayName":"  Autoservis Konina  ","activity":"autoservis a výfuky"}},"local":{"geography":{"city":"Praha"}}}')) ->> 'revision' as rev1 \gset
select pg_temp.ok(:rev1 = 1, 'první uložení konceptu vrací revizi 1');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 0, %s, '{"shared":{},"local":{}}'::jsonb) $q$, :'c1', :ver),
  'PT409', 'zastaralá revize (0 místo 1) vrací PT409', '"current_revision": 1');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 5, %s, '{"shared":{},"local":{}}'::jsonb) $q$, :'c1', :ver),
  'PT409', 'budoucí revize (5) vrací PT409', 'current_revision');
select (pg_temp.call_as(:'u1', 'authenticated', format($q$ select public.profile_get(%L) $q$, :'c1')) #>> '{draft,data,shared,identity,displayName}') as dn \gset
select pg_temp.ok(:'dn' = 'Autoservis Konina', 'okraje textu se ořežou (trim)');

-- stejná data = beze změny, revize se nezvýší
select (pg_temp.call_as(:'u2', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, %s, %L::jsonb) $q$, :'c1', :ver,
  '{"shared":{"identity":{"displayName":"Autoservis Konina","activity":"autoservis a výfuky"}},"local":{"geography":{"city":"Praha"}}}')) ->> 'revision') as rev_same \gset
select pg_temp.ok(:rev_same = 1, 'uložení stejných dat revizi nezvyšuje (a správce smí)');

-- ---- 2) oprávnění --------------------------------------------------------------------------------------
select pg_temp.expect_as(:'u3', 'authenticated', format($q$ select public.profile_get(%L) $q$, :'c1'), '42501', 'zaměstnanec nesmí číst');
select pg_temp.expect_as(:'u3', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, %s, '{"shared":{},"local":{}}'::jsonb) $q$, :'c1', :ver), '42501', 'zaměstnanec nesmí ukládat');
select pg_temp.expect_as(:'u4', 'authenticated', format($q$ select public.profile_get(%L) $q$, :'c1'), '42501', 'člen cizí firmy nesmí číst');
select pg_temp.expect_as(:'u6', 'authenticated', format($q$ select public.profile_get(%L) $q$, :'c1'), '42501', 'uživatel bez členství nesmí číst');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_get(%L) $q$, :'c3'), '42501', 'majitel A nesmí číst firmu B (podvržené cid)');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 0, %s, '{"shared":{},"local":{}}'::jsonb) $q$, :'c3', :ver), '42501', 'majitel A nesmí ukládat do firmy B');
select pg_temp.expect_as(null, 'anon', format($q$ select public.profile_get(%L) $q$, :'c1'), '42501', 'anon nemá právo volat profile_get');
select pg_temp.expect_as(null, 'service_role', format($q$ select public.profile_get(%L) $q$, :'c1'), '42501', 'service_role nemá právo volat profile_get');
select pg_temp.expect_as(null, 'service_role', format($q$ select public.profile_confirm(%L, 1, 'x') $q$, :'c1'), '42501', 'service_role nemůže potvrdit profil');
-- i kdyby práva na funkci byla (superuživatel), bez lidské identity se nic nepotvrdí:
select pg_temp.expect_as(null, 'postgres', format($q$ select public.profile_confirm(%L, 1, 'x') $q$, :'c1'), '42501', 'bez identity (auth.uid() null) se nepotvrdí ani jako postgres');
select pg_temp.expect_as(:'u1', 'postgres', format($q$ select public.profile_confirm(%L, 1, 'x') $q$, :'c1'), '42501', 'token s rolí postgres, ale cizí identitou, neprojde (role není authenticated)');
select pg_temp.expect_as(:'u1', 'authenticated', $q$ select count(*)::text::jsonb from private.company_profile_drafts $q$, '42501', 'authenticated nesmí číst tabulku draftů přímo');
select pg_temp.expect_as(:'u1', 'authenticated', $q$ select count(*)::text::jsonb from private.company_profile_versions $q$, '42501', 'authenticated nesmí číst tabulku verzí přímo');
select pg_temp.expect_as(:'u1', 'authenticated', $q$ select private.vx_trim('"a"'::jsonb) $q$, '42501', 'authenticated nesmí volat pomocné funkce');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select private.profile_actor(%L, true)::text::jsonb $q$, :'c1'), '42501', 'authenticated nesmí volat profile_actor');

-- ---- 3) verze schématu, validace --------------------------------------------------------------------
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, 999, '{"shared":{},"local":{}}'::jsonb) $q$, :'c1'), 'PT412', 'jiná verze schématu vrací PT412', 'server_version');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, %s, '{"shared":{"identity":{"displayName":"x","evil":1}},"local":{}}'::jsonb) $q$, :'c1', :ver),
  'PT422', 'validace: krátké jméno a neznámé pole', '$.shared.identity.displayName:minLength');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, %s, '{"shared":{"identity":{"website":"http://user:pw@x.cz"}},"local":{}}'::jsonb) $q$, :'c1', :ver),
  'PT422', 'validace: adresa s přihlašovacími údaji', '$.shared.identity.website:format');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, %s, '{"shared":{"financialContext":{"revenueMinor":-5}},"local":{}}'::jsonb) $q$, :'c1', :ver),
  'PT422', 'validace: záporná částka', 'revenueMinor:minimum');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, %s, '{"shared":{"channels":[{"channel":"tiktok"}]},"local":{}}'::jsonb) $q$, :'c1', :ver),
  'PT422', 'validace: neznámý kanál', 'channels[0].channel:enum');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, %s, '{"jine":{}}'::jsonb) $q$, :'c1', :ver),
  'PT422', 'validace: neznámá sekce nejvyšší úrovně', '$.jine:additional');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, %s, '[]'::jsonb) $q$, :'c1', :ver), 'PT422', 'validace: dokument není objekt', '$:type');

-- ---- 4) odvozený cíl: 146 000 Kč + 35 % = 197 100 Kč ---------------------------------------------------
select pg_temp.call_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, %s, %L::jsonb) $q$, :'c1', :ver,
 '{"shared":{"identity":{"displayName":"Autoservis Konina","activity":"autoservis a výfuky"},
   "services":{"items":[{"name":"Výměna a úpravy výfuků"}]},
   "audience":{"description":"Řidiči v okolí Prahy"},
   "financialContext":{"revenueMinor":14600000,"revenueCurrency":"CZK","revenuePeriod":"month","budgetMinor":500000,"budgetCurrency":"CZK","budgetPeriod":"month"},
   "goals":[{"metric":"revenue","baselineMinor":14600000,"growthBp":3500,"targetMinor":1,"dueDate":"2027-05-07","startDate":"2026-11-07"}],
   "channels":[{"channel":"facebook"},{"channel":"instagram"}]},
  "local":{"geography":{"city":"Praha","serviceArea":"okolí Prahy","radiusKm":null}}}')) as r \gset
select (:'r'::jsonb) ->> 'revision' as rev2 \gset
select pg_temp.ok(:rev2 = 2, 'revize se zvýšila na 2');
select ((:'r'::jsonb) #>> '{data,shared,goals,0,targetMinor}')::bigint as tgt \gset
select pg_temp.ok(:tgt = 19710000, 'cíl 146 000 Kč + 35 % = 197 100 Kč (19 710 000 haléřů) počítá databáze, ne klient');
select pg_temp.ok(((:'r'::jsonb) #>> '{data,shared,goals,0,targetSource}') = 'calc', 'cíl je označen jako odvozený výpočet');
select pg_temp.ok(private.vx_goal_target(1, 5000) = 2 and private.vx_goal_target(0, 3500) = 0 and private.vx_goal_target(3, 1500) = 3, 'zaokrouhlení půl nahoru a nuly');
select (:'r'::jsonb) ->> 'hash' as hash2 \gset

-- ---- 5) potvrzení ---------------------------------------------------------------------------------------
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_confirm(%L, 1, %L) $q$, :'c1', :'hash2'), 'PT409', 'potvrzení se zastaralou revizí = PT409');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_confirm(%L, 2, 'neplatny') $q$, :'c1'), 'PT409', 'potvrzení s jiným otiskem obsahu = PT409');
select pg_temp.expect_as(:'u3', 'authenticated', format($q$ select public.profile_confirm(%L, 2, %L) $q$, :'c1', :'hash2'), '42501', 'zaměstnanec nesmí potvrdit');
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_confirm(%L, 2, %L) $q$, :'c4', :'hash2'), '42501', 'cizí identita nepotvrdí cizí firmu');
select pg_temp.call_as(:'u2', 'authenticated', format($q$ select public.profile_confirm(%L, 2, %L) $q$, :'c1', :'hash2')) as cf \gset
select pg_temp.ok((:'cf'::jsonb ->> 'version')::int = 1 and (:'cf'::jsonb ->> 'unchanged') = 'false', 'správce potvrdil verzi 1');
select pg_temp.call_as(:'u1', 'authenticated', format($q$ select public.profile_confirm(%L, 2, %L) $q$, :'c1', :'hash2')) as cf2 \gset
select pg_temp.ok((:'cf2'::jsonb ->> 'version')::int = 1 and (:'cf2'::jsonb ->> 'unchanged') = 'true', 'opakované potvrzení stejného obsahu je idempotentní (verze 1)');
select pg_temp.ok((select confirmed_by from private.company_profile_versions where company_id = :'c1' and version = 1) = :'u2'::uuid, 'potvrdil člověk: confirmed_by = identita správce');

-- úprava po potvrzení = nový koncept, potvrzená verze zůstává
select pg_temp.call_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 2, %s, %L::jsonb) $q$, :'c1', :ver,
 '{"shared":{"identity":{"displayName":"Autoservis Konina","activity":"autoservis a výfuky","website":null},
   "services":{"items":[{"name":"Výměna a úpravy výfuků"}]},"audience":{"description":"Řidiči v okolí Prahy"},
   "financialContext":{"revenueMinor":14600000,"revenueCurrency":"CZK","revenuePeriod":"month"},
   "goals":[{"metric":"revenue","baselineMinor":14600000,"growthBp":3500,"dueDate":"2027-05-07"}]},
  "local":{"geography":{"city":"Praha"}}}')) ->> 'hash' as hash3 \gset
select pg_temp.ok((select content_hash from private.company_profile_versions where company_id = :'c1' and version = 1) = :'hash2', 'potvrzená verze 1 zůstala beze změny');
select pg_temp.call_as(:'u1', 'authenticated', format($q$ select public.profile_confirm(%L, 3, %L) $q$, :'c1', :'hash3')) as cf3 \gset
select pg_temp.ok((:'cf3'::jsonb ->> 'version')::int = 2, 'po úpravě vznikla verze 2');
select pg_temp.call_as(:'u2', 'authenticated', format($q$ select public.profile_get(%L) $q$, :'c1')) as g1 \gset
select pg_temp.ok((:'g1'::jsonb #>> '{active,version}')::int = 2 and jsonb_array_length(:'g1'::jsonb -> 'versions') = 2, 'aktivní je verze 2 a historie má 2 verze');
select pg_temp.ok((pg_temp.call_as(:'u2', 'authenticated', format($q$ select public.profile_version_get(%L, 1) $q$, :'c1')) #>> '{data,shared,financialContext,revenueMinor}')::bigint = 14600000, 'starou verzi 1 lze přečíst');
select pg_temp.expect_as(:'u2', 'authenticated', format($q$ select public.profile_version_get(%L, 9) $q$, :'c1'), 'PT404', 'neexistující verze = PT404');

-- neúplný profil nejde potvrdit
select pg_temp.call_as(:'u1', 'authenticated', format($q$ select public.profile_save_draft(%L, 3, %s, %L::jsonb) $q$, :'c1', :ver,
 '{"shared":{"identity":{"displayName":"Autoservis Konina"},"financialContext":{"revenueMinor":100},"unknowns":[{"field":"web","blocking":true}],
   "goals":[{"metric":"jobs","growthBp":1000}]},"local":{}}')) as inc \gset
select pg_temp.expect_as(:'u1', 'authenticated', format($q$ select public.profile_confirm(%L, 4, %L) $q$, :'c1', (:'inc'::jsonb ->> 'hash')),
  'PT422', 'neúplný profil nejde potvrdit (měna, období, lokalita, blokující otázka…)', 'shared.financialContext.revenueCurrency:required');

-- ---- 6) pobočka ----------------------------------------------------------------------------------------
select pg_temp.call_as(:'u5', 'authenticated', format($q$ select public.profile_save_draft(%L, 0, %s, %L::jsonb) $q$, :'c2', :ver,
  '{"local":{"geography":{"city":"Beroun","radiusKm":30},"localNotes":"Jen pneuservis"}}')) as b1 \gset
select pg_temp.ok((:'b1'::jsonb ->> 'revision')::int = 1, 'správce pobočky uloží lokální sekci');
select pg_temp.expect_as(:'u5', 'authenticated', format($q$ select public.profile_save_draft(%L, 1, %s, '{"shared":{"identity":{"displayName":"Hacknuto"}},"local":{}}'::jsonb) $q$, :'c2', :ver),
  'PT422', 'pobočka nesmí měnit společné údaje', '$.shared:branch_not_allowed');
select pg_temp.expect_as(:'u5', 'authenticated', format($q$ select public.profile_get(%L) $q$, :'c1'), '42501', 'správce jen pobočky nesmí číst profil hlavní firmy');
select pg_temp.call_as(:'u5', 'authenticated', format($q$ select public.profile_get(%L) $q$, :'c2')) as bg \gset
select pg_temp.ok((:'bg'::jsonb #>> '{shared_from_root,data,identity,displayName}') = 'Autoservis Konina', 'pobočka vidí společné údaje hlavní firmy');
select pg_temp.ok((:'bg'::jsonb #> '{shared_from_root,data,financialContext}') is null and (:'bg'::jsonb #> '{shared_from_root,data,goals}') is null,
  'správce jen pobočky nevidí finance a cíle hlavní firmy');
select pg_temp.call_as(:'u1', 'authenticated', format($q$ select public.profile_get(%L) $q$, :'c2')) as bg1 \gset
select pg_temp.ok((:'bg1'::jsonb #> '{shared_from_root,data,goals}') is not null and (:'bg1'::jsonb #> '{shared_from_root,data,financialContext}') is not null, 'majitel hlavní firmy vidí v pobočce i finance a cíle');
select pg_temp.call_as(:'u5', 'authenticated', format($q$ select public.profile_confirm(%L, 1, %L) $q$, :'c2', (:'b1'::jsonb ->> 'hash'))) as bc \gset
select pg_temp.ok((:'bc'::jsonb ->> 'version')::int = 1, 'pobočka potvrdí lokální profil (stačí lokalita)');

-- ---- 7) firma jen pro čtení (prošlá zkušební doba) ----------------------------------------------------
select pg_temp.ok((pg_temp.call_as(:'u7', 'authenticated', format($q$ select public.profile_get(%L) $q$, :'c4')) ->> 'can_write') = 'false', 'prošlá zkouška: čtení funguje, can_write = false');
select pg_temp.expect_as(:'u7', 'authenticated', format($q$ select public.profile_save_draft(%L, 0, %s, '{"shared":{},"local":{}}'::jsonb) $q$, :'c4', :ver), '42501', 'prošlá zkouška: ukládání zakázáno');

-- ---- 8) neměnnost, audit, výmaz firmy ----------------------------------------------------------------
select pg_temp.expect_as(null, 'postgres', $q$ update private.company_profile_versions set data = '{}'::jsonb returning to_jsonb(1) $q$, 'P0001', 'potvrzenou verzi nelze upravit (ani vlastník tabulky)');
select pg_temp.expect_as(null, 'postgres', $q$ update private.company_profile_events set operation = 'confirm' returning to_jsonb(1) $q$, 'P0001', 'auditní událost nelze upravit');
select pg_temp.ok((select count(*) from private.company_profile_events where company_id = :'c1' and operation = 'draft_created') = 1
              and (select count(*) from private.company_profile_events where company_id = :'c1' and operation = 'confirm') = 2
              and not exists (select 1 from private.company_profile_events where actor is null), 'audit: 1× koncept, 2× potvrzení, vždy s identitou');

-- smazání firmy (výmaz dat) projde přes neměnné záznamy kaskádou
select pg_temp.call_as(:'u4', 'authenticated', format($q$ select public.profile_save_draft(%L, 0, %s, %L::jsonb) $q$, :'c3', :ver,
  '{"shared":{"identity":{"displayName":"Cizí firma","activity":"x"},"audience":{"description":"y"}},"local":{"geography":{"city":"Brno"}}}')) as o1 \gset
select pg_temp.call_as(:'u4', 'authenticated', format($q$ select public.profile_confirm(%L, 1, %L) $q$, :'c3', (:'o1'::jsonb ->> 'hash'))) as o2 \gset
select pg_temp.ok((select count(*) from private.company_profile_versions where company_id = :'c3') = 1, 'cizí firma má potvrzenou verzi (tarif START je také povolen)');
delete from public.companies where id = :'c3';
select pg_temp.ok((select count(*) from private.company_profile_drafts where company_id = :'c3')
                + (select count(*) from private.company_profile_versions where company_id = :'c3')
                + (select count(*) from private.company_active_profile where company_id = :'c3')
                + (select count(*) from private.company_profile_events where company_id = :'c3') = 0, 'smazání firmy odstranilo všechna data profilu');

-- ---- 9) matice práv --------------------------------------------------------------------------------------
select pg_temp.ok(
  not has_function_privilege('anon', 'public.profile_get(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.profile_save_draft(uuid,integer,integer,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.profile_confirm(uuid,integer,text)', 'execute')
  and not has_function_privilege('anon', 'public.profile_version_get(uuid,integer)', 'execute')
  and not has_function_privilege('anon', 'public.profile_schema_info()', 'execute'), 'anon nesmí spouštět žádnou funkci profile_*');
select pg_temp.ok(
  not has_function_privilege('service_role', 'public.profile_get(uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.profile_confirm(uuid,integer,text)', 'execute')
  and not has_function_privilege('service_role', 'private.profile_confirm_core(uuid,integer,text)', 'execute'), 'service_role nesmí spouštět potvrzení ani čtení profilu');
select pg_temp.ok(
  has_function_privilege('authenticated', 'public.profile_get(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.profile_save_draft(uuid,integer,integer,jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.profile_confirm(uuid,integer,text)', 'execute'), 'authenticated smí spouštět obálky profile_*');
select pg_temp.ok(
  not has_function_privilege('authenticated', 'private.vx_json_validate(jsonb,jsonb,text)', 'execute')
  and not has_function_privilege('authenticated', 'private.vx_trim(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'private.profile_actor(uuid,boolean)', 'execute')
  and not has_function_privilege('authenticated', 'private.profile_conflict(integer)', 'execute'), 'pomocné funkce nejsou pro authenticated');
select pg_temp.ok(
  (select bool_and(not has_table_privilege(r, t, 'select') and not has_table_privilege(r, t, 'insert') and not has_table_privilege(r, t, 'update') and not has_table_privilege(r, t, 'delete'))
     from unnest(array['anon', 'authenticated']) r,
          unnest(array['private.company_profile_drafts', 'private.company_profile_versions', 'private.company_active_profile', 'private.company_profile_events']) t), 'anon ani authenticated nemají práva na tabulky profilu');
select pg_temp.ok(
  (select bool_and(not has_table_privilege('service_role', t, 'select') and not has_table_privilege('service_role', t, 'insert')
                   and not has_table_privilege('service_role', t, 'update') and not has_table_privilege('service_role', t, 'delete'))
     from unnest(array['private.company_profile_drafts', 'private.company_profile_versions', 'private.company_active_profile', 'private.company_profile_events']) t),
  'ani service_role nemá práva na tabulky profilu (klíč nemůže obejít potvrzování zápisem do tabulek)');
select pg_temp.ok((select bool_and(relrowsecurity) from pg_class where oid in ('private.company_profile_drafts'::regclass, 'private.company_profile_versions'::regclass, 'private.company_active_profile'::regclass, 'private.company_profile_events'::regclass)), 'RLS je na všech tabulkách profilu zapnuté');

rollback;
\echo VŠECHNY SQL TESTY PROFILU PROŠLY (transakce vrácena, žádná data nezůstala)
