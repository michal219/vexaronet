-- Jen pro LOKÁLNÍ PostgreSQL (ne pro Supabase!). Napodobí části Supabase, na kterých migrace závisí:
-- role anon / authenticated / service_role, schéma auth s auth.users a auth.uid(), výchozí práva
-- na funkce ve schématu public (v Supabase je dostávají anon, authenticated i service_role).
-- Bez těchto výchozích práv by test nepoznal, že migrace musí práva výslovně odebírat.
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    raise exception 'Toto je jen pro lokální test, ne pro Supabase.';
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

create schema if not exists auth;
create schema if not exists private;
grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema private to authenticated, service_role;   -- v produkci: authenticated ano, anon ne

create table if not exists auth.users (
  id uuid primary key,
  email text,
  email_confirmed_at timestamptz
);

create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))
$$;

alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
