-- AI tým (AI Marketing, Obchodník, CEO, Účetnictví, Weby a e-shopy, Automatizace): společná vrstva. NEAPLIKOVÁNO NA PRODUKCI.
-- Viz docs/AI_TYM.md. Závisí na: profil firmy (20261107120000), limity Autopilota (20261108110000), pilot (20261113100000), AI marketing (20261112100000).
-- Zásady:
--  * Úlohu (ai_jobs) zadává člověk (vlastník/správce) nebo plán, který člověk schválil. Výsledek ukládá jen server (service_role).
--  * AI nic neprovádí sama: změny dat navrhuje jako akce (ai_actions). Provede je až člověk funkcí ai_action_decide,
--    která schvaluje KONKRÉTNÍ obsah (otisk). service_role tuto funkci spustit nesmí.
--  * Fronta: zámek s časovým omezením, omezený počet pokusů, idempotenční klíč. Úlohy z plánů běží i bez prohlížeče.
--  * Peníze: limit firmy (stávající), nově limit na uživatele, limit na jednu operaci a strop podle tarifu.

-- ---------- limity: uživatel, operace, tarif ----------
alter table private.autopilot_budgets add column if not exists per_user_monthly_nusd bigint check (per_user_monthly_nusd is null or per_user_monthly_nusd between 0 and 50000000000);
alter table private.autopilot_budgets add column if not exists per_run_max_nusd bigint check (per_run_max_nusd is null or per_run_max_nusd between 0 and 50000000000);
create table if not exists private.autopilot_plan_caps (
  plan text primary key, max_monthly_nusd bigint not null check (max_monthly_nusd >= 0), default_per_run_nusd bigint not null check (default_per_run_nusd >= 0));
alter table private.autopilot_plan_caps enable row level security;
revoke all on private.autopilot_plan_caps from public, anon, authenticated;
insert into private.autopilot_plan_caps (plan, max_monthly_nusd, default_per_run_nusd) values
  ('pro', 2000000000, 10000000), ('business', 10000000000, 10000000), ('enterprise', 50000000000, 10000000) on conflict (plan) do nothing;

create or replace function private.ap_plan(root uuid) returns text language sql stable security definer set search_path = '' as $$
  select lower(s.plan) from public.subscriptions s where s.company_id = root limit 1 $$;

create or replace function private.autopilot_budget_cap_check() returns trigger language plpgsql security definer set search_path = '' as $$
declare cap bigint;
begin
  select max_monthly_nusd into cap from private.autopilot_plan_caps where plan = private.ap_plan(new.root_company_id);
  if cap is not null and new.monthly_limit_nusd > cap then
    perform private.ap_raise('PT422', 'budget_over_plan_cap', jsonb_build_object('cap_nusd', cap));
  end if;
  return new;
end $$;
drop trigger if exists autopilot_budget_cap_check on private.autopilot_budgets;
create trigger autopilot_budget_cap_check before insert or update on private.autopilot_budgets for each row execute function private.autopilot_budget_cap_check();

create or replace function private.autopilot_limits_check() returns trigger language plpgsql security definer set search_path = '' as $$
declare b private.autopilot_budgets; per_run bigint; used bigint;
begin
  select * into b from private.autopilot_budgets where root_company_id = new.root_company_id;
  per_run := coalesce(b.per_run_max_nusd, (select default_per_run_nusd from private.autopilot_plan_caps where plan = private.ap_plan(new.root_company_id)));
  if per_run is not null and new.reserved_nusd > per_run then
    perform private.ap_raise('PT402', 'run_limit_exceeded', jsonb_build_object('per_run_nusd', per_run, 'requested_nusd', new.reserved_nusd));
  end if;
  if b.per_user_monthly_nusd is not null and new.created_by is not null then
    select coalesce(sum(case when status in ('reserved', 'expired') then reserved_nusd else coalesce(actual_nusd, 0) end), 0) into used
      from private.autopilot_runs where root_company_id = new.root_company_id and created_by = new.created_by and created_at >= private.ap_month_start();
    if used + new.reserved_nusd > b.per_user_monthly_nusd then
      perform private.ap_raise('PT402', 'user_limit_exceeded', jsonb_build_object('per_user_nusd', b.per_user_monthly_nusd, 'used_nusd', used));
    end if;
  end if;
  return new;
end $$;
drop trigger if exists autopilot_limits_check on private.autopilot_runs;
create trigger autopilot_limits_check before insert on private.autopilot_runs for each row execute function private.autopilot_limits_check();

create or replace function public.autopilot_set_limits(cid uuid, p_per_user_nusd bigint, p_per_run_nusd bigint) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); root uuid := private.business_root(cid);
begin
  if root <> cid then perform private.ap_raise('PT403', 'only_root', '{}'::jsonb); end if;
  if (p_per_user_nusd is not null and p_per_user_nusd not between 0 and 50000000000) or (p_per_run_nusd is not null and p_per_run_nusd not between 0 and 50000000000) then
    perform private.ap_raise('PT422', 'validation_failed', '[]'::jsonb); end if;
  update private.autopilot_budgets set per_user_monthly_nusd = p_per_user_nusd, per_run_max_nusd = p_per_run_nusd, updated_by = uid, updated_at = now() where root_company_id = root;
  if not found then perform private.ap_raise('PT402', 'budget_not_set', '{}'::jsonb); end if;
  insert into private.autopilot_events (root_company_id, actor, operation, details) values (root, uid, 'set_budget', jsonb_build_object('per_user_nusd', p_per_user_nusd, 'per_run_nusd', p_per_run_nusd));
  return jsonb_build_object('per_user_monthly_nusd', p_per_user_nusd, 'per_run_max_nusd', p_per_run_nusd);
end $$;

-- ---------- rezervace: společné jádro pro člověka i schválený plán ----------
-- Tělo je shodné s původní autopilot_reserve_core (20261108110000); liší se jen tím, že uživatele dostane parametrem.
create or replace function private.autopilot_reserve_impl(uid uuid, cid uuid, p_mode text, p_model text, p_max_in integer, p_max_out integer, p_key text) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare root uuid; plat boolean; lim bigint; pr record; spent bigint; need bigint; open_n integer; r record; nid uuid;
begin
  root := private.business_root(cid);
  if p_mode is null or p_mode not in ('marketing', 'obchodnik', 'ceo', 'ucetnictvi', 'weby_eshopy', 'automatizace')
     or p_key is null or length(p_key) not between 8 and 120 or p_max_in is null or p_max_in not between 1 and 8000
     or p_max_out is null or p_max_out not between 1 and 4000 or p_model is null then
    perform private.ap_raise('PT422', 'validation_failed', '["$:invalid_arguments"]'::jsonb);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(root::text, 7312));
  select * into r from private.autopilot_runs where root_company_id = root and idempotency_key = p_key;
  if found then
    if r.company_id <> cid or r.mode <> p_mode or r.model <> p_model then perform private.ap_raise('PT409', 'idempotency_conflict', '{}'::jsonb); end if;
    return jsonb_build_object('run_id', r.id, 'reserved_nusd', r.reserved_nusd, 'status', r.status, 'reused', true,
                              'max_out_tokens', r.max_out_tokens, 'max_in_tokens', r.max_in_tokens, 'model', r.model);
  end if;
  if not private.booking_plan_allowed(root) then
    perform private.ap_raise('PT403', 'plan_not_allowed', '{"reason":"AI Autopilot je součástí tarifů PRO a vyšších"}'::jsonb);
  end if;
  select paid_runs_enabled into plat from private.autopilot_platform where id;
  if not coalesce(plat, false) then perform private.ap_raise('PT403', 'paid_runs_disabled', '{"reason":"platform"}'::jsonb); end if;
  select monthly_limit_nusd into lim from private.autopilot_budgets where root_company_id = root;
  if lim is null or lim <= 0 then perform private.ap_raise('PT402', 'budget_not_set', '{}'::jsonb); end if;
  select * into pr from private.ai_model_prices where model = p_model and active;
  if not found then perform private.ap_raise('PT422', 'unknown_model', jsonb_build_object('model', p_model)); end if;
  perform private.ap_expire_stale(root);
  select count(*) into open_n from private.autopilot_runs where root_company_id = root and status = 'reserved';
  if open_n >= 3 then perform private.ap_raise('PT429', 'too_many_open_runs', jsonb_build_object('open', open_n)); end if;
  need := p_max_in::bigint * pr.input_nusd_per_token + p_max_out::bigint * pr.output_nusd_per_token;
  spent := private.ap_spent(root);
  if spent + need > lim then
    perform private.ap_raise('PT402', 'budget_exceeded', jsonb_build_object('limit_nusd', lim, 'spent_nusd', spent, 'requested_nusd', need));
  end if;
  insert into private.autopilot_runs (root_company_id, company_id, mode, model, in_price, out_price, max_in_tokens, max_out_tokens, reserved_nusd, idempotency_key, created_by)
    values (root, cid, p_mode, p_model, pr.input_nusd_per_token, pr.output_nusd_per_token, p_max_in, p_max_out, need, p_key, uid) returning id into nid;
  insert into private.autopilot_events (root_company_id, actor, operation, details)
    values (root, uid, 'reserve', jsonb_build_object('run_id', nid, 'mode', p_mode, 'model', p_model, 'reserved_nusd', need));
  return jsonb_build_object('run_id', nid, 'reserved_nusd', need, 'status', 'reserved', 'reused', false,
                            'spent_after_nusd', spent + need, 'remaining_after_nusd', lim - spent - need,
                            'max_in_tokens', p_max_in, 'max_out_tokens', p_max_out, 'model', p_model);
