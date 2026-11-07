-- Zpět k 20261107120000_profil_firmy.sql. Odstraní jen objekty, které tato migrace vytvořila.
-- POZOR: smaže uložené koncepty, potvrzené verze a události profilů firem (nevratně).
-- Před spuštěním na produkci zálohujte private.company_profile_* (např. pg_dump -t).
begin;

drop function if exists public.profile_confirm(uuid, integer, text);
drop function if exists public.profile_save_draft(uuid, integer, integer, jsonb);
drop function if exists public.profile_version_get(uuid, integer);
drop function if exists public.profile_get(uuid);
drop function if exists public.profile_schema_info();

drop function if exists private.profile_confirm_core(uuid, integer, text);
drop function if exists private.profile_save_draft_core(uuid, integer, integer, jsonb);
drop function if exists private.profile_version_get_core(uuid, integer);
drop function if exists private.profile_get_core(uuid);
drop function if exists private.profile_schema_info_core();
drop function if exists private.profile_invalid(text[]);
drop function if exists private.profile_conflict(integer);
drop function if exists private.profile_actor(uuid, boolean);
drop function if exists private.vx_jwt_role();

drop table if exists private.company_profile_events;
drop table if exists private.company_active_profile;
drop table if exists private.company_profile_versions;
drop table if exists private.company_profile_drafts;

drop function if exists private.vx_incomplete(jsonb, boolean);
drop function if exists private.vx_nonempty(jsonb);
drop function if exists private.vx_has(jsonb);
drop function if exists private.vx_hash(jsonb);
drop function if exists private.vx_apply_derived(jsonb);
drop function if exists private.vx_goal_target(bigint, integer);
drop function if exists private.vx_trim(jsonb);
drop function if exists private.vx_profile_validate(jsonb, boolean);
drop function if exists private.vx_json_validate(jsonb, jsonb, text);
drop function if exists private.vx_sort(text[]);
drop function if exists private.vx_block_update();
drop function if exists private.profile_schema_version();
drop function if exists private.profile_schema();

notify pgrst, 'reload schema';
commit;
