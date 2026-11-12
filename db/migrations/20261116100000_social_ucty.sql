-- Propojení sociálních sítí (Facebook stránky, Instagram profesionální účty) a publikace schválených příspěvků.
-- Závislosti (už v produkci): 20261107120000_profil_firmy (private.profile_actor), 20261112100000_ai_marketing (mkt_items, mkt_hash, mkt_fail).
-- Zásady:
--  * přístupový token ukládá jen server, a to ZAŠIFROVANÝ (AES-GCM, klíč je jen v prostředí Cloudflare); databáze klíč nezná a klient token nikdy nedostane
--  * publikaci zahajuje jen člověk (vlastník/správce) svým tokenem; server může dokončit jen publikaci, kterou člověk zahájil
--  * publikuje se pouze text, který je právě schválený (otisk schválení = otisk aktuálního textu)
--  * každý příspěvek jde na jeden účet nejvýš jednou (opakované kliknutí nic znovu nezveřejní)
-- Návrat: 20261116100000_social_ucty_rollback.sql

create table if not exists private.social_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  provider text not null check (provider in ('facebook', 'instagram')),
  external_id text not null check (external_id ~ '^[0-9]{1,40}$'),
  name text not null check (char_length(name) between 1 and 200),
  username text check (username is null or char_length(username) <= 200),
  token_enc text not null check (char_length(token_enc) <= 4000),          -- prázdné po odpojení
  connected_by uuid not null,
  connected_at timestamptz not null default now(),
  disconnected_at timestamptz,
  last_used_at timestamptz,
  last_error text check (last_error is null or char_length(last_error) <= 300),
  unique (company_id, provider, external_id));
alter table private.social_accounts enable row level security;

create table if not exists private.social_oauth_states (
  state_hash text primary key check (state_hash ~ '^[0-9a-f]{64}$'),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '10 minutes',
  used_at timestamptz);
alter table private.social_oauth_states enable row level security;

create table if not exists private.social_publications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  post_id uuid not null references public.marketing_posts(id) on delete cascade,
  account_id uuid not null references private.social_accounts(id) on delete cascade,
  approved_hash text not null,
  image_url text check (image_url is null or (char_length(image_url) <= 1000 and image_url ~ '^https://[^[:space:]]+$')),
  status text not null default 'pending' check (status in ('pending', 'published', 'failed', 'unknown')),
  external_id text check (external_id is null or char_length(external_id) <= 100),
  permalink text check (permalink is null or (char_length(permalink) <= 1000 and permalink ~ '^https://[^[:space:]]+$')),
  error text check (error is null or char_length(error) <= 300),
  requested_by uuid not null,
  requested_at timestamptz not null default now(),
  finished_at timestamptz);
alter table private.social_publications enable row level security;
-- jeden příspěvek na jeden účet nejvýš jednou; „unknown“ (nejasný výsledek) blokuje, dokud ho člověk nevyřeší
create unique index if not exists social_pub_once on private.social_publications (post_id, account_id) where status in ('pending', 'published', 'unknown');
create index if not exists social_pub_company on private.social_publications (company_id, requested_at desc);

-- ---------- propojení (OAuth) ----------
-- Zahájení: člověk (vlastník/správce) si u serveru zaregistruje otisk náhodného stavu. Nejvýš 5 otevřených stavů na firmu.
create or replace function public.social_oauth_begin(cid uuid, p_state_hash text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true);
begin
  if p_state_hash is null or p_state_hash !~ '^[0-9a-f]{64}$' then perform private.mkt_fail('PT422', 'invalid_state'); end if;
  delete from private.social_oauth_states where expires_at < now() - interval '1 day';
  if (select count(*) from private.social_oauth_states s where s.company_id = cid and s.used_at is null and s.expires_at > now()) >= 5 then
    perform private.mkt_fail('PT429', 'too_many_attempts'); end if;
  insert into private.social_oauth_states (state_hash, company_id, user_id) values (p_state_hash, cid, uid);
  return jsonb_build_object('ok', true);
end $$;

