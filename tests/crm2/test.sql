\set A '''aaaaaaaa-0000-0000-0000-000000000001'''
\set B '''bbbbbbbb-0000-0000-0000-000000000002'''
create temp table r(name text, ok boolean);
grant all on r to authenticated;
insert into public.companies values (:A,'A',null),(:B,'B',null);
insert into public.company_members values (:A,'11111111-0000-0000-0000-000000000001','owner'),(:A,'11111111-0000-0000-0000-000000000002','employee'),(:B,'22222222-0000-0000-0000-000000000001','owner');
insert into public.subscriptions values (:A,'pro','trial',now()+interval '10 days',null),(:B,'pro','trial',now()+interval '10 days',null);
grant select, insert, update, delete on all tables in schema public to authenticated;
insert into public.customers(id,company_id,name,email,phone,ico,dic) values
 ('c1000000-0000-0000-0000-000000000001',:A,'Novák s.r.o.','novak@x.cz','','',''),
 ('c1000000-0000-0000-0000-000000000002',:A,'Novak sro','','+420777111222','12345678','CZ12345678'),
 ('c2000000-0000-0000-0000-000000000001',:B,'Cizí firma','cizi@x.cz','','','');
insert into public.jobs(company_id,customer_id,title) values (:A,'c1000000-0000-0000-0000-000000000002','Zakázka dup');
insert into public.reservations(company_id,customer_id,title) values (:A,'c1000000-0000-0000-0000-000000000002','Rezervace dup');
insert into public.deals(company_id,customer_id,title) values (:A,'c1000000-0000-0000-0000-000000000002','Případ dup');
insert into public.quotes(company_id,customer_id,title) values (:A,'c1000000-0000-0000-0000-000000000002','Nabídka dup');
insert into public.client_notes(company_id,customer_id,body,created_by) values (:A,'c1000000-0000-0000-0000-000000000002','Poznámka zaměstnance','11111111-0000-0000-0000-000000000002');
insert into public.tasks(company_id,title) values (:A,'Úkol bez klienta');

