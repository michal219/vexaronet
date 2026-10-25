-- Vexaronet: pozvánky zaměstnanců. Nic existujícího nemění ani nemaže.
-- Spouští se jednou v Supabase SQL Editoru.

create table if not exists public.company_invites (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  email text not null,
  role text not null default 'employee' check (role in ('admin','employee')),
  invited_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);
create unique index if not exists company_invites_open_uniq
  on public.company_invites (company_id, lower(email)) where accepted_at is null;

alter table public.company_invites enable row level security;
drop policy if exists invites_select on public.company_invites;
create policy invites_select on public.company_invites for select to authenticated
  using (exists (select 1 from public.company_members m
                 where m.company_id = company_invites.company_id
                   and m.user_id = auth.uid() and m.role in ('owner','admin')));
-- zápis jen přes funkce níže (žádná insert/update/delete politika)

-- Tým firmy (e-maily členů smí vidět jen člen téže firmy)
create or replace function public.company_team(cid uuid)
returns table(user_id uuid, email text, role text, is_me boolean)
language sql security definer set search_path = public, auth as $$
  select m.user_id, u.email::text, m.role::text, (m.user_id = auth.uid())
  from public.company_members m join auth.users u on u.id = m.user_id
  where m.company_id = cid
    and exists (select 1 from public.company_members x where x.company_id = cid and x.user_id = auth.uid())
  order by (m.role = 'owner') desc, u.email;
$$;

-- Pozvání člena (kontroluje oprávnění, roli i limit uživatelů podle tarifu)
create or replace function public.invite_member(cid uuid, invite_email text, invite_role text)
returns uuid language plpgsql security definer set search_path = public, auth as $$
declare
  me text; s record; p text; lim int; used int; e text := lower(trim(invite_email)); nid uuid;
begin
  select m.role::text into me from public.company_members m where m.company_id = cid and m.user_id = auth.uid();
  if me is null or me not in ('owner','admin') then raise exception 'Nemáte oprávnění zvát členy týmu.'; end if;
  if invite_role not in ('admin','employee') then raise exception 'Neplatná role.'; end if;
  if invite_role = 'admin' and me <> 'owner' then raise exception 'Správce může přidat jen majitel.'; end if;
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Zadejte platný e-mail.'; end if;
  if exists (select 1 from public.company_members m join auth.users u on u.id = m.user_id
             where m.company_id = cid and lower(u.email) = e) then
    raise exception 'Tento člověk už ve firmě je.'; end if;

  select * into s from public.subscriptions where company_id = cid limit 1;
  p := lower(coalesce(s.plan::text, 'start'));
  if s.status::text in ('expired','canceled') or (s.status::text = 'trial' and s.trial_end is not null and s.trial_end < now()) then p := 'start'; end if;
  lim := case p when 'start' then 1 when 'accountant' then 2 when 'pro' then 3 when 'business' then 10 else 1000 end;
  select (select count(*) from public.company_members where company_id = cid)
       + (select count(*) from public.company_invites where company_id = cid and accepted_at is null) into used;
  if used >= lim then raise exception 'Váš tarif umožňuje nejvýše % uživatelů (včetně nevyřízených pozvánek).', lim; end if;

  insert into public.company_invites(company_id, email, role) values (cid, e, invite_role) returning id into nid;
  return nid;
exception when unique_violation then
  raise exception 'Tento e-mail už je pozvaný.';
end $$;

create or replace function public.cancel_invite(invite_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select company_id into cid from public.company_invites where id = invite_id and accepted_at is null;
  if cid is null then return; end if;
  if not exists (select 1 from public.company_members m where m.company_id = cid and m.user_id = auth.uid() and m.role in ('owner','admin'))
    then raise exception 'Nemáte oprávnění.'; end if;
  delete from public.company_invites where id = invite_id;
end $$;

create or replace function public.remove_member(cid uuid, member_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me text; tr text;
begin
  select role::text into me from public.company_members where company_id = cid and user_id = auth.uid();
  select role::text into tr from public.company_members where company_id = cid and user_id = member_id;
  if me is null or me not in ('owner','admin') then raise exception 'Nemáte oprávnění.'; end if;
  if tr is null then return; end if;
  if tr = 'owner' then raise exception 'Majitele firmy nelze odebrat.'; end if;
  if member_id = auth.uid() then raise exception 'Sami sebe odebrat nelze.'; end if;
  if tr = 'admin' and me <> 'owner' then raise exception 'Správce může odebrat jen majitel.'; end if;
  delete from public.company_members where company_id = cid and user_id = member_id;
end $$;

-- Po přihlášení pozvaného: přidá ho do firmy, která ho pozvala (jen s potvrzeným e-mailem a jen pokud ještě nemá firmu)
create or replace function public.accept_company_invites()
returns int language plpgsql security definer set search_path = public, auth as $$
declare em text; n int := 0; i record;
begin
  select lower(email) into em from auth.users where id = auth.uid() and email_confirmed_at is not null;
  if em is null then return 0; end if;
  if exists (select 1 from public.company_members where user_id = auth.uid()) then return 0; end if;
  for i in select * from public.company_invites where lower(email) = em and accepted_at is null order by created_at limit 1 loop
    insert into public.company_members(company_id, user_id, role) values (i.company_id, auth.uid(), i.role);
    update public.company_invites set accepted_at = now() where id = i.id;
    n := n + 1;
  end loop;
  return n;
end $$;

revoke all on function public.company_team(uuid), public.invite_member(uuid,text,text), public.cancel_invite(uuid),
  public.remove_member(uuid,uuid), public.accept_company_invites() from public, anon;
grant execute on function public.company_team(uuid), public.invite_member(uuid,text,text), public.cancel_invite(uuid),
  public.remove_member(uuid,uuid), public.accept_company_invites() to authenticated;