-- Dokončení: jen server. Stav musí existovat, být platný a nepoužitý; použije se jednou (i při neúspěchu).
-- p_accounts: [{provider, external_id, name, username, token_enc}] – tokeny už zašifrované serverem.
create or replace function public.social_oauth_finish(p_state_hash text, p_accounts jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare s private.social_oauth_states; a jsonb; n int := 0;
begin
  update private.social_oauth_states set used_at = now() where state_hash = p_state_hash and used_at is null and expires_at > now() returning * into s;
  if s.state_hash is null then perform private.mkt_fail('PT412', 'invalid_state'); end if;
  if not exists (select 1 from public.company_members m where m.company_id = s.company_id and m.user_id = s.user_id and m.role in ('owner', 'admin')) then
    perform private.mkt_fail('PT403', 'forbidden'); end if;
  if jsonb_typeof(p_accounts) <> 'array' or jsonb_array_length(p_accounts) > 50 then perform private.mkt_fail('PT422', 'invalid_accounts'); end if;
  for a in select value from jsonb_array_elements(p_accounts) loop
    if coalesce(a->>'token_enc', '') = '' then perform private.mkt_fail('PT422', 'invalid_accounts'); end if;
    insert into private.social_accounts (company_id, provider, external_id, name, username, token_enc, connected_by)
      values (s.company_id, a->>'provider', a->>'external_id', left(a->>'name', 200), nullif(left(a->>'username', 200), ''), a->>'token_enc', s.user_id)
    on conflict (company_id, provider, external_id) do update set name = excluded.name, username = excluded.username, token_enc = excluded.token_enc,
      connected_by = excluded.connected_by, connected_at = now(), disconnected_at = null, last_error = null;
    n := n + 1;
  end loop;
  return jsonb_build_object('company_id', s.company_id, 'connected', n);
end $$;

-- Odpojení: token se z databáze smaže hned. (Oprávnění aplikace u Meta ruší uživatel ve svém účtu Facebook.)
create or replace function public.social_disconnect(cid uuid, p_account uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true);
begin
  update private.social_accounts set token_enc = '', disconnected_at = now(), last_error = null where id = p_account and company_id = cid and disconnected_at is null;
  if not found then perform private.mkt_fail('PT404', 'not_found'); end if;
  update private.social_publications set status = 'failed', error = 'disconnected', finished_at = now() where account_id = p_account and status = 'pending';
  return jsonb_build_object('ok', true);
end $$;

-- Stav pro uživatele firmy: účty (bez tokenů) a poslední publikace.
create or replace function public.social_state(cid uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, false);
begin
  return jsonb_build_object(
    'accounts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'provider', a.provider, 'name', a.name, 'username', a.username,
        'connected_at', a.connected_at, 'last_used_at', a.last_used_at, 'last_error', a.last_error) order by a.provider, a.name)
      from private.social_accounts a where a.company_id = cid and a.disconnected_at is null), '[]'::jsonb),
    'publications', coalesce((select jsonb_agg(x.j order by x.t desc) from (
        select jsonb_build_object('id', p.id, 'post_id', p.post_id, 'account_id', p.account_id, 'provider', a.provider, 'account', a.name, 'status', p.status,
          'permalink', p.permalink, 'error', p.error, 'requested_at', p.requested_at, 'finished_at', p.finished_at) j, p.requested_at t
        from private.social_publications p join private.social_accounts a on a.id = p.account_id
        where p.company_id = cid order by p.requested_at desc limit 100) x), '[]'::jsonb));
end $$;

-- ---------- publikace ----------
-- Zahájení: jen člověk. Kontroluje schválení přesně aktuálního textu, vlastnictví účtu a to, že příspěvek na tento účet ještě nešel.
create or replace function public.social_publish_begin(cid uuid, p_post uuid, p_account uuid, p_image_url text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); p public.marketing_posts; i private.mkt_items; a private.social_accounts; h text; pid uuid; ex private.social_publications;
begin
  select * into p from public.marketing_posts where id = p_post and company_id = cid for update;
  if p.id is null then perform private.mkt_fail('PT404', 'not_found'); end if;
  select * into i from private.mkt_items where post_id = p.id;
  h := private.mkt_hash(p.title, p.body, p.channel);
  if i.approved_hash is null or i.approved_hash <> h then perform private.mkt_fail('PT412', 'not_approved'); end if;
  select * into a from private.social_accounts where id = p_account and company_id = cid and disconnected_at is null;
  if a.id is null or a.token_enc = '' then perform private.mkt_fail('PT404', 'account_not_found'); end if;
  if p_image_url is not null and (char_length(p_image_url) > 1000 or p_image_url !~ '^https://[^[:space:]]+$') then perform private.mkt_fail('PT422', 'invalid_image_url'); end if;
  if a.provider = 'instagram' and p_image_url is null then perform private.mkt_fail('PT422', 'image_required'); end if;
  if char_length(p.body) > (case a.provider when 'instagram' then 2200 else 60000 end) then perform private.mkt_fail('PT422', 'text_too_long'); end if;
  -- rozpracovaná publikace starší 5 minut = server ji nedokončil a výsledek není známý
  update private.social_publications set status = 'unknown', error = 'timeout', finished_at = now()
    where post_id = p.id and account_id = a.id and status = 'pending' and requested_at < now() - interval '5 minutes';
  select * into ex from private.social_publications where post_id = p.id and account_id = a.id and status in ('pending', 'published', 'unknown') limit 1;
  if ex.status = 'published' then perform private.mkt_fail('PT409', 'already_published'); end if;
  if ex.status = 'pending' then perform private.mkt_fail('PT409', 'in_progress'); end if;
  if ex.status = 'unknown' then perform private.mkt_fail('PT409', 'unknown_outcome'); end if;
  insert into private.social_publications (company_id, post_id, account_id, approved_hash, image_url, requested_by)
    values (cid, p.id, a.id, h, case when a.provider = 'instagram' then p_image_url else null end, uid) returning id into pid;
  return jsonb_build_object('publication_id', pid, 'provider', a.provider, 'external_id', a.external_id, 'text', p.body, 'image_url', p_image_url);
