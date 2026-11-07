-- =====================================================================================
-- Vexaronet AI Autopilot: vynucování nákladového limitu (BEZ jakéhokoli volání AI)       2026-11-08
-- STAV: PŘIPRAVENO, NEAPLIKOVÁNO NA PRODUKCI. Vyžaduje migraci 20261107120000_profil_firmy.sql.
--
-- Co migrace dělá: přidává tabulky ve schématu private a funkce autopilot_*. Nic existujícího nemění,
-- nesahá na reserve_ai, ai_requests ani na jiné AI tabulky.
--
-- Jak se limit vynucuje (vše uvnitř databáze, jedna transakce, zámek na hlavní firmě):
--   1. Než se zavolá poskytovatel AI, zařízení zavolá autopilot_reserve (jménem přihlášeného uživatele).
--      Rezervuje se nejvyšší možná cena (max. vstupní × cena + max. výstupní × cena). Když by součet
--      za měsíc překročil limit, rezervace se odmítne a poskytovatel se nevolá.
--   2. Po odpovědi server (service_role) zavolá autopilot_settle se skutečnou spotřebou tokenů.
--   3. Nedokončené rezervace se po 15 minutách označí „expired“ a počítají se v plné rezervované výši (bezpečná strana).
--
-- Placené běhy jsou ve výchozím stavu VYPNUTÉ ze tří nezávislých důvodů, musí platit všechny:
--   a) platformní vypínač private.autopilot_platform.paid_runs_enabled (výchozí false; žádná API funkce ho nemění)
--   b) firma má nastavený měsíční limit (autopilot_set_budget); bez limitu se rezervace odmítne
--   c) tarif hlavní firmy je PRO, BUSINESS nebo ENTERPRISE (private.booking_plan_allowed)
--
-- Kódy chyb (PostgREST je mapuje na HTTP stav): PT402 limit (nenastaven / vyčerpán), PT403 vypnuto nebo tarif nebo
-- jen hlavní firma, PT404 neexistuje, PT409 kolize idempotence, PT422 neplatné hodnoty, PT429 příliš mnoho otevřených běhů,
-- 42501 bez oprávnění.
-- Zpět: db/migrations/20261108110000_autopilot_limity_rollback.sql
-- =====================================================================================
begin;

do $$ begin
  if to_regprocedure('private.profile_actor(uuid,boolean)') is null or to_regprocedure('private.vx_block_update()') is null then
    raise exception 'Nejdřív aplikujte migraci 20261107120000_profil_firmy.sql.';
  end if;
  if to_regprocedure('private.booking_plan_allowed(uuid)') is null or to_regprocedure('private.business_root(uuid)') is null then
    raise exception 'Chybí private.booking_plan_allowed / private.business_root (základ aplikace).';
  end if;
end $$;

-- ---------------------------------------------------------------------------------
-- Tabulky (private; RLS zapnuté; žádná práva pro anon, authenticated ani service_role)
-- ---------------------------------------------------------------------------------
-- Ceny v nanodolarech za JEDEN token (0,30 USD / 1 M tokenů = 300 nUSD). Cena je ověřená z oficiálního ceníku Google
-- (Standard tarif, bez vyhledávání Google a bez cachování kontextu; ty se účtují zvlášť a Autopilot je nesmí používat).
create table if not exists private.ai_model_prices (
  model                 text primary key check (length(model) between 3 and 80),
  input_nusd_per_token  integer not null check (input_nusd_per_token > 0),
  output_nusd_per_token integer not null check (output_nusd_per_token > 0),
  source_url            text not null,
  verified_on           date not null,
  active                boolean not null default false,
  note                  text not null default ''
);
insert into private.ai_model_prices (model, input_nusd_per_token, output_nusd_per_token, source_url, verified_on, active, note)
values ('gemini-3.5-flash-lite', 300, 2500, 'https://ai.google.dev/gemini-api/docs/pricing', date '2026-11-07', true,
        'Standard: 0,30 USD / 1 M vstupních, 2,50 USD / 1 M výstupních tokenů (výstup zahrnuje přemýšlecí tokeny). Bez grounding a bez cachování.')
on conflict (model) do nothing;

create table if not exists private.autopilot_platform (
  id                boolean primary key default true check (id),
  paid_runs_enabled boolean not null default false,
  updated_at        timestamptz not null default now()
);
insert into private.autopilot_platform (id) values (true) on conflict do nothing;

create table if not exists private.autopilot_budgets (
  root_company_id   uuid primary key references public.companies(id) on delete cascade,
  monthly_limit_nusd bigint not null check (monthly_limit_nusd between 0 and 50000000000),   -- nejvýše 50 USD (ochrana před překlepem)
  updated_by        uuid references auth.users(id) on delete set null,
  updated_at        timestamptz not null default now()
);

