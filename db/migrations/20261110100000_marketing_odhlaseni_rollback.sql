-- Zpět k 20261110100000_marketing_odhlaseni.sql. POZOR: smaže evidenci odhlášení a odeslání novinek.
-- Před rollbackem exportujte private.marketing_suppressions: odhlášené adresy se NESMÍ znovu oslovit (§ 7 zák. č. 480/2004 Sb.).
begin;
drop function if exists public.marketing_finish(uuid, text, text, text);
drop function if exists public.marketing_send_allowed(uuid, text);
drop function if exists public.marketing_claim(integer);
drop function if exists public.marketing_queue(text, text, timestamptz);
drop function if exists public.marketing_unsubscribe(text);
drop function if exists private.mk_suppressed(text);
drop function if exists private.mk_hash(text);
drop function if exists private.mk_norm(text);
drop table if exists private.marketing_deliveries;
drop table if exists private.marketing_messages;
drop table if exists private.marketing_suppressions;
notify pgrst, 'reload schema';
commit;
