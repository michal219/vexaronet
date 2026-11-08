-- Výchozí stav pro migrace 20261110100000 (marketing) a 20261110110000 (DSA): tabulky, které migrace jen čtou.
-- Tvar sloupců podle produkčního katalogu (2026-11-09). Nic dalšího se nevytváří.
create table if not exists public.newsletter_subscribers (id uuid primary key default gen_random_uuid(), email text not null, name text, company text,
  business_type text, interested_plan text, message text, consent boolean not null default false, created_at timestamptz not null default now());
create table if not exists private.platform_admins (user_id uuid primary key references auth.users(id));
create table if not exists public.sites (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id), slug text unique, enabled boolean default true, data jsonb);
create table if not exists public.shop_settings (company_id uuid primary key references public.companies(id), slug text unique, enabled boolean default true);
create table if not exists public.booking_profiles (company_id uuid primary key references public.companies(id), slug text unique, enabled boolean default true);
alter table public.newsletter_subscribers enable row level security;
alter table private.platform_admins enable row level security;
alter table public.sites enable row level security;
alter table public.shop_settings enable row level security;
alter table public.booking_profiles enable row level security;
revoke all on public.newsletter_subscribers, public.sites, public.shop_settings, public.booking_profiles from anon, authenticated;
grant insert on public.newsletter_subscribers to anon, authenticated;
revoke all on private.platform_admins from public, anon, authenticated;
