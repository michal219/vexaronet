-- Vexaronet: dochazka zamestnancu (online / offline) + prava zamestnancu pridavat zakazniky a zakazky.
-- Spousti se jednou v Supabase SQL Editoru (cele najednou). Nic existujiciho nemeni ani nemaze.

create table if not exists public.time_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null,
  person text not null,
  shift_id uuid references public.shifts(id) on delete set null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  note text,
  created_at timestamptz not null default now(),
  check (ended_at is null or ended_at >= started_at)
);
create index if not exists time_entries_company_start on public.time_entries (company_id, started_at);
-- jeden clovek muze byt ve firme online jen jednou
create unique index if not exists time_entries_one_open on public.time_entries (company_id, user_id) where ended_at is null;

alter table public.time_entries enable row level security;
drop policy if exists te_select on public.time_entries;
create policy te_select on public.time_entries for select to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = time_entries.company_id and m.user_id = auth.uid()
                 and (m.role in ('owner','admin') or time_entries.user_id = auth.uid())));
drop policy if exists te_manage on public.time_entries;
create policy te_manage on public.time_entries for all to authenticated
  using (exists (select 1 from public.company_members m where m.company_id = time_entries.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')))
  with check (exists (select 1 from public.company_members m where m.company_id = time_entries.company_id and m.user_id = auth.uid() and m.role in ('owner','admin')));
-- zapis zamestnance jde jen pres funkce nize (cas bere server, ne telefon)

create or replace function public.clock_in(cid uuid, sid uuid default null)
returns uuid language plpgsql security definer set search_path = public, auth as $fn$
declare nid uuid; em text;
begin
  if not exists (select 1 from public.company_members m where m.company_id = cid and m.user_id = auth.uid()) then
    raise exception 'Nemate pristup do teto firmy.'; end if;
  select email::text into em from auth.users where id = auth.uid();
  insert into public.time_entries(company_id, user_id, person, shift_id) values (cid, auth.uid(), coalesce(em, '?'), sid) returning id into nid;
  return nid;
exception when unique_violation then
  raise exception 'Jste uz online.';
end $fn$;

create or replace function public.clock_out(cid uuid, target uuid default null)
returns void language plpgsql security definer set search_path = public as $fn$
declare who uuid := coalesce(target, auth.uid());
begin
  if who <> auth.uid() and not exists (select 1 from public.company_members m where m.company_id = cid and m.user_id = auth.uid() and m.role in ('owner','admin')) then
    raise exception 'Nemate opravneni ukoncit cizi smenu.'; end if;
  if not exists (select 1 from public.company_members m where m.company_id = cid and m.user_id = auth.uid()) then
    raise exception 'Nemate pristup do teto firmy.'; end if;
  update public.time_entries set ended_at = now() where company_id = cid and user_id = who and ended_at is null;
end $fn$;

grant execute on function public.clock_in(uuid, uuid) to authenticated;
grant execute on function public.clock_out(uuid, uuid) to authenticated;

-- Zamestnanec (clen firmy) smi pridavat a upravovat zakazniky, zakazky a ukoly. Mazat nemuze.
do $do$
declare t text;
begin
  foreach t in array array['customers','jobs','tasks'] loop
    begin
      execute format('drop policy if exists %I on public.%I', 'members_insert_' || t, t);
      execute format('create policy %I on public.%I for insert to authenticated with check (exists (select 1 from public.company_members m where m.company_id = %I.company_id and m.user_id = auth.uid()))', 'members_insert_' || t, t, t);
      execute format('drop policy if exists %I on public.%I', 'members_update_' || t, t);
      execute format('create policy %I on public.%I for update to authenticated using (exists (select 1 from public.company_members m where m.company_id = %I.company_id and m.user_id = auth.uid())) with check (exists (select 1 from public.company_members m where m.company_id = %I.company_id and m.user_id = auth.uid()))', 'members_update_' || t, t, t, t);
    exception when others then
      raise notice 'Tabulku % se nepodarilo upravit: %', t, sqlerrm;
    end;
  end loop;
end
$do$;
