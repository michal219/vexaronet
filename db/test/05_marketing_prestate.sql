-- Výchozí stav pro migraci 20261112100000_ai_marketing.sql: tabulky, které migrace používá, ve tvaru produkce (katalog 2026-11-09).
create table if not exists public.marketing_posts (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
  title text not null, channel text, status text not null default 'draft', planned_on date, body text, created_by uuid default auth.uid(), created_at timestamptz not null default now());
alter table public.marketing_posts enable row level security;
drop policy if exists mkp_select on public.marketing_posts;
drop policy if exists mkp_write on public.marketing_posts;
create policy mkp_select on public.marketing_posts for select to authenticated using (exists (select 1 from public.company_members m where m.company_id = marketing_posts.company_id and m.user_id = auth.uid()));
create policy mkp_write on public.marketing_posts for all to authenticated using (exists (select 1 from public.company_members m where m.company_id = marketing_posts.company_id and m.user_id = auth.uid() and m.role = any (array['owner','admin'])));
revoke all on public.marketing_posts from public, anon; grant select, insert, update, delete on public.marketing_posts to authenticated;
create table if not exists public.sites (id uuid primary key default gen_random_uuid(), company_id uuid not null unique references public.companies(id) on delete cascade, slug text unique, enabled boolean not null default true, data jsonb);
alter table public.sites enable row level security; revoke all on public.sites from public, anon, authenticated;
create table if not exists public.deals (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, title text, created_at timestamptz not null default now());
create table if not exists public.customers (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, name text, created_at timestamptz not null default now());
create table if not exists public.reservations (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, title text, created_at timestamptz not null default now());
create table if not exists public.shop_orders (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, created_at timestamptz not null default now());
alter table public.deals enable row level security; alter table public.customers enable row level security;
alter table public.reservations enable row level security; alter table public.shop_orders enable row level security;
revoke all on public.deals, public.customers, public.reservations, public.shop_orders from public, anon, authenticated;
