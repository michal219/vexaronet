-- =====================================================================================
-- Vexaronet – SNAPSHOT jádra databáze (firmy, členství, předplatné, firemní profil, AI limity)
-- Zdroj: živý Supabase projekt micymdbqgzeckiqyvvkn (PostgreSQL 17), stav k 2026-11-07.
-- Získáno POUZE čtením systémového katalogu (pg_catalog, information_schema, pg_policies,
-- pg_get_functiondef). Neobsahuje žádná zákaznická data ani tajemství.
--
-- STAV: DOKUMENTACE, NIKOLI OTESTOVANÁ OBNOVOVACÍ MIGRACE.
--   * Obnova z tohoto souboru nebyla ověřena v oddělené testovací databázi.
--   * Soubor pokrývá jen objekty potřebné pro onboarding (viz README.md). Celá DB má ve schématech public a private
--     100 tabulek a 193 funkcí; ostatní jsou jen v manifestu (otisky md5).
--   * Pořadí příkazů neřeší všechny závislosti (např. FK na customers/jobs, auth.users).
--   * Práva EXECUTE u funkcí jsou zapsaná jako komentář (zjištěno has_function_privilege),
--     ne jako přesné GRANT/REVOKE.
--
-- Pojistka: soubor se při spuštění okamžitě zastaví.
do $$ begin raise exception 'Snapshot je dokumentace, nespouštět. Viz db/snapshot/README.md'; end $$;
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- SCHÉMATA A PRÁVA NA SCHÉMATA (ověřeno has_schema_privilege)
--   public:  anon USAGE = ano, authenticated USAGE = ano
--   private: anon USAGE = ne,  authenticated USAGE = ano
-- Rozšíření: plpgsql, pg_stat_statements, uuid-ossp, pgcrypto, supabase_vault, btree_gist,
--            pg_cron, pg_net, pg_jsonschema (jsonb_matches_schema se používá v companies)
-- -------------------------------------------------------------------------------------


-- =====================================================================================
-- TABULKY
-- =====================================================================================

-- ---- public.companies ---------------------------------------------------------------
-- Firma. Pobočka = řádek s parent_company_id. Jeden vlastník smí mít jen jednu hlavní firmu.
create table public.companies (
  id uuid not null default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,
  industry text not null default 'Služby'::text,
  auto_task boolean not null default false,
  created_at timestamp with time zone not null default now(),
  parent_company_id uuid,
  branch_address text not null default ''::text,
  country text not null default 'CZ'::text,
  currency text not null default 'CZK'::text,
  workspace_config jsonb not null default '{"industries": [], "hiddenModules": []}'::jsonb,
  constraint companies_pkey primary key (id),
  constraint companies_owner_id_fkey foreign key (owner_id) references auth.users(id),
  constraint companies_parent_company_id_fkey foreign key (parent_company_id) references public.companies(id),
  constraint companies_name_check check (((length(name) >= 2) and (length(name) <= 120))),
  constraint companies_branch_address_check check ((length(branch_address) <= 500)),
  constraint companies_currency_check check ((currency = any (array['CZK'::text, 'EUR'::text]))),
  constraint companies_country_check check ((country = any (array['AT'::text, 'BE'::text, 'BG'::text, 'HR'::text, 'CY'::text, 'CZ'::text, 'DK'::text, 'EE'::text, 'FI'::text, 'FR'::text, 'DE'::text, 'GR'::text, 'HU'::text, 'IE'::text, 'IT'::text, 'LV'::text, 'LT'::text, 'LU'::text, 'MT'::text, 'NL'::text, 'PL'::text, 'PT'::text, 'RO'::text, 'SK'::text, 'SI'::text, 'ES'::text, 'SE'::text]))),
  constraint workspace_config_shape check (jsonb_matches_schema('{"type":"object","additionalProperties":false,"required":["industries","hiddenModules"],"properties":{"industries":{"type":"array","maxItems":10,"uniqueItems":true,"items":{"type":"string","minLength":2,"maxLength":120}},"hiddenModules":{"type":"array","maxItems":24,"uniqueItems":true,"items":{"enum":["customers","jobs","tasks","reservations","financial_entries","team","automation","ai","invoices","business_website","shop","inventory","campaigns","business_email","analytics","processes","custom_apps","booking_settings","business_branches","customer_care","business_reports","backups"]}}}}'::json, workspace_config))
);
create index companies_parent_idx on public.companies using btree (parent_company_id);
create unique index one_trial_per_owner on public.companies using btree (owner_id) where (parent_company_id is null);
alter table public.companies enable row level security;
create policy members_read on public.companies for select to authenticated
  using ((private.member_role(id) is not null));
