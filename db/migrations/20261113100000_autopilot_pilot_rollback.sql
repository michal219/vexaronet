-- Návrat migrace 20261113100000_autopilot_pilot (pilot placených běhů).
drop trigger if exists autopilot_pilot_check on private.autopilot_runs;
drop function if exists private.autopilot_pilot_check();
alter table private.autopilot_platform drop column if exists pilot_root_ids;