end $$;
create or replace function private.autopilot_reserve_core(cid uuid, p_mode text, p_model text, p_max_in integer, p_max_out integer, p_key text) returns jsonb
  language plpgsql security definer set search_path = '' as $$
begin
  return private.autopilot_reserve_impl(private.profile_actor(cid, true), cid, p_mode, p_model, p_max_in, p_max_out, p_key);
end $$;
revoke all on function private.autopilot_reserve_impl(uuid, uuid, text, text, integer, integer, text) from public, anon, authenticated, service_role;

-- ---------- katalog úloh, úlohy, akce, chat, plány, cíle ----------
create table if not exists private.ai_kinds (
  module text not null check (module in ('marketing', 'obchodnik', 'ceo', 'ucetnictvi', 'weby_eshopy', 'automatizace')),
  kind text not null check (kind ~ '^[a-z][a-z0-9_]{2,40}$'),
  title text not null, schedulable boolean not null default false,
  primary key (module, kind));
create table if not exists private.ai_schedules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  module text not null, kind text not null,
  cadence text not null check (cadence in ('daily', 'weekly', 'monthly')),
  brief text not null default '' check (char_length(brief) <= 1000),
  enabled boolean not null default true,
  approved_by uuid not null, approved_at timestamptz not null default now(),
  next_run_at timestamptz not null, last_run_at timestamptz, last_status text,
  created_at timestamptz not null default now(),
  foreign key (module, kind) references private.ai_kinds(module, kind),
  unique (company_id, module, kind, cadence));
create table if not exists private.ai_jobs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  module text not null, kind text not null,
  brief text not null default '' check (char_length(brief) <= 2000),
  input jsonb not null default '{}'::jsonb check (pg_column_size(input) <= 8000),
  status text not null default 'queued' check (status in ('queued', 'running', 'awaiting_approval', 'done', 'failed', 'cancelled')),
  source text not null default 'user' check (source in ('user', 'ceo', 'schedule')),
  parent_id uuid references private.ai_jobs(id) on delete cascade,
  schedule_id uuid references private.ai_schedules(id) on delete set null,
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  output jsonb, error text,
  run_id uuid references private.autopilot_runs(id),
  attempts integer not null default 0, max_attempts integer not null default 3,
  lock_token uuid, lock_until timestamptz, next_attempt_at timestamptz not null default now(),
  created_by uuid not null, created_at timestamptz not null default now(), finished_at timestamptz,
  foreign key (module, kind) references private.ai_kinds(module, kind),
  unique (company_id, idempotency_key));
create index if not exists ai_jobs_company_idx on private.ai_jobs (company_id, created_at desc);
create index if not exists ai_jobs_queue_idx on private.ai_jobs (next_attempt_at) where status in ('queued', 'running');
create table if not exists private.ai_actions (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references private.ai_jobs(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  type text not null check (type in ('task', 'marketing_post', 'customer_note', 'finance_entry', 'quote_draft', 'site_text', 'product_description', 'goal', 'schedule')),
  payload jsonb not null, payload_hash text not null,
  status text not null default 'proposed' check (status in ('proposed', 'applied', 'rejected')),
  decided_by uuid, decided_at timestamptz, result jsonb,
  created_at timestamptz not null default now());
create index if not exists ai_actions_company_idx on private.ai_actions (company_id, status);
create table if not exists private.ai_chat (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  module text not null check (module in ('marketing', 'obchodnik', 'ceo', 'ucetnictvi', 'weby_eshopy', 'automatizace')),
  user_id uuid not null, role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(content) between 1 and 6000),
  run_id uuid references private.autopilot_runs(id), created_at timestamptz not null default now());
create index if not exists ai_chat_idx on private.ai_chat (company_id, module, id desc);
create table if not exists private.ai_goals (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 200),
  metric text not null check (metric in ('poptavky', 'zakaznici', 'rezervace', 'objednavky', 'trzby')),
  target numeric not null check (target > 0 and target <= 1e10),
  starts_on date not null default current_date, due_on date not null,
  status text not null default 'active' check (status in ('active', 'closed')),
  created_by uuid not null, action_id uuid references private.ai_actions(id), created_at timestamptz not null default now(),
  check (due_on >= starts_on));
do $$ declare t text; begin
  foreach t in array array['ai_kinds', 'ai_schedules', 'ai_jobs', 'ai_actions', 'ai_chat', 'ai_goals'] loop
    execute format('alter table private.%I enable row level security', t);
    execute format('revoke all on private.%I from public, anon, authenticated', t);
  end loop; end $$;
alter table private.autopilot_events drop constraint if exists autopilot_events_operation_check;
alter table private.autopilot_events add constraint autopilot_events_operation_check
  check (operation in ('set_budget', 'reserve', 'settle', 'expire', 'job', 'action', 'schedule'));

insert into private.ai_kinds (module, kind, title, schedulable) values
  ('marketing', 'audience_analysis', 'Analýza firmy a cílových zákazníků', false),
  ('marketing', 'plan_7', 'Plán obsahu na 7 dní', true),
  ('marketing', 'plan_30', 'Plán obsahu na 30 dní', true),
  ('marketing', 'video_scripts', 'Scénáře pro Reels, Shorts a TikTok', false),
  ('marketing', 'ad_copy', 'Reklamní texty', false),
  ('marketing', 'campaign', 'Příprava kampaně', false),
  ('marketing', 'results_review', 'Vyhodnocení výsledků a doporučení ke konverzím', true),
  ('obchodnik', 'opportunities', 'Analýza obchodních příležitostí', true),
  ('obchodnik', 'customer_scoring', 'Hodnocení zákazníků z CRM', false),
  ('obchodnik', 'quote_draft', 'Návrh obchodní nabídky', false),
  ('obchodnik', 'followup', 'Příprava následné komunikace', false),
  ('obchodnik', 'next_steps', 'Další obchodní kroky a úkoly', true),
  ('obchodnik', 'quote_success', 'Vyhodnocení úspěšnosti nabídek', false),
  ('ceo', 'finance_analysis', 'Analýza hospodaření', false),
  ('ceo', 'cost_cuts', 'Návrhy na snížení nákladů', false),
  ('ceo', 'risks', 'Podnikatelská rizika', false),
  ('ceo', 'growth_plan', 'Plán růstu a měřitelné cíle', false),
  ('ceo', 'weekly_report', 'Týdenní report', true),
  ('ceo', 'monthly_report', 'Měsíční report', true),
  ('ceo', 'orchestrate', 'Komplexní zadání rozdělené mezi AI pracovníky', false),
  ('ucetnictvi', 'records_review', 'Kontrola evidence příjmů a výdajů', true),
  ('ucetnictvi', 'unpaid_followup', 'Neuhrazené faktury a další kroky', true),
  ('ucetnictvi', 'vat_commentary', 'Komentář k přehledu DPH', false),
  ('ucetnictvi', 'posting_suggestions', 'Návrhy účetních zápisů ke kontrole', false),
  ('ucetnictvi', 'cashflow', 'Orientační výhled peněz', false),
  ('weby_eshopy', 'site_draft', 'Návrh textů a struktury webu', false),
  ('weby_eshopy', 'text_improve', 'Úpravy textů webu', false),
  ('weby_eshopy', 'product_descriptions', 'Popisy produktů', false),
  ('weby_eshopy', 'seo_tips', 'SEO doporučení', false),
  ('weby_eshopy', 'conversion_review', 'Analýza konverzí a optimalizace', true),
  ('automatizace', 'automation_ideas', 'Návrh automatizací a plánů', false),
  ('automatizace', 'ops_digest', 'Provozní přehled a úkoly', true)
on conflict (module, kind) do update set title = excluded.title, schedulable = excluded.schedulable;

-- ---------- pomocné ----------
create or replace function private.ai_fail(code text, msg text) returns void language plpgsql set search_path = '' as $$
begin raise exception '%', msg using errcode = code; end $$;
create or replace function private.ai_hash(d jsonb) returns text language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to(d::text, 'UTF8')), 'hex') $$;
create or replace function private.ai_member_role_of(uid uuid, cid uuid) returns text language sql stable security definer set search_path = '' as $$
  select m.role from public.company_members m where m.company_id = cid and m.user_id = uid $$;
create or replace function private.ai_writable_company(cid uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.subscriptions s where s.company_id = cid
    and ((s.status = 'trial' and s.trial_end > now()) or (s.status = 'active' and (s.paid_until > now() or s.plan = 'start')))) $$;
create or replace function private.ai_next_run(cadence text, base timestamptz) returns timestamptz language sql immutable set search_path = '' as $$
  select base + case cadence when 'daily' then interval '1 day' when 'weekly' then interval '7 days' else interval '1 month' end $$;

