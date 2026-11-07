-- Testy schématu AI Marketing Autopilota. Každý řádek výsledku: název | ok
\set A '''aaaaaaaa-0000-0000-0000-000000000001'''
\set B '''bbbbbbbb-0000-0000-0000-000000000002'''
\set C '''cccccccc-0000-0000-0000-000000000003'''
create temp table r(name text, ok boolean);
grant all on r to authenticated, service_role, anon;
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', u, false); end $$;
create or replace function pg_temp.fails(sql text) returns boolean language plpgsql as $$ begin execute sql; return false; exception when others then return true; end $$;
grant execute on all functions in schema pg_temp to authenticated, service_role, anon;

-- vlastník A zadá úlohu
set role authenticated; select pg_temp.as_user('11111111-0000-0000-0000-000000000001');
insert into r select 'owner A: mkt_request vrátí id', public.mkt_request(:A, 'strategy', 'Strategie na 30 dní', '{"days":30}', 'k1') is not null;
insert into r select 'owner A: stejný idem klíč nevytvoří duplikát', (select count(*) from public.mkt_tasks where idem_key='k1') = 1 and public.mkt_request(:A, 'strategy', 'Strategie na 30 dní', '{"days":30}', 'k1') = (select id from public.mkt_tasks where idem_key='k1');
insert into r select 'owner A: neznámý typ úlohy odmítnut', pg_temp.fails($$select public.mkt_request('aaaaaaaa-0000-0000-0000-000000000001','morning','xxx')$$);
select public.mkt_chat_send(:A, 'Připrav obsah na příští týden');
insert into r select 'owner A: chat vytvoří zprávu a úlohu', (select count(*) from public.mkt_chat) = 1 and (select count(*) from public.mkt_tasks where kind='chat') = 1;
insert into r select 'owner A: přímý zápis do mkt_tasks zakázán', pg_temp.fails($$insert into public.mkt_tasks(company_id,kind,title) values ('aaaaaaaa-0000-0000-0000-000000000001','strategy','x')$$);
insert into r select 'owner A: přímý zápis výsledku (mkt_content) zakázán', pg_temp.fails($$insert into public.mkt_content(company_id,channel) values ('aaaaaaaa-0000-0000-0000-000000000001','instagram')$$);
insert into r select 'owner A: profil uloží', pg_temp.fails($$insert into public.mkt_profiles(company_id,business_name,completed) values ('aaaaaaaa-0000-0000-0000-000000000001','Firma A',true)$$) = false;
insert into r select 'owner A: nemůže psát profil firmy B', pg_temp.fails($$insert into public.mkt_profiles(company_id,business_name) values ('bbbbbbbb-0000-0000-0000-000000000002','cizí')$$);
insert into r select 'owner A: nemůže zadat úlohu firmě B', pg_temp.fails($$select public.mkt_request('bbbbbbbb-0000-0000-0000-000000000002','strategy','cizí úloha')$$);
insert into r select 'owner A: ruční metrika jen source=manual', pg_temp.fails($$insert into public.mkt_metrics(company_id,metric_date,channel,metric,value,source) values ('aaaaaaaa-0000-0000-0000-000000000001',current_date,'meta','clicks',5,'meta')$$)
  and not pg_temp.fails($$insert into public.mkt_metrics(company_id,metric_date,channel,metric,value) values ('aaaaaaaa-0000-0000-0000-000000000001',current_date,'instagram','reach',120)$$);
reset role;

-- zaměstnanec A čte, ale nezadává
set role authenticated; select pg_temp.as_user('11111111-0000-0000-0000-000000000002');
insert into r select 'employee A: vidí úlohy firmy', (select count(*) from public.mkt_tasks) = 2;
insert into r select 'employee A: nesmí zadat úlohu', pg_temp.fails($$select public.mkt_request('aaaaaaaa-0000-0000-0000-000000000001','strategy','Strategie zaměstnance')$$);
insert into r select 'employee A: nesmí pozastavit AI', pg_temp.fails($$select public.mkt_set_paused('aaaaaaaa-0000-0000-0000-000000000001', true)$$);
reset role;