create table if not exists private.autopilot_runs (
  id               uuid primary key default gen_random_uuid(),
  root_company_id  uuid not null references public.companies(id) on delete cascade,
  company_id       uuid not null references public.companies(id) on delete cascade,
  mode             text not null check (mode in ('marketing', 'obchodnik', 'ceo', 'ucetnictvi', 'weby_eshopy', 'automatizace')),
  model            text not null references private.ai_model_prices(model),
  in_price         integer not null,
  out_price        integer not null,
  max_in_tokens    integer not null check (max_in_tokens between 1 and 8000),
  max_out_tokens   integer not null check (max_out_tokens between 1 and 4000),
  reserved_nusd    bigint not null check (reserved_nusd >= 0),
  actual_nusd      bigint check (actual_nusd >= 0),
  tokens_in        integer check (tokens_in >= 0),
  tokens_out       integer check (tokens_out >= 0),
  overrun          boolean not null default false,
  status           text not null default 'reserved' check (status in ('reserved', 'succeeded', 'failed', 'expired')),
  idempotency_key  text not null check (length(idempotency_key) between 8 and 120),
  created_by       uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  finished_at      timestamptz,
  unique (root_company_id, idempotency_key)
);
create index if not exists autopilot_runs_root_month_idx on private.autopilot_runs (root_company_id, created_at);

create table if not exists private.autopilot_events (
  id              bigint generated always as identity primary key,
  root_company_id uuid not null references public.companies(id) on delete cascade,
  actor           uuid,
  operation       text not null check (operation in ('set_budget', 'reserve', 'settle', 'expire')),
  details         jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);
drop trigger if exists autopilot_events_immutable on private.autopilot_events;
create trigger autopilot_events_immutable before update on private.autopilot_events
  for each row execute function private.vx_block_update();

alter table private.ai_model_prices  enable row level security;
alter table private.autopilot_platform enable row level security;
alter table private.autopilot_budgets enable row level security;
alter table private.autopilot_runs   enable row level security;
alter table private.autopilot_events enable row level security;
revoke all on private.ai_model_prices, private.autopilot_platform, private.autopilot_budgets, private.autopilot_runs, private.autopilot_events
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------
-- Pomocné funkce
-- ---------------------------------------------------------------------------------
create or replace function private.ap_raise(code text, msg text, det jsonb default '{}'::jsonb) returns void
  language plpgsql set search_path = '' as $$
begin raise exception '%', msg using errcode = code, detail = det::text; end $$;

create or replace function private.ap_month_start() returns timestamptz
  language sql stable set search_path = '' as
$$select (date_trunc('month', now() at time zone 'Europe/Prague')) at time zone 'Europe/Prague'$$;

-- skutečná nebo rezervovaná spotřeba tohoto měsíce; otevřená a prošlá rezervace se počítá v plné rezervované výši
create or replace function private.ap_spent(root uuid) returns bigint
  language sql stable set search_path = '' as
$$select coalesce(sum(case when status in ('reserved', 'expired') then reserved_nusd else coalesce(actual_nusd, 0) end), 0)::bigint
    from private.autopilot_runs where root_company_id = root and created_at >= private.ap_month_start()$$;

create or replace function private.ap_expire_stale(root uuid) returns integer
  language plpgsql set search_path = '' as $$
declare n integer;
begin
  update private.autopilot_runs set status = 'expired'
   where status = 'reserved' and created_at < now() - interval '15 minutes' and (root is null or root_company_id = root);
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------------------
-- Funkce pro přihlášené (vlastník nebo správce, zapisovatelný účet)
-- ---------------------------------------------------------------------------------
create or replace function private.autopilot_status_core(cid uuid) returns jsonb
  language plpgsql stable security definer set search_path = '' as $$
declare root uuid; plat boolean; lim bigint; spent bigint; openr bigint; remaining bigint; plan_ok boolean;
begin
  perform private.profile_actor(cid, false);
  root := private.business_root(cid);
  select paid_runs_enabled into plat from private.autopilot_platform where id;
  select monthly_limit_nusd into lim from private.autopilot_budgets where root_company_id = root;
  spent := private.ap_spent(root);
  select coalesce(sum(reserved_nusd), 0) into openr from private.autopilot_runs
    where root_company_id = root and status in ('reserved', 'expired') and created_at >= private.ap_month_start();
  plan_ok := private.booking_plan_allowed(root);
  remaining := case when lim is null then null else greatest(lim - spent, 0) end;
  return jsonb_build_object(
    'root_id', root, 'is_root', root = cid, 'plan_allowed', plan_ok,
    'platform_paid_runs_enabled', coalesce(plat, false),
    'monthly_limit_nusd', lim, 'spent_nusd', spent, 'open_reserved_nusd', openr, 'remaining_nusd', remaining,
    'runs_this_month', (select count(*) from private.autopilot_runs where root_company_id = root and created_at >= private.ap_month_start()),
    'month_start', private.ap_month_start(),
    'paid_runs_possible', (plan_ok and coalesce(plat, false) and lim is not null and lim > 0 and remaining > 0),
    'models', coalesce((select jsonb_agg(jsonb_build_object('model', model, 'input_nusd_per_token', input_nusd_per_token,
                'output_nusd_per_token', output_nusd_per_token, 'verified_on', verified_on, 'source_url', source_url) order by model)
                from private.ai_model_prices where active), '[]'::jsonb));