-- Kontrola a normalizace návrhu akce. Vrací očištěný payload, nebo NULL, když návrh nevyhovuje (takový se neuloží).
create or replace function private.ai_action_clean(cid uuid, p_type text, p jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare t text; n numeric; d integer; x jsonb; items jsonb := '[]'::jsonb; tot numeric := 0;
begin
  if jsonb_typeof(p) <> 'object' then return null; end if;
  if p_type = 'task' then
    t := btrim(p->>'title'); d := case when (p->>'due_in_days') ~ '^\d{1,3}$' then (p->>'due_in_days')::int end;
    if char_length(coalesce(t, '')) not between 3 and 200 or coalesce(char_length(p->>'description'), 0) > 2000 or coalesce(d, 0) > 365 then return null; end if;
    return jsonb_strip_nulls(jsonb_build_object('title', t, 'description', nullif(btrim(p->>'description'), ''), 'due_in_days', d));
  elsif p_type = 'marketing_post' then
    d := case when (p->>'planned_in_days') ~ '^\d{1,3}$' then (p->>'planned_in_days')::int else 0 end;
    if char_length(coalesce(btrim(p->>'title'), '')) not between 3 and 100 or char_length(coalesce(p->>'body', '')) not between 20 and 4000
       or not private.mkt_channel_ok(p->>'channel') or d > 120 then return null; end if;
    return jsonb_build_object('title', btrim(p->>'title'), 'body', p->>'body', 'channel', p->>'channel', 'planned_in_days', d);
  elsif p_type = 'customer_note' then
    if (p->>'customer_id') !~ '^[0-9a-f-]{36}$' or char_length(coalesce(btrim(p->>'body'), '')) not between 3 and 2000
       or not exists (select 1 from public.customers c where c.id = (p->>'customer_id')::uuid and c.company_id = cid) then return null; end if;
    return jsonb_build_object('customer_id', p->>'customer_id', 'body', btrim(p->>'body'));
  elsif p_type = 'finance_entry' then
    n := case when jsonb_typeof(p->'amount') = 'number' then (p->>'amount')::numeric end;
    if char_length(coalesce(btrim(p->>'title'), '')) not between 1 and 200 or n is null or n <= 0 or n > 1e9 or (p->>'kind') not in ('income', 'expense')
       or (p->>'entry_date') !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
    return jsonb_build_object('title', btrim(p->>'title'), 'amount', round(n, 2), 'kind', p->>'kind', 'entry_date', p->>'entry_date');
  elsif p_type = 'quote_draft' then
    if (p->>'customer_id') !~ '^[0-9a-f-]{36}$' or not exists (select 1 from public.customers c where c.id = (p->>'customer_id')::uuid and c.company_id = cid)
       or char_length(coalesce(btrim(p->>'title'), '')) not between 3 and 200 or jsonb_typeof(p->'items') <> 'array' or jsonb_array_length(p->'items') not between 1 and 20
       or coalesce(char_length(p->>'note'), 0) > 2000 then return null; end if;
    if (p->>'deal_id') is not null and ((p->>'deal_id') !~ '^[0-9a-f-]{36}$' or not exists (select 1 from public.deals dl where dl.id = (p->>'deal_id')::uuid and dl.company_id = cid)) then return null; end if;
    for x in select value from jsonb_array_elements(p->'items') loop
      if char_length(coalesce(btrim(x->>'name'), '')) not between 1 and 200 or jsonb_typeof(x->'qty') <> 'number' or jsonb_typeof(x->'price') <> 'number'
         or (x->>'qty')::numeric <= 0 or (x->>'qty')::numeric > 100000 or (x->>'price')::numeric < 0 or (x->>'price')::numeric > 1e8 then return null; end if;
      items := items || jsonb_build_object('name', btrim(x->>'name'), 'qty', (x->>'qty')::numeric, 'price', round((x->>'price')::numeric, 2));
      tot := tot + (x->>'qty')::numeric * round((x->>'price')::numeric, 2);
    end loop;
    return jsonb_strip_nulls(jsonb_build_object('customer_id', p->>'customer_id', 'deal_id', p->>'deal_id', 'title', btrim(p->>'title'), 'items', items, 'total', round(tot, 2), 'note', nullif(btrim(p->>'note'), '')));
  elsif p_type = 'site_text' then
    if (p->>'field') not in ('hero.title', 'hero.subtitle', 'about.title', 'about.text') or char_length(coalesce(btrim(p->>'value'), '')) not between 3 and 2000
       or not exists (select 1 from public.sites s where s.company_id = cid) then return null; end if;
    return jsonb_build_object('field', p->>'field', 'value', btrim(p->>'value'));
  elsif p_type = 'product_description' then
    if (p->>'product_id') !~ '^[0-9a-f-]{36}$' or char_length(coalesce(btrim(p->>'description'), '')) not between 10 and 2000
       or not exists (select 1 from public.products pr where pr.id = (p->>'product_id')::uuid and pr.company_id = cid) then return null; end if;
    return jsonb_build_object('product_id', p->>'product_id', 'description', btrim(p->>'description'));
  elsif p_type = 'goal' then
    n := case when jsonb_typeof(p->'target') = 'number' then (p->>'target')::numeric end;
    d := case when (p->>'days') ~ '^\d{1,3}$' then (p->>'days')::int end;
    if char_length(coalesce(btrim(p->>'title'), '')) not between 3 and 200 or (p->>'metric') not in ('poptavky', 'zakaznici', 'rezervace', 'objednavky', 'trzby')
       or n is null or n <= 0 or n > 1e10 or d is null or d not between 7 and 365 then return null; end if;
    return jsonb_build_object('title', btrim(p->>'title'), 'metric', p->>'metric', 'target', n, 'days', d);
  elsif p_type = 'schedule' then
    if (p->>'cadence') not in ('daily', 'weekly', 'monthly') or coalesce(char_length(p->>'brief'), 0) > 1000
       or not exists (select 1 from private.ai_kinds k where k.module = p->>'module' and k.kind = p->>'kind' and k.schedulable) then return null; end if;
    return jsonb_build_object('module', p->>'module', 'kind', p->>'kind', 'cadence', p->>'cadence', 'brief', coalesce(btrim(p->>'brief'), ''));
  end if;
  return null;
end $$;

-- ---------- kontext pro AI (počítá server z databáze, ne prohlížeč) ----------
create or replace function private.ai_context_impl(cid uuid, p_module text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare root uuid := private.business_root(cid); out jsonb; m0 date := date_trunc('month', current_date)::date;
  want_fin boolean := p_module in ('ceo', 'ucetnictvi'); want_crm boolean := p_module in ('ceo', 'obchodnik', 'marketing');
  want_mkt boolean := p_module in ('ceo', 'marketing'); want_web boolean := p_module in ('ceo', 'weby_eshopy', 'marketing'); want_ops boolean := p_module in ('ceo', 'automatizace');
begin
  out := jsonb_build_object('dnes', current_date, 'firma', (select jsonb_build_object('nazev', c.name, 'obor', c.industry) from public.companies c where c.id = cid),
    'profil', (select v.data->'shared' from private.company_active_profile a join private.company_profile_versions v on v.id = a.version_id where a.company_id in (cid, root) order by (a.company_id = cid) desc limit 1));
  if want_fin then
    out := out || jsonb_build_object('finance', jsonb_build_object(
      'mesice', (select coalesce(jsonb_agg(jsonb_build_object('mesic', to_char(m, 'YYYY-MM'), 'prijmy', i, 'vydaje', e) order by m), '[]'::jsonb) from (
          select g.m, coalesce(sum(f.amount) filter (where f.kind = 'income'), 0) i, coalesce(sum(f.amount) filter (where f.kind = 'expense'), 0) e
          from generate_series(m0 - interval '5 months', m0, interval '1 month') g(m)
          left join public.financial_entries f on f.company_id = cid and date_trunc('month', f.entry_date) = g.m group by g.m) q),
      'nejvetsi_vydaje_90_dni', (select coalesce(jsonb_agg(jsonb_build_object('nazev', left(title, 80), 'castka', amount, 'datum', entry_date)), '[]'::jsonb) from (
          select title, amount, entry_date from public.financial_entries where company_id = cid and kind = 'expense' and entry_date >= current_date - 90 order by amount desc limit 12) q),
      'faktury', (select jsonb_build_object('vystavene', count(*) filter (where lifecycle = 'issued'),
          'neuhrazene', count(*) filter (where lifecycle = 'issued' and paid_at is null), 'neuhrazene_castka', coalesce(sum(total) filter (where lifecycle = 'issued' and paid_at is null), 0),
          'po_splatnosti', count(*) filter (where lifecycle = 'issued' and paid_at is null and due_on < current_date),
          'po_splatnosti_castka', coalesce(sum(total) filter (where lifecycle = 'issued' and paid_at is null and due_on < current_date), 0)) from public.invoices where company_id = cid),
      'po_splatnosti_seznam', (select coalesce(jsonb_agg(jsonb_build_object('cislo', number, 'odberatel', left(customer_snapshot->>'name', 60), 'castka', total, 'splatnost', due_on)), '[]'::jsonb) from (
          select number, customer_snapshot, total, due_on from public.invoices where company_id = cid and lifecycle = 'issued' and paid_at is null and due_on < current_date order by due_on limit 10) q)));
  end if;
  if p_module = 'ucetnictvi' then
    out := out || jsonb_build_object('ucetnictvi', jsonb_build_object(
      'rezim', coalesce((select jsonb_build_object('rezim', regime, 'platce_dph', vat_payer) from private.acc_settings where company_id = cid), '{"rezim":"neurceno"}'::jsonb),
      'doklady', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from private.acc_documents where company_id = cid group by status) q),
      'doklady_ke_kontrole', (select coalesce(jsonb_agg(jsonb_build_object('dodavatel', left(doc->>'supplier_name', 60), 'cislo', doc->>'document_number', 'castka', doc->'total_amount', 'dph', doc->'vat_amount',
          'sazba', doc->'vat_rate', 'kategorie', doc->>'category', 'popis', left(doc->>'description', 80))), '[]'::jsonb) from (select doc from private.acc_documents where company_id = cid and status = 'extracted' order by created_at desc limit 10) q),
      'banka_nesparovano', (select count(*) from private.bank_transactions where company_id = cid and status = 'unmatched')));
  end if;
  if want_crm then
    out := out || jsonb_build_object('obchod', jsonb_build_object(
      'pripady_podle_faze', (select coalesce(jsonb_object_agg(stage, jsonb_build_object('pocet', n, 'hodnota', v)), '{}'::jsonb) from (select stage, count(*) n, coalesce(sum(value), 0) v from public.deals where company_id = cid group by stage) q),
      'otevrene_pripady', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'nazev', left(d.title, 80), 'hodnota', d.value, 'faze', d.stage, 'pravdepodobnost', d.probability, 'ocekavane_uzavreni', d.expected_close,
          'zakaznik_id', d.customer_id, 'zakaznik', left(c.name, 60), 'dni_bez_zmeny', (current_date - d.updated_at::date))), '[]'::jsonb)
          from (select * from public.deals where company_id = cid and stage not in ('won', 'lost') order by value desc limit 15) d left join public.customers c on c.id = d.customer_id),
      'nabidky', (select coalesce(jsonb_object_agg(status, jsonb_build_object('pocet', n, 'hodnota', v)), '{}'::jsonb) from (select status, count(*) n, coalesce(sum(total), 0) v from public.quotes where company_id = cid group by status) q),
      'zakaznici', (select jsonb_build_object('celkem', count(*), 'novi_30_dni', count(*) filter (where created_at >= now() - interval '30 days')) from public.customers where company_id = cid and not archived),
      'nejlepsi_zakaznici', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nazev', left(name, 60), 'fakturovano', inv, 'pripady', dn)), '[]'::jsonb) from (
          select c.id, c.name, (select coalesce(sum(i.total), 0) from public.invoices i where i.company_id = cid and i.lifecycle = 'issued' and i.customer_snapshot->>'name' = c.name) inv,
                 (select count(*) from public.deals d where d.customer_id = c.id) dn
          from public.customers c where c.company_id = cid and not c.archived order by 3 desc, 4 desc limit 12) q)));
  end if;
  if want_mkt then
    out := out || jsonb_build_object('marketing', jsonb_build_object(
      'strategie', (select doc from private.mkt_strategies where company_id = cid and status = 'approved' order by version desc limit 1),
      'prispevky_podle_stavu', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.marketing_posts where company_id = cid group by status) q),
      'posledni_prispevky', (select coalesce(jsonb_agg(jsonb_build_object('nazev', left(title, 80), 'kanal', channel, 'stav', status, 'datum', planned_on)), '[]'::jsonb) from (
          select title, channel, status, planned_on from public.marketing_posts where company_id = cid order by created_at desc limit 10) q),
      'za_30_dni', jsonb_build_object('poptavky', private.mkt_goal_value(cid, 'poptavky', now() - interval '30 days'), 'zakaznici', private.mkt_goal_value(cid, 'zakaznici', now() - interval '30 days'),
          'rezervace', private.mkt_goal_value(cid, 'rezervace', now() - interval '30 days'), 'objednavky', private.mkt_goal_value(cid, 'objednavky', now() - interval '30 days')),
      'predchozich_30_dni', jsonb_build_object('poptavky', private.mkt_count(cid, 'poptavky', now() - interval '60 days', now() - interval '30 days'),
          'zakaznici', private.mkt_count(cid, 'zakaznici', now() - interval '60 days', now() - interval '30 days'))));
  end if;
  if want_web then
    out := out || jsonb_build_object('web', jsonb_build_object(
      'stranka', (select jsonb_build_object('zapnuta', s.enabled, 'titulek', left(s.data#>>'{hero,title}', 200), 'podtitulek', left(s.data#>>'{hero,subtitle}', 300),
          'o_nas_nadpis', left(s.data#>>'{about,title}', 200), 'o_nas', left(s.data#>>'{about,text}', 1200), 'sluzby', coalesce(jsonb_array_length(case when jsonb_typeof(s.data->'services') = 'array' then s.data->'services' end), 0))
          from public.sites s where s.company_id = cid),
      'produkty', (select jsonb_build_object('celkem', count(*), 'v_eshopu', count(*) filter (where shop_visible), 'bez_popisu', count(*) filter (where coalesce(description, '') = '')) from public.products where company_id = cid and active),
      'produkty_seznam', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nazev', left(name, 80), 'cena', price, 'popis', left(coalesce(description, ''), 160))), '[]'::jsonb) from (
          select id, name, price, description from public.products where company_id = cid and active order by (coalesce(description, '') = '') desc, created_at desc limit 12) q),
      'objednavky_30_dni', (select jsonb_build_object('pocet', count(*), 'castka', coalesce(sum(total), 0)) from public.shop_orders where company_id = cid and created_at >= now() - interval '30 days')));
  end if;
  if want_ops then
    out := out || jsonb_build_object('provoz', jsonb_build_object(
      'ukoly', (select jsonb_build_object('otevrene', count(*) filter (where not completed), 'po_terminu', count(*) filter (where not completed and due_at < now())) from public.tasks where company_id = cid),
      'zakazky_podle_stavu', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.jobs where company_id = cid group by status) q),
      'rezervace_7_dni', (select count(*) from public.reservations where company_id = cid and not canceled and starts_at between now() and now() + interval '7 days'),
      'plany_ai', (select coalesce(jsonb_agg(jsonb_build_object('modul', module, 'uloha', kind, 'opakovani', cadence, 'zapnuto', enabled)), '[]'::jsonb) from private.ai_schedules where company_id = cid),
      'cile', (select coalesce(jsonb_agg(jsonb_build_object('nazev', title, 'metrika', metric, 'cil', target, 'do', due_on)), '[]'::jsonb) from private.ai_goals where company_id = cid and status = 'active')));
  end if;
  return out;