end $$;

-- Nejasný výsledek vyřeší člověk poté, co se podíval na síť: buď příspěvek zveřejněný je (zadá odkaz), nebo není (půjde zkusit znovu).
create or replace function public.social_publish_resolve(cid uuid, p_pub uuid, p_published boolean, p_url text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.profile_actor(cid, true); x private.social_publications; a private.social_accounts;
begin
  select * into x from private.social_publications where id = p_pub and company_id = cid and status = 'unknown' for update;
  if x.id is null then perform private.mkt_fail('PT404', 'not_found'); end if;
  if p_url is not null and (char_length(p_url) > 1000 or p_url !~ '^https://[^[:space:]]+$') then perform private.mkt_fail('PT422', 'invalid_url'); end if;
  if not p_published then
    update private.social_publications set status = 'failed', error = 'resolved_not_published', finished_at = now() where id = x.id;
    return jsonb_build_object('status', 'failed');
  end if;
  select * into a from private.social_accounts where id = x.account_id;
  update private.social_publications set status = 'published', permalink = p_url, error = null, finished_at = now() where id = x.id;
  update private.mkt_items set published_channel = case a.provider when 'instagram' then 'Instagram' else 'Facebook' end, published_url = p_url,
    published_at = now(), published_by = uid, web_publish_on = null where post_id = x.post_id and approved_hash = x.approved_hash;
  update public.marketing_posts set status = 'done' where id = x.post_id;
  return jsonb_build_object('status', 'published');
end $$;

-- Jen server: zašifrovaný token pro rozpracovanou publikaci, kterou zahájil člověk.
create or replace function public.social_publish_token(p_pub uuid) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('token_enc', a.token_enc, 'provider', a.provider, 'external_id', a.external_id)
  from private.social_publications p join private.social_accounts a on a.id = p.account_id
  where p.id = p_pub and p.status = 'pending' and a.disconnected_at is null and a.token_enc <> '' $$;

-- Jen server: zápis výsledku. p_status: published | failed | unknown. Zveřejnění se propíše do evidence příspěvku.
create or replace function public.social_publish_finish(p_pub uuid, p_status text, p_external_id text default null, p_permalink text default null, p_error text default null, p_reauth boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x private.social_publications; a private.social_accounts; link text;
begin
  if p_status not in ('published', 'failed', 'unknown') then perform private.mkt_fail('PT422', 'invalid_status'); end if;
  select * into x from private.social_publications where id = p_pub and status = 'pending' for update;
  if x.id is null then perform private.mkt_fail('PT404', 'not_found'); end if;
  select * into a from private.social_accounts where id = x.account_id;
  link := case when p_permalink ~ '^https://[^[:space:]]+$' and char_length(p_permalink) <= 1000 then p_permalink else null end;
  update private.social_publications set status = p_status, external_id = left(p_external_id, 100), permalink = link, error = left(p_error, 300), finished_at = now() where id = x.id;
  update private.social_accounts set last_used_at = now(), last_error = case when p_status = 'published' then null when p_reauth then 'reauth' else left(p_error, 300) end where id = a.id;
  if p_status = 'published' then
    update private.mkt_items set published_channel = case a.provider when 'instagram' then 'Instagram' else 'Facebook' end, published_url = link,
      published_at = now(), published_by = x.requested_by, web_publish_on = null where post_id = x.post_id and approved_hash = x.approved_hash;
    update public.marketing_posts set status = 'done' where id = x.post_id;
  end if;
  return jsonb_build_object('status', p_status, 'post_id', x.post_id);
end $$;

-- ---------- práva ----------
revoke all on table private.social_accounts, private.social_oauth_states, private.social_publications from public, anon, authenticated;
revoke all on function public.social_oauth_begin(uuid, text), public.social_oauth_finish(text, jsonb), public.social_disconnect(uuid, uuid), public.social_state(uuid),
  public.social_publish_begin(uuid, uuid, uuid, text), public.social_publish_resolve(uuid, uuid, boolean, text), public.social_publish_token(uuid),
  public.social_publish_finish(uuid, text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.social_oauth_begin(uuid, text), public.social_disconnect(uuid, uuid), public.social_state(uuid),
  public.social_publish_begin(uuid, uuid, uuid, text), public.social_publish_resolve(uuid, uuid, boolean, text) to authenticated;
grant execute on function public.social_oauth_finish(text, jsonb), public.social_publish_token(uuid), public.social_publish_finish(uuid, text, text, text, text, boolean) to service_role;

notify pgrst, 'reload schema';
