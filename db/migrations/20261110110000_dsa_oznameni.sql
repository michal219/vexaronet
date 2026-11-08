-- Oznamování nezákonného obsahu podle čl. 16 a odůvodnění podle čl. 17 nařízení (EU) 2022/2065 (DSA). Viz docs/PRAVNI_SOULAD.md, oblast 6.
-- NEAPLIKOVÁNO NA PRODUKCI. Jen nové objekty. Nic se neodstraňuje automaticky: rozhodnutí zapisuje člověk (správce platformy)
-- a samotné omezení obsahu provádí ručně podle rozhodnutí; evidence (dsa_events) je jen pro připisování.
begin;

create table if not exists private.dsa_notices (
  id uuid primary key default gen_random_uuid(),
  ref text not null unique,
  created_at timestamptz not null default now(),
  content_urls text[] not null check (cardinality(content_urls) between 1 and 10),
  location_details text check (location_details is null or char_length(location_details) <= 2000),
  category text not null check (category in ('csam','terorismus','nenavist','podvod','dusevni_vlastnictvi','osobni_udaje','nebezpecne_zbozi','spotrebitel','jine')),
  explanation text not null check (char_length(explanation) between 30 and 5000),
  notifier_name text check (notifier_name is null or char_length(notifier_name) between 2 and 200),
  notifier_email text check (notifier_email is null or (char_length(notifier_email) <= 254 and notifier_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  good_faith boolean not null check (good_faith),
  target_kind text check (target_kind in ('web','obchod','rezervace','jine')),
  target_slug text,
  target_company_id uuid,
  status text not null default 'received' check (status in ('received','in_review','decided')),
  decision text check (decision in ('bez_opatreni','odstraneni','znepristupneni','omezeni_viditelnosti','pozastaveni_sluzby','predano_organum')),
  decision_ground text check (decision_ground in ('nezakonny_obsah','smluvni_podminky','neodpovida')),
  decision_reason text check (decision_reason is null or char_length(decision_reason) between 20 and 5000),
  decided_at timestamptz, decided_by uuid,
  ack_sent_at timestamptz, notifier_informed_at timestamptz, uploader_informed_at timestamptz,
  ip_hash text check (ip_hash is null or ip_hash ~ '^[0-9a-f]{64}$'),
  -- jméno a e-mail smí chybět jen u oznámení obsahu sexuálního zneužívání dětí (čl. 16 odst. 2 písm. c) DSA)
  constraint dsa_notifier_identity check (category = 'csam' or (notifier_name is not null and notifier_email is not null)));
create table if not exists private.dsa_events (
  id bigint generated always as identity primary key,
  notice_id uuid not null references private.dsa_notices(id),
  at timestamptz not null default now(),
  actor uuid,
  event text not null check (event in ('prijato','potvrzeni_odeslano','v_posouzeni','rozhodnuto','oznamovatel_vyrozumen','poskytovatel_obsahu_vyrozumen','poznamka')),
  detail jsonb not null default '{}'::jsonb);
alter table private.dsa_notices enable row level security;
alter table private.dsa_events enable row level security;
revoke all on private.dsa_notices, private.dsa_events from public, anon, authenticated;

-- evidence se nesmí přepisovat ani mazat (ani přes funkce)
create or replace function private.dsa_events_append_only() returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'Záznamy evidence DSA nelze měnit ani mazat.'; end $$;
drop trigger if exists dsa_events_no_change on private.dsa_events;
create trigger dsa_events_no_change before update or delete on private.dsa_events for each row execute function private.dsa_events_append_only();

create or replace function private.dsa_is_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from private.platform_admins a where a.user_id = auth.uid()) $$;

