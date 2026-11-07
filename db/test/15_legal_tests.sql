-- Odhlášení z marketingu a oznámení podle DSA (po migracích 20261110100000 a 20261110110000). Pod skutečnými rolemi, jedna transakce, ROLLBACK.
\set ON_ERROR_STOP on
\pset tuples_only on
begin;
\i db/test/helpers.sql

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-00000000a001', 'admin@example.invalid', now()),
  ('00000000-0000-0000-0000-00000000a002', 'uzivatel@example.invalid', now());
insert into private.platform_admins (user_id) values ('00000000-0000-0000-0000-00000000a001');
insert into public.companies (id, owner_id, name) values ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000a002', 'Firma s webem');
insert into public.sites (company_id, slug, enabled) values ('00000000-0000-0000-0000-00000000c001', 'demo-web', true);
insert into public.newsletter_subscribers (email, consent) values ('Anna@Example.invalid', true), ('bob@example.invalid', true), ('cyril@example.invalid', false);
\set adm '00000000-0000-0000-0000-00000000a001'
\set usr '00000000-0000-0000-0000-00000000a002'

-- ============ M: marketing ============
select pg_temp.expect_as(:'usr', 'authenticated', $q$select to_jsonb(public.marketing_queue('Novinky', 'Text zprávy novinek.'))$q$, '42501', 'M: běžný uživatel zprávu nenaplánuje');
select pg_temp.expect_as(null, 'anon', $q$select public.marketing_claim(10)$q$, '42501', 'M: anon nemůže vybírat příjemce');
select pg_temp.expect_as(:'usr', 'authenticated', $q$select public.marketing_claim(10)$q$, '42501', 'M: přihlášený uživatel nemůže vybírat příjemce');
select pg_temp.expect_as(null, 'anon', $q$select to_jsonb(count(*)) from private.marketing_suppressions$q$, '42501', 'M: seznam odhlášených není čitelný');
create temp table m (k text primary key, v text);
grant all on m to public;
insert into m select 'm1', (pg_temp.call_as(:'adm', 'authenticated', $q$select to_jsonb(public.marketing_queue('Novinky 1', 'První zpráva novinek pro test.', now() - interval '1 minute'))$q$)) #>> '{}';
insert into m select 'm2', (pg_temp.call_as(:'adm', 'authenticated', $q$select to_jsonb(public.marketing_queue('Novinky 2', 'Naplánovaná zpráva na zítra.', now() + interval '1 day'))$q$)) #>> '{}';
select pg_temp.ok((select count(*) from private.marketing_messages) = 2, 'M: správce platformy naplánoval dvě zprávy (jednu na zítra)');