end $$;

-- ---------- úlohy ----------
create or replace function public.ai_job_create(cid uuid, p_module text, p_kind text, p_brief text, p_input jsonb, p_key text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); j private.ai_jobs;
begin
  if p_key is null or length(p_key) not between 8 and 120 or coalesce(char_length(p_brief), 0) > 2000 then perform private.ai_fail('PT422', 'validation_failed'); end if;
  if not exists (select 1 from private.ai_kinds where module = p_module and kind = p_kind) then perform private.ai_fail('PT422', 'unknown_kind'); end if;
  select * into j from private.ai_jobs where company_id = cid and idempotency_key = p_key;
  if j.id is not null then
    if j.module <> p_module or j.kind <> p_kind then perform private.ai_fail('PT409', 'idempotency_conflict'); end if;
    return jsonb_build_object('id', j.id, 'status', j.status, 'reused', true);
  end if;
  if (select count(*) from private.ai_jobs where company_id = cid and created_at > now() - interval '1 day') >= 200 then perform private.ai_fail('PT429', 'too_many_jobs'); end if;
  insert into private.ai_jobs (company_id, module, kind, brief, input, idempotency_key, created_by)
    values (cid, p_module, p_kind, coalesce(btrim(p_brief), ''), coalesce(p_input, '{}'::jsonb), p_key, uid) returning * into j;
  insert into private.autopilot_events (root_company_id, actor, operation, details) values (private.business_root(cid), uid, 'job', jsonb_build_object('job_id', j.id, 'module', p_module, 'kind', p_kind, 'event', 'created'));
  return jsonb_build_object('id', j.id, 'status', j.status, 'reused', false);
end $$;

create or replace function public.ai_job_cancel(cid uuid, p_job uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true);
begin
  update private.ai_jobs set status = 'cancelled', finished_at = now() where id = p_job and company_id = cid and status in ('queued', 'running');
  if not found then perform private.ai_fail('PT409', 'not_cancellable'); end if;
  return jsonb_build_object('id', p_job, 'status', 'cancelled');
end $$;

-- Ověření před spuštěním čekající úlohy z prohlížeče (např. dílčí úlohy AI CEO): jen člověk s právem zápisu ve firmě úlohy.
create or replace function public.ai_job_status(cid uuid, p_job uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); j private.ai_jobs;
begin
  select * into j from private.ai_jobs where id = p_job and company_id = cid;
  if j.id is null then perform private.ai_fail('PT404', 'not_found'); end if;
  return jsonb_build_object('id', j.id, 'status', j.status, 'module', j.module, 'kind', j.kind);