-- Pozn.: politika existuje, ale authenticated NEMÁ právo UPDATE na tabulku -> politika se neuplatní.
create policy company_edit on public.companies for update to authenticated
  using (((private.member_role(id) = any (array['owner'::text, 'admin'::text])) and private.writable(id)))
  with check (((private.member_role(id) = any (array['owner'::text, 'admin'::text])) and private.writable(id)));
-- Práva: authenticated SELECT; anon žádná.
create trigger branch_preferences_inherit before insert on public.companies
  for each row execute function private.branch_preferences_inherit();

-- ---- public.company_members ---------------------------------------------------------
create table public.company_members (
  company_id uuid not null,
  user_id uuid not null,
  role text not null,
  display_name text not null default ''::text,
  constraint company_members_pkey primary key (company_id, user_id),
  constraint company_members_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade,
  constraint company_members_user_id_fkey foreign key (user_id) references auth.users(id) on delete cascade,
  constraint company_members_role_check check ((role = any (array['owner'::text, 'admin'::text, 'employee'::text])))
);
create index company_members_user_id_idx on public.company_members using btree (user_id);
alter table public.company_members enable row level security;
create policy team_read on public.company_members for select to authenticated
  using ((private.member_role(company_id) is not null));
create policy own_display_name on public.company_members for update to authenticated
  using ((user_id = ( select auth.uid() as uid)))
  with check ((user_id = ( select auth.uid() as uid)));
-- Práva: authenticated SELECT; anon žádná. Vkládání/mazání jen přes SECURITY DEFINER funkce.
create trigger audit after insert or update on public.company_members
  for each row execute function private.log_change();
create trigger capacity before insert on public.company_members
  for each row execute function private.enforce_team_capacity();

-- ---- public.subscriptions -----------------------------------------------------------
create table public.subscriptions (
  company_id uuid not null,
  plan text not null default 'business'::text,
  status text not null default 'trial'::text,
  trial_start timestamp with time zone not null default now(),
  trial_end timestamp with time zone default (now() + '30 days'::interval),
  paid_until timestamp with time zone,
  constraint subscriptions_pkey primary key (company_id),
  constraint subscriptions_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade,
  constraint subscriptions_plan_check check ((plan = any (array['start'::text, 'accountant'::text, 'pro'::text, 'business'::text, 'enterprise'::text]))) not valid,
  constraint subscriptions_status_check check ((status = any (array['trial'::text, 'active'::text, 'past_due'::text, 'expired'::text, 'canceled'::text])))
);
alter table public.subscriptions enable row level security;
create policy sub_read on public.subscriptions for select to authenticated
  using ((private.member_role(company_id) is not null));
-- Práva: authenticated SELECT; anon žádná.
create trigger sync_branch_subscription after update on public.subscriptions
  for each row execute function private.sync_branch_subscription();

