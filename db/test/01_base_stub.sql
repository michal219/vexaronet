-- Minimální základ aplikace pro testy (lokální DB i bezplatný Supabase projekt).
-- Tabulky mají sloupce a politiky jako v živé databázi (db/snapshot/2026-11-07_jadro_firmy.sql),
-- mimo CHECK workspace_config (vyžaduje pg_jsonschema) a mimo tabulky, které profil nepoužívá.
-- Funkce member_role / writable / business_root jsou opsané doslova ze živé databáze;
-- test tests/db/run_local.sh ověřuje, že mají stejný md5 otisk jako v db/snapshot/*_manifest.txt.
-- OCHRANA: stub patří jen do PRÁZDNÉHO testovacího projektu nebo lokální databáze.
do $$ begin
  if to_regclass('public.customers') is not null or to_regclass('public.invoices') is not null
     or to_regclass('public.jobs') is not null then
    raise exception 'Tohle je databáze s tabulkami aplikace (customers/jobs/invoices). Stub nespouštějte, patří jen do prázdného testovacího projektu.';
  end if;
end $$;

create schema if not exists private;
grant usage on schema private to authenticated;

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id),
  name text not null check (length(name) >= 2 and length(name) <= 120),
  industry text not null default 'Služby',
  auto_task boolean not null default false,
  created_at timestamptz not null default now(),
  parent_company_id uuid references public.companies(id),
  branch_address text not null default '',
  country text not null default 'CZ',
  currency text not null default 'CZK'
);
create unique index if not exists one_trial_per_owner on public.companies (owner_id) where (parent_company_id is null);

create table if not exists public.company_members (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role = any (array['owner','admin','employee'])),
  display_name text not null default '',
  primary key (company_id, user_id)
);

create table if not exists public.subscriptions (
  company_id uuid primary key references public.companies(id) on delete cascade,
  plan text not null default 'business',
  status text not null default 'trial',
  trial_start timestamptz not null default now(),
  trial_end timestamptz default (now() + interval '30 days'),
  paid_until timestamptz,
  check (plan = any (array['start','accountant','pro','business','enterprise'])),
  check (status = any (array['trial','active','past_due','expired','canceled']))
);

alter table public.companies enable row level security;
alter table public.company_members enable row level security;
alter table public.subscriptions enable row level security;
revoke all on public.companies, public.company_members, public.subscriptions from anon, authenticated;
grant select on public.companies, public.company_members, public.subscriptions to authenticated;

CREATE OR REPLACE FUNCTION private.member_role(cid uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select m.role from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and auth.uid() is not null $function$;

CREATE OR REPLACE FUNCTION private.writable(cid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select auth.uid() is not null and exists(select 1 from public.subscriptions s where s.company_id=cid and ((s.status='trial' and s.trial_end>now()) or (s.status='active' and (s.paid_until>now() or s.plan='start'))))$function$;

CREATE OR REPLACE FUNCTION private.business_root(cid uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select coalesce(parent_company_id,id) from public.companies where id=cid$function$;

revoke all on function private.member_role(uuid), private.writable(uuid), private.business_root(uuid) from public, anon, authenticated, service_role;
grant execute on function private.member_role(uuid), private.writable(uuid) to authenticated;

drop policy if exists members_read on public.companies;
create policy members_read on public.companies for select to authenticated using ((private.member_role(id) is not null));
drop policy if exists team_read on public.company_members;
create policy team_read on public.company_members for select to authenticated using ((private.member_role(company_id) is not null));
drop policy if exists sub_read on public.subscriptions;
create policy sub_read on public.subscriptions for select to authenticated using ((private.member_role(company_id) is not null));
