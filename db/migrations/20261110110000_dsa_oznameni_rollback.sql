-- Zpět k 20261110110000_dsa_oznameni.sql. POZOR: smaže přijatá oznámení a jejich evidenci.
-- Před rollbackem exportujte private.dsa_notices a private.dsa_events (evidence rozhodnutí může být potřeba pro dozor nebo spor).
begin;
drop function if exists public.dsa_admin_review(uuid);
drop function if exists public.dsa_admin_decide(uuid, text, text, text);
drop function if exists public.dsa_admin_list(text);
drop function if exists public.dsa_mark(uuid, text);
drop function if exists public.dsa_submit(jsonb, text);
drop function if exists private.dsa_is_admin();
drop trigger if exists dsa_events_no_change on private.dsa_events;
drop table if exists private.dsa_events;
drop table if exists private.dsa_notices;
drop function if exists private.dsa_events_append_only();
notify pgrst, 'reload schema';
commit;