-- vlastník B nevidí data A; START firma C nemá přístup k AI
set role authenticated; select pg_temp.as_user('22222222-0000-0000-0000-000000000001');
insert into r select 'owner B: nevidí úlohy, chat ani profil A', (select count(*) from public.mkt_tasks) = 0 and (select count(*) from public.mkt_chat) = 0 and (select count(*) from public.mkt_profiles) = 0 and (select count(*) from public.mkt_metrics) = 0;
insert into r select 'owner B: nesmí volat serverový claim', pg_temp.fails($$select * from public.mkt_worker_claim(null)$$);
insert into r select 'owner B: nesmí ověřit dispatch token', pg_temp.fails($$select public.mkt_worker_dispatch_ok('x')$$);
select pg_temp.as_user('33333333-0000-0000-0000-000000000001');
insert into r select 'owner C (START): AI Marketing není v tarifu', pg_temp.fails($$select public.mkt_request('cccccccc-0000-0000-0000-000000000003','strategy','Strategie C')$$);
reset role;

-- anon nemá přístup
set role anon; select pg_temp.as_user('');
insert into r select 'anon: nečte tabulky', pg_temp.fails($$select * from public.mkt_tasks$$);
insert into r select 'anon: nevolá mkt_request', pg_temp.fails($$select public.mkt_request('aaaaaaaa-0000-0000-0000-000000000001','strategy','xxx')$$);
reset role;

-- server: claim, souběh, opakování, lease
set role service_role;
insert into r select 'service: dispatch token správný/špatný', public.mkt_worker_dispatch_ok(repeat('ab',32)) and not public.mkt_worker_dispatch_ok('spatny') and not coalesce(public.mkt_worker_dispatch_ok(null),false);
create temp table c1 as select * from public.mkt_worker_claim(null);
insert into r select 'service: claim vezme nejvyšší prioritu (chat)', (select kind from c1) = 'chat' and (select status from public.mkt_tasks where id=(select id from c1)) = 'running';
create temp table c2 as select * from public.mkt_worker_claim(null);
insert into r select 'service: druhý claim nevezme stejnou úlohu', (select id from c2) <> (select id from c1);
create temp table c3 as select * from public.mkt_worker_claim(null);
insert into r select 'service: prázdná fronta vrátí nic', (select count(*) from c3) = 0;
insert into r select 'service: finish se špatným lease nic nezmění', public.mkt_worker_finish((select id from c1), gen_random_uuid(), true, '{}', null) = false;
insert into r select 'service: finish ok vrátí true', public.mkt_worker_finish((select id from c1), (select lease_token from c1), true, '{"x":1}', null);
insert into r select 'service: finish ok -> done', (select status from public.mkt_tasks where id=(select id from c1)) = 'done';
insert into r select 'service: dvojí finish se nepovede', public.mkt_worker_finish((select id from c1), (select lease_token from c1), true, '{}', null) = false;
select public.mkt_worker_finish((select id from c2), (select lease_token from c2), false, null, 'timeout');
insert into r select 'service: chyba -> zpět do fronty s odkladem', (select status='queued' and run_after > now() and error='timeout' from public.mkt_tasks where id=(select id from c2));
update public.mkt_tasks set run_after = now() - interval '1 minute' where id = (select id from c2);
create temp table c4 as select * from public.mkt_worker_claim(null);
insert into r select 'service: opakovaný pokus má attempts=2', (select attempts from c4) = 2;
-- spadlý worker: lease vypršel -> úloha se znovu převezme
update public.mkt_tasks set lease_until = now() - interval '1 second' where id = (select id from c4);
create temp table c5 as select * from public.mkt_worker_claim(null);
insert into r select 'service: po vypršení lease převezme znovu (attempts=3)', (select id from c5) = (select id from c4) and (select attempts from c5) = 3;
select public.mkt_worker_finish((select id from c5), (select lease_token from c5), false, null, 'model error');
insert into r select 'service: konečná chyba po vyčerpání pokusů', (select status from public.mkt_tasks where id=(select id from c5)) = 'failed';
insert into r select 'service: budget firmy A', (public.mkt_worker_budget('aaaaaaaa-0000-0000-0000-000000000001')->>'limit')::int = 150 and (public.mkt_worker_budget('aaaaaaaa-0000-0000-0000-000000000001')->>'used')::int = 0;
-- AI vytvoří návrh příspěvku + schválení
insert into public.mkt_content(id, company_id, channel, caption, status) values ('c0000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','instagram','Text','pending_approval');
insert into public.mkt_approvals(id, company_id, entity, entity_id, level, summary) values ('a0000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','content','c0000000-0000-0000-0000-000000000001','rule','Příspěvek');
insert into public.mkt_campaigns(id, company_id, name, budget_total) values ('d0000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Kampaň',3000);
insert into public.mkt_approvals(id, company_id, entity, entity_id, level, summary) values ('a0000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','campaign','d0000000-0000-0000-0000-000000000001','separate','Kampaň 3000 Kč');
reset role;

