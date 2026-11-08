-- AI Marketing Autopilot: strategie → obsah → schválení → publikace → výsledky (docs/AI_DOKONCENI.md). NEAPLIKOVÁNO NA PRODUKCI.
-- Nové objekty + jeden trigger na public.marketing_posts (po změně schváleného obsahu vrátí příspěvek do konceptu).
-- Závisí na: profil firmy (20261107120000), limity Autopilota (20261108110000), public.marketing_posts, public.sites,
--            public.deals / customers / reservations / shop_orders (jen čtení pro výsledky).
-- Pravidla:
--  * výsledky AI ukládá jen server (service_role) a vždy s vazbou na běh Autopilota (autopilot_runs) téže firmy;
--  * schvaluje jen člověk (JWT role authenticated, vlastník/správce, zapisovatelný účet) a schvaluje KONKRÉTNÍ obsah (otisk);
--  * publikace jen schváleného a od schválení nezměněného obsahu; veřejný web vidí jen příspěvky s datem do dneška.
begin;

create table if not exists private.mkt_strategies (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  version integer not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'superseded')),
  source text not null check (source in ('ai', 'manual')),
  run_id uuid unique references private.autopilot_runs(id),
  profile_version integer not null,
  doc jsonb not null,
  doc_hash text not null,
  created_by uuid, created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz,
  unique (company_id, version));
create table if not exists private.mkt_items (
  post_id uuid primary key references public.marketing_posts(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  strategy_id uuid references private.mkt_strategies(id),
  run_id uuid references private.autopilot_runs(id),
  ai_hash text,
  approved_hash text, approved_by uuid, approved_at timestamptz,
  published_channel text, published_url text, published_at timestamptz, published_by uuid,
  web_publish_on date);
create index if not exists mkt_items_run on private.mkt_items (run_id);
create index if not exists mkt_items_web on private.mkt_items (company_id, web_publish_on) where web_publish_on is not null;
create table if not exists private.mkt_results (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  post_id uuid not null references public.marketing_posts(id) on delete cascade,
  metric text not null check (metric in ('dosah', 'zobrazeni', 'prokliky', 'reakce', 'komentare', 'sdileni', 'zpravy', 'jine')),
  value numeric not null check (value >= 0 and value <= 1e9),
  period_start date not null, period_end date not null check (period_end >= period_start),
  source text not null check (char_length(source) between 3 and 120),
  entered_by uuid not null, created_at timestamptz not null default now());
alter table private.mkt_strategies enable row level security;
alter table private.mkt_items enable row level security;
alter table private.mkt_results enable row level security;
revoke all on private.mkt_strategies, private.mkt_items, private.mkt_results from public, anon, authenticated;

-- ---------- pomocné ----------
create or replace function private.mkt_hash(t text, b text, ch text) returns text language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to(coalesce(t, '') || E'\x1f' || coalesce(b, '') || E'\x1f' || coalesce(ch, ''), 'UTF8')), 'hex') $$;
create or replace function private.mkt_doc_hash(d jsonb) returns text language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to(d::text, 'UTF8')), 'hex') $$;
create or replace function private.mkt_fail(code text, msg text) returns void language plpgsql set search_path = '' as $$
begin raise exception '%', msg using errcode = code; end $$;
create or replace function private.mkt_channel_ok(c text) returns boolean language sql immutable set search_path = '' as $$
  select c in ('Instagram', 'Facebook', 'E-mail', 'Web nebo blog', 'Reklama', 'Jiné') $$;
