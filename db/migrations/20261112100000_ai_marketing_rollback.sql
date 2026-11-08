-- Zpět k 20261112100000_ai_marketing.sql. Příspěvky v public.marketing_posts zůstanou (jen bez vazby na strategii,
-- schválení a publikaci); strategie, záznamy schválení a ručně zadané výsledky se smažou (před rollbackem exportovat).
begin;
drop trigger if exists mkt_post_changed on public.marketing_posts;
drop function if exists public.mkt_results(uuid);
drop function if exists public.mkt_result_add(uuid, uuid, text, numeric, date, date, text);
drop function if exists public.public_site_news(text);
drop function if exists public.mkt_unpublish(uuid, uuid);
drop function if exists public.mkt_publish(uuid, uuid, text, text, date);
drop function if exists public.mkt_post_approve(uuid, uuid, text);
drop function if exists public.mkt_posts_store(uuid, uuid, uuid, jsonb);
drop function if exists public.mkt_strategy_approve(uuid, uuid, text);
drop function if exists public.mkt_strategy_edit(uuid, uuid, text, jsonb);
drop function if exists public.mkt_strategy_store(uuid, uuid, jsonb);
drop function if exists public.mkt_state(uuid);
drop function if exists private.mkt_post_changed();
drop table if exists private.mkt_results;
drop table if exists private.mkt_items;
drop table if exists private.mkt_strategies;
drop function if exists private.mkt_count(uuid, text, timestamptz, timestamptz);
drop function if exists private.mkt_goal_value(uuid, text, timestamptz);
drop function if exists private.mkt_active_profile_version(uuid);
drop function if exists private.mkt_strategy_errors(jsonb);
drop function if exists private.mkt_channel_ok(text);
drop function if exists private.mkt_fail(text, text);
drop function if exists private.mkt_doc_hash(jsonb);
drop function if exists private.mkt_hash(text, text, text);
notify pgrst, 'reload schema';
commit;
