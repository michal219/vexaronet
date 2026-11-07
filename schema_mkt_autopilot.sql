-- Vexaronet: AI Marketing Autopilot (část 1). Jen přidává nové tabulky a funkce, nic existujícího nemění ani nemaže.
-- Data firem odděluje RLS přes private.member_role(company_id). Zápis výsledků AI dělá jen serverová funkce
-- mkt-autopilot (service role). Uživatel zadává úlohy, schvaluje a pozastavuje přes funkce mkt_* níže.

-- ---------- profil a nastavení ----------
create table if not exists public.mkt_profiles (
  company_id uuid primary key references public.companies(id) on delete cascade,
  business_name text check (char_length(business_name) <= 120),
  industry text check (char_length(industry) <= 120),
  offer text check (char_length(offer) <= 2000),
  location text check (char_length(location) <= 200),
  audience text check (char_length(audience) <= 1000),
  competitors text check (char_length(competitors) <= 1000),
  website text check (char_length(website) <= 300),
  budget_monthly numeric(12,2) check (budget_monthly >= 0 and budget_monthly <= 10000000),
  goals text check (char_length(goals) <= 1000),
  tone text check (char_length(tone) <= 200),
  channels text[] not null default '{}' check (cardinality(channels) <= 10),
  analysis jsonb,
  completed boolean not null default false,
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now()
);

create table if not exists public.mkt_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  autopilot_on boolean not null default false,
  paused boolean not null default false,
  paused_at timestamptz,
  morning_hour smallint not null default 7 check (morning_hour between 0 and 23),
  evening_hour smallint not null default 19 check (evening_hour between 0 and 23),
  monthly_ai_limit integer not null default 150 check (monthly_ai_limit between 0 and 3000),
  updated_at timestamptz not null default now()
);

-- ---------- fronta úloh ----------
create table if not exists public.mkt_tasks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null check (kind in ('chat','strategy','content_plan','campaign','video','diagnose','analysis','morning','evening')),
  title text not null check (char_length(title) <= 200),
  status text not null default 'queued' check (status in ('queued','running','done','failed','canceled')),
  source text not null default 'user' check (source in ('user','chat','schedule','system')),
  priority smallint not null default 5,
  run_after timestamptz not null default now(),
  attempts smallint not null default 0,
  max_attempts smallint not null default 3,
  lease_until timestamptz,
  lease_token uuid,
  idem_key text check (char_length(idem_key) <= 120),
  payload jsonb not null default '{}'::jsonb check (pg_column_size(payload) <= 8000),
  result jsonb,
  error text check (char_length(error) <= 1000),
  parent_id uuid references public.mkt_tasks(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  unique (company_id, idem_key)
);
create index if not exists mkt_tasks_queue on public.mkt_tasks (status, run_after) where status in ('queued','running');
create index if not exists mkt_tasks_company on public.mkt_tasks (company_id, created_at desc);

