-- Vexaronet: Ranni prehled (e-mail) a pobocky. Nic existujiciho nemaze.

-- 1) Pobocky / mista
create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  address text,
  city text,
  phone text,
  email text,
  hours text,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists locations_company on public.locations (company_id);
alter table public.locations enable row level security;
drop policy if exists loc_select on public.locations;
create policy loc_select on public.locations for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = locations.company_id and m.user_id = auth.uid()));
drop policy if exists loc_write on public.locations;
create policy loc_write on public.locations for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = locations.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = locations.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));

-- pobocka u zakazek, rezervaci a smen (nepovinne)
alter table public.jobs add column if not exists location_id uuid references public.locations(id) on delete set null;
alter table public.reservations add column if not exists location_id uuid references public.locations(id) on delete set null;
alter table public.shifts add column if not exists location_id uuid references public.locations(id) on delete set null;

-- 2) Nastaveni rannino prehledu (kazdy uzivatel si nastavuje svuj)
create table if not exists public.digest_settings (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  send_hour int not null default 7 check (send_hour between 0 and 23),
  email text,
  last_sent_on date,
  created_at timestamptz not null default now(),
  primary key (company_id, user_id)
);
alter table public.digest_settings enable row level security;
drop policy if exists dig_own on public.digest_settings;
create policy dig_own on public.digest_settings for all to authenticated
  using (user_id = auth.uid() and exists (select 1 from public.company_members m where m.company_id = digest_settings.company_id and m.user_id = auth.uid()))
  with check (user_id = auth.uid() and exists (select 1 from public.company_members m where m.company_id = digest_settings.company_id and m.user_id = auth.uid()));

-- 3) Planovac: kazdou hodinu zavola /api/digest (posle ty, kterym prave zacina jejich hodina).
-- Nejdriv v Supabase: Database -> Extensions -> zapnout "pg_cron" a "pg_net".
-- Pak ZMENTE heslo DIGEST_SECRET na stejnou hodnotu, jakou date do Cloudflare, a spustte:
--
-- select cron.schedule('vexaronet-digest', '0 * * * *', $$
--   select net.http_post(
--     url := 'https://vexaronet.com/api/digest',
--     headers := jsonb_build_object('content-type','application/json','x-cron-secret','ZDE_VLOZTE_DIGEST_SECRET'),
--     body := '{}'::jsonb
--   );
-- $$);
