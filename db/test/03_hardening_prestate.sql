-- Kopie výchozího stavu z živé databáze (katalog čtený 2026-11-09, jen čtení) pro migraci 20261109100000_zprisneni_prav.sql.
-- Opsané jsou: struktura a politiky formulářových tabulek, politiky a práva vzorových firemních tabulek
-- (products, shifts mají v produkci anon = arwdDxtm; politiky jen pro authenticated), anon SELECT na public_profiles
-- a nastavení search_path veřejných SECURITY DEFINER funkcí. Těla funkcí jsou zjednodušená.

-- formuláře (anon smí jen INSERT přes politiku)
create table public.newsletter_subscribers (id uuid primary key default gen_random_uuid(), email text not null, name text, company text,
  business_type text, interested_plan text, message text, consent boolean not null default false, created_at timestamptz not null default now());
create table public.custom_inquiries (id uuid primary key default gen_random_uuid(), email text not null, name text not null, company text,
  business_type text, message text, created_at timestamptz not null default now());
alter table public.newsletter_subscribers enable row level security;
alter table public.custom_inquiries enable row level security;
create policy "anyone can subscribe" on public.newsletter_subscribers for insert to anon, authenticated
  with check ((consent = true) and ((char_length(email) >= 5) and (char_length(email) <= 200)));
create policy ci_insert on public.custom_inquiries for insert to anon, authenticated with check (true);

-- veřejný profil (anon SELECT záměrně)
create table public.public_profiles (company_id uuid primary key references public.companies(id), published boolean not null default false, title text);
alter table public.public_profiles enable row level security;
create policy published_read on public.public_profiles for select to anon using (published);

-- vzorové firemní tabulky s produkčními politikami
create table public.products (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, name text not null);
create table public.shifts (id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade, user_id uuid, starts_at timestamptz);
alter table public.products enable row level security;
alter table public.shifts enable row level security;
create policy prod_select on public.products for select to authenticated using (exists (select 1 from public.company_members m where m.company_id = products.company_id and m.user_id = auth.uid()));
create policy prod_write on public.products for all to authenticated using (exists (select 1 from public.company_members m where m.company_id = products.company_id and m.user_id = auth.uid() and m.role = any (array['owner','admin'])));
create policy shifts_select on public.shifts for select to authenticated using (exists (select 1 from public.company_members m where m.company_id = shifts.company_id and m.user_id = auth.uid()));
create policy shifts_write on public.shifts for all to authenticated using (exists (select 1 from public.company_members m where m.company_id = shifts.company_id and m.user_id = auth.uid() and m.role = any (array['owner','admin'])));

-- práva jako v produkci (výchozí práva Supabase pro nové tabulky ve schématu public)
revoke all on public.newsletter_subscribers, public.custom_inquiries, public.products, public.shifts, public.public_profiles from public;
grant all on public.newsletter_subscribers, public.custom_inquiries, public.products, public.shifts to anon, authenticated, service_role;
grant select on public.public_profiles to anon;
grant all on public.public_profiles to authenticated, service_role;

-- veřejné SECURITY DEFINER funkce s neúplným search_path (v produkci: 'public' nebo 'public, auth')
create function public.public_book(p_slug text, p_service uuid, p_start timestamptz, p_name text, p_email text, p_phone text) returns jsonb
  language plpgsql security definer set search_path = public as $$ begin return jsonb_build_object('ok', true, 'slug', p_slug); end $$;
create function public.public_slots(p_slug text, p_service uuid, p_day date) returns jsonb
  language plpgsql security definer set search_path = public as $$ begin return '[]'::jsonb; end $$;
create function public.company_team(cid uuid) returns table(user_id uuid, role text)
  language sql security definer set search_path = public, auth as $$ select m.user_id, m.role from public.company_members m where m.company_id = cid
    and exists (select 1 from public.company_members x where x.company_id = cid and x.user_id = auth.uid()) $$;
create function public.shop_cancel_order(p_order uuid) returns void
  language plpgsql security definer set search_path = '' as $$ begin return; end $$;
revoke all on function public.public_book(text,uuid,timestamptz,text,text,text), public.public_slots(text,uuid,date), public.company_team(uuid), public.shop_cancel_order(uuid) from public;
grant execute on function public.public_book(text,uuid,timestamptz,text,text,text), public.public_slots(text,uuid,date) to anon, authenticated, service_role;
grant execute on function public.company_team(uuid), public.shop_cancel_order(uuid) to authenticated, service_role;