set role authenticated;
set request.jwt.claim.sub = '11111111-0000-0000-0000-000000000001';
-- A) rozšířená kontrola IČ DPH a IČO
create or replace function pg_temp.fails(q text) returns boolean language plpgsql as $$ begin execute q; return false; exception when others then return true; end $$;
grant execute on function pg_temp.fails(text) to authenticated;
insert into r select 'zákazník s německým IČ DPH projde', not pg_temp.fails($q$insert into public.customers(company_id,name,dic,country_code,status) values ('aaaaaaaa-0000-0000-0000-000000000001','GmbH','DE123456789','DE','lead')$q$);
insert into r select 'zákazník s nizozemským IČ DPH projde', not pg_temp.fails($q$insert into public.customers(company_id,name,dic,country_code) values ('aaaaaaaa-0000-0000-0000-000000000001','BV','NL123456789B01','NL')$q$);
insert into r select 'zahraniční registrační číslo firmy projde', not pg_temp.fails($q$insert into public.customers(company_id,name,ico,country_code) values ('aaaaaaaa-0000-0000-0000-000000000001','Ltd','HRB 12345','DE')$q$);
insert into r select 'DIČ s malými písmeny a mezerou se odmítne', pg_temp.fails($q$insert into public.customers(company_id,name,dic) values ('aaaaaaaa-0000-0000-0000-000000000001','x','de 123')$q$);
insert into r select 'neznámý stát se odmítne', pg_temp.fails($q$insert into public.customers(company_id,name,country_code) values ('aaaaaaaa-0000-0000-0000-000000000001','x','US')$q$);
insert into r select 'neplatný stav se odmítne', pg_temp.fails($q$insert into public.customers(company_id,name,status) values ('aaaaaaaa-0000-0000-0000-000000000001','x','vip')$q$);
insert into r select 'staré české DIČ a IČO fungují dál', not pg_temp.fails($q$insert into public.customers(company_id,name,ico,dic) values ('aaaaaaaa-0000-0000-0000-000000000001','CZ firma','87654321','CZ87654321')$q$);
insert into r select 'výchozí stav zákazníka je active', (select status from public.customers where id='c1000000-0000-0000-0000-000000000001')='active';
-- B) obchodní případy: uzavření a důvod prohry
insert into public.deals(id,company_id,title,stage) values ('d1000000-0000-0000-0000-000000000001',:A,'Obchod','offer');
update public.deals set stage='lost', lost_reason='Příliš drahé' where id='d1000000-0000-0000-0000-000000000001';
insert into r select 'prohra nastaví čas uzavření a důvod', (select closed_at is not null and lost_reason='Příliš drahé' from public.deals where id='d1000000-0000-0000-0000-000000000001');
update public.deals set stage='won' where id='d1000000-0000-0000-0000-000000000001';
insert into r select 'změna na vyhráno smaže důvod prohry', (select lost_reason is null and closed_at is not null from public.deals where id='d1000000-0000-0000-0000-000000000001');
update public.deals set stage='negotiation' where id='d1000000-0000-0000-0000-000000000001';
insert into r select 'znovuotevření vynuluje čas uzavření', (select closed_at is null from public.deals where id='d1000000-0000-0000-0000-000000000001');
-- C) úkoly s vazbou na klienta, izolace firem
insert into r select 'úkol navázaný na vlastního klienta projde', not pg_temp.fails($q$insert into public.tasks(company_id,title,customer_id) values ('aaaaaaaa-0000-0000-0000-000000000001','Zavolat','c1000000-0000-0000-0000-000000000001')$q$);
insert into r select 'úkol navázaný na klienta jiné firmy se odmítne', pg_temp.fails($q$insert into public.tasks(company_id,title,customer_id) values ('aaaaaaaa-0000-0000-0000-000000000001','Zavolat','c2000000-0000-0000-0000-000000000001')$q$);
insert into r select 'úkol navázaný na případ jiné firmy se odmítne', pg_temp.fails($q$insert into public.tasks(company_id,title,deal_id) values ('aaaaaaaa-0000-0000-0000-000000000001','x',(select '00000000-0000-0000-0000-000000000000'::uuid))$q$);
-- D) měny nabídek
insert into r select 'nabídka v PLN projde', not pg_temp.fails($q$insert into public.quotes(company_id,title,currency) values ('aaaaaaaa-0000-0000-0000-000000000001','pl','PLN')$q$);
insert into r select 'nabídka v USD se odmítne', pg_temp.fails($q$insert into public.quotes(company_id,title,currency) values ('aaaaaaaa-0000-0000-0000-000000000001','us','USD')$q$);
-- E) sloučení duplicit
insert into r select 'sloučení: zaměstnanec nesmí', pg_temp.fails(format($q$select public.crm_merge_customers('aaaaaaaa-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002')$q$)) from (select set_config('request.jwt.claim.sub','11111111-0000-0000-0000-000000000002',false)) s;
select set_config('request.jwt.claim.sub','22222222-0000-0000-0000-000000000001',false);
insert into r select 'sloučení: vlastník jiné firmy nesmí', pg_temp.fails($q$select public.crm_merge_customers('aaaaaaaa-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002')$q$);
insert into r select 'sloučení: zákazník z cizí firmy se odmítne', pg_temp.fails($q$select public.crm_merge_customers('bbbbbbbb-0000-0000-0000-000000000002','c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001')$q$);
select set_config('request.jwt.claim.sub','11111111-0000-0000-0000-000000000001',false);
insert into r select 'sloučení: sám se sebou se odmítne', pg_temp.fails($q$select public.crm_merge_customers('aaaaaaaa-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001')$q$);
create temp table mres as select public.crm_merge_customers(:A,'c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002') as j;
grant all on mres to authenticated;
insert into r select 'sloučení: přesunuto 1 zakázka, rezervace, případ, nabídka a záznam', (select j->>'jobs'='1' and j->>'reservations'='1' and j->>'deals'='1' and j->>'quotes'='1' and j->>'notes'='1' from mres);
insert into r select 'sloučení: poznámka zaměstnance zůstala u zachovaného klienta', (select count(*)=1 from public.client_notes where customer_id='c1000000-0000-0000-0000-000000000001');
insert into r select 'sloučení: doplněny prázdné údaje (telefon, IČO, DIČ)', (select phone='+420777111222' and ico='12345678' and dic='CZ12345678' and email='novak@x.cz' from public.customers where id='c1000000-0000-0000-0000-000000000001');
insert into r select 'sloučení: duplicita je archivovaná, ne smazaná', (select archived and notes like 'Sloučeno do%' from public.customers where id='c1000000-0000-0000-0000-000000000002');
insert into r select 'sloučení: na duplicitě nic nezbylo', (select (select count(*) from public.jobs where customer_id='c1000000-0000-0000-0000-000000000002')+(select count(*) from public.deals where customer_id='c1000000-0000-0000-0000-000000000002')+(select count(*) from public.quotes where customer_id='c1000000-0000-0000-0000-000000000002')=0);
insert into r select 'sloučení: cizí firma zůstala beze změny', (select name='Cizí firma' and not coalesce(archived,false) from public.customers where id='c2000000-0000-0000-0000-000000000001');
-- F) anonym nemá přístup k funkci
reset role;
insert into r select 'anonym nemůže volat sloučení', not has_function_privilege('anon','public.crm_merge_customers(uuid,uuid,uuid)','execute');
select case when ok then 'OK   ' else 'FAIL ' end || name from r;
select count(*) filter (where ok) || '/' || count(*) || ' prošlo' from r;