end $$;

-- Převzetí úlohy serverem: zámek na 3 minuty, nejvýše max_attempts pokusů. Vrací úlohu s kontextem, nebo NULL.
create or replace function public.ai_job_claim(p_job uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare j private.ai_jobs; tok uuid := gen_random_uuid(); r text;
begin
  select * into j from private.ai_jobs where id = p_job for update skip locked;
  if j.id is null then return null; end if;
  if not (j.status = 'queued' or (j.status = 'running' and j.lock_until < now())) or j.next_attempt_at > now() then return null; end if;
  if j.attempts >= j.max_attempts then
    update private.ai_jobs set status = 'failed', error = coalesce(error, 'max_attempts'), finished_at = now() where id = j.id; return null;
  end if;
  -- zadavatel (nebo ten, kdo schválil plán) musí být stále vlastník nebo správce a účet zapisovatelný
  r := private.ai_member_role_of(j.created_by, j.company_id);
  if r is null or r not in ('owner', 'admin') or not private.ai_writable_company(j.company_id) then
    update private.ai_jobs set status = 'failed', error = 'requester_not_allowed', finished_at = now() where id = j.id; return null;
  end if;
  update private.ai_jobs set status = 'running', attempts = attempts + 1, lock_token = tok, lock_until = now() + interval '3 minutes' where id = j.id;
  return jsonb_build_object('id', j.id, 'company_id', j.company_id, 'module', j.module, 'kind', j.kind, 'brief', j.brief, 'input', j.input, 'source', j.source,
    'attempt', j.attempts + 1, 'lock_token', tok, 'created_by', j.created_by, 'context', private.ai_context_impl(j.company_id, j.module),
    'parent', (select jsonb_build_object('brief', p.brief, 'summary', left(p.output->>'summary', 600)) from private.ai_jobs p where p.id = j.parent_id));
end $$;

-- Rezervace peněz pro úlohu z plánu nebo z delegace (bez prohlížeče): na účet toho, kdo plán nebo zadání schválil.
create or replace function public.ai_job_reserve(p_job uuid, p_lock uuid, p_model text, p_max_in integer, p_max_out integer) returns jsonb language plpgsql security definer set search_path = '' as $$
declare j private.ai_jobs; r jsonb;
begin
  select * into j from private.ai_jobs where id = p_job;
  if j.id is null or j.status <> 'running' or j.lock_token is distinct from p_lock then perform private.ai_fail('PT409', 'lock_lost'); end if;
  r := private.autopilot_reserve_impl(j.created_by, j.company_id, j.module, p_model, p_max_in, p_max_out, 'job:' || j.id::text || ':' || j.attempts::text);
  update private.ai_jobs set run_id = (r->>'run_id')::uuid where id = j.id;
  return r;
end $$;

create or replace function public.ai_job_finish(p_job uuid, p_lock uuid, p_ok boolean, p_output jsonb, p_actions jsonb, p_delegations jsonb, p_error text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare j private.ai_jobs; a jsonb; c jsonb; n_ok integer := 0; n_drop integer := 0; n_del integer := 0; st text; d jsonb;
begin
  select * into j from private.ai_jobs where id = p_job for update;
  if j.id is null or j.status <> 'running' or j.lock_token is distinct from p_lock then perform private.ai_fail('PT409', 'lock_lost'); end if;
  if not p_ok then
    if j.source = 'schedule' and j.attempts < j.max_attempts then
      update private.ai_jobs set status = 'queued', error = left(p_error, 300), lock_token = null, lock_until = null, next_attempt_at = now() + (j.attempts * interval '10 minutes') where id = j.id;
      return jsonb_build_object('status', 'queued', 'retry', true);
    end if;
    update private.ai_jobs set status = 'failed', error = left(coalesce(p_error, 'failed'), 300), lock_token = null, lock_until = null, finished_at = now() where id = j.id;
    if j.schedule_id is not null then update private.ai_schedules set last_status = 'failed' where id = j.schedule_id; end if;
    return jsonb_build_object('status', 'failed', 'retry', false);
  end if;
  if jsonb_typeof(p_output) <> 'object' or pg_column_size(p_output) > 60000 then perform private.ai_fail('PT422', 'invalid_output'); end if;
  for a in select value from jsonb_array_elements(case when jsonb_typeof(p_actions) = 'array' then p_actions else '[]'::jsonb end) limit 12 loop
    c := private.ai_action_clean(j.company_id, a->>'type', a->'payload');
    if c is null then n_drop := n_drop + 1;
    else insert into private.ai_actions (job_id, company_id, type, payload, payload_hash) values (j.id, j.company_id, a->>'type', c, private.ai_hash(c)); n_ok := n_ok + 1; end if;
  end loop;
  if j.module = 'ceo' and j.kind = 'orchestrate' and jsonb_typeof(p_delegations) = 'array' then
    for d in select value from jsonb_array_elements(p_delegations) limit 5 loop
      if exists (select 1 from private.ai_kinds k where k.module = d->>'module' and k.kind = d->>'kind' and not (k.module = 'ceo' and k.kind = 'orchestrate')) and char_length(coalesce(d->>'brief', '')) between 3 and 1000 then
        n_del := n_del + 1;
        insert into private.ai_jobs (company_id, module, kind, brief, source, parent_id, idempotency_key, created_by)
          values (j.company_id, d->>'module', d->>'kind', btrim(d->>'brief'), 'ceo', j.id, 'del:' || j.id::text || ':' || n_del::text, j.created_by) on conflict do nothing;
      end if;
    end loop;
  end if;
  st := case when n_ok > 0 then 'awaiting_approval' else 'done' end;
  update private.ai_jobs set status = st, output = p_output || jsonb_build_object('dropped_actions', n_drop), error = null, lock_token = null, lock_until = null, finished_at = now() where id = j.id;
  if j.schedule_id is not null then update private.ai_schedules set last_status = 'ok' where id = j.schedule_id; end if;
  insert into private.autopilot_events (root_company_id, actor, operation, details) values (private.business_root(j.company_id), null, 'job', jsonb_build_object('job_id', j.id, 'event', 'finished', 'actions', n_ok, 'dropped', n_drop, 'delegations', n_del));
  return jsonb_build_object('status', st, 'actions', n_ok, 'dropped', n_drop, 'delegations', n_del);
end $$;

-- ---------- schválení a provedení akce (jen člověk; schvaluje se konkrétní obsah) ----------
create or replace function public.ai_action_decide(cid uuid, p_action uuid, p_expected_hash text, p_approve boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); a private.ai_actions; p jsonb; res jsonb := '{}'::jsonb; nid uuid; old text; path text[];
begin
  select * into a from private.ai_actions where id = p_action and company_id = cid for update;
  if a.id is null then perform private.ai_fail('PT404', 'not_found'); end if;
  if a.status <> 'proposed' then return jsonb_build_object('id', a.id, 'status', a.status, 'already', true); end if;
  if a.payload_hash <> p_expected_hash then perform private.ai_fail('PT409', 'stale'); end if;
  p := a.payload;
  if not p_approve then
    update private.ai_actions set status = 'rejected', decided_by = uid, decided_at = now() where id = a.id;
  else
    if private.ai_action_clean(cid, a.type, p) is null then perform private.ai_fail('PT409', 'no_longer_valid'); end if;   -- např. zákazník mezitím smazán
    if a.type = 'task' then
      insert into public.tasks (company_id, title, description, due_at) values (cid, p->>'title', p->>'description', case when p ? 'due_in_days' then now() + make_interval(days => (p->>'due_in_days')::int) end) returning id into nid;
    elsif a.type = 'marketing_post' then
      insert into public.marketing_posts (company_id, title, channel, status, planned_on, body, created_by) values (cid, p->>'title', p->>'channel', 'draft', current_date + (p->>'planned_in_days')::int, p->>'body', uid) returning id into nid;
    elsif a.type = 'customer_note' then
      insert into public.client_notes (company_id, customer_id, kind, body, created_by) values (cid, (p->>'customer_id')::uuid, 'note', p->>'body', uid) returning id into nid;
    elsif a.type = 'finance_entry' then
      insert into public.financial_entries (company_id, title, amount, kind, entry_date) values (cid, p->>'title', (p->>'amount')::numeric, p->>'kind', (p->>'entry_date')::date) returning id into nid;
    elsif a.type = 'quote_draft' then
      insert into public.quotes (company_id, customer_id, deal_id, title, items, total, status, note, created_by, valid_until)
        values (cid, (p->>'customer_id')::uuid, (p->>'deal_id')::uuid, p->>'title', p->'items', (p->>'total')::numeric, 'draft', p->>'note', uid, current_date + 30) returning id into nid;
    elsif a.type = 'site_text' then
      path := string_to_array(p->>'field', '.');
      select data #>> path into old from public.sites where company_id = cid for update;
      update public.sites set data = jsonb_set(case when data ? path[1] then data else data || jsonb_build_object(path[1], '{}'::jsonb) end, path, to_jsonb(p->>'value'), true) where company_id = cid;
      res := jsonb_build_object('previous', old);
    elsif a.type = 'product_description' then
      select description into old from public.products where id = (p->>'product_id')::uuid and company_id = cid for update;
      update public.products set description = p->>'description' where id = (p->>'product_id')::uuid and company_id = cid;
      res := jsonb_build_object('previous', old);
    elsif a.type = 'goal' then
      insert into private.ai_goals (company_id, title, metric, target, due_on, created_by, action_id) values (cid, p->>'title', p->>'metric', (p->>'target')::numeric, current_date + (p->>'days')::int, uid, a.id) returning id into nid;
    elsif a.type = 'schedule' then
      insert into private.ai_schedules (company_id, module, kind, cadence, brief, approved_by, next_run_at)
        values (cid, p->>'module', p->>'kind', p->>'cadence', p->>'brief', uid, private.ai_next_run(p->>'cadence', now()))
        on conflict (company_id, module, kind, cadence) do update set enabled = true, brief = excluded.brief, approved_by = excluded.approved_by, approved_at = now() returning id into nid;
    end if;
    update private.ai_actions set status = 'applied', decided_by = uid, decided_at = now(), result = res || jsonb_build_object('record_id', nid) where id = a.id;
  end if;
  if not exists (select 1 from private.ai_actions where job_id = a.job_id and status = 'proposed') then
    update private.ai_jobs set status = 'done' where id = a.job_id and status = 'awaiting_approval';
  end if;
  insert into private.autopilot_events (root_company_id, actor, operation, details) values (private.business_root(cid), uid, 'action', jsonb_build_object('action_id', a.id, 'type', a.type, 'approved', p_approve, 'record_id', nid));
  return jsonb_build_object('id', a.id, 'status', case when p_approve then 'applied' else 'rejected' end, 'record_id', nid, 'already', false);
end $$;

-- ---------- chat ----------
create or replace function public.ai_chat_store(cid uuid, p_module text, p_run uuid, p_user text, p_reply text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare r private.autopilot_runs;
begin
  select * into r from private.autopilot_runs where id = p_run;
  if r.id is null or r.company_id <> cid or r.mode <> p_module or r.created_by is null then perform private.ai_fail('PT404', 'run_not_found'); end if;
  if exists (select 1 from private.ai_chat where run_id = p_run) then return '{"stored":false}'::jsonb; end if;
  insert into private.ai_chat (company_id, module, user_id, role, content, run_id) values (cid, p_module, r.created_by, 'user', left(p_user, 6000), p_run), (cid, p_module, r.created_by, 'assistant', left(p_reply, 6000), p_run);
  return '{"stored":true}'::jsonb;
end $$;
create or replace function public.ai_chat_history(cid uuid, p_module text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, false);
begin
  return coalesce((select jsonb_agg(jsonb_build_object('role', role, 'content', content, 'at', created_at) order by id) from (
    select * from private.ai_chat where company_id = cid and module = p_module and user_id = uid order by id desc limit 30) q), '[]'::jsonb);
end $$;
-- kontext pro chat (člověk; server ho volá tokenem uživatele)
create or replace function public.ai_context(cid uuid, p_module text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.profile_actor(cid, false);
  if p_module not in ('marketing', 'obchodnik', 'ceo', 'ucetnictvi', 'weby_eshopy', 'automatizace') then perform private.ai_fail('PT422', 'unknown_module'); end if;
  return private.ai_context_impl(cid, p_module);
end $$;

-- ---------- plány (běh na pozadí) ----------
create or replace function public.ai_schedule_save(cid uuid, p_module text, p_kind text, p_cadence text, p_brief text, p_enabled boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); sid uuid;
begin
  if p_cadence not in ('daily', 'weekly', 'monthly') or coalesce(char_length(p_brief), 0) > 1000 then perform private.ai_fail('PT422', 'validation_failed'); end if;
  if not exists (select 1 from private.ai_kinds where module = p_module and kind = p_kind and schedulable) then perform private.ai_fail('PT422', 'not_schedulable'); end if;
  if (select count(*) from private.ai_schedules where company_id = cid and enabled) >= 10 and coalesce(p_enabled, true) then perform private.ai_fail('PT429', 'too_many_schedules'); end if;
  insert into private.ai_schedules (company_id, module, kind, cadence, brief, enabled, approved_by, next_run_at)
    values (cid, p_module, p_kind, p_cadence, coalesce(btrim(p_brief), ''), coalesce(p_enabled, true), uid, private.ai_next_run(p_cadence, now()))
    on conflict (company_id, module, kind, cadence) do update set brief = excluded.brief, enabled = excluded.enabled, approved_by = uid, approved_at = now(),
      next_run_at = case when private.ai_schedules.enabled then private.ai_schedules.next_run_at else excluded.next_run_at end
    returning id into sid;
  insert into private.autopilot_events (root_company_id, actor, operation, details) values (private.business_root(cid), uid, 'schedule', jsonb_build_object('schedule_id', sid, 'module', p_module, 'kind', p_kind, 'cadence', p_cadence, 'enabled', coalesce(p_enabled, true)));
  return jsonb_build_object('id', sid);
end $$;
create or replace function public.ai_schedule_stop_all(cid uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, false); n integer; m integer;
begin
  update private.ai_schedules set enabled = false where company_id = cid and enabled; get diagnostics n = row_count;
  update private.ai_jobs set status = 'cancelled', finished_at = now() where company_id = cid and status = 'queued' and source in ('schedule', 'ceo'); get diagnostics m = row_count;
  insert into private.autopilot_events (root_company_id, actor, operation, details) values (private.business_root(cid), uid, 'schedule', jsonb_build_object('event', 'stop_all', 'schedules', n, 'jobs', m));
  return jsonb_build_object('schedules_stopped', n, 'jobs_cancelled', m);
end $$;
-- Tik plánovače (jen server): pro splatné plány založí úlohy (jedna na plán a den) a vrátí úlohy k převzetí.
create or replace function public.ai_schedule_tick(p_limit integer default 5) returns jsonb language plpgsql security definer set search_path = '' as $$
declare s private.ai_schedules; made integer := 0;
begin
  for s in select * from private.ai_schedules where enabled and next_run_at <= now() order by next_run_at limit 20 for update skip locked loop
    insert into private.ai_jobs (company_id, module, kind, brief, source, schedule_id, idempotency_key, created_by)
      values (s.company_id, s.module, s.kind, s.brief, 'schedule', s.id, 'sch:' || s.id::text || ':' || to_char(now(), 'YYYYMMDD'), s.approved_by) on conflict do nothing;
    update private.ai_schedules set next_run_at = private.ai_next_run(cadence, greatest(next_run_at, now() - interval '1 day')), last_run_at = now() where id = s.id;
    made := made + 1;
  end loop;
  return jsonb_build_object('created', made, 'jobs', coalesce((select jsonb_agg(id) from (
    select id from private.ai_jobs where source = 'schedule' and next_attempt_at <= now()
      and (status = 'queued' or (status = 'running' and lock_until < now()))
    order by next_attempt_at limit greatest(1, least(coalesce(p_limit, 5), 20))) q), '[]'::jsonb));
end $$;

-- ---------- stav pro rozhraní ----------
create or replace function private.ai_goal_value(cid uuid, metric text, since date) returns numeric language plpgsql stable security definer set search_path = '' as $$
begin
  if metric = 'trzby' then return (select coalesce(sum(amount), 0) from public.financial_entries where company_id = cid and kind = 'income' and entry_date >= since); end if;
  return private.mkt_goal_value(cid, metric, since::timestamptz);
end $$;
create or replace function public.ai_team_state(cid uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, false); root uuid := private.business_root(cid); b private.autopilot_budgets;
begin
  select * into b from private.autopilot_budgets where root_company_id = root;
  return jsonb_build_object(
    'kinds', (select jsonb_agg(jsonb_build_object('module', module, 'kind', kind, 'title', title, 'schedulable', schedulable) order by module, kind) from private.ai_kinds),
    'limits', jsonb_build_object('monthly_nusd', b.monthly_limit_nusd, 'per_user_nusd', b.per_user_monthly_nusd,
      'per_run_nusd', coalesce(b.per_run_max_nusd, (select default_per_run_nusd from private.autopilot_plan_caps where plan = private.ap_plan(root))),
      'plan_cap_nusd', (select max_monthly_nusd from private.autopilot_plan_caps where plan = private.ap_plan(root)),
      'spent_nusd', private.ap_spent(root), 'paid_runs_enabled', (select paid_runs_enabled from private.autopilot_platform where id),
      'by_module', (select coalesce(jsonb_object_agg(mode, s), '{}'::jsonb) from (select mode, sum(coalesce(actual_nusd, reserved_nusd)) s from private.autopilot_runs where root_company_id = root and created_at >= private.ap_month_start() group by mode) q)),
    'jobs', (select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from (
      select j.id, j.module, j.kind, k.title, j.brief, j.status, j.source, j.parent_id, j.error, j.created_at, j.finished_at, j.output,
             (select r.actual_nusd from private.autopilot_runs r where r.id = j.run_id) cost_nusd
      from private.ai_jobs j join private.ai_kinds k on k.module = j.module and k.kind = j.kind where j.company_id = cid order by j.created_at desc limit 40) q),
    'actions', (select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from (
      select a.id, a.job_id, j.module, a.type, a.payload, a.payload_hash, a.status, a.created_at, a.decided_at, a.result
      from private.ai_actions a join private.ai_jobs j on j.id = a.job_id where a.company_id = cid order by (a.status = 'proposed') desc, a.created_at desc limit 60) q),
    'schedules', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'module', s.module, 'kind', s.kind, 'title', k.title, 'cadence', s.cadence, 'brief', s.brief, 'enabled', s.enabled,
      'next_run_at', s.next_run_at, 'last_run_at', s.last_run_at, 'last_status', s.last_status) order by s.created_at), '[]'::jsonb) from private.ai_schedules s join private.ai_kinds k on k.module = s.module and k.kind = s.kind where s.company_id = cid),
    'goals', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'title', g.title, 'metric', g.metric, 'target', g.target, 'starts_on', g.starts_on, 'due_on', g.due_on, 'status', g.status,
      'value', private.ai_goal_value(cid, g.metric, g.starts_on)) order by g.created_at desc), '[]'::jsonb) from private.ai_goals g where g.company_id = cid));
