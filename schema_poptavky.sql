-- Vexaronet: poptavky na system na miru (oddelene od odberu novinek).
create table if not exists public.custom_inquiries (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  name text not null,
  company text,
  business_type text,
  message text,
  created_at timestamptz not null default now()
);
alter table public.custom_inquiries enable row level security;
drop policy if exists ci_insert on public.custom_inquiries;
create policy ci_insert on public.custom_inquiries for insert to anon, authenticated with check (true);
