-- Vexaronet: přihlášky k novinkám a žádosti o změnu tarifu
-- Spouští se ručně v Supabase SQL Editoru. Nic nemaže ani nemění existující tabulky.

create table if not exists public.newsletter_subscribers (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  name text,
  company text,
  business_type text,
  interested_plan text,
  message text,
  consent boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists newsletter_subscribers_email_key on public.newsletter_subscribers (lower(email));
alter table public.newsletter_subscribers enable row level security;
-- návštěvník smí jen PŘIDAT přihlášku se souhlasem; číst smí jen správce databáze
drop policy if exists "anyone can subscribe" on public.newsletter_subscribers;
create policy "anyone can subscribe" on public.newsletter_subscribers
  for insert to anon, authenticated
  with check (consent = true and char_length(email) between 5 and 200);

create table if not exists public.plan_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null default auth.uid(),
  current_plan text,
  requested_plan text not null,
  note text,
  status text not null default 'new',
  created_at timestamptz not null default now()
);
alter table public.plan_requests enable row level security;
drop policy if exists "members create plan requests" on public.plan_requests;
create policy "members create plan requests" on public.plan_requests
  for insert to authenticated
  with check (user_id = auth.uid() and exists (
    select 1 from public.company_members m where m.company_id = plan_requests.company_id and m.user_id = auth.uid()));
drop policy if exists "members read plan requests" on public.plan_requests;
create policy "members read plan requests" on public.plan_requests
  for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = plan_requests.company_id and m.user_id = auth.uid()));