end $$;

-- ---------- AI Účetnictví: doklady, režim, DPH, export ----------
create table if not exists private.acc_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  regime text not null default 'neurceno' check (regime in ('neurceno', 'danova_evidence', 'ucetnictvi', 'pausalni_dan')),
  vat_payer boolean not null default false, updated_by uuid, updated_at timestamptz not null default now());
create table if not exists private.acc_documents (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  status text not null default 'extracted' check (status in ('extracted', 'approved', 'rejected')),
  file_hash text not null check (file_hash ~ '^[0-9a-f]{64}$'), mime text not null,
  ai_doc jsonb not null, doc jsonb not null, doc_hash text not null,
  dedupe_key text, duplicate_of uuid references private.acc_documents(id) on delete set null,
  financial_entry_id uuid, matched_invoice_id uuid,
  created_by uuid not null, created_at timestamptz not null default now(), decided_by uuid, decided_at timestamptz);
create index if not exists acc_documents_company_idx on private.acc_documents (company_id, created_at desc);
create index if not exists acc_documents_dedupe_idx on private.acc_documents (company_id, dedupe_key);
alter table private.acc_settings enable row level security; alter table private.acc_documents enable row level security;
revoke all on private.acc_settings, private.acc_documents from public, anon, authenticated;

create or replace function private.acc_doc_clean(d jsonb) returns jsonb language plpgsql immutable set search_path = '' as $$
declare cats text[] := array['material', 'sluzby', 'pohonne hmoty', 'najem', 'energie', 'telefon a internet', 'software', 'marketing', 'doprava', 'opravy a udrzba', 'ostatni'];
  num_ok boolean;
