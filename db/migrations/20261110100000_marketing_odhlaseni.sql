-- Marketingové e-maily „Novinky Vexaronet“: odhlášení bez přihlášení a jeho vynucení při každém odeslání (docs/PRAVNI_SOULAD.md, oblast 4).
-- NEAPLIKOVÁNO NA PRODUKCI. Nové objekty, stávající tabulky a funkce se nemění (newsletter_subscribers se jen čte).
-- § 7 zák. č. 480/2004 Sb.: zpráva označená jako obchodní sdělení, totožnost odesílatele, platná adresa pro odmítnutí v každé zprávě.
-- Token: 2 × UUIDv4 (≈244 bitů náhody), v DB jen jeho SHA-256; v odkazu není e-mail ani ID příjemce. Jeden token na zprávu a příjemce.
-- Odhlášení se kontroluje 3×: při výběru příjemců dávky, těsně před odesláním (marketing_send_allowed) a při zápisu výsledku.
begin;

create table if not exists private.marketing_suppressions (
  email_norm text primary key check (char_length(email_norm) between 3 and 254),
  list text not null default 'novinky',
  source text not null,
  unsubscribed_at timestamptz not null default now());
create table if not exists private.marketing_messages (
  id uuid primary key default gen_random_uuid(),
  list text not null default 'novinky' check (list = 'novinky'),
  subject text not null check (char_length(subject) between 3 and 150),
  body_text text not null check (char_length(body_text) between 10 and 20000),
  scheduled_at timestamptz not null default now(),
  status text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'canceled')),
  created_by uuid, created_at timestamptz not null default now(), finished_at timestamptz);
create table if not exists private.marketing_deliveries (
  message_id uuid not null references private.marketing_messages(id) on delete cascade,
  email_norm text not null,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  claimed_at timestamptz not null default now(),
  sent_at timestamptz, provider_id text, skipped text,
  primary key (message_id, email_norm));
alter table private.marketing_suppressions enable row level security;
alter table private.marketing_messages enable row level security;
alter table private.marketing_deliveries enable row level security;
revoke all on private.marketing_suppressions, private.marketing_messages, private.marketing_deliveries from public, anon, authenticated;

create or replace function private.mk_norm(e text) returns text language sql immutable set search_path = '' as $$ select lower(btrim(coalesce(e, ''))) $$;
create or replace function private.mk_hash(t text) returns text language sql immutable set search_path = '' as $$ select encode(sha256(convert_to(t, 'UTF8')), 'hex') $$;
create or replace function private.mk_suppressed(e text) returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from private.marketing_suppressions s where s.email_norm = private.mk_norm(e)) $$;

-- Odhlášení odkazem z e-mailu. Volá ho kdokoli s tokenem (bez přihlášení). Neprozrazuje adresu.
create or replace function public.marketing_unsubscribe(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare em text;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  select d.email_norm into em from private.marketing_deliveries d where d.token_hash = private.mk_hash(p_token);
  if em is null then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  insert into private.marketing_suppressions (email_norm, source) values (em, 'odkaz v e-mailu') on conflict (email_norm) do nothing;
  return jsonb_build_object('ok', true, 'list', 'Novinky Vexaronet');
end $$;

-- Naplánování zprávy: jen správce platformy (private.platform_admins).
create or replace function public.marketing_queue(p_subject text, p_body text, p_scheduled_at timestamptz default now()) returns uuid
language plpgsql security definer set search_path = '' as $$
declare nid uuid;
begin
  if auth.uid() is null or not exists (select 1 from private.platform_admins a where a.user_id = auth.uid()) then
    raise exception 'forbidden' using errcode = '42501'; end if;
  insert into private.marketing_messages (subject, body_text, scheduled_at, created_by) values (p_subject, p_body, coalesce(p_scheduled_at, now()), auth.uid()) returning id into nid;
  return nid;
end $$;

-- Dávka k odeslání (jen service_role, worker). Vybírá jen platné souhlasy, které nejsou odhlášené, a vrací jednorázové tokeny.
create or replace function public.marketing_claim(p_limit integer default 20) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare m private.marketing_messages; rec record; tok text; out jsonb := '[]'::jsonb;
begin
  perform pg_advisory_xact_lock(7302551);
  select * into m from private.marketing_messages where status in ('queued', 'sending') and scheduled_at <= now() order by scheduled_at, created_at limit 1 for update;
  if m.id is null then return jsonb_build_object('message', null, 'recipients', '[]'::jsonb); end if;
  update private.marketing_messages set status = 'sending' where id = m.id;
  for rec in
    select distinct private.mk_norm(n.email) as e from public.newsletter_subscribers n
    where n.consent and private.mk_norm(n.email) ~ '^[^@[:space:]]+@[^@[:space:]]+$'
      and not private.mk_suppressed(n.email)
      and not exists (select 1 from private.marketing_deliveries d where d.message_id = m.id and d.email_norm = private.mk_norm(n.email))
    order by 1 limit greatest(1, least(coalesce(p_limit, 20), 100))
  loop
    tok := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    insert into private.marketing_deliveries (message_id, email_norm, token_hash) values (m.id, rec.e, private.mk_hash(tok));
    out := out || jsonb_build_object('email', rec.e, 'token', tok);
  end loop;
  if jsonb_array_length(out) = 0 and not exists (select 1 from private.marketing_deliveries d where d.message_id = m.id and d.sent_at is null and d.skipped is null) then
    update private.marketing_messages set status = 'sent', finished_at = now() where id = m.id;
  end if;
  return jsonb_build_object('message', jsonb_build_object('id', m.id, 'subject', m.subject, 'body_text', m.body_text), 'recipients', out);
end $$;

-- Kontrola těsně před odesláním jedné zprávy (odhlášení mezi výběrem dávky a odesláním).
create or replace function public.marketing_send_allowed(p_message uuid, p_email text) returns boolean
language sql security definer set search_path = '' as $$
  select exists (select 1 from private.marketing_deliveries d join private.marketing_messages m on m.id = d.message_id
    where d.message_id = p_message and d.email_norm = private.mk_norm(p_email) and d.sent_at is null and d.skipped is null and m.status = 'sending')
  and not private.mk_suppressed(p_email)
  and exists (select 1 from public.newsletter_subscribers n where n.consent and private.mk_norm(n.email) = private.mk_norm(p_email)) $$;

create or replace function public.marketing_finish(p_message uuid, p_email text, p_provider_id text, p_skipped text default null) returns void
language sql security definer set search_path = '' as $$
  update private.marketing_deliveries set sent_at = case when p_skipped is null then now() end, provider_id = left(p_provider_id, 200), skipped = left(p_skipped, 200)
  where message_id = p_message and email_norm = private.mk_norm(p_email) and sent_at is null and skipped is null $$;

revoke all on function private.mk_norm(text), private.mk_hash(text), private.mk_suppressed(text) from public, anon, authenticated;
revoke all on function public.marketing_unsubscribe(text), public.marketing_queue(text, text, timestamptz), public.marketing_claim(integer),
  public.marketing_send_allowed(uuid, text), public.marketing_finish(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.marketing_unsubscribe(text) to anon, authenticated, service_role;
grant execute on function public.marketing_queue(text, text, timestamptz) to authenticated, service_role;
grant execute on function public.marketing_claim(integer), public.marketing_send_allowed(uuid, text), public.marketing_finish(uuid, text, text, text) to service_role;

notify pgrst, 'reload schema';
commit;
