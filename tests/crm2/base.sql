-- Zjednodušená kopie struktury produkce (jen tabulky a kontroly, které CRM používá) pro lokální test migrace.
create extension if not exists pgcrypto;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
end $$;
create schema auth; create schema private;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
grant usage on schema auth, public, private to anon, authenticated;
create table public.companies(id uuid primary key, name text, parent_company_id uuid);
create table public.company_members(company_id uuid, user_id uuid, role text);
create table public.subscriptions(company_id uuid, plan text, status text, trial_end timestamptz, paid_until timestamptz);
create function private.member_role(cid uuid) returns text language sql stable security definer set search_path='' as $$ select m.role from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and auth.uid() is not null $$;
create function private.writable(cid uuid) returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.subscriptions s where s.company_id=cid and ((s.status='trial' and s.trial_end>now()) or (s.status='active' and (s.paid_until>now() or s.plan='start'))))$$;
grant execute on all functions in schema private to authenticated;
create table public.customers(id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id), name text not null,
  email text, phone text, notes text, archived boolean default false, created_at timestamptz default now(), billing_address text, ico text not null default '', dic text not null default '',
  unique(company_id,id),
  check (length(billing_address) <= 500), check ((dic = '') or (dic ~ '^CZ[0-9]{8,10}$')), check ((ico = '') or (ico ~ '^[0-9]{8}$')), check (length(name) between 1 and 150));
create table public.jobs(id uuid primary key default gen_random_uuid(), company_id uuid not null, customer_id uuid, title text, foreign key (company_id, customer_id) references public.customers(company_id, id));
create table public.reservations(id uuid primary key default gen_random_uuid(), company_id uuid not null, customer_id uuid, title text, foreign key (company_id, customer_id) references public.customers(company_id, id));
create table public.tasks(id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id), title text not null, due_at timestamptz, completed boolean default false, description text, created_at timestamptz default now());
create table public.invoices(id uuid primary key default gen_random_uuid(), company_id uuid);