end $$;

create or replace function private.autopilot_set_budget_core(cid uuid, p_limit_nusd bigint) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare uid uuid; root uuid; old bigint;
begin
  uid := private.profile_actor(cid, true);
  root := private.business_root(cid);
  if root <> cid then perform private.ap_raise('PT403', 'only_root', jsonb_build_object('root_id', root)); end if;
  if p_limit_nusd is not null and (p_limit_nusd < 0 or p_limit_nusd > 50000000000) then
    perform private.ap_raise('PT422', 'validation_failed', '["$.limit:range"]'::jsonb);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(root::text, 7312));
  select monthly_limit_nusd into old from private.autopilot_budgets where root_company_id = root;
  if p_limit_nusd is null then
    delete from private.autopilot_budgets where root_company_id = root;
  else
    insert into private.autopilot_budgets (root_company_id, monthly_limit_nusd, updated_by) values (root, p_limit_nusd, uid)
      on conflict (root_company_id) do update set monthly_limit_nusd = excluded.monthly_limit_nusd, updated_by = excluded.updated_by, updated_at = now();
  end if;
  insert into private.autopilot_events (root_company_id, actor, operation, details)
    values (root, uid, 'set_budget', jsonb_build_object('old_nusd', old, 'new_nusd', p_limit_nusd));
  return jsonb_build_object('monthly_limit_nusd', p_limit_nusd);
end $$;

create or replace function private.autopilot_reserve_core(cid uuid, p_mode text, p_model text, p_max_in integer, p_max_out integer, p_key text) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare uid uuid; root uuid; plat boolean; lim bigint; pr record; spent bigint; need bigint; open_n integer; r record; nid uuid;
begin
  uid := private.profile_actor(cid, true);                                   -- lidská identita, owner/admin, zapisovatelný účet
  root := private.business_root(cid);
  if p_mode is null or p_mode not in ('marketing', 'obchodnik', 'ceo', 'ucetnictvi', 'weby_eshopy', 'automatizace')
     or p_key is null or length(p_key) not between 8 and 120 or p_max_in is null or p_max_in not between 1 and 8000
     or p_max_out is null or p_max_out not between 1 and 4000 or p_model is null then
    perform private.ap_raise('PT422', 'validation_failed', '["$:invalid_arguments"]'::jsonb);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(root::text, 7312));         -- všechny rezervace jedné firmy po jedné

  select * into r from private.autopilot_runs where root_company_id = root and idempotency_key = p_key;
  if found then                                                              -- opakované volání nevytvoří druhou rezervaci
    if r.company_id <> cid or r.mode <> p_mode or r.model <> p_model then
      perform private.ap_raise('PT409', 'idempotency_conflict', '{}'::jsonb);
    end if;
    return jsonb_build_object('run_id', r.id, 'reserved_nusd', r.reserved_nusd, 'status', r.status, 'reused', true,
                              'max_out_tokens', r.max_out_tokens, 'max_in_tokens', r.max_in_tokens, 'model', r.model);
  end if;

  if not private.booking_plan_allowed(root) then
    perform private.ap_raise('PT403', 'plan_not_allowed', '{"reason":"AI Autopilot je součástí tarifů PRO a vyšších"}'::jsonb);
  end if;
  select paid_runs_enabled into plat from private.autopilot_platform where id;
  if not coalesce(plat, false) then
    perform private.ap_raise('PT403', 'paid_runs_disabled', '{"reason":"platform"}'::jsonb);
  end if;
  select monthly_limit_nusd into lim from private.autopilot_budgets where root_company_id = root;
  if lim is null or lim <= 0 then
    perform private.ap_raise('PT402', 'budget_not_set', '{}'::jsonb);
  end if;
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

-- ---------------------------------------------------------------------------------
-- Funkce jen pro server (service_role): vypořádání skutečné spotřeby a úklid prošlých rezervací
-- ---------------------------------------------------------------------------------
create or replace function private.autopilot_settle_core(p_run uuid, p_in integer, p_out integer, p_ok boolean) returns jsonb
  language plpgsql security definer set search_path = '' as $$
