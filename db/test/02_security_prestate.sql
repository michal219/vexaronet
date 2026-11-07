-- Kopie výchozího stavu, který zjistil audit v živé databázi 2026-11-07 (jen objekty, kterých se týká
-- migrace 20261108100000_bezpecnostni_opravy.sql). Práva (ACL), RLS i politiky jsou opsané z katalogu:
--   private.*: vlastník postgres, bez práv pro ostatní, RLS vypnuté
--   public.ai_usage / company_invites / plan_requests: ACL postgres, anon, authenticated, service_role = arwdDxtm; RLS zapnuté
--   public.clock_in / clock_out / shop_cancel_order: EXECUTE pro PUBLIC, postgres, anon, authenticated, service_role
-- Těla funkcí jsou zjednodušená (testuje se jen to, kdo je smí volat a zda RLS neomezí funkce definer).
create schema if not exists private;

create table private.platform_admins (user_id uuid primary key references auth.users(id));
create table private.ai_requests (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id),
  user_id uuid not null references auth.users(id), created_at timestamptz not null default now());
create table private.feedback_mail_delivery (id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now());
create table private.push_deliveries (id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now());

create table public.ai_usage (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null default 'doc', created_by uuid default auth.uid(), created_at timestamptz not null default now());
create table public.company_invites (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
  email text not null, role text not null default 'employee' check (role in ('admin','employee')), invited_by uuid default auth.uid(),
  created_at timestamptz not null default now(), accepted_at timestamptz);
create table public.plan_requests (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null default auth.uid(), current_plan text, requested_plan text not null, note text, status text not null default 'new', created_at timestamptz not null default now());
alter table public.ai_usage enable row level security;
alter table public.company_invites enable row level security;
alter table public.plan_requests enable row level security;
revoke all on public.ai_usage, public.company_invites, public.plan_requests from public;
grant all on public.ai_usage, public.company_invites, public.plan_requests to anon, authenticated, service_role;

create policy ai_usage_select on public.ai_usage for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = ai_usage.company_id and m.user_id = auth.uid()));
create policy ai_usage_insert on public.ai_usage for insert to authenticated
  with check (exists (select 1 from public.company_members m where m.company_id = ai_usage.company_id and m.user_id = auth.uid()));
create policy invites_select on public.company_invites for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = company_invites.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));
create policy "members read plan requests" on public.plan_requests for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = plan_requests.company_id and m.user_id = auth.uid()));
create policy "members create plan requests" on public.plan_requests for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.company_members m where m.company_id = plan_requests.company_id and m.user_id = auth.uid()));

create function public.clock_in(cid uuid, sid uuid) returns uuid language plpgsql security definer set search_path = public, auth as $$
begin if not exists (select 1 from public.company_members m where m.company_id = cid and m.user_id = auth.uid()) then raise exception 'Nemate pristup do teto firmy.'; end if; return gen_random_uuid(); end $$;
create function public.clock_out(cid uuid, target uuid) returns void language plpgsql security definer set search_path = public as $$
begin if not exists (select 1 from public.company_members m where m.company_id = cid and m.user_id = auth.uid()) then raise exception 'Nemate pristup do teto firmy.'; end if; end $$;
create function public.shop_cancel_order(p_order uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
begin if auth.uid() is null then raise exception 'Nemáte oprávnění.'; end if; return '{}'::jsonb; end $$;
-- funkce, které jsou veřejné ZÁMĚRNĚ (e-shop, rezervace); migrace se jich nesmí dotknout
create function public.public_shop(p_slug text) returns jsonb language sql security definer set search_path = '' as $$select '{}'::jsonb$$;

revoke all on function public.clock_in(uuid, uuid), public.clock_out(uuid, uuid), public.shop_cancel_order(uuid), public.public_shop(text) from public;
grant execute on function public.clock_in(uuid, uuid), public.clock_out(uuid, uuid), public.shop_cancel_order(uuid), public.public_shop(text) to public, anon, authenticated, service_role;
