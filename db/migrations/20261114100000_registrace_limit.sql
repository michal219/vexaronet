-- Vývojová fáze: nejvýše N nových firem (výchozí 10) pro zpětnou vazbu, potom se zakládání firem uzavře; přihlášení funguje dál.
--  * private.registration_limit: limit, od kdy se firmy počítají (starší testovací firmy se nepočítají) a datum plného spuštění.
--  * Trigger před vložením do public.companies odmítne novou HLAVNÍ firmu (parent_company_id is null) nad limit,
--    pokud ji zakládá uživatel přes API (JWT role authenticated/anon). Pobočky, pozvaní zaměstnanci a správa přes SQL nejsou dotčeny.
--    Souběžné zakládání serializuje advisory zámek, takže limit nejde překročit dvěma současnými registracemi.
--  * public.registration_status(): veřejný stav pro web (otevřeno/uzavřeno, volná místa, datum spuštění). Nic dalšího neprozrazuje.
-- Změna nastavení: update private.registration_limit set max_companies = 15;  /  set active = false (vypnout omezení)
-- Návrat: 20261114100000_registrace_limit_rollback.sql
create table if not exists private.registration_limit (
  id             boolean primary key default true check (id),
  active         boolean not null default true,
  max_companies  integer not null default 10 check (max_companies between 0 and 100000),
  counted_since  timestamptz not null,
  launch_on      date,
  updated_at     timestamptz not null default now());
alter table private.registration_limit enable row level security;
revoke all on private.registration_limit from public, anon, authenticated;
insert into private.registration_limit (id, active, max_companies, counted_since, launch_on)
  values (true, true, 10, timestamptz '2026-11-09 00:00:00+01', date '2026-12-09') on conflict (id) do nothing;

create or replace function private.registration_used() returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.companies c, private.registration_limit l
   where l.id and c.parent_company_id is null and c.created_at >= l.counted_since $$;

create or replace function public.registration_status() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare l private.registration_limit; u integer;
begin
  select * into l from private.registration_limit where id;
  if l.id is null or not l.active then return jsonb_build_object('limited', false, 'open', true, 'launch_on', l.launch_on); end if;
  u := private.registration_used();
  return jsonb_build_object('limited', true, 'open', u < l.max_companies, 'max', l.max_companies,
    'remaining', greatest(l.max_companies - u, 0), 'launch_on', l.launch_on);
end $$;

create or replace function private.registration_limit_check() returns trigger language plpgsql security definer set search_path = '' as $$
declare l private.registration_limit;
begin
  if new.parent_company_id is not null or coalesce(auth.role(), '') not in ('authenticated', 'anon') then return new; end if;
  select * into l from private.registration_limit where id;
  if l.id is null or not l.active then return new; end if;
  perform pg_advisory_xact_lock(7340012);
  if private.registration_used() >= l.max_companies then
    raise exception 'registration_closed' using errcode = 'PT403', detail = 'Kapacita firem ve vývojové fázi je naplněná.';
  end if;
  return new;
end $$;
drop trigger if exists registration_limit_check on public.companies;
create trigger registration_limit_check before insert on public.companies for each row execute function private.registration_limit_check();

revoke all on function private.registration_used(), private.registration_limit_check(), public.registration_status() from public, anon, authenticated;
grant execute on function public.registration_status() to anon, authenticated;
notify pgrst, 'reload schema';