begin
  if jsonb_typeof(d) <> 'object' then return null; end if;
  num_ok := (d->'total_amount' is null or jsonb_typeof(d->'total_amount') in ('number', 'null')) and (d->'vat_amount' is null or jsonb_typeof(d->'vat_amount') in ('number', 'null'))
        and (d->'vat_rate' is null or jsonb_typeof(d->'vat_rate') in ('number', 'null'));
  if not num_ok or coalesce((d->>'total_amount')::numeric, 0) < 0 or coalesce((d->>'total_amount')::numeric, 0) > 1e10 or coalesce((d->>'vat_rate')::numeric, 0) not between 0 and 100
     or ((d->>'issue_date') is not null and (d->>'issue_date') !~ '^\d{4}-\d{2}-\d{2}$') or ((d->>'due_date') is not null and (d->>'due_date') !~ '^\d{4}-\d{2}-\d{2}$') then return null; end if;
  return jsonb_build_object(
    'document_type', case when (d->>'document_type') in ('received_invoice', 'receipt', 'issued_invoice', 'other') then d->>'document_type' else 'other' end,
    'supplier_name', left(nullif(btrim(d->>'supplier_name'), ''), 120), 'supplier_ico', left(nullif(regexp_replace(coalesce(d->>'supplier_ico', ''), '\s', '', 'g'), ''), 20),
    'supplier_dic', left(nullif(btrim(d->>'supplier_dic'), ''), 20), 'document_number', left(nullif(btrim(d->>'document_number'), ''), 60),
    'issue_date', d->>'issue_date', 'due_date', d->>'due_date', 'total_amount', round((d->>'total_amount')::numeric, 2), 'vat_amount', round((d->>'vat_amount')::numeric, 2),
    'vat_rate', (d->>'vat_rate')::numeric, 'currency', coalesce(upper(left(nullif(btrim(d->>'currency'), ''), 6)), 'CZK'),
    'description', left(nullif(btrim(d->>'description'), ''), 120), 'category', case when (d->>'category') = any(cats) then d->>'category' end,
    'variable_symbol', case when (d->>'variable_symbol') ~ '^[0-9]{1,10}$' then d->>'variable_symbol' end);
end $$;
create or replace function private.acc_dedupe_key(d jsonb) returns text language sql immutable set search_path = '' as $$
  select case when (d->>'document_number') is not null and (d->>'total_amount') is not null and coalesce(d->>'supplier_ico', d->>'supplier_name') is not null
    then lower(coalesce(d->>'supplier_ico', d->>'supplier_name')) || '|' || lower(d->>'document_number') || '|' || (d->>'total_amount') end $$;

create or replace function public.acc_settings_save(cid uuid, p_regime text, p_vat_payer boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true);
begin
  if p_regime not in ('neurceno', 'danova_evidence', 'ucetnictvi', 'pausalni_dan') then perform private.ai_fail('PT422', 'validation_failed'); end if;
  insert into private.acc_settings (company_id, regime, vat_payer, updated_by) values (cid, p_regime, coalesce(p_vat_payer, false), uid)
    on conflict (company_id) do update set regime = excluded.regime, vat_payer = excluded.vat_payer, updated_by = uid, updated_at = now();
  return jsonb_build_object('regime', p_regime, 'vat_payer', coalesce(p_vat_payer, false));
end $$;

-- Uložení vytěženého dokladu (volá server tokenem uživatele hned po vytěžení). Duplicitu pozná podle otisku souboru nebo dodavatel+číslo+částka.
create or replace function public.acc_document_store(cid uuid, p_file_hash text, p_mime text, p_doc jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); c jsonb := private.acc_doc_clean(p_doc); k text; dup uuid; nid uuid; reason text;
begin
  if c is null or p_file_hash !~ '^[0-9a-f]{64}$' or coalesce(char_length(p_mime), 0) not between 3 and 60 then perform private.ai_fail('PT422', 'validation_failed'); end if;
  k := private.acc_dedupe_key(c);
  select id into dup from private.acc_documents where company_id = cid and file_hash = p_file_hash and status <> 'rejected' order by created_at limit 1;
  if dup is not null then reason := 'same_file';
  elsif k is not null then
    select id into dup from private.acc_documents where company_id = cid and dedupe_key = k and status <> 'rejected' order by created_at limit 1;
    if dup is not null then reason := 'same_supplier_number_amount'; end if;
  end if;
  insert into private.acc_documents (company_id, file_hash, mime, ai_doc, doc, doc_hash, dedupe_key, duplicate_of, created_by)
    values (cid, p_file_hash, p_mime, c, c, private.ai_hash(c), k, dup, uid) returning id into nid;
  return jsonb_build_object('id', nid, 'duplicate_of', dup, 'duplicate_reason', reason, 'doc', c, 'hash', private.ai_hash(c));
end $$;
create or replace function public.acc_document_update(cid uuid, p_id uuid, p_expected_hash text, p_doc jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); c jsonb := private.acc_doc_clean(p_doc); r private.acc_documents;
begin
  select * into r from private.acc_documents where id = p_id and company_id = cid for update;
  if r.id is null then perform private.ai_fail('PT404', 'not_found'); end if;
  if r.status <> 'extracted' then perform private.ai_fail('PT409', 'already_decided'); end if;
  if r.doc_hash <> p_expected_hash then perform private.ai_fail('PT409', 'stale'); end if;
  if c is null then perform private.ai_fail('PT422', 'validation_failed'); end if;
  update private.acc_documents set doc = c, doc_hash = private.ai_hash(c), dedupe_key = private.acc_dedupe_key(c),
    duplicate_of = (select d.id from private.acc_documents d where d.company_id = cid and d.id <> r.id and d.status <> 'rejected'
                      and (d.file_hash = r.file_hash or d.dedupe_key = private.acc_dedupe_key(c)) order by d.created_at limit 1) where id = r.id;
  return jsonb_build_object('id', r.id, 'hash', private.ai_hash(c));
