-- Návrat migrace 20261115100000_ai_tym. POZOR: smaže úlohy, akce, chat, plány, cíle AI a evidenci dokladů (před návratem exportovat private.ai_* a private.acc_*).
drop function if exists public.autopilot_set_limits(uuid, bigint, bigint), public.ai_job_create(uuid, text, text, text, jsonb, text), public.ai_job_cancel(uuid, uuid), public.ai_job_claim(uuid),
  public.ai_job_reserve(uuid, uuid, text, integer, integer), public.ai_job_finish(uuid, uuid, boolean, jsonb, jsonb, jsonb, text), public.ai_action_decide(uuid, uuid, text, boolean),
  public.ai_chat_store(uuid, text, uuid, text, text), public.ai_chat_history(uuid, text), public.ai_context(uuid, text), public.ai_schedule_save(uuid, text, text, text, text, boolean),
  public.ai_schedule_stop_all(uuid), public.ai_schedule_tick(integer), public.ai_team_state(uuid), public.acc_settings_save(uuid, text, boolean),
  public.acc_document_store(uuid, text, text, jsonb), public.acc_document_update(uuid, uuid, text, jsonb), public.acc_document_decide(uuid, uuid, text, boolean, boolean),
  public.acc_state(uuid), public.acc_vat_summary(uuid, date, date), public.acc_export(uuid, date, date);
drop trigger if exists autopilot_limits_check on private.autopilot_runs;
drop trigger if exists autopilot_budget_cap_check on private.autopilot_budgets;
drop table if exists private.ai_goals, private.ai_chat, private.ai_actions, private.ai_jobs, private.ai_schedules, private.ai_kinds, private.acc_documents, private.acc_settings, private.autopilot_plan_caps cascade;
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
drop function if exists private.autopilot_reserve_impl(uuid, uuid, text, text, integer, integer, text), private.ap_plan(uuid), private.autopilot_budget_cap_check(), private.autopilot_limits_check(),
  private.ai_fail(text, text), private.ai_hash(jsonb), private.ai_member_role_of(uuid, uuid), private.ai_writable_company(uuid), private.ai_next_run(text, timestamptz),
  private.ai_action_clean(uuid, text, jsonb), private.ai_context_impl(uuid, text), private.ai_goal_value(uuid, text, date), private.acc_doc_clean(jsonb), private.acc_dedupe_key(jsonb);
alter table private.autopilot_budgets drop column if exists per_user_monthly_nusd, drop column if exists per_run_max_nusd;
delete from private.autopilot_events where operation in ('job', 'action', 'schedule');
alter table private.autopilot_events drop constraint if exists autopilot_events_operation_check;
alter table private.autopilot_events add constraint autopilot_events_operation_check check (operation in ('set_budget', 'reserve', 'settle', 'expire'));
notify pgrst, 'reload schema';