-- ---------- výstupy AI ----------
create table if not exists public.mkt_strategies (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  period text not null check (period in ('week','month')),
  starts_on date, ends_on date,
  title text check (char_length(title) <= 200),
  summary text,
  data jsonb not null default '{}'::jsonb,
  status text not null default 'proposed' check (status in ('proposed','active','archived')),
  task_id uuid references public.mkt_tasks(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists mkt_strategies_company on public.mkt_strategies (company_id, created_at desc);

create table if not exists public.mkt_content (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  strategy_id uuid references public.mkt_strategies(id) on delete set null,
  channel text not null check (channel in ('instagram','facebook','tiktok','youtube','email','web')),
  format text not null default 'post' check (format in ('post','reel','short','story','video','email','article')),
  series text check (char_length(series) <= 120),
  title text check (char_length(title) <= 200),
  caption text check (char_length(caption) <= 5000),
  hashtags text[] not null default '{}' check (cardinality(hashtags) <= 30),
  cta text check (char_length(cta) <= 300),
  planned_at timestamptz,
  status text not null default 'pending_approval' check (status in ('draft','pending_approval','approved','rejected','published')),
  published_url text check (char_length(published_url) <= 500),
  media_id uuid,
  task_id uuid references public.mkt_tasks(id) on delete set null,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create index if not exists mkt_content_company on public.mkt_content (company_id, planned_at);

create table if not exists public.mkt_campaigns (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform text not null default 'meta' check (platform in ('meta','google','tiktok','other')),
  name text not null check (char_length(name) <= 200),
  objective text check (char_length(objective) <= 500),
  audience jsonb not null default '{}'::jsonb,
  budget_total numeric(12,2) check (budget_total >= 0),
  budget_daily numeric(12,2) check (budget_daily >= 0),
  starts_on date, ends_on date,
  ads jsonb not null default '[]'::jsonb,
  kpis jsonb not null default '{}'::jsonb,
  status text not null default 'pending_approval' check (status in ('pending_approval','approved','rejected','running','paused','finished')),
  task_id uuid references public.mkt_tasks(id) on delete set null,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

create table if not exists public.mkt_media (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null default 'video' check (kind in ('video','image')),
  title text not null check (char_length(title) <= 200),
  aspect text not null default '9:16' check (aspect in ('9:16','1:1','16:9')),
  package jsonb not null default '{}'::jsonb,
  status text not null default 'pending_approval' check (status in ('pending_approval','approved','rejected','rendering','ready','failed')),
  render_note text,
  storage_path text,
  task_id uuid references public.mkt_tasks(id) on delete set null,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

create table if not exists public.mkt_reports (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null check (kind in ('morning','evening','diagnose','analysis')),
  title text not null check (char_length(title) <= 200),
  body text,
  data jsonb not null default '{}'::jsonb,
  task_id uuid references public.mkt_tasks(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists mkt_reports_company on public.mkt_reports (company_id, created_at desc);

-- ---------- schvalování ----------
create table if not exists public.mkt_approvals (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  entity text not null check (entity in ('content','campaign','media')),
  entity_id uuid not null,
  level text not null check (level in ('rule','separate')),
  summary text not null check (char_length(summary) <= 500),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  decided_by uuid,
  decided_at timestamptz,
  note text check (char_length(note) <= 500),
  created_at timestamptz not null default now(),
  unique (entity, entity_id)
);
create index if not exists mkt_approvals_pending on public.mkt_approvals (company_id, status);

-- ---------- integrace, analytika, chat, historie ----------
create table if not exists public.mkt_integrations (
  company_id uuid not null references public.companies(id) on delete cascade,
  provider text not null check (provider in ('meta','tiktok','youtube','google_ads')),
  status text not null default 'not_connected' check (status in ('not_connected','pending','connected','error')),
  account_label text check (char_length(account_label) <= 200),
  connected_at timestamptz,
  primary key (company_id, provider)
);
-- Přístupové tokeny propojených účtů jen na serveru (žádná politika = žádný přístup z aplikace).
create table if not exists private.mkt_integration_tokens (
  company_id uuid not null references public.companies(id) on delete cascade,
  provider text not null,
  token_ciphertext text not null,
  expires_at timestamptz,
  primary key (company_id, provider)
);
revoke all on private.mkt_integration_tokens from public, anon, authenticated;

create table if not exists public.mkt_metrics (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  metric_date date not null,
  channel text not null check (char_length(channel) <= 40),
  metric text not null check (metric in ('views','reach','clicks','conversions','leads','customers','spend','revenue')),
  value numeric(14,2) not null check (value >= 0),
  campaign_id uuid references public.mkt_campaigns(id) on delete set null,
  source text not null default 'manual' check (source in ('manual','meta','tiktok','youtube','google_ads')),
  note text check (char_length(note) <= 300),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists mkt_metrics_company on public.mkt_metrics (company_id, metric_date);

create table if not exists public.mkt_chat (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  role text not null check (role in ('user','assistant')),
  body text not null check (char_length(body) <= 4000),
  task_id uuid references public.mkt_tasks(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists mkt_chat_company on public.mkt_chat (company_id, created_at);

create table if not exists public.mkt_activity (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  actor text not null check (actor in ('ai','user','system')),
  action text not null check (char_length(action) <= 80),
  detail text check (char_length(detail) <= 1000),
  task_id uuid references public.mkt_tasks(id) on delete set null,
  model text,
  input_tokens integer,
  output_tokens integer,
  cost_usd numeric(12,6),
  user_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists mkt_activity_company on public.mkt_activity (company_id, created_at desc);

-- ---------- RLS ----------
do $$
declare t text;
begin
  foreach t in array array['mkt_profiles','mkt_settings','mkt_tasks','mkt_strategies','mkt_content','mkt_campaigns','mkt_media','mkt_reports','mkt_approvals','mkt_integrations','mkt_metrics','mkt_chat','mkt_activity'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (private.member_role(company_id) is not null)', t || '_read', t);
  end loop;
end $$;

-- profil a nastavení zapisuje vlastník nebo správce
drop policy if exists mkt_profiles_write on public.mkt_profiles;
create policy mkt_profiles_write on public.mkt_profiles for all to authenticated
  using (private.member_role(company_id) in ('owner','admin'))
  with check (private.member_role(company_id) in ('owner','admin'));
drop policy if exists mkt_settings_write on public.mkt_settings;
create policy mkt_settings_write on public.mkt_settings for all to authenticated
  using (private.member_role(company_id) in ('owner','admin'))
  with check (private.member_role(company_id) in ('owner','admin'));
-- ruční zadání skutečných výsledků (analytika)
drop policy if exists mkt_metrics_ins on public.mkt_metrics;
create policy mkt_metrics_ins on public.mkt_metrics for insert to authenticated
  with check (private.member_role(company_id) in ('owner','admin') and source = 'manual');
drop policy if exists mkt_metrics_del on public.mkt_metrics;
create policy mkt_metrics_del on public.mkt_metrics for delete to authenticated
  using (private.member_role(company_id) in ('owner','admin') and source = 'manual');
-- úprava textu příspěvku před schválením (jen vybrané sloupce)
drop policy if exists mkt_content_edit on public.mkt_content;
create policy mkt_content_edit on public.mkt_content for update to authenticated
  using (private.member_role(company_id) in ('owner','admin') and status in ('draft','pending_approval','approved'))
  with check (private.member_role(company_id) in ('owner','admin'));
revoke update on public.mkt_content from authenticated;
grant update (title, caption, hashtags, cta, planned_at) on public.mkt_content to authenticated;
-- ostatní tabulky zapisuje jen server (service role) nebo funkce níže
revoke insert, update, delete on public.mkt_tasks, public.mkt_strategies, public.mkt_campaigns, public.mkt_media,
  public.mkt_reports, public.mkt_approvals, public.mkt_integrations, public.mkt_chat, public.mkt_activity from authenticated;

-- ---------- pomocné funkce ----------
create or replace function private.mkt_plan_ok(cid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.subscriptions s where s.company_id = private.business_root(cid) and s.plan in ('pro','business','enterprise'))
$$;

create or replace function private.mkt_require(cid uuid) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or coalesce(private.member_role(cid), '') not in ('owner','admin') then raise exception 'Forbidden'; end if;
  if not private.writable(cid) then raise exception 'Předplatné není aktivní.'; end if;
  if not private.mkt_plan_ok(cid) then raise exception 'AI Marketing je součástí tarifů PRO a BUSINESS.'; end if;
end $$;

-- zadání úlohy uživatelem
create or replace function public.mkt_request(p_company uuid, p_kind text, p_title text, p_payload jsonb default '{}'::jsonb, p_key text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  perform private.mkt_require(p_company);
  if p_kind not in ('strategy','content_plan','campaign','video','diagnose','analysis','evening') then raise exception 'Neznámý typ úlohy.'; end if;
  if char_length(coalesce(p_title,'')) not between 3 and 200 then raise exception 'Chybí název úlohy.'; end if;
  if pg_column_size(coalesce(p_payload,'{}'::jsonb)) > 4000 then raise exception 'Zadání je příliš dlouhé.'; end if;
  if (select count(*) from public.mkt_tasks where company_id = p_company and status in ('queued','running')) >= 15 then
    raise exception 'Ve frontě je příliš mnoho úloh. Počkejte na jejich dokončení.'; end if;
  insert into public.mkt_tasks(company_id, kind, title, payload, source, idem_key, created_by, priority)
  values (p_company, p_kind, p_title, coalesce(p_payload,'{}'::jsonb), 'user', p_key, auth.uid(), 7)
  on conflict (company_id, idem_key) do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.mkt_tasks where company_id = p_company and idem_key = p_key; end if;
  insert into public.mkt_activity(company_id, actor, action, detail, task_id, user_id) values (p_company, 'user', 'task_requested', p_title, v_id, auth.uid());
  return v_id;
end $$;

-- zpráva do chatu = úloha typu chat
create or replace function public.mkt_chat_send(p_company uuid, p_text text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_msg uuid; v_task uuid;
begin
  perform private.mkt_require(p_company);
  if char_length(trim(coalesce(p_text,''))) not between 2 and 1500 then raise exception 'Napište zprávu do 1 500 znaků.'; end if;
  if (select count(*) from public.mkt_chat where company_id = p_company and role = 'user' and created_at > now() - interval '1 minute') >= 5 then
    raise exception 'Zkuste to znovu za minutu.'; end if;
  insert into public.mkt_chat(company_id, role, body, created_by) values (p_company, 'user', trim(p_text), auth.uid()) returning id into v_msg;
  insert into public.mkt_tasks(company_id, kind, title, payload, source, created_by, priority)
  values (p_company, 'chat', left('Chat: ' || trim(p_text), 200), jsonb_build_object('message_id', v_msg), 'chat', auth.uid(), 9) returning id into v_task;
  update public.mkt_chat set task_id = v_task where id = v_msg;
  return v_task;
end $$;

create or replace function public.mkt_cancel(p_task uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_cid uuid;
begin
  select company_id into v_cid from public.mkt_tasks where id = p_task;
  if v_cid is null or coalesce(private.member_role(v_cid),'') not in ('owner','admin') then raise exception 'Forbidden'; end if;
  update public.mkt_tasks set status = 'canceled', finished_at = now() where id = p_task and status = 'queued';
  insert into public.mkt_activity(company_id, actor, action, task_id, user_id) values (v_cid, 'user', 'task_canceled', p_task, auth.uid());
end $$;

-- okamžité pozastavení / obnovení AI
create or replace function public.mkt_set_paused(p_company uuid, p_paused boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or coalesce(private.member_role(p_company),'') not in ('owner','admin') then raise exception 'Forbidden'; end if;
  insert into public.mkt_settings(company_id, paused, paused_at) values (p_company, p_paused, case when p_paused then now() end)
  on conflict (company_id) do update set paused = excluded.paused, paused_at = excluded.paused_at, updated_at = now();
  insert into public.mkt_activity(company_id, actor, action, user_id) values (p_company, 'user', case when p_paused then 'paused' else 'resumed' end, auth.uid());
end $$;

-- schválení / zamítnutí návrhu
create or replace function public.mkt_decide(p_approval uuid, p_decision text, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare a public.mkt_approvals; v_new text;
begin
  select * into a from public.mkt_approvals where id = p_approval for update;
  if not found or coalesce(private.member_role(a.company_id),'') not in ('owner','admin') then raise exception 'Forbidden'; end if;
  if a.status <> 'pending' then raise exception 'Návrh už byl rozhodnut.'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Neplatné rozhodnutí.'; end if;
  update public.mkt_approvals set status = p_decision, decided_by = auth.uid(), decided_at = now(), note = left(p_note, 500) where id = a.id;
  v_new := p_decision;
  if a.entity = 'content' then
    update public.mkt_content set status = v_new, decided_at = now() where id = a.entity_id and company_id = a.company_id and status = 'pending_approval';
  elsif a.entity = 'campaign' then
    update public.mkt_campaigns set status = v_new, decided_at = now() where id = a.entity_id and company_id = a.company_id and status = 'pending_approval';
  elsif a.entity = 'media' then
    update public.mkt_media set status = v_new, decided_at = now() where id = a.entity_id and company_id = a.company_id and status = 'pending_approval';
  end if;
  insert into public.mkt_activity(company_id, actor, action, detail, user_id)
  values (a.company_id, 'user', 'decision_' || p_decision, a.summary, auth.uid());
end $$;

-- ruční označení publikace (dokud není připojená integrace sociální sítě)
create or replace function public.mkt_mark_published(p_content uuid, p_url text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare v_cid uuid;
begin
  select company_id into v_cid from public.mkt_content where id = p_content and status = 'approved';
  if v_cid is null or coalesce(private.member_role(v_cid),'') not in ('owner','admin') then raise exception 'Příspěvek musí být schválený.'; end if;
  if p_url is not null and p_url !~ '^https://' then raise exception 'Odkaz musí začínat https://'; end if;
  update public.mkt_content set status = 'published', published_url = left(p_url, 500) where id = p_content;
  insert into public.mkt_activity(company_id, actor, action, detail, user_id) values (v_cid, 'user', 'marked_published', p_url, auth.uid());
end $$;

-- ---------- serverová část (jen service role) ----------
create or replace function public.mkt_worker_dispatch_ok(p_token text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_token is not null and exists(select 1 from vault.decrypted_secrets where name = 'vexaronet_mkt_dispatch' and decrypted_secret = p_token)
$$;

create or replace function public.mkt_worker_claim(p_company uuid default null) returns setof public.mkt_tasks
language plpgsql security definer set search_path = '' as $$
begin
  -- úlohy, kterým došly pokusy po pádu, ukončit
  update public.mkt_tasks set status = 'failed', finished_at = now(), error = coalesce(error, 'Úloha se nedokončila ani po opakování.')
  where status = 'running' and lease_until < now() and attempts >= max_attempts;
  return query
  with c as (
    select t.id from public.mkt_tasks t
    where ((t.status = 'queued' and t.run_after <= now()) or (t.status = 'running' and t.lease_until < now() and t.attempts < t.max_attempts))
      and (p_company is null or t.company_id = p_company)
      and not exists (select 1 from public.mkt_settings s where s.company_id = t.company_id and s.paused)
    order by t.priority desc, t.run_after
    limit 1
    for update of t skip locked)
  update public.mkt_tasks t set status = 'running', attempts = t.attempts + 1, lease_until = now() + interval '4 minutes',
    lease_token = gen_random_uuid(), started_at = now()
  from c where t.id = c.id
  returning t.*;
end $$;

create or replace function public.mkt_worker_finish(p_task uuid, p_lease uuid, p_ok boolean, p_result jsonb, p_error text, p_final boolean default false)
returns boolean language plpgsql security definer set search_path = '' as $$
declare t public.mkt_tasks;
begin
  select * into t from public.mkt_tasks where id = p_task and lease_token = p_lease and status = 'running' for update;
  if not found then return false; end if;
  if p_ok then
    update public.mkt_tasks set status = 'done', result = p_result, error = null, finished_at = now(), lease_until = null where id = p_task;
  elsif p_final or t.attempts >= t.max_attempts then
    update public.mkt_tasks set status = 'failed', error = left(p_error, 1000), finished_at = now(), lease_until = null where id = p_task;
  else
    update public.mkt_tasks set status = 'queued', error = left(p_error, 1000), lease_until = null,
      run_after = now() + make_interval(mins => (power(2, t.attempts))::int) where id = p_task;
  end if;
  return true;
end $$;

-- měsíční limit AI požadavků firmy: min(nastavení firmy, strop tarifu)
create or replace function public.mkt_worker_budget(p_company uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  with p as (select s.plan from public.subscriptions s where s.company_id = private.business_root(p_company) limit 1),
  cap as (select case (select plan from p) when 'pro' then 300 when 'business' then 1000 when 'enterprise' then 3000 else 0 end as v),
  lim as (select least(coalesce((select monthly_ai_limit from public.mkt_settings where company_id = p_company), 150), (select v from cap)) as v),
  used as (select count(*)::int as v from public.mkt_activity where company_id = p_company and actor = 'ai' and model is not null
           and created_at >= date_trunc('month', now() at time zone 'Europe/Prague') at time zone 'Europe/Prague')
  select jsonb_build_object('used', (select v from used), 'limit', (select v from lim), 'plan', (select plan from p),
    'active', exists(select 1 from public.subscriptions s where s.company_id = p_company and ((s.status = 'trial' and s.trial_end > now()) or (s.status = 'active' and (s.paid_until > now() or s.plan = 'start')))))
$$;

-- ranní a večerní rutina pro firmy se zapnutým autopilotem (idempotentně podle data)
create or replace function private.mkt_enqueue_routines() returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer := 0; v_hour int := extract(hour from now() at time zone 'Europe/Prague'); v_day text := to_char(now() at time zone 'Europe/Prague', 'YYYY-MM-DD'); r record; k int;
begin
  for r in select s.company_id, s.morning_hour, s.evening_hour from public.mkt_settings s
           where s.autopilot_on and not s.paused and private.mkt_plan_ok(s.company_id) loop
    if v_hour = r.morning_hour then
      insert into public.mkt_tasks(company_id, kind, title, source, idem_key, priority)
      values (r.company_id, 'morning', 'Ranní kontrola marketingu', 'schedule', 'morning:' || v_day, 4)
      on conflict (company_id, idem_key) do nothing;
      get diagnostics k = row_count; n := n + k;
    end if;
    if v_hour = r.evening_hour then
      insert into public.mkt_tasks(company_id, kind, title, source, idem_key, priority)
      values (r.company_id, 'evening', 'Večerní report', 'schedule', 'evening:' || v_day, 4)
      on conflict (company_id, idem_key) do nothing;
      get diagnostics k = row_count; n := n + k;
    end if;
  end loop;
  return n;
end $$;

-- práva: uživatelské funkce pro přihlášené, serverové jen pro service role
revoke all on function public.mkt_request(uuid,text,text,jsonb,text), public.mkt_chat_send(uuid,text), public.mkt_cancel(uuid),
  public.mkt_set_paused(uuid,boolean), public.mkt_decide(uuid,text,text), public.mkt_mark_published(uuid,text) from public, anon;
grant execute on function public.mkt_request(uuid,text,text,jsonb,text), public.mkt_chat_send(uuid,text), public.mkt_cancel(uuid),
  public.mkt_set_paused(uuid,boolean), public.mkt_decide(uuid,text,text), public.mkt_mark_published(uuid,text) to authenticated;
revoke all on function public.mkt_worker_dispatch_ok(text), public.mkt_worker_claim(uuid), public.mkt_worker_finish(uuid,uuid,boolean,jsonb,text,boolean),
  public.mkt_worker_budget(uuid) from public, anon, authenticated;
grant execute on function public.mkt_worker_dispatch_ok(text), public.mkt_worker_claim(uuid), public.mkt_worker_finish(uuid,uuid,boolean,jsonb,text,boolean),
  public.mkt_worker_budget(uuid) to service_role;
revoke all on function private.mkt_enqueue_routines(), private.mkt_plan_ok(uuid), private.mkt_require(uuid) from public, anon, authenticated;
