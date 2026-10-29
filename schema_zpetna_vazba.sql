-- Vexaronet: zpetna vazba z aplikace (tlacitko "Neco nefunguje?").
-- Spousti se jednou v Supabase SQL Editoru. Nic existujiciho nemeni ani nemaze.
-- Zpravy vidi jen majitel/spravce firmy a ten, kdo je napsal.

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete cascade,
  user_id uuid not null default auth.uid(),
  email text,
  kind text not null default 'problem' check (kind in ('problem','napad','jine')),
  message text not null check (char_length(message) between 3 and 4000),
  page text,
  user_agent text,
  created_at timestamptz not null default now()
);
create index if not exists feedback_company_created on public.feedback (company_id, created_at desc);
alter table public.feedback enable row level security;

drop policy if exists fb_insert on public.feedback;
create policy fb_insert on public.feedback for insert to authenticated
  with check (user_id = auth.uid() and (company_id is null or exists (select 1 from public.company_members m where m.company_id = feedback.company_id and m.user_id = auth.uid())));

drop policy if exists fb_select on public.feedback;
create policy fb_select on public.feedback for select to authenticated
  using (user_id = auth.uid() or exists (select 1 from public.company_members m where m.company_id = feedback.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));
