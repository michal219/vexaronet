-- Návrat migrace 20261116100000_social_ucty. POZOR: smaže uložené (zašifrované) tokeny propojených účtů a evidenci publikací na sítě.
-- Záznam o zveřejnění u příspěvků (private.mkt_items) zůstává.
drop function if exists public.social_publish_finish(uuid, text, text, text, text, boolean);
drop function if exists public.social_publish_token(uuid);
drop function if exists public.social_publish_resolve(uuid, uuid, boolean, text);
drop function if exists public.social_publish_begin(uuid, uuid, uuid, text);
drop function if exists public.social_state(uuid);
drop function if exists public.social_disconnect(uuid, uuid);
drop function if exists public.social_oauth_finish(text, jsonb);
drop function if exists public.social_oauth_begin(uuid, text);
drop table if exists private.social_publications;
drop table if exists private.social_oauth_states;
drop table if exists private.social_accounts;
notify pgrst, 'reload schema';
