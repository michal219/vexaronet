-- Vexaronet: AI Ucetni. Nic existujiciho nemaze.
-- CAST 1: pocitadlo zpracovanych dokladu za mesic
create table if not exists public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null default 'doc',
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists ai_usage_company_month on public.ai_usage (company_id, kind, created_at);
alter table public.ai_usage enable row level security;
drop policy if exists ai_usage_select on public.ai_usage;
create policy ai_usage_select on public.ai_usage for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = ai_usage.company_id and m.user_id = auth.uid()));
drop policy if exists ai_usage_insert on public.ai_usage;
create policy ai_usage_insert on public.ai_usage for insert to authenticated
  with check (exists (select 1 from public.company_members m where m.company_id = ai_usage.company_id and m.user_id = auth.uid()));

-- CAST 2 (spustit zvlast): povoli tarif accountant (AI Ucetni) v tabulce predplatneho
-- do $do$
-- declare r record;
-- begin
--   for r in select conname from pg_constraint where conrelid = 'public.subscriptions'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%plan%' loop
--     execute format('alter table public.subscriptions drop constraint %I', r.conname);
--   end loop;
--   alter table public.subscriptions add constraint subscriptions_plan_check check (plan in ('start','accountant','pro','business','enterprise')) not valid;
-- end $do$;