insert into m select 'c1', pg_temp.call_as(null, 'service_role', $q$select public.marketing_claim(10)$q$)::text;
select pg_temp.ok(((select v from m where k = 'c1')::jsonb #>> '{message,id}') = (select v from m where k = 'm1'), 'M: dávka vybrala jen zprávu, která je na řadě (ne tu na zítra)');
select pg_temp.ok((select array_agg(x->>'email' order by x->>'email') from jsonb_array_elements((select v from m where k = 'c1')::jsonb->'recipients') x) = array['anna@example.invalid', 'bob@example.invalid'],
  'M: příjemci jen se souhlasem (cyril bez souhlasu ne), adresy normalizované');
select pg_temp.ok((select bool_and(x->>'token' ~ '^[0-9a-f]{64}$' and position('anna' in x->>'token') = 0) from jsonb_array_elements((select v from m where k = 'c1')::jsonb->'recipients') x), 'M: token je 64 hex znaků a neobsahuje adresu');
select pg_temp.ok(not exists (select 1 from private.marketing_deliveries d, jsonb_array_elements((select v from m where k = 'c1')::jsonb->'recipients') x where d.token_hash = x->>'token'), 'M: v DB je jen otisk tokenu, ne token');
insert into m select 'tokA', x->>'token' from jsonb_array_elements((select v from m where k = 'c1')::jsonb->'recipients') x where x->>'email' = 'anna@example.invalid';
select pg_temp.ok(pg_temp.call_as(null, 'service_role', format('select to_jsonb(public.marketing_send_allowed(%L, %L))', (select v from m where k = 'm1'), 'anna@example.invalid')) = 'true'::jsonb, 'M: před odhlášením je odeslání povoleno');

-- odhlášení odkazem bez přihlášení
select pg_temp.ok((pg_temp.call_as(null, 'anon', format('select public.marketing_unsubscribe(%L)', (select v from m where k = 'tokA'))) ->> 'ok') = 'true', 'M: odhlášení odkazem funguje bez přihlášení');
select pg_temp.ok(not (pg_temp.call_as(null, 'anon', format('select public.marketing_unsubscribe(%L)', (select v from m where k = 'tokA'))) ? 'email'), 'M: odpověď neprozrazuje adresu');
select pg_temp.ok((pg_temp.call_as(null, 'anon', format('select public.marketing_unsubscribe(%L)', (select v from m where k = 'tokA'))) ->> 'ok') = 'true', 'M: opakované odhlášení je bez chyby');
select pg_temp.ok((pg_temp.call_as(null, 'anon', $q$select public.marketing_unsubscribe('0000000000000000000000000000000000000000000000000000000000000000')$q$) ->> 'ok') = 'false', 'M: neplatný token nic neodhlásí');
select pg_temp.ok((pg_temp.call_as(null, 'anon', $q$select public.marketing_unsubscribe('anna@example.invalid')$q$) ->> 'ok') = 'false', 'M: adresa místo tokenu nic neodhlásí');
select pg_temp.ok(pg_temp.call_as(null, 'service_role', format('select to_jsonb(public.marketing_send_allowed(%L, %L))', (select v from m where k = 'm1'), 'anna@example.invalid')) = 'false'::jsonb,
  'M: odhlášení mezi výběrem dávky a odesláním zastaví odeslání (kontrola těsně před odesláním)');
select pg_temp.ok(pg_temp.call_as(null, 'service_role', format('select to_jsonb(public.marketing_send_allowed(%L, %L))', (select v from m where k = 'm1'), 'bob@example.invalid')) = 'true'::jsonb, 'M: neodhlášený příjemce zůstává povolen');
select pg_temp.call_as(null, 'service_role', format('select to_jsonb(public.marketing_finish(%L, %L, %L)) ', (select v from m where k = 'm1'), 'bob@example.invalid', 'prov-1'));
select pg_temp.ok((select sent_at is not null from private.marketing_deliveries where email_norm = 'bob@example.invalid'), 'M: odeslání se zapsalo');
-- naplánovaná zpráva: zítra přijde čas, odhlášená adresa se nevybere
update private.marketing_messages set scheduled_at = now() - interval '1 second' where id = (select v from m where k = 'm2')::uuid;
update private.marketing_messages set status = 'sent' where id = (select v from m where k = 'm1')::uuid;
insert into m select 'c2', pg_temp.call_as(null, 'service_role', $q$select public.marketing_claim(10)$q$)::text;
select pg_temp.ok(((select v from m where k = 'c2')::jsonb #>> '{message,id}') = (select v from m where k = 'm2'), 'M: naplánovaná zpráva je na řadě');
select pg_temp.ok((select array_agg(x->>'email') from jsonb_array_elements((select v from m where k = 'c2')::jsonb->'recipients') x) = array['bob@example.invalid'],
  'M: naplánovaná zpráva NEjde na adresu odhlášenou po jejím naplánování');
insert into public.newsletter_subscribers (email, consent) values ('ANNA@example.invalid ', true);
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(pg_temp.call_as(null, 'service_role', $q$select public.marketing_claim(10)$q$)->'recipients') x where x->>'email' like 'anna%'),
  'M: ani nová přihláška stejné adresy (jiná velikost písmen) odhlášení neobejde');

-- ============ D: DSA ============
create temp table d (k text primary key, v jsonb);
grant all on d to public;
select pg_temp.expect_as(null, 'anon', $q$select public.dsa_submit('{}'::jsonb, null)$q$, '42501', 'D: oznámení jde přijmout jen přes serverovou funkci (anon přímo ne)');
insert into d select 'n1', pg_temp.call_as(null, 'service_role', format('select public.dsa_submit(%L::jsonb, %L)',
  '{"urls":["https://vexaronet.com/?w=demo-web"],"details":"Sekce Služby, druhý odstavec","category":"podvod","explanation":"Web nabízí falešné služby a vybírá zálohy od lidí, kteří nic nedostanou.","name":"Jana Oznamovatelka","email":"Jana@Example.invalid","good_faith":true}',
  repeat('a', 64)));
select pg_temp.ok((select v->>'ref' from d where k = 'n1') ~ '^DSA-[0-9]{8}-[0-9A-F]{8}$', 'D: oznámení má referenční číslo');
select pg_temp.ok((select target_kind = 'web' and target_company_id = '00000000-0000-0000-0000-00000000c001' and notifier_email = 'jana@example.invalid' from private.dsa_notices where id = (select (v->>'id')::uuid from d where k = 'n1')),
  'D: oznámení je přiřazené ke konkrétnímu webu firmy');
select pg_temp.ok((select count(*) from private.dsa_events where event = 'prijato') = 1, 'D: přijetí je v evidenci');
select pg_temp.expect_as(null, 'service_role', $q$select public.dsa_submit('{"urls":["https://vexaronet.com/?w=demo-web"],"category":"podvod","explanation":"Dostatečně dlouhé vysvětlení důvodů nezákonnosti obsahu.","good_faith":true}'::jsonb, null)$q$,
  '23514', 'D: bez jména a e-mailu nelze (mimo zneužívání dětí)');
select pg_temp.ok((pg_temp.call_as(null, 'service_role', $q$select public.dsa_submit('{"urls":["https://vexaronet.com/?s=obchod"],"category":"csam","explanation":"Anonymní oznámení obsahu sexuálního zneužívání dětí.","good_faith":true}'::jsonb, null)$q$) ->> 'ref') is not null,
  'D: oznámení zneužívání dětí lze podat anonymně (čl. 16 odst. 2 písm. c)');
select pg_temp.expect_as(null, 'service_role', $q$select public.dsa_submit('{"urls":["javascript:alert(1)"],"category":"jine","explanation":"Vysvětlení s dostatečnou délkou textu pro test.","name":"Jan","email":"jan@example.invalid","good_faith":true}'::jsonb, null)$q$,
  'P0001', 'D: adresa obsahu musí být http(s)');
select pg_temp.expect_as(null, 'service_role', $q$select public.dsa_submit('{"urls":["https://vexaronet.com/?w=demo-web"],"category":"jine","explanation":"krátké","name":"Jan","email":"jan@example.invalid","good_faith":true}'::jsonb, null)$q$,
  '23514', 'D: vysvětlení musí být dostatečně podložené (min. 30 znaků)');
select pg_temp.expect_as(null, 'service_role', $q$select public.dsa_submit('{"urls":["https://vexaronet.com/?w=demo-web"],"category":"jine","explanation":"Vysvětlení s dostatečnou délkou textu pro test.","name":"Jan","email":"jan@example.invalid","good_faith":false}'::jsonb, null)$q$,
  '23514', 'D: bez prohlášení o dobré víře nelze');
do $$ begin for i in 1..10 loop perform public.dsa_submit('{"urls":["https://vexaronet.com/?w=demo-web"],"category":"jine","explanation":"Opakované oznámení se stejným otiskem IP adresy.","name":"Jan","email":"jan@example.invalid","good_faith":true}'::jsonb, repeat('b', 64)); end loop; end $$;
select pg_temp.expect_as(null, 'service_role', format('select public.dsa_submit(%L::jsonb, %L)', '{"urls":["https://vexaronet.com/?w=demo-web"],"category":"jine","explanation":"Jedenácté oznámení ze stejné adresy za hodinu.","name":"Jan","email":"jan@example.invalid","good_faith":true}', repeat('b', 64)),
  'P0001', 'D: ochrana proti zahlcení (10 oznámení za hodinu z jedné adresy)');
select pg_temp.expect_as(:'usr', 'authenticated', $q$select public.dsa_admin_list(null)$q$, '42501', 'D: běžný uživatel oznámení nevidí');
select pg_temp.ok(jsonb_array_length(pg_temp.call_as(:'adm', 'authenticated', $q$select public.dsa_admin_list(null)$q$)) = 12
  and not (pg_temp.call_as(:'adm', 'authenticated', $q$select public.dsa_admin_list(null)$q$) -> 0 ? 'ip_hash'), 'D: správce platformy vidí oznámení (bez otisku IP)');
select pg_temp.expect_as(:'adm', 'authenticated', format('select public.dsa_admin_decide(%L, %L, %L, %L)', (select v->>'id' from d where k = 'n1'), 'odstraneni', 'nezakonny_obsah', 'krátce'), 'P0001', 'D: rozhodnutí vyžaduje odůvodnění');
select pg_temp.expect_as(:'usr', 'authenticated', format('select public.dsa_admin_decide(%L, %L, %L, %L)', (select v->>'id' from d where k = 'n1'), 'bez_opatreni', 'neodpovida', 'Odůvodnění dostatečně dlouhé pro test.'), '42501', 'D: běžný uživatel nerozhoduje');
insert into d select 'dec', pg_temp.call_as(:'adm', 'authenticated', format('select public.dsa_admin_decide(%L, %L, %L, %L)', (select v->>'id' from d where k = 'n1'), 'znepristupneni', 'nezakonny_obsah',
  'Web vybírá zálohy za neexistující služby; jde o podvodné jednání podle § 209 trestního zákoníku.'));
select pg_temp.ok((select v->>'notifier_email' from d where k = 'dec') = 'jana@example.invalid' and (select v->>'target_company_id' from d where k = 'dec') = '00000000-0000-0000-0000-00000000c001', 'D: rozhodnutí vrací údaje pro vyrozumění oznamovatele a provozovatele webu');
select pg_temp.ok((select enabled from public.sites where slug = 'demo-web'), 'D: rozhodnutí ani oznámení obsah automaticky nevypnuly (provede se ručně)');
select pg_temp.expect_as(:'adm', 'authenticated', format('select public.dsa_admin_decide(%L, %L, %L, %L)', (select v->>'id' from d where k = 'n1'), 'bez_opatreni', 'neodpovida', 'Druhé rozhodnutí o stejném oznámení.'), 'P0001', 'D: rozhodnutí nelze přepsat');
select pg_temp.expect_as(:'usr', 'authenticated', format('select to_jsonb(public.dsa_mark(%L, %L))', (select v->>'id' from d where k = 'n1'), 'oznamovatel_vyrozumen'), '42501', 'D: vyrozumění nemůže zapsat běžný uživatel');
select pg_temp.call_as(null, 'service_role', format('select to_jsonb(public.dsa_mark(%L, %L))', (select v->>'id' from d where k = 'n1'), 'oznamovatel_vyrozumen'));
select pg_temp.ok((select notifier_informed_at is not null from private.dsa_notices where id = (select (v->>'id')::uuid from d where k = 'n1')), 'D: vyrozumění oznamovatele je zaznamenané');
select pg_temp.ok((select array_agg(event order by id) from private.dsa_events where notice_id = (select (v->>'id')::uuid from d where k = 'n1')) = array['prijato', 'rozhodnuto', 'oznamovatel_vyrozumen'], 'D: evidence obsahuje celý průběh');
do $$ begin
  begin update private.dsa_events set event = 'poznamka'; raise exception 'TEST_FAIL evidence šla změnit' using errcode = 'XX999';
  exception when others then if sqlstate = 'XX999' then raise; end if; end;
  begin delete from private.dsa_events; raise exception 'TEST_FAIL evidence šla smazat' using errcode = 'XX999';
  exception when others then if sqlstate = 'XX999' then raise; end if; end;
  raise notice 'ok  D: evidenci nelze měnit ani mazat (ani vlastník tabulky)';
end $$;
select pg_temp.expect_as(null, 'anon', $q$select to_jsonb(count(*)) from private.dsa_notices$q$, '42501', 'D: oznámení nejsou čitelná přes API');

do $$ begin raise notice 'VŠECHNY KONTROLY PROŠLY'; end $$;
rollback;