-- ---- public.user_business_profiles --------------------------------------------------
-- Fakturační údaje DODAVATELE. Navzdory názvu je klíčem company_id (= společné pro firmu).
create table public.user_business_profiles (
  company_id uuid not null,
  legal_name text not null default ''::text,
  ico text not null default ''::text,
  dic text not null default ''::text,
  address_text text not null default ''::text,
  registration_text text not null default ''::text,
  vat_payer boolean not null default false,
  bank_account text not null default ''::text,
  iban text not null default ''::text,
  email text not null default ''::text,
  logo_data_url text not null default ''::text,
  default_due_days integer not null default 14,
  updated_at timestamp with time zone not null default now(),
  country_code text not null default 'CZ'::text,
  tax_id text not null default ''::text,
  invoice_language text not null default 'cs'::text,
  default_currency text not null default 'CZK'::text,
  constraint user_business_profiles_pkey primary key (company_id),
  constraint user_business_profiles_company_id_fkey foreign key (company_id) references public.companies(id),
  constraint user_business_profiles_country_code_check check ((country_code = any (array['CZ'::text, 'SK'::text]))),
  constraint user_business_profiles_default_currency_check check ((default_currency = any (array['CZK'::text, 'EUR'::text]))),
  constraint user_business_profiles_default_due_days_check check (((default_due_days >= 0) and (default_due_days <= 90))),
  constraint user_business_profiles_invoice_language_check check ((invoice_language = any (array['cs'::text, 'sk'::text, 'en'::text]))),
  constraint user_business_profiles_logo_data_url_check check ((length(logo_data_url) <= 240000)),
  constraint user_business_profiles_tax_id_check check ((length(tax_id) <= 30))
);
alter table public.user_business_profiles enable row level security;
create policy invoice_manager_read on public.user_business_profiles for select to authenticated
  using ((private.member_role(company_id) = any (array['owner'::text, 'admin'::text])));
-- Práva: authenticated SELECT; anon žádná. Zápis jen přes public.invoice_action(cid,'profile',doc).
create trigger invoice_profile_check before insert or update on public.user_business_profiles
  for each row execute function private.invoice_profile_check();

-- ---- public.public_profiles (veřejný profil firmy, zveřejnění jen Pro/Business) ------
create table public.public_profiles (
  company_id uuid not null,
  slug text not null,
  name text not null,
  description text not null default ''::text,
  services text not null default ''::text,
  city text not null default ''::text,
  email text not null default ''::text,
  phone text not null default ''::text,
  website text not null default ''::text,
  opening_hours text not null default ''::text,
  published boolean not null default false,
  constraint public_profiles_pkey primary key (company_id),
  constraint public_profiles_company_id_fkey foreign key (company_id) references public.companies(id),
  constraint public_profiles_slug_key unique (slug),
  constraint public_profiles_slug_check check ((slug ~ '^[a-z0-9][a-z0-9-]{1,80}$'::text)),
  constraint public_profiles_website_check check (((website = ''::text) or (website ~ '^https://'::text)))
);
alter table public.public_profiles enable row level security;
create policy tenant_read on public.public_profiles for select to authenticated using ((private.member_role(company_id) is not null));
create policy published_read on public.public_profiles for select to anon using ((published and private.public_profile_allowed(company_id)));
create policy manager_insert on public.public_profiles for insert to authenticated
  with check (((private.member_role(company_id) = any (array['owner'::text, 'admin'::text])) and private.writable(company_id)));
create policy manager_update on public.public_profiles for update to authenticated
  using (((private.member_role(company_id) = any (array['owner'::text, 'admin'::text])) and private.writable(company_id)))
  with check (((private.member_role(company_id) = any (array['owner'::text, 'admin'::text])) and private.writable(company_id)));
-- Práva: anon SELECT; authenticated INSERT, SELECT, UPDATE.
-- Trigger private.profile_plan_guard existuje jako funkce; navázání triggeru na tuto tabulku nebylo v dotazu zahrnuto.

-- ---- public.profiles (osobní profil uživatele) ---------------------------------------
create table public.profiles (
  id uuid not null,
  full_name text not null default ''::text,
  created_at timestamp with time zone not null default now(),
  constraint profiles_pkey primary key (id),
  constraint profiles_id_fkey foreign key (id) references auth.users(id) on delete cascade
);
alter table public.profiles enable row level security;
create policy self_read on public.profiles for select to authenticated using ((id = ( select auth.uid() as uid)));
create policy self_update on public.profiles for update to authenticated
  using ((id = ( select auth.uid() as uid))) with check ((id = ( select auth.uid() as uid)));
-- Práva: authenticated SELECT (UPDATE grant chybí -> politika self_update se neuplatní).

