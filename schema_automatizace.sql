-- Vexaronet: Automatizace (zapnuti a vypnuti pravidel). Nic existujiciho nemaze.
create table if not exists public.automation_rules (
  company_id uuid not null references public.companies(id) on delete cascade,
  rule text not null check (length(rule) between 1 and 40),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (company_id, rule)
);

alter table public.automation_rules enable row level security;
drop policy if exists aur_select on public.automation_rules;
create policy aur_select on public.automation_rules for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = automation_rules.company_id and m.user_id = auth.uid()));
drop policy if exists aur_write on public.automation_rules;
create policy aur_write on public.automation_rules for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = automation_rules.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = automation_rules.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));