-- Přijetí oznámení (jen service_role: Cloudflare funkce /api/dsa-notice, která počítá otisk IP a posílá potvrzení).
create or replace function public.dsa_submit(doc jsonb, p_ip_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare urls text[]; u text; nid uuid; r text; cat text := doc->>'category'; tk text; ts text; tc uuid;
begin
  perform pg_advisory_xact_lock(7302661);
  if p_ip_hash is not null and (select count(*) from private.dsa_notices where ip_hash = p_ip_hash and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'too_many' using errcode = 'P0001'; end if;
  if (select count(*) from private.dsa_notices where created_at > now() - interval '1 day') >= 500 then raise exception 'too_many' using errcode = 'P0001'; end if;
  select array_agg(btrim(x)) into urls from jsonb_array_elements_text(coalesce(doc->'urls', '[]'::jsonb)) x where btrim(x) <> '';
  if urls is null or cardinality(urls) = 0 then raise exception 'url_required' using errcode = 'P0001'; end if;
  foreach u in array urls loop
    if char_length(u) > 2000 or u !~ '^https?://[^[:space:]]+$' then raise exception 'url_invalid' using errcode = 'P0001'; end if;
  end loop;
  -- přiřazení k obsahu firmy podle adresy na vexaronet.com (?w= web, ?s= obchod, ?r= rezervace)
  tk := case when urls[1] ~* '^https://(www\.)?vexaronet\.com/.*[?&]w=' then 'web' when urls[1] ~* '^https://(www\.)?vexaronet\.com/.*[?&]s=' then 'obchod'
             when urls[1] ~* '^https://(www\.)?vexaronet\.com/.*[?&]r=' then 'rezervace' else 'jine' end;
  ts := lower(substring(urls[1] from '[?&][wsr]=([A-Za-z0-9-]{3,41})'));
  if tk = 'web' then select company_id into tc from public.sites where slug = ts;
  elsif tk = 'obchod' then select company_id into tc from public.shop_settings where slug = ts;
  elsif tk = 'rezervace' then select company_id into tc from public.booking_profiles where slug = ts; end if;
  r := 'DSA-' || to_char(now() at time zone 'Europe/Prague', 'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  insert into private.dsa_notices (ref, content_urls, location_details, category, explanation, notifier_name, notifier_email, good_faith, target_kind, target_slug, target_company_id, ip_hash)
  values (r, urls, nullif(btrim(doc->>'details'), ''), cat, btrim(coalesce(doc->>'explanation', '')), nullif(btrim(doc->>'name'), ''), nullif(lower(btrim(doc->>'email')), ''),
          coalesce((doc->>'good_faith')::boolean, false), tk, ts, tc, p_ip_hash)
  returning id into nid;
  insert into private.dsa_events (notice_id, event, detail) values (nid, 'prijato', jsonb_build_object('kategorie', cat, 'pocet_url', cardinality(urls)));
  return jsonb_build_object('id', nid, 'ref', r);
end $$;

create or replace function public.dsa_mark(p_id uuid, p_event text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_event not in ('potvrzeni_odeslano', 'oznamovatel_vyrozumen', 'poskytovatel_obsahu_vyrozumen') then raise exception 'invalid_event'; end if;
  if auth.role() is distinct from 'service_role' and not private.dsa_is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  update private.dsa_notices set ack_sent_at = case when p_event = 'potvrzeni_odeslano' then now() else ack_sent_at end,
    notifier_informed_at = case when p_event = 'oznamovatel_vyrozumen' then now() else notifier_informed_at end,
    uploader_informed_at = case when p_event = 'poskytovatel_obsahu_vyrozumen' then now() else uploader_informed_at end where id = p_id;
  insert into private.dsa_events (notice_id, actor, event) values (p_id, auth.uid(), p_event);
end $$;

-- Správce platformy: přehled a rozhodnutí.
create or replace function public.dsa_admin_list(p_status text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not private.dsa_is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(n) - 'ip_hash' || jsonb_build_object('events',
      (select jsonb_agg(jsonb_build_object('at', e.at, 'event', e.event, 'detail', e.detail) order by e.id) from private.dsa_events e where e.notice_id = n.id))
    order by n.created_at desc) from private.dsa_notices n where p_status is null or n.status = p_status), '[]'::jsonb);
end $$;

create or replace function public.dsa_admin_decide(p_id uuid, p_decision text, p_ground text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n private.dsa_notices; owners jsonb;
begin
  if not private.dsa_is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 20 then raise exception 'reason_required' using errcode = 'P0001'; end if;
  if p_decision = 'bez_opatreni' and p_ground <> 'neodpovida' then raise exception 'ground_mismatch' using errcode = 'P0001'; end if;
  if p_decision <> 'bez_opatreni' and p_ground not in ('nezakonny_obsah', 'smluvni_podminky') then raise exception 'ground_mismatch' using errcode = 'P0001'; end if;
  select * into n from private.dsa_notices where id = p_id for update;
  if n.id is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  if n.status = 'decided' then raise exception 'already_decided' using errcode = 'P0001'; end if;
  update private.dsa_notices set status = 'decided', decision = p_decision, decision_ground = p_ground, decision_reason = btrim(p_reason), decided_at = now(), decided_by = auth.uid() where id = p_id;
  insert into private.dsa_events (notice_id, actor, event, detail) values (p_id, auth.uid(), 'rozhodnuto', jsonb_build_object('rozhodnuti', p_decision, 'duvod', p_ground));
  return jsonb_build_object('ref', n.ref, 'urls', n.content_urls, 'notifier_email', n.notifier_email, 'target_company_id', n.target_company_id,
    'decision', p_decision, 'ground', p_ground, 'reason', btrim(p_reason));
end $$;

create or replace function public.dsa_admin_review(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.dsa_is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  update private.dsa_notices set status = 'in_review' where id = p_id and status = 'received';
  if found then insert into private.dsa_events (notice_id, actor, event) values (p_id, auth.uid(), 'v_posouzeni'); end if;
end $$;

revoke all on function private.dsa_events_append_only(), private.dsa_is_admin() from public, anon, authenticated;
revoke all on function public.dsa_submit(jsonb, text), public.dsa_mark(uuid, text), public.dsa_admin_list(text), public.dsa_admin_decide(uuid, text, text, text), public.dsa_admin_review(uuid) from public, anon, authenticated;
grant execute on function public.dsa_submit(jsonb, text) to service_role;
grant execute on function public.dsa_mark(uuid, text) to authenticated, service_role;
grant execute on function public.dsa_admin_list(text), public.dsa_admin_decide(uuid, text, text, text), public.dsa_admin_review(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