declare rt uuid; r record; act bigint;
begin
  select root_company_id into rt from private.autopilot_runs where id = p_run;
  if rt is null then perform private.ap_raise('PT404', 'run_not_found', '{}'::jsonb); end if;
  perform pg_advisory_xact_lock(hashtextextended(rt::text, 7312));
  select * into r from private.autopilot_runs where id = p_run for update;
  if r.status in ('succeeded', 'failed') then                                -- opakované vypořádání nic nepřičte podruhé
    return jsonb_build_object('run_id', r.id, 'status', r.status, 'actual_nusd', r.actual_nusd, 'already', true);
  end if;
  if (p_in is not null and p_in < 0) or (p_out is not null and p_out < 0) or (p_ok and (p_in is null or p_out is null)) then
    perform private.ap_raise('PT422', 'validation_failed', '["$:tokens"]'::jsonb);
  end if;
  act := coalesce(p_in, 0)::bigint * r.in_price + coalesce(p_out, 0)::bigint * r.out_price;
  update private.autopilot_runs
     set status = case when p_ok then 'succeeded' else 'failed' end, tokens_in = p_in, tokens_out = p_out,
         actual_nusd = act, overrun = (act > r.reserved_nusd), finished_at = now()
   where id = p_run;
  insert into private.autopilot_events (root_company_id, actor, operation, details)
    values (rt, null, 'settle', jsonb_build_object('run_id', p_run, 'ok', p_ok, 'actual_nusd', act, 'reserved_nusd', r.reserved_nusd, 'overrun', act > r.reserved_nusd));
  return jsonb_build_object('run_id', p_run, 'status', case when p_ok then 'succeeded' else 'failed' end, 'actual_nusd', act,
                            'reserved_nusd', r.reserved_nusd, 'overrun', act > r.reserved_nusd, 'already', false);
end $$;

create or replace function private.autopilot_expire_core() returns integer
  language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  n := private.ap_expire_stale(null);
  if n > 0 then
    insert into private.autopilot_events (root_company_id, actor, operation, details)
      select distinct root_company_id, null, 'expire', jsonb_build_object('count', n) from private.autopilot_runs where status = 'expired';
  end if;
  return n;
end $$;

-- ---------------------------------------------------------------------------------
-- Veřejné obálky (SECURITY INVOKER) a práva
-- ---------------------------------------------------------------------------------
create or replace function public.autopilot_status(cid uuid) returns jsonb language sql set search_path = '' as $$select private.autopilot_status_core(cid)$$;
create or replace function public.autopilot_set_budget(cid uuid, p_limit_nusd bigint) returns jsonb language sql set search_path = '' as $$select private.autopilot_set_budget_core(cid, p_limit_nusd)$$;
create or replace function public.autopilot_reserve(cid uuid, p_mode text, p_model text, p_max_in integer, p_max_out integer, p_key text) returns jsonb
  language sql set search_path = '' as $$select private.autopilot_reserve_core(cid, p_mode, p_model, p_max_in, p_max_out, p_key)$$;
create or replace function public.autopilot_settle(p_run uuid, p_in integer, p_out integer, p_ok boolean) returns jsonb
  language sql set search_path = '' as $$select private.autopilot_settle_core(p_run, p_in, p_out, p_ok)$$;
create or replace function public.autopilot_expire_stale() returns integer language sql set search_path = '' as $$select private.autopilot_expire_core()$$;

revoke all on function
  private.ap_raise(text, text, jsonb), private.ap_month_start(), private.ap_spent(uuid), private.ap_expire_stale(uuid),
  private.autopilot_status_core(uuid), private.autopilot_set_budget_core(uuid, bigint),
  private.autopilot_reserve_core(uuid, text, text, integer, integer, text),
  private.autopilot_settle_core(uuid, integer, integer, boolean), private.autopilot_expire_core()
  from public, anon, authenticated, service_role;
grant execute on function private.autopilot_status_core(uuid), private.autopilot_set_budget_core(uuid, bigint),
  private.autopilot_reserve_core(uuid, text, text, integer, integer, text) to authenticated;
grant execute on function private.autopilot_settle_core(uuid, integer, integer, boolean), private.autopilot_expire_core() to service_role;

revoke all on function public.autopilot_status(uuid), public.autopilot_set_budget(uuid, bigint),
  public.autopilot_reserve(uuid, text, text, integer, integer, text), public.autopilot_settle(uuid, integer, integer, boolean),
  public.autopilot_expire_stale() from public, anon, authenticated, service_role;
grant execute on function public.autopilot_status(uuid), public.autopilot_set_budget(uuid, bigint),
  public.autopilot_reserve(uuid, text, text, integer, integer, text) to authenticated;
grant execute on function public.autopilot_settle(uuid, integer, integer, boolean), public.autopilot_expire_stale() to service_role;

notify pgrst, 'reload schema';
commit;
