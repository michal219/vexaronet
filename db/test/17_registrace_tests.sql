-- Testy migrace 20261114100000_registrace_limit. Každá kontrola vypíše NOTICE "ok …", selhání ukončí běh.
\set ON_ERROR_STOP 1
create function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'TEST_FAIL %', m; end if; raise notice 'ok  %', m; end $$;
create function pg_temp.jwt(r text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claims', json_build_object('role', r, 'sub', gen_random_uuid())::text, false); end $$;
create function pg_temp.new_co(n text) returns text language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users (id, email) values (u, n || '@test.invalid');
  begin insert into public.companies (owner_id, name) values (u, n); return 'ok';
  exception when others then return sqlstate || ':' || sqlerrm; end;
end $$;
-- 8 starších testovacích firem (před counted_since) se nepočítají
select pg_temp.jwt('');
insert into auth.users (id, email) select gen_random_uuid(), 'old' || g || '@test.invalid' from generate_series(1, 8) g;
insert into public.companies (owner_id, name, created_at) select id, email, timestamptz '2026-11-01 10:00+01' from auth.users where email like 'old%';
select pg_temp.ok((public.registration_status()->>'remaining')::int = 10, 'starší firmy se nepočítají: volných 10 z 10');
-- 10 nových firem přes API (role authenticated) projde, 11. ne
select pg_temp.jwt('authenticated');
select pg_temp.ok(bool_and(pg_temp.new_co('nova' || g) = 'ok'), '10 nových firem přes API se založí') from generate_series(1, 10) g;
select pg_temp.ok(pg_temp.new_co('jedenacta') like 'PT403:registration_closed%', '11. firma přes API je odmítnuta (PT403 registration_closed)');
select pg_temp.ok((select count(*) from public.companies where name = 'jedenacta') = 0, 'odmítnutá firma se neuložila');
select pg_temp.jwt('anon');
select pg_temp.ok(pg_temp.new_co('anonymni') like 'PT403:registration_closed%', 'ani role anon firmu nad limit nezaloží');
select pg_temp.jwt('authenticated');
-- pobočka existující firmy limit neovlivní
insert into public.companies (owner_id, name, parent_company_id) select owner_id, 'pobocka', id from public.companies where name = 'nova1';
select pg_temp.ok(exists (select 1 from public.companies where name = 'pobocka'), 'pobočka existující firmy se založí i po naplnění');
-- veřejný stav
select pg_temp.ok(public.registration_status() @> '{"limited":true,"open":false,"remaining":0,"max":10,"launch_on":"2026-12-09"}', 'stav: uzavřeno, 0 volných, spuštění 2026-12-09');
select pg_temp.ok(has_function_privilege('anon', 'public.registration_status()', 'execute'), 'anon smí číst veřejný stav');
select pg_temp.ok(not has_table_privilege('anon', 'private.registration_limit', 'select') and not has_table_privilege('authenticated', 'private.registration_limit', 'update'), 'nastavení limitu nejde číst ani měnit přes API');
select pg_temp.ok(not has_function_privilege('authenticated', 'private.registration_limit_check()', 'execute'), 'triggerovou funkci nejde volat přes API');
-- správa přes SQL (bez JWT) a změna nastavení
select pg_temp.jwt('');
select pg_temp.ok(pg_temp.new_co('rucne_spravce') = 'ok', 'správce přes SQL (bez JWT) firmu založí');
update private.registration_limit set max_companies = 12;
select pg_temp.jwt('authenticated');
select pg_temp.ok(pg_temp.new_co('po_navyseni') = 'ok', 'po navýšení limitu na 12 lze založit další firmu');
select pg_temp.ok(pg_temp.new_co('nad_12') like 'PT403:%', 'a nad 12 už ne');
update private.registration_limit set active = false;
select pg_temp.ok(pg_temp.new_co('vypnuto') = 'ok' and public.registration_status() @> '{"limited":false,"open":true}', 'vypnutý limit: registrace otevřená');
select pg_temp.jwt('');
do $$ begin raise notice 'VŠECHNY TESTY REGISTRACE PROŠLY'; end $$;
