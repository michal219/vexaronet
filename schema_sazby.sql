-- Vexaronet: hodinova sazba zamestnance (pro vypocet vydelku za odpracovane hodiny).
-- Spousti se jednou v Supabase SQL Editoru. Nic existujiciho nemeni ani nemaze.
-- Sazbu vidi a meni majitel / spravce firmy; zamestnanec vidi jen svou vlastni.

create table if not exists public.member_rates (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null,
  hourly_rate numeric(10,2) not null check (hourly_rate >= 0),
  updated_at timestamptz not null default now(),
  primary key (company_id, user_id)
);
alter table public.member_rates enable row level security;

drop policy if exists mr_select on public.member_rates;
create policy mr_select on public.member_rates for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = member_rates.company_id and m.user_id = auth.uid()
                 and (m.role in ('owner','admin') or member_rates.user_id = auth.uid())));

drop policy if exists mr_manage on public.member_rates;
create policy mr_manage on public.member_rates for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = member_rates.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = member_rates.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));
