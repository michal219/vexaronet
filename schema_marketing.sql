-- Vexaronet: Marketing (plan prispevku a navrhy textu). Nic existujiciho nemaze.
create table if not exists public.marketing_posts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  channel text,
  status text not null default 'draft',
  planned_on date,
  body text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists marketing_posts_company on public.marketing_posts (company_id, planned_on);

alter table public.marketing_posts enable row level security;
drop policy if exists mkp_select on public.marketing_posts;
create policy mkp_select on public.marketing_posts for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = marketing_posts.company_id and m.user_id = auth.uid()));
drop policy if exists mkp_write on public.marketing_posts;
create policy mkp_write on public.marketing_posts for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = marketing_posts.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = marketing_posts.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));
