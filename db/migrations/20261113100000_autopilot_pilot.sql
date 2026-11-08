-- Pilot placených AI běhů: placené běhy smí rezervovat jen vybrané hlavní firmy (vynucuje databáze pro všechny AI moduly).
--  * private.autopilot_platform.pilot_root_ids: NULL = bez omezení; jinak jen uvedené hlavní firmy (business_root).
--  * Trigger před vložením rezervace do private.autopilot_runs odmítne firmu mimo seznam stejnou chybou jako vypnuté
--    placené běhy (PT403 paid_runs_disabled, detail {"reason":"not_in_pilot"}), takže se nic nezaplatí a nic nezůstane.
--  * Pořadí kontrol v autopilot_reserve se nemění (role, tarif, vypínač, limit); pilot je poslední pojistka při zápisu.
-- Nastavení pilotu: update private.autopilot_platform set pilot_root_ids = array['<uuid hlavní firmy>']::uuid[];
-- Návrat: 20261113100000_autopilot_pilot_rollback.sql
alter table private.autopilot_platform add column if not exists pilot_root_ids uuid[];

create or replace function private.autopilot_pilot_check() returns trigger language plpgsql security definer set search_path = '' as $$
declare pilot uuid[];
begin
  select pilot_root_ids into pilot from private.autopilot_platform where id;
  if pilot is not null and not (new.root_company_id = any(pilot)) then
    perform private.ap_raise('PT403', 'paid_runs_disabled', '{"reason":"not_in_pilot"}'::jsonb);
  end if;
  return new;
end $$;
revoke all on function private.autopilot_pilot_check() from public, anon, authenticated;
drop trigger if exists autopilot_pilot_check on private.autopilot_runs;
create trigger autopilot_pilot_check before insert on private.autopilot_runs for each row execute function private.autopilot_pilot_check();