-- validace dokumentu strategie (tvar, délky, výčty). Vrací seznam chyb (prázdný = v pořádku).
create or replace function private.mkt_strategy_errors(d jsonb) returns text[] language plpgsql immutable set search_path = '' as $$
declare e text[] := '{}'; x jsonb;
begin
  if jsonb_typeof(d) <> 'object' then return array['doc']; end if;
  if jsonb_typeof(d->'goal') <> 'object' or (d#>>'{goal,metric}') not in ('poptavky', 'zakaznici', 'rezervace', 'objednavky')
     or jsonb_typeof(d#>'{goal,target}') <> 'number' or (d#>>'{goal,target}')::numeric not between 1 and 10000 or (d#>>'{goal,target}')::numeric <> trunc((d#>>'{goal,target}')::numeric)
     or jsonb_typeof(d#>'{goal,days}') <> 'number' or (d#>>'{goal,days}')::numeric not between 7 and 180 or (d#>>'{goal,days}')::numeric <> trunc((d#>>'{goal,days}')::numeric) then e := e || 'goal'::text; end if;
  if coalesce(char_length(d->>'audience'), 0) not between 10 and 1000 then e := e || 'audience'::text; end if;
  if coalesce(char_length(d->>'positioning'), 0) not between 10 and 1000 then e := e || 'positioning'::text; end if;
  if coalesce(char_length(d->>'tone'), 0) > 300 then e := e || 'tone'::text; end if;
  if jsonb_typeof(d->'channels') <> 'array' or jsonb_array_length(d->'channels') not between 1 and 6 then e := e || 'channels'::text;
  else for x in select value from jsonb_array_elements(d->'channels') loop
    if not private.mkt_channel_ok(x->>'channel') or coalesce(char_length(x->>'why'), 0) not between 3 and 300 then e := e || 'channels'::text; exit; end if; end loop; end if;
  if jsonb_typeof(d->'themes') <> 'array' or jsonb_array_length(d->'themes') not between 2 and 8 then e := e || 'themes'::text;
  else for x in select value from jsonb_array_elements(d->'themes') loop
    if coalesce(char_length(x->>'title'), 0) not between 3 and 120 or coalesce(char_length(x->>'angle'), 0) > 400 then e := e || 'themes'::text; exit; end if; end loop; end if;
  if jsonb_typeof(d->'cadence_per_week') <> 'number' or (d->>'cadence_per_week')::numeric not between 1 and 14 then e := e || 'cadence_per_week'::text; end if;
  if (select count(*) from jsonb_object_keys(d) k where k not in ('goal', 'audience', 'positioning', 'tone', 'channels', 'themes', 'cadence_per_week', 'notes')) > 0 then e := e || 'extra'::text; end if;
  if coalesce(char_length(d->>'notes'), 0) > 2000 then e := e || 'notes'::text; end if;
  return e;
end $$;
create or replace function private.mkt_active_profile_version(cid uuid) returns integer language sql stable security definer set search_path = '' as $$
  select v.version from private.company_active_profile a join private.company_profile_versions v on v.id = a.version_id
   where a.company_id = cid $$;
create or replace function private.mkt_goal_value(cid uuid, metric text, since timestamptz) returns integer language plpgsql stable security definer set search_path = '' as $$
declare n integer;
begin
  if metric = 'poptavky' then select count(*) into n from public.deals where company_id = cid and created_at >= since;
  elsif metric = 'zakaznici' then select count(*) into n from public.customers where company_id = cid and created_at >= since;
  elsif metric = 'rezervace' then select count(*) into n from public.reservations where company_id = cid and created_at >= since;
  elsif metric = 'objednavky' then select count(*) into n from public.shop_orders where company_id = cid and created_at >= since;
  end if;
  return coalesce(n, 0);
end $$;
create or replace function private.mkt_count(cid uuid, metric text, a timestamptz, b timestamptz) returns integer language plpgsql stable security definer set search_path = '' as $$
begin return private.mkt_goal_value(cid, metric, a) - private.mkt_goal_value(cid, metric, b); end $$;

-- ---------- stav pro dashboard ----------
create or replace function public.mkt_state(cid uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, false); pv integer; cur private.mkt_strategies; apr private.mkt_strategies; prog jsonb;
begin
  pv := private.mkt_active_profile_version(cid);
  if pv is null then pv := private.mkt_active_profile_version(private.business_root(cid)); end if;
  select * into cur from private.mkt_strategies where company_id = cid order by version desc limit 1;
  select * into apr from private.mkt_strategies where company_id = cid and status = 'approved' order by version desc limit 1;
  if apr.id is not null then
    prog := jsonb_build_object('metric', apr.doc#>>'{goal,metric}', 'target', (apr.doc#>>'{goal,target}')::int, 'days', (apr.doc#>>'{goal,days}')::int,
      'since', apr.approved_at, 'until', apr.approved_at + make_interval(days => (apr.doc#>>'{goal,days}')::int),
      'value', private.mkt_goal_value(cid, apr.doc#>>'{goal,metric}', apr.approved_at));
  end if;
  return jsonb_build_object(
    'profile', jsonb_build_object('confirmed', pv is not null, 'version', pv),
    'strategy', case when cur.id is null then null else jsonb_build_object('id', cur.id, 'version', cur.version, 'status', cur.status, 'source', cur.source,
        'doc', cur.doc, 'hash', cur.doc_hash, 'profile_version', cur.profile_version, 'created_at', cur.created_at, 'approved_at', cur.approved_at) end,
    'approved', case when apr.id is null then null else jsonb_build_object('id', apr.id, 'version', apr.version, 'doc', apr.doc, 'approved_at', apr.approved_at) end,
    'progress', prog,
    'items', coalesce((select jsonb_agg(jsonb_build_object('post_id', i.post_id, 'strategy_id', i.strategy_id, 'ai', i.run_id is not null,
        'approved', i.approved_hash is not null and i.approved_hash = private.mkt_hash(p.title, p.body, p.channel),
        'changed_after_approval', i.approved_hash is not null and i.approved_hash <> private.mkt_hash(p.title, p.body, p.channel),
        'published_channel', i.published_channel, 'published_url', i.published_url, 'published_at', i.published_at, 'web_publish_on', i.web_publish_on))
      from private.mkt_items i join public.marketing_posts p on p.id = i.post_id where i.company_id = cid), '[]'::jsonb));
end $$;

-- ---------- strategie ----------
create or replace function public.mkt_strategy_store(cid uuid, p_run uuid, p_doc jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare r private.autopilot_runs; s private.mkt_strategies; pv integer; v integer; err text[];
begin
  select * into s from private.mkt_strategies where run_id = p_run;
  if s.id is not null then return jsonb_build_object('id', s.id, 'version', s.version, 'reused', true); end if;
  select * into r from private.autopilot_runs where id = p_run;
  if r.id is null or r.company_id <> cid or r.mode <> 'marketing' then perform private.mkt_fail('PT404', 'run_not_found'); end if;
  err := private.mkt_strategy_errors(p_doc);
  if cardinality(err) > 0 then raise exception 'invalid_strategy' using errcode = 'PT422', detail = array_to_string(err, ','); end if;
  pv := coalesce(private.mkt_active_profile_version(cid), private.mkt_active_profile_version(private.business_root(cid)));
  if pv is null then perform private.mkt_fail('PT412', 'profile_not_confirmed'); end if;
  perform pg_advisory_xact_lock(hashtextextended(cid::text, 7321));
  select coalesce(max(version), 0) + 1 into v from private.mkt_strategies where company_id = cid;
  insert into private.mkt_strategies (company_id, version, source, run_id, profile_version, doc, doc_hash, created_by)
    values (cid, v, 'ai', p_run, pv, p_doc, private.mkt_doc_hash(p_doc), r.created_by) returning * into s;
  return jsonb_build_object('id', s.id, 'version', s.version, 'reused', false);
end $$;

create or replace function public.mkt_strategy_edit(cid uuid, p_id uuid, p_expected_hash text, p_doc jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); s private.mkt_strategies; err text[]; v integer; nid uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended(cid::text, 7321));
  select * into s from private.mkt_strategies where id = p_id and company_id = cid for update;
  if s.id is null then perform private.mkt_fail('PT404', 'not_found'); end if;
  if s.doc_hash <> p_expected_hash then perform private.mkt_fail('PT409', 'stale'); end if;
  err := private.mkt_strategy_errors(p_doc);
  if cardinality(err) > 0 then raise exception 'invalid_strategy' using errcode = 'PT422', detail = array_to_string(err, ','); end if;
  if s.status = 'draft' then
    update private.mkt_strategies set doc = p_doc, doc_hash = private.mkt_doc_hash(p_doc), source = 'manual' where id = s.id;
    return jsonb_build_object('id', s.id, 'version', s.version, 'hash', private.mkt_doc_hash(p_doc));
  end if;
  select coalesce(max(version), 0) + 1 into v from private.mkt_strategies where company_id = cid;   -- úprava schválené = nový koncept
  insert into private.mkt_strategies (company_id, version, source, profile_version, doc, doc_hash, created_by)
    values (cid, v, 'manual', s.profile_version, p_doc, private.mkt_doc_hash(p_doc), uid) returning id into nid;
  return jsonb_build_object('id', nid, 'version', v, 'hash', private.mkt_doc_hash(p_doc));
end $$;

create or replace function public.mkt_strategy_approve(cid uuid, p_id uuid, p_expected_hash text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); s private.mkt_strategies;
begin
  perform pg_advisory_xact_lock(hashtextextended(cid::text, 7321));
  select * into s from private.mkt_strategies where id = p_id and company_id = cid for update;
  if s.id is null then perform private.mkt_fail('PT404', 'not_found'); end if;
  if s.doc_hash <> p_expected_hash then perform private.mkt_fail('PT409', 'stale'); end if;
  if s.status = 'approved' then return jsonb_build_object('id', s.id, 'already', true); end if;
  if s.status <> 'draft' then perform private.mkt_fail('PT409', 'not_draft'); end if;
  update private.mkt_strategies set status = 'superseded' where company_id = cid and status = 'approved';
  update private.mkt_strategies set status = 'approved', approved_by = uid, approved_at = now() where id = s.id;
  return jsonb_build_object('id', s.id, 'already', false);
end $$;

-- ---------- návrhy příspěvků z AI (jen server) ----------
create or replace function public.mkt_posts_store(cid uuid, p_run uuid, p_strategy uuid, p_posts jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare r private.autopilot_runs; s private.mkt_strategies; x jsonb; nid uuid; ids uuid[] := '{}'; d date;
begin
  if exists (select 1 from private.mkt_items where run_id = p_run) then
    return jsonb_build_object('reused', true, 'post_ids', (select jsonb_agg(post_id) from private.mkt_items where run_id = p_run)); end if;
  select * into r from private.autopilot_runs where id = p_run;
  if r.id is null or r.company_id <> cid or r.mode <> 'marketing' then perform private.mkt_fail('PT404', 'run_not_found'); end if;
  select * into s from private.mkt_strategies where id = p_strategy and company_id = cid;
  if s.id is null or s.status <> 'approved' then perform private.mkt_fail('PT412', 'strategy_not_approved'); end if;
  if jsonb_typeof(p_posts) <> 'array' or jsonb_array_length(p_posts) not between 1 and 14 then perform private.mkt_fail('PT422', 'invalid_posts'); end if;
  for x in select value from jsonb_array_elements(p_posts) loop
    if coalesce(char_length(x->>'title'), 0) not between 3 and 100 or coalesce(char_length(x->>'body'), 0) not between 20 and 4000
       or not private.mkt_channel_ok(x->>'channel') or (x->>'planned_on') !~ '^\d{4}-\d{2}-\d{2}$' then perform private.mkt_fail('PT422', 'invalid_posts'); end if;
    d := (x->>'planned_on')::date;
    if d < current_date or d > current_date + 120 then perform private.mkt_fail('PT422', 'invalid_posts'); end if;
  end loop;
  for x in select value from jsonb_array_elements(p_posts) loop
    insert into public.marketing_posts (company_id, title, channel, status, planned_on, body, created_by)
      values (cid, x->>'title', x->>'channel', 'draft', (x->>'planned_on')::date, x->>'body', r.created_by) returning id into nid;
    insert into private.mkt_items (post_id, company_id, strategy_id, run_id, ai_hash) values (nid, cid, s.id, p_run, private.mkt_hash(x->>'title', x->>'body', x->>'channel'));
    ids := ids || nid;
  end loop;
  return jsonb_build_object('reused', false, 'post_ids', to_jsonb(ids));
end $$;

-- ---------- schválení a publikace (jen člověk) ----------
create or replace function public.mkt_post_approve(cid uuid, p_post uuid, p_expected_hash text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); p public.marketing_posts; h text;
begin
  select * into p from public.marketing_posts where id = p_post and company_id = cid for update;
  if p.id is null then perform private.mkt_fail('PT404', 'not_found'); end if;
  h := private.mkt_hash(p.title, p.body, p.channel);
  if h <> p_expected_hash then perform private.mkt_fail('PT409', 'stale'); end if;
  if coalesce(char_length(p.body), 0) < 1 then perform private.mkt_fail('PT422', 'empty_body'); end if;
  insert into private.mkt_items (post_id, company_id, approved_hash, approved_by, approved_at) values (p.id, cid, h, uid, now())
    on conflict (post_id) do update set approved_hash = excluded.approved_hash, approved_by = excluded.approved_by, approved_at = excluded.approved_at;
  update public.marketing_posts set status = case when status = 'done' then status else 'planned' end where id = p.id;
  return jsonb_build_object('post_id', p.id, 'hash', h);
end $$;

create or replace function public.mkt_publish(cid uuid, p_post uuid, p_channel text, p_url text default null, p_on date default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); p public.marketing_posts; i private.mkt_items; d date;
begin
  select * into p from public.marketing_posts where id = p_post and company_id = cid for update;
  if p.id is null then perform private.mkt_fail('PT404', 'not_found'); end if;
  select * into i from private.mkt_items where post_id = p.id;
  if i.approved_hash is null or i.approved_hash <> private.mkt_hash(p.title, p.body, p.channel) then perform private.mkt_fail('PT412', 'not_approved'); end if;
  if p_channel = 'web' then
    if not exists (select 1 from public.sites s where s.company_id = cid and s.enabled and s.slug is not null) then perform private.mkt_fail('PT412', 'no_site'); end if;
    d := coalesce(p_on, p.planned_on, current_date);
    if d < current_date then d := current_date; end if;
    update private.mkt_items set published_channel = 'web', web_publish_on = d, published_url = null, published_at = now(), published_by = uid where post_id = p.id;
    update public.marketing_posts set status = case when d <= current_date then 'done' else 'planned' end, planned_on = d where id = p.id;
    return jsonb_build_object('post_id', p.id, 'channel', 'web', 'publish_on', d, 'live', d <= current_date);
  end if;
  if not private.mkt_channel_ok(p_channel) then perform private.mkt_fail('PT422', 'invalid_channel'); end if;
  if p_url is not null and (char_length(p_url) > 1000 or p_url !~ '^https://[^[:space:]]+$') then perform private.mkt_fail('PT422', 'invalid_url'); end if;
  update private.mkt_items set published_channel = p_channel, published_url = p_url, published_at = now(), published_by = uid, web_publish_on = null where post_id = p.id;
  update public.marketing_posts set status = 'done' where id = p.id;
  return jsonb_build_object('post_id', p.id, 'channel', p_channel, 'live', true);
end $$;

create or replace function public.mkt_unpublish(cid uuid, p_post uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true);
begin
  update private.mkt_items set published_channel = null, published_url = null, published_at = null, published_by = null, web_publish_on = null
   where post_id = p_post and company_id = cid;
  if not found then perform private.mkt_fail('PT404', 'not_found'); end if;
  update public.marketing_posts set status = 'planned' where id = p_post and company_id = cid;
  return jsonb_build_object('post_id', p_post);
end $$;

-- po změně schváleného obsahu (jakýmkoli zápisem) se schválení ruší a příspěvek se vrací do konceptu; z webu zmizí
create or replace function private.mkt_post_changed() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (new.title, new.body, new.channel) is distinct from (old.title, old.body, old.channel)
     and exists (select 1 from private.mkt_items i where i.post_id = new.id and i.approved_hash is not null) then
    update private.mkt_items set approved_hash = null, approved_by = null, approved_at = null,
      published_channel = case when published_channel = 'web' then null else published_channel end,
      web_publish_on = null where post_id = new.id;
    if new.status = 'planned' then new.status := 'draft'; end if;
  end if;
  return new;
end $$;
drop trigger if exists mkt_post_changed on public.marketing_posts;
create trigger mkt_post_changed before update on public.marketing_posts for each row execute function private.mkt_post_changed();

-- veřejný web firmy: jen schválené, nezměněné příspěvky s datem do dneška
create or replace function public.public_site_news(p_slug text) returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('title', x.title, 'body', x.body, 'date', x.web_publish_on) order by x.web_publish_on desc), '[]'::jsonb)
  from (select p.title, p.body, i.web_publish_on from public.sites s
          join private.mkt_items i on i.company_id = s.company_id and i.published_channel = 'web' and i.web_publish_on <= (now() at time zone 'Europe/Prague')::date
          join public.marketing_posts p on p.id = i.post_id
         where s.slug = lower(p_slug) and s.enabled and i.approved_hash = private.mkt_hash(p.title, p.body, p.channel)
         order by i.web_publish_on desc limit 20) x $$;

-- ---------- výsledky ----------
create or replace function public.mkt_result_add(cid uuid, p_post uuid, p_metric text, p_value numeric, p_from date, p_to date, p_source text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); nid uuid;
begin
  if not exists (select 1 from private.mkt_items i where i.post_id = p_post and i.company_id = cid and i.published_at is not null) then perform private.mkt_fail('PT412', 'not_published'); end if;
  insert into private.mkt_results (company_id, post_id, metric, value, period_start, period_end, source, entered_by)
    values (cid, p_post, p_metric, p_value, p_from, p_to, btrim(p_source), uid) returning id into nid;
  return jsonb_build_object('id', nid);
end $$;

create or replace function public.mkt_results(cid uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, false);
begin
  return coalesce((select jsonb_agg(jsonb_build_object('post_id', p.id, 'title', p.title, 'channel', i.published_channel, 'published_at', i.published_at,
      'published_url', i.published_url, 'web_publish_on', i.web_publish_on,
      'window_days', 7,
      'system', (select jsonb_object_agg(m, jsonb_build_object(
          'after', private.mkt_count(cid, m, coalesce(i.web_publish_on::timestamptz, i.published_at), coalesce(i.web_publish_on::timestamptz, i.published_at) + interval '7 days'),
          'before', private.mkt_count(cid, m, coalesce(i.web_publish_on::timestamptz, i.published_at) - interval '7 days', coalesce(i.web_publish_on::timestamptz, i.published_at)),
          'complete', coalesce(i.web_publish_on::timestamptz, i.published_at) + interval '7 days' <= now()))
        from unnest(array['poptavky', 'zakaznici', 'rezervace', 'objednavky']) m),
      'manual', coalesce((select jsonb_agg(jsonb_build_object('metric', r.metric, 'value', r.value, 'from', r.period_start, 'to', r.period_end, 'source', r.source) order by r.created_at)
                 from private.mkt_results r where r.post_id = p.id), '[]'::jsonb))
      order by i.published_at desc)
    from private.mkt_items i join public.marketing_posts p on p.id = i.post_id
   where i.company_id = cid and i.published_at is not null), '[]'::jsonb);
end $$;

-- ---------- práva ----------
revoke all on function private.mkt_hash(text, text, text), private.mkt_doc_hash(jsonb), private.mkt_fail(text, text), private.mkt_channel_ok(text),
  private.mkt_strategy_errors(jsonb), private.mkt_active_profile_version(uuid), private.mkt_goal_value(uuid, text, timestamptz),
  private.mkt_count(uuid, text, timestamptz, timestamptz), private.mkt_post_changed() from public, anon, authenticated;
revoke all on function public.mkt_state(uuid), public.mkt_strategy_store(uuid, uuid, jsonb), public.mkt_strategy_edit(uuid, uuid, text, jsonb),
  public.mkt_strategy_approve(uuid, uuid, text), public.mkt_posts_store(uuid, uuid, uuid, jsonb), public.mkt_post_approve(uuid, uuid, text),
  public.mkt_publish(uuid, uuid, text, text, date), public.mkt_unpublish(uuid, uuid), public.public_site_news(text),
  public.mkt_result_add(uuid, uuid, text, numeric, date, date, text), public.mkt_results(uuid) from public, anon, authenticated;
grant execute on function public.mkt_state(uuid), public.mkt_strategy_edit(uuid, uuid, text, jsonb), public.mkt_strategy_approve(uuid, uuid, text),
  public.mkt_post_approve(uuid, uuid, text), public.mkt_publish(uuid, uuid, text, text, date), public.mkt_unpublish(uuid, uuid),
  public.mkt_result_add(uuid, uuid, text, numeric, date, date, text), public.mkt_results(uuid) to authenticated;
grant execute on function public.mkt_strategy_store(uuid, uuid, jsonb), public.mkt_posts_store(uuid, uuid, uuid, jsonb) to service_role;
grant execute on function public.public_site_news(text) to anon, authenticated;

notify pgrst, 'reload schema';
commit;
