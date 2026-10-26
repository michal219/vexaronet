-- Vexaronet: Jednoduchy web (editor + verejna stranka). Nic existujiciho nemaze.
create table if not exists public.sites (
  company_id uuid primary key references public.companies(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,40}$'),
  enabled boolean not null default false,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.sites enable row level security;
drop policy if exists sites_select on public.sites;
create policy sites_select on public.sites for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = sites.company_id and m.user_id = auth.uid()));
drop policy if exists sites_write on public.sites;
create policy sites_write on public.sites for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = sites.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = sites.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));

-- Verejna stranka: vraci jen zapnute weby a jen obsah, ktery majitel zverejnil
create or replace function public.public_site(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare s public.sites; cname text; bslug text;
begin
  select * into s from public.sites where slug = lower(p_slug) and enabled;
  if not found then return null; end if;
  select name into cname from public.companies where id = s.company_id;
  select slug into bslug from public.booking_profiles where company_id = s.company_id and enabled;
  return jsonb_build_object('name', cname, 'data', s.data, 'booking', bslug);
end $fn$;

grant execute on function public.public_site(text) to anon, authenticated;