-- ---- public.user_preferences (osobní nastavení uživatele) ----------------------------
create table public.user_preferences (
  user_id uuid not null,
  language text not null default 'cs'::text,
  theme text not null default 'dark'::text,
  country text not null default 'CZ'::text,
  currency text not null default 'CZK'::text,
  constraint user_preferences_pkey primary key (user_id),
  constraint user_preferences_user_id_fkey foreign key (user_id) references auth.users(id) on delete cascade,
  constraint user_preferences_language_check check ((language = any (array['cs'::text, 'sk'::text, 'en'::text]))),
  constraint user_preferences_theme_check check ((theme = any (array['light'::text, 'dark'::text]))),
  constraint user_preferences_currency_check check ((currency = any (array['CZK'::text, 'EUR'::text]))),
  constraint user_preferences_country_check check ((country = any (array['AT'::text, 'BE'::text, 'BG'::text, 'HR'::text, 'CY'::text, 'CZ'::text, 'DK'::text, 'EE'::text, 'FI'::text, 'FR'::text, 'DE'::text, 'GR'::text, 'HU'::text, 'IE'::text, 'IT'::text, 'LV'::text, 'LT'::text, 'LU'::text, 'MT'::text, 'NL'::text, 'PL'::text, 'PT'::text, 'RO'::text, 'SK'::text, 'SI'::text, 'ES'::text, 'SE'::text])))
);
alter table public.user_preferences enable row level security;
create policy own_preferences on public.user_preferences for all to authenticated
  using ((user_id = ( select auth.uid() as uid))) with check ((user_id = ( select auth.uid() as uid)));
-- Práva: authenticated INSERT, SELECT, UPDATE.

-- ---- public.company_invites (pozvánky e-mailem, používá aplikace z repozitáře) -------
create table public.company_invites (
  id uuid not null default gen_random_uuid(),
  company_id uuid not null,
  email text not null,
  role text not null default 'employee'::text,
  invited_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  accepted_at timestamp with time zone,
  constraint company_invites_pkey primary key (id),
  constraint company_invites_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade,
  constraint company_invites_role_check check ((role = any (array['admin'::text, 'employee'::text])))
);
create unique index company_invites_open_uniq on public.company_invites using btree (company_id, lower(email)) where (accepted_at is null);
alter table public.company_invites enable row level security;
create policy invites_select on public.company_invites for select to authenticated
  using ((exists ( select 1 from public.company_members m
     where ((m.company_id = company_invites.company_id) and (m.user_id = auth.uid()) and (m.role = any (array['owner'::text, 'admin'::text]))))));
-- Práva: anon i authenticated VŠECHNA (vč. DELETE, UPDATE, TRUNCATE). DML omezuje RLS.
-- Pozn.: existuje i druhá tabulka pozvánek public.invitations (s tokenem), aplikace z repozitáře ji nepoužívá.