end $$;
-- Schválení člověkem: přijatý doklad vytvoří výdaj v evidenci; vystavená faktura se jen sváže s existující fakturou (žádný druhý příjem).
create or replace function public.acc_document_decide(cid uuid, p_id uuid, p_expected_hash text, p_approve boolean, p_allow_duplicate boolean default false) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); r private.acc_documents; d jsonb; eid uuid; inv uuid;
begin
  select * into r from private.acc_documents where id = p_id and company_id = cid for update;
  if r.id is null then perform private.ai_fail('PT404', 'not_found'); end if;
  if r.status <> 'extracted' then return jsonb_build_object('id', r.id, 'status', r.status, 'already', true); end if;
  if r.doc_hash <> p_expected_hash then perform private.ai_fail('PT409', 'stale'); end if;
  d := r.doc;
  if not p_approve then
    update private.acc_documents set status = 'rejected', decided_by = uid, decided_at = now() where id = r.id;
    return jsonb_build_object('id', r.id, 'status', 'rejected', 'already', false);
  end if;
  if r.duplicate_of is not null and exists (select 1 from private.acc_documents x where x.id = r.duplicate_of and x.status <> 'rejected') and not coalesce(p_allow_duplicate, false) then
    perform private.ai_fail('PT409', 'duplicate'); end if;
  if (d->>'total_amount') is null or (d->>'total_amount')::numeric <= 0 or (d->>'issue_date') is null then perform private.ai_fail('PT422', 'incomplete'); end if;
  if (d->>'document_type') = 'issued_invoice' then
    select id into inv from public.invoices where company_id = cid and lifecycle = 'issued' and number = d->>'document_number' and total = (d->>'total_amount')::numeric limit 1;
    if inv is null then perform private.ai_fail('PT409', 'issued_invoice_not_found'); end if;
  else
    insert into public.financial_entries (company_id, title, amount, kind, entry_date)
      values (cid, left(coalesce(d->>'supplier_name', 'Doklad') || coalesce(' ' || (d->>'document_number'), '') || coalesce(' (' || (d->>'category') || ')', ''), 200), (d->>'total_amount')::numeric, 'expense', (d->>'issue_date')::date)
      returning id into eid;
  end if;
  update private.acc_documents set status = 'approved', decided_by = uid, decided_at = now(), financial_entry_id = eid, matched_invoice_id = inv where id = r.id;
  return jsonb_build_object('id', r.id, 'status', 'approved', 'financial_entry_id', eid, 'matched_invoice_id', inv, 'already', false);
end $$;
create or replace function public.acc_state(cid uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, false);
begin
  return jsonb_build_object(
    'settings', coalesce((select jsonb_build_object('regime', regime, 'vat_payer', vat_payer) from private.acc_settings where company_id = cid), '{"regime":"neurceno","vat_payer":false}'::jsonb),
    'documents', (select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from (
      select id, status, mime, doc, doc_hash, ai_doc, duplicate_of, financial_entry_id, matched_invoice_id, created_at, decided_at from private.acc_documents where company_id = cid order by created_at desc limit 100) q),
    'invoices', (select jsonb_build_object('unpaid', count(*) filter (where paid_at is null), 'overdue', count(*) filter (where paid_at is null and due_on < current_date),
      'unpaid_amount', coalesce(sum(total) filter (where paid_at is null), 0)) from public.invoices where company_id = cid and lifecycle = 'issued'),
    'bank_unmatched', (select count(*) from private.bank_transactions where company_id = cid and status = 'unmatched'));
end $$;
-- Orientační přehled DPH za období: výstup z vystavených faktur (podle data zdanitelného plnění), vstup ze schválených přijatých dokladů.
create or replace function public.acc_vat_summary(cid uuid, p_from date, p_to date) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, false);
begin
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 370 then perform private.ai_fail('PT422', 'validation_failed'); end if;
  return jsonb_build_object('from', p_from, 'to', p_to,
    'output', (select coalesce(jsonb_agg(jsonb_build_object('rate', vat_rate, 'base', b, 'vat', t) order by vat_rate), '[]'::jsonb) from (
      select it.vat_rate, sum(it.net) b, sum(it.tax) t from public.invoices i join public.invoice_items it on it.invoice_id = i.id
       where i.company_id = cid and i.lifecycle = 'issued' and i.vat_payer and coalesce(i.taxable_supply_on, i.issued_on) between p_from and p_to group by it.vat_rate) q),
    'input', (select coalesce(jsonb_agg(jsonb_build_object('rate', r, 'base', b, 'vat', t, 'documents', n) order by r), '[]'::jsonb) from (
      select coalesce((doc->>'vat_rate')::numeric, 0) r, sum((doc->>'total_amount')::numeric - coalesce((doc->>'vat_amount')::numeric, 0)) b, sum(coalesce((doc->>'vat_amount')::numeric, 0)) t, count(*) n
        from private.acc_documents where company_id = cid and status = 'approved' and (doc->>'document_type') in ('received_invoice', 'receipt')
         and (doc->>'issue_date')::date between p_from and p_to group by 1) q),
    'documents_without_vat', (select count(*) from private.acc_documents where company_id = cid and status = 'approved' and (doc->>'vat_amount') is null and (doc->>'issue_date')::date between p_from and p_to),
    'note', 'Orientační přehled z údajů ve Vexaronetu. Nezohledňuje krácení odpočtu, přenesení daňové povinnosti u přijatých plnění, opravy ani doklady mimo evidenci. Není to daňové přiznání.');
end $$;
create or replace function public.acc_export(cid uuid, p_from date, p_to date) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, false);
begin
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 370 then perform private.ai_fail('PT422', 'validation_failed'); end if;
  return jsonb_build_object(
    'entries', (select coalesce(jsonb_agg(jsonb_build_object('date', entry_date, 'kind', kind, 'title', title, 'amount', amount) order by entry_date, created_at), '[]'::jsonb) from public.financial_entries where company_id = cid and entry_date between p_from and p_to),
    'documents', (select coalesce(jsonb_agg(doc || jsonb_build_object('status', status, 'financial_entry_id', financial_entry_id) order by created_at), '[]'::jsonb) from private.acc_documents where company_id = cid and status = 'approved' and (doc->>'issue_date')::date between p_from and p_to),
    'invoices', (select coalesce(jsonb_agg(jsonb_build_object('number', number, 'issued_on', issued_on, 'due_on', due_on, 'customer', customer_snapshot->>'name', 'total', total, 'currency', currency, 'paid_at', paid_at) order by issued_on), '[]'::jsonb)
                   from public.invoices where company_id = cid and lifecycle = 'issued' and issued_on between p_from and p_to));
end $$;

-- ---------- práva ----------
revoke all on function private.ap_plan(uuid), private.autopilot_budget_cap_check(), private.autopilot_limits_check(), private.ai_fail(text, text), private.ai_hash(jsonb),
  private.ai_member_role_of(uuid, uuid), private.ai_writable_company(uuid), private.ai_next_run(text, timestamptz), private.ai_action_clean(uuid, text, jsonb),
  private.ai_context_impl(uuid, text), private.ai_goal_value(uuid, text, date), private.acc_doc_clean(jsonb), private.acc_dedupe_key(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.autopilot_set_limits(uuid, bigint, bigint), public.ai_job_create(uuid, text, text, text, jsonb, text), public.ai_job_cancel(uuid, uuid), public.ai_job_status(uuid, uuid), public.ai_job_claim(uuid),
  public.ai_job_reserve(uuid, uuid, text, integer, integer), public.ai_job_finish(uuid, uuid, boolean, jsonb, jsonb, jsonb, text), public.ai_action_decide(uuid, uuid, text, boolean),
  public.ai_chat_store(uuid, text, uuid, text, text), public.ai_chat_history(uuid, text), public.ai_context(uuid, text), public.ai_schedule_save(uuid, text, text, text, text, boolean),
  public.ai_schedule_stop_all(uuid), public.ai_schedule_tick(integer), public.ai_team_state(uuid), public.acc_settings_save(uuid, text, boolean),
  public.acc_document_store(uuid, text, text, jsonb), public.acc_document_update(uuid, uuid, text, jsonb), public.acc_document_decide(uuid, uuid, text, boolean, boolean),
  public.acc_state(uuid), public.acc_vat_summary(uuid, date, date), public.acc_export(uuid, date, date) from public, anon, authenticated, service_role;
grant execute on function public.autopilot_set_limits(uuid, bigint, bigint), public.ai_job_create(uuid, text, text, text, jsonb, text), public.ai_job_cancel(uuid, uuid), public.ai_job_status(uuid, uuid),
  public.ai_action_decide(uuid, uuid, text, boolean), public.ai_chat_history(uuid, text), public.ai_context(uuid, text), public.ai_schedule_save(uuid, text, text, text, text, boolean),
  public.ai_schedule_stop_all(uuid), public.ai_team_state(uuid), public.acc_settings_save(uuid, text, boolean), public.acc_document_store(uuid, text, text, jsonb),
  public.acc_document_update(uuid, uuid, text, jsonb), public.acc_document_decide(uuid, uuid, text, boolean, boolean), public.acc_state(uuid), public.acc_vat_summary(uuid, date, date),
  public.acc_export(uuid, date, date) to authenticated;
grant execute on function public.ai_job_claim(uuid), public.ai_job_reserve(uuid, uuid, text, integer, integer), public.ai_job_finish(uuid, uuid, boolean, jsonb, jsonb, jsonb, text),
  public.ai_chat_store(uuid, text, uuid, text, text), public.ai_schedule_tick(integer) to service_role;
notify pgrst, 'reload schema';