-- schvalování
set role authenticated; select pg_temp.as_user('11111111-0000-0000-0000-000000000002');
insert into r select 'employee A: nesmí schválit kampaň', pg_temp.fails($$select public.mkt_decide('a0000000-0000-0000-0000-000000000002','approved')$$);
select pg_temp.as_user('22222222-0000-0000-0000-000000000001');
insert into r select 'owner B: nesmí schválit návrh firmy A', pg_temp.fails($$select public.mkt_decide('a0000000-0000-0000-0000-000000000001','approved')$$);
select pg_temp.as_user('11111111-0000-0000-0000-000000000001');
update public.mkt_content set caption='Upravený text' where id='c0000000-0000-0000-0000-000000000001';
insert into r select 'owner A: úprava textu před schválením', (select caption from public.mkt_content where id='c0000000-0000-0000-0000-000000000001')='Upravený text';
insert into r select 'owner A: nesmí sám změnit stav příspěvku', pg_temp.fails($$update public.mkt_content set status='published' where id='c0000000-0000-0000-0000-000000000001'$$);
insert into r select 'owner A: publikace před schválením odmítnuta', pg_temp.fails($$select public.mkt_mark_published('c0000000-0000-0000-0000-000000000001')$$);
select public.mkt_decide('a0000000-0000-0000-0000-000000000001','approved');
insert into r select 'owner A: schválení příspěvku změní stav', (select status from public.mkt_content where id='c0000000-0000-0000-0000-000000000001') = 'approved';
insert into r select 'owner A: druhé rozhodnutí odmítnuto', pg_temp.fails($$select public.mkt_decide('a0000000-0000-0000-0000-000000000001','rejected')$$);
select public.mkt_decide('a0000000-0000-0000-0000-000000000002','rejected','Moc drahé');
insert into r select 'owner A: zamítnutí kampaně', (select status from public.mkt_campaigns where id='d0000000-0000-0000-0000-000000000001') = 'rejected';
insert into r select 'owner A: odkaz publikace musí být https', pg_temp.fails($$select public.mkt_mark_published('c0000000-0000-0000-0000-000000000001','javascript:alert(1)')$$);
select public.mkt_mark_published('c0000000-0000-0000-0000-000000000001','https://instagram.com/p/x');
insert into r select 'owner A: ruční publikace schváleného', (select status from public.mkt_content where id='c0000000-0000-0000-0000-000000000001') = 'published';
-- pozastavení: claim nic nevezme
select public.mkt_request(:A, 'diagnose', 'Proč klesají poptávky');
select public.mkt_set_paused(:A, true);
reset role;
set role service_role;
insert into r select 'pauza: claim nebere úlohy pozastavené firmy', (select count(*) from public.mkt_worker_claim(null)) = 0;
reset role;
set role authenticated; select pg_temp.as_user('11111111-0000-0000-0000-000000000001');
select public.mkt_set_paused(:A, false);
insert into r select 'historie zaznamenala pauzu, schválení i zamítnutí', (select count(*) from public.mkt_activity where action in ('paused','resumed','decision_approved','decision_rejected')) = 4;
reset role;
-- rutiny
insert into public.mkt_settings(company_id, autopilot_on, morning_hour, evening_hour) values (:B, true, extract(hour from now() at time zone 'Europe/Prague')::int, extract(hour from now() at time zone 'Europe/Prague')::int)
  on conflict (company_id) do update set autopilot_on = true;
insert into public.mkt_settings(company_id, autopilot_on, morning_hour) values (:C, true, extract(hour from now() at time zone 'Europe/Prague')::int);
select private.mkt_enqueue_routines(); select private.mkt_enqueue_routines();
insert into r select 'rutina: ráno i večer jen jednou za den, jen firmy s PRO', (select count(*) from public.mkt_tasks where company_id = :B and source = 'schedule') = 2 and (select count(*) from public.mkt_tasks where company_id = :C) = 0;

select name, ok from r order by ok, name;
select count(*) filter (where ok) as prošlo, count(*) as celkem from r;