-- ---- public.plan_requests (žádosti o změnu tarifu) -----------------------------------
create table public.plan_requests (
  id uuid not null default gen_random_uuid(),
  company_id uuid not null,
  user_id uuid not null default auth.uid(),
  current_plan text,
  requested_plan text not null,
  note text,
  status text not null default 'new'::text,
  created_at timestamp with time zone not null default now(),
  constraint plan_requests_pkey primary key (id),
  constraint plan_requests_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
alter table public.plan_requests enable row level security;
create policy "members create plan requests" on public.plan_requests for insert to authenticated
  with check (((user_id = auth.uid()) and (exists ( select 1 from public.company_members m
    where ((m.company_id = plan_requests.company_id) and (m.user_id = auth.uid()))))));
create policy "members read plan requests" on public.plan_requests for select to authenticated
  using ((exists ( select 1 from public.company_members m
    where ((m.company_id = plan_requests.company_id) and (m.user_id = auth.uid())))));
-- Práva: anon i authenticated VŠECHNA. DML omezuje RLS.

-- ---- public.ai_usage (počítadlo dokladů AI Účetní; používá functions/api/accountant.js)
create table public.ai_usage (
  id uuid not null default gen_random_uuid(),
  company_id uuid not null,
  kind text not null default 'doc'::text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  constraint ai_usage_pkey primary key (id),
  constraint ai_usage_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
create index ai_usage_company_month on public.ai_usage using btree (company_id, kind, created_at);
alter table public.ai_usage enable row level security;
create policy ai_usage_select on public.ai_usage for select to authenticated
  using ((exists ( select 1 from public.company_members m where ((m.company_id = ai_usage.company_id) and (m.user_id = auth.uid())))));
create policy ai_usage_insert on public.ai_usage for insert to authenticated
  with check ((exists ( select 1 from public.company_members m where ((m.company_id = ai_usage.company_id) and (m.user_id = auth.uid())))));
-- Práva: anon i authenticated VŠECHNA. DML omezuje RLS.

-- ---- private.registration_acceptance (souhlas s podmínkami) --------------------------
create table private.registration_acceptance (
  user_id uuid not null,
  version text not null,
  accepted_at timestamp with time zone not null default now(),
  constraint registration_acceptance_pkey primary key (user_id),
  constraint registration_acceptance_user_id_fkey foreign key (user_id) references auth.users(id) on delete cascade
);
alter table private.registration_acceptance enable row level security;   -- bez politik
-- Práva: anon ani authenticated žádná.

-- ---- private.ai_requests (serverové počítadlo AI požadavků pro public.reserve_ai) -----
create table private.ai_requests (
  id uuid not null default gen_random_uuid(),
  company_id uuid not null,
  user_id uuid not null,
  created_at timestamp with time zone not null default now(),
  constraint ai_requests_pkey primary key (id),
  constraint ai_requests_company_id_fkey foreign key (company_id) references public.companies(id),
  constraint ai_requests_user_id_fkey foreign key (user_id) references auth.users(id)
);
create index ai_requests_company_id_created_at_idx on private.ai_requests using btree (company_id, created_at);
create index ai_requests_created_at_idx on private.ai_requests using btree (created_at);
-- RLS VYPNUTÉ. Práva: anon ani authenticated žádná (proto přes API nedostupné).

-- ---- private.platform_admins ---------------------------------------------------------
create table private.platform_admins (
  user_id uuid not null,
  constraint platform_admins_pkey primary key (user_id),
  constraint platform_admins_user_id_fkey foreign key (user_id) references auth.users(id)
);
-- RLS VYPNUTÉ. Práva: anon ani authenticated žádná.

-- ---- auth.users: vlastní trigger projektu ---------------------------------------------
create trigger vexaronet_welcome_registration after insert or update of email_confirmed_at on auth.users
  for each row execute function private.enqueue_welcome_mail();


-- =====================================================================================
-- FUNKCE (doslovně z pg_get_functiondef; konce řádků CRLF převedeny na LF)
-- Ve sloupci "exec" je, kdo smí funkci volat (anon / authenticated).
-- =====================================================================================

-- exec: authenticated
CREATE OR REPLACE FUNCTION private.member_role(cid uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select m.role from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and auth.uid() is not null $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION private.writable(cid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select auth.uid() is not null and exists(select 1 from public.subscriptions s where s.company_id=cid and ((s.status='trial' and s.trial_end>now()) or (s.status='active' and (s.paid_until>now() or s.plan='start'))))$function$;

-- exec: nikdo z anon/authenticated
CREATE OR REPLACE FUNCTION private.business_root(cid uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select coalesce(parent_company_id,id) from public.companies where id=cid$function$;

-- exec: nikdo z anon/authenticated
CREATE OR REPLACE FUNCTION private.suite_plan(cid uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select s.plan from public.subscriptions s where s.company_id=private.business_root(cid)$function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION private.create_company_core(company_name text, company_industry text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare cid uuid; begin
if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Ověřte svůj e-mail'; end if;
if exists(select 1 from public.company_members where user_id=auth.uid()) then raise exception 'Již jste členem firmy'; end if;
insert into public.profiles(id,full_name) values(auth.uid(),'') on conflict do nothing;
insert into public.companies(owner_id,name,industry) values(auth.uid(),trim(company_name),company_industry) returning id into cid;
insert into public.company_members(company_id,user_id,role,display_name) values(cid,auth.uid(),'owner','Vlastník');
insert into public.subscriptions(company_id) values(cid);
return cid; end $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION private.create_company_for_plan(company_name text, company_industry text, selected_plan text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid;
begin
 if selected_plan is null or selected_plan not in ('start','pro','business','enterprise') then raise exception 'Vyberte platný tarif.';end if;
 cid:=private.create_company_core(company_name,company_industry);
 perform private.choose_trial_plan(cid,selected_plan);
 return cid;
end $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.create_company_for_plan(company_name text, company_industry text, selected_plan text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.create_company_for_plan(company_name,company_industry,selected_plan)$function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.create_company(company_name text, company_industry text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.create_company_core(company_name,company_industry)$function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION private.choose_trial_plan(cid uuid, selected_plan text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare subscription public.subscriptions;
begin
 if auth.uid() is null or private.member_role(cid) is distinct from 'owner' or private.business_root(cid) is distinct from cid then raise exception 'Tarif zkušební verze mění vlastník hlavní firmy.';end if;
 if selected_plan is null or selected_plan not in ('start','pro','business','enterprise') then raise exception 'Vyberte platný tarif.';end if;
 perform pg_advisory_xact_lock(hashtextextended(cid::text,991));
 select * into subscription from public.subscriptions where company_id=cid for update;
 if subscription.company_id is null or subscription.status<>'trial' or subscription.trial_end<=now() then raise exception 'Změna je dostupná pouze během aktivního zkušebního období.';end if;
 if selected_plan<>subscription.plan and exists(select 1 from public.companies where parent_company_id=cid) then raise exception 'Firma má další provozovny. Změnu tarifu nejprve vyřešte s podporou.';end if;
 if selected_plan='start' then
  update public.subscriptions set plan='start', status='active', trial_end=null where company_id=cid;
 else
  update public.subscriptions set plan=selected_plan, trial_end=subscription.trial_start + interval '30 days' where company_id=cid;
 end if;
 return selected_plan;
end $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.choose_trial_plan(cid uuid, selected_plan text)
 RETURNS text
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.choose_trial_plan(cid,selected_plan)$function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION private.record_registration_acceptance(version text, accepted boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
if auth.uid() is null or version<>'beta-2026-10-18' or accepted is distinct from true then raise exception 'Accept the current terms to continue.';end if;
insert into private.registration_acceptance(user_id,version) values(auth.uid(),version) on conflict(user_id) do nothing;return true;end $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.record_registration_acceptance(version text, accepted boolean)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.record_registration_acceptance(version,accepted)$function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.accept_company_invites()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare em text; n int := 0; i record;
begin
  select lower(email) into em from auth.users where id = auth.uid() and email_confirmed_at is not null;
  if em is null then return 0; end if;
  if exists (select 1 from public.company_members where user_id = auth.uid()) then return 0; end if;
  for i in select * from public.company_invites where lower(email) = em and accepted_at is null order by created_at limit 1 loop
    insert into public.company_members(company_id, user_id, role) values (i.company_id, auth.uid(), i.role);
    update public.company_invites set accepted_at = now() where id = i.id;
    n := n + 1;
  end loop;
  return n;
end $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.invite_member(cid uuid, invite_email text, invite_role text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  me text; s record; p text; lim int; used int; e text := lower(trim(invite_email)); nid uuid;
begin
  select m.role::text into me from public.company_members m where m.company_id = cid and m.user_id = auth.uid();
  if me is null or me not in ('owner','admin') then raise exception 'Nemate opravneni zvat cleny tymu.'; end if;
  if invite_role not in ('admin','employee') then raise exception 'Neplatna role.'; end if;
  if invite_role = 'admin' and me <> 'owner' then raise exception 'Spravce muze pridat jen majitel.'; end if;
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Zadejte platny e-mail.'; end if;
  if exists (select 1 from public.company_members m join auth.users u on u.id = m.user_id
             where m.company_id = cid and lower(u.email) = e) then
    raise exception 'Tento clovek uz ve firme je.'; end if;

  select * into s from public.subscriptions where company_id = cid limit 1;
  p := lower(coalesce(s.plan::text, 'start'));
  if s.status::text in ('expired','canceled') or (s.status::text = 'trial' and s.trial_end is not null and s.trial_end < now()) then p := 'start'; end if;
  lim := case p when 'start' then 1 when 'accountant' then 2 when 'pro' then 3 when 'business' then 10 else 1000 end;
  select (select count(*) from public.company_members where company_id = cid)
       + (select count(*) from public.company_invites where company_id = cid and accepted_at is null) into used;
  if used >= lim then raise exception 'Vas tarif umoznuje nejvyse % uzivatelu (vcetne nevyrizenych pozvanek).', lim; end if;

  insert into public.company_invites(company_id, email, role) values (cid, e, invite_role) returning id into nid;
  return nid;
exception when unique_violation then
  raise exception 'Tento e-mail uz je pozvany.';
end $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.company_team(cid uuid)
 RETURNS TABLE(user_id uuid, email text, role text, is_me boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  select m.user_id, u.email::text, m.role::text, (m.user_id = auth.uid())
  from public.company_members m join auth.users u on u.id = m.user_id
  where m.company_id = cid
    and exists (select 1 from public.company_members x where x.company_id = cid and x.user_id = auth.uid())
  order by (m.role = 'owner') desc, u.email;
$function$;

-- trigger (exec: nikdo z anon/authenticated)
CREATE OR REPLACE FUNCTION private.enforce_team_capacity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare p text; n bigint; begin
perform pg_advisory_xact_lock(hashtextextended(new.company_id::text,0));
select plan into p from public.subscriptions where company_id=new.company_id;
if p in ('business','enterprise') then return new;end if;
select count(*) into n from public.company_members where company_id=new.company_id;
if n>=(case p when 'start' then 2 when 'pro' then 10 else 50 end) then raise exception 'Dosažen limit členů týmu'; end if; return new; end $function$;

-- trigger (exec: nikdo z anon/authenticated)
CREATE OR REPLACE FUNCTION private.sync_branch_subscription()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
if not exists(select 1 from public.companies where id=new.company_id and parent_company_id is null) then return new;end if;
update public.subscriptions set plan=new.plan,status=case when (new.status='trial' and new.trial_end>now()) or (new.status='active' and new.plan in ('business','enterprise') and new.paid_until>now()) then new.status else 'expired' end,trial_start=new.trial_start,trial_end=new.trial_end,paid_until=new.paid_until where company_id in(select id from public.companies where parent_company_id=new.company_id);return new;end $function$;

-- trigger (exec: nikdo z anon/authenticated)
CREATE OR REPLACE FUNCTION private.branch_preferences_inherit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if new.parent_company_id is not null then select country,currency into new.country,new.currency from public.companies where id=new.parent_company_id;end if;return new;
end $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.subscription_clock(cid uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select to_jsonb(s)||jsonb_build_object('server_now',now()) from public.subscriptions s where s.company_id=cid$function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION private.workspace_settings(cid uuid, doc jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare root uuid:=private.business_root(cid);cur text;begin
if auth.uid() is null or coalesce(private.member_role(cid),'') not in ('owner','admin') or not private.writable(cid) then raise exception 'Nemáte oprávnění měnit nastavení firmy.';end if;
perform pg_advisory_xact_lock(hashtextextended(root::text,930));select currency into cur from public.companies where id=cid;
if doc->>'currency' is distinct from cur then
if cid<>root then raise exception 'Měnu nastavuje hlavní firma pro všechny provozovny.';end if;
if exists(select 1 from public.jobs j where private.business_root(j.company_id)=root) or exists(select 1 from public.financial_entries f where private.business_root(f.company_id)=root) or exists(select 1 from public.invoices i where private.business_root(i.company_id)=root) then raise exception 'Měnu existujících dat nelze změnit. Faktury v jiné měně mohou mít vlastní směnný kurz.';end if;
update public.companies set currency=doc->>'currency' where id=root or parent_company_id=root;
end if;
update public.companies set country=doc->>'country' where id=cid;
return (select jsonb_build_object('country',country,'currency',currency) from public.companies where id=cid);end $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.workspace_settings(cid uuid, doc jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.workspace_settings(cid,doc)$function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION private.reserve_ai_core(cid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
if auth.uid() is null or private.member_role(cid) is null or not private.writable(cid) then raise exception 'Forbidden';end if;
if not exists(select 1 from public.subscriptions s where s.company_id=private.business_root(cid) and s.plan in ('pro','business','enterprise')) then raise exception 'Vexaronet AI je součástí tarifů Pro a Business. Starter AI neobsahuje.';end if;
-- Serialize reservations across companies: hard request caps remain correct under concurrency.
perform pg_advisory_xact_lock(1498628);
if (select count(*) from private.ai_requests where created_at>date_trunc('day',now()))>=100 then raise exception 'Denní limit AI platformy byl vyčerpán';end if;
if (select count(*) from private.ai_requests where company_id=cid and created_at>date_trunc('month',now()))>=300 then raise exception 'Měsíční limit AI firmy byl vyčerpán';end if;
if (select count(*) from private.ai_requests where company_id=cid and created_at>date_trunc('day',now()))>=20 then raise exception 'Denní limit AI firmy byl vyčerpán';end if;
if (select count(*) from private.ai_requests where user_id=auth.uid() and created_at>now()-interval '1 minute')>=3 then raise exception 'Zkuste AI znovu za minutu';end if;
insert into private.ai_requests(company_id,user_id) values(cid,auth.uid());end $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.reserve_ai(cid uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.reserve_ai_core(cid)$function$;

-- exec: nikdo z anon/authenticated
CREATE OR REPLACE FUNCTION private.booking_plan_allowed(cid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.subscriptions s where s.company_id=private.business_root(cid) and s.plan in ('pro','business','enterprise') and ((s.status='trial' and s.trial_end>now()) or (s.status='active' and s.paid_until>now())));
$function$;

-- exec: anon, authenticated
CREATE OR REPLACE FUNCTION private.public_profile_allowed(cid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select private.booking_plan_allowed(cid)$function$;

-- trigger (exec: nikdo z anon/authenticated)
CREATE OR REPLACE FUNCTION private.profile_plan_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
if new.published and not private.booking_plan_allowed(new.company_id) then raise exception 'Veřejný profil a rezervace jsou součástí Pro a Business.';end if;return new;end $function$;

-- trigger (exec: nikdo z anon/authenticated)
CREATE OR REPLACE FUNCTION private.invoice_profile_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare account text;prefix text;main text;
begin
 if new.bank_account<>'' then
 if new.bank_account !~ '^([0-9]{1,6}-)?[0-9]{1,10}/[0-9]{4}$' then raise exception 'Zkontrolujte číslo účtu.';end if;
 account:=split_part(new.bank_account,'/',1);
 prefix:=case when position('-' in account)>0 then split_part(account,'-',1) else '0' end;
 main:=case when position('-' in account)>0 then split_part(account,'-',2) else account end;
 if substring(new.iban,5,4)<>split_part(new.bank_account,'/',2)
 or substring(new.iban,9,6)<>lpad(prefix,6,'0')
 or substring(new.iban,15,10)<>lpad(main,10,'0') then raise exception 'Číslo účtu neodpovídá IBAN.';end if;
 end if;
 return new;
end $function$;

-- exec: authenticated
CREATE OR REPLACE FUNCTION public.invoice_action(cid uuid, action text, doc jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.invoice_action_core(cid,action,doc)$function$;

-- private.invoice_action_core(cid uuid, action text, doc jsonb) – 14 003 znaků, SECURITY DEFINER,
-- exec: authenticated, md5 ec8dc7d75ceee5f0d302783eb596d32a. Celé tělo zde NENÍ.
-- Ověřené části:
--   * akce: 'profile', 'start', 'issue', 'paid'
--   * úvodní kontrola: auth.uid() not null, member_role(cid) in ('owner','admin'), writable(cid);
--     jinak 'Nemáte oprávnění nebo aktivní přístup.'
--   * 'profile': povinné legal_name (2–200), address_text (5–500), registration_text (3–500),
--     platné IČO (private.invoice_ico_valid), platný IBAN (private.invoice_iban_valid), platný e-mail;
--     plátce DPH musí mít DIČ CZ/SK; country_code jen CZ/SK; SK vyžaduje tax_id (10 číslic);
--     logo jen PNG data URL do 240 000 znaků; celý doc do 245 000 znaků;
--     pak INSERT ... ON CONFLICT (company_id) DO UPDATE do public.user_business_profiles.
