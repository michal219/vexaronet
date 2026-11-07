create extension if not exists pgcrypto;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema auth; create schema private; create schema vault;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
grant usage on schema auth, public, private to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
create table vault.decrypted_secrets(name text, decrypted_secret text);
insert into vault.decrypted_secrets values ('vexaronet_mkt_dispatch', repeat('ab',32));
create table public.companies(id uuid primary key, name text, parent_company_id uuid);
create table public.company_members(company_id uuid, user_id uuid, role text);
create table public.subscriptions(company_id uuid, plan text, status text, trial_end timestamptz, paid_until timestamptz);
create function private.member_role(cid uuid) returns text language sql stable security definer set search_path='' as $$ select m.role from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and auth.uid() is not null $$;
create function private.writable(cid uuid) returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.subscriptions s where s.company_id=cid and ((s.status='trial' and s.trial_end>now()) or (s.status='active' and (s.paid_until>now() or s.plan='start'))))$$;
create function private.business_root(cid uuid) returns uuid language sql stable security definer set search_path='' as $$select coalesce(parent_company_id,id) from public.companies where id=cid$$;
grant execute on all functions in schema private to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated, service_role;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated, service_role;
-- data: firma A (PRO, uživatelé owner a employee), firma B (PRO, owner), firma C (START)
insert into public.companies values ('aaaaaaaa-0000-0000-0000-000000000001','A',null),('bbbbbbbb-0000-0000-0000-000000000002','B',null),('cccccccc-0000-0000-0000-000000000003','C',null);
insert into public.company_members values
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001','owner'),
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000002','employee'),
 ('bbbbbbbb-0000-0000-0000-000000000002','22222222-0000-0000-0000-000000000001','owner'),
 ('cccccccc-0000-0000-0000-000000000003','33333333-0000-0000-0000-000000000001','owner');
insert into public.subscriptions values
 ('aaaaaaaa-0000-0000-0000-000000000001','pro','trial',now()+interval '10 days',null),
 ('bbbbbbbb-0000-0000-0000-000000000002','pro','active',null,now()+interval '20 days'),
 ('cccccccc-0000-0000-0000-000000000003','start','active',null,null);
