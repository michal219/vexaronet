-- Kontrola invariantů oprávnění v produkci. POUZE ČTENÍ KATALOGU: nečte zákaznická data, nic nemění, nic nezkouší.
-- Spouštět pravidelně a po každé migraci (Supabase SQL editor nebo MCP execute_sql). Výsledek: řádek na kontrolu, stav OK/NÁLEZ.
-- Popis nálezů a oprav: docs/SECURITY_STATUS.md.
with
allow_anon_policy(tbl, pol) as (values ('public_profiles','published_read'), ('newsletter_subscribers','anyone can subscribe'), ('custom_inquiries','ci_insert')),
allow_anon_fn(fn) as (values ('public_book'),('public_booking_info'),('public_shop'),('public_shop_order'),('public_site'),('public_slots'),
  ('campaign_config'),('capture_campaign'),('withdraw_campaign'),('crm_same_company'),('quotes_same_deal'),('quotes_set_number'),
  ('public_profile_allowed'),('campaign_config_core'),('capture_campaign_core'),('withdraw_campaign_core')),
allow_anon_tbl(tbl, priv) as (values ('newsletter_subscribers','INSERT'), ('custom_inquiries','INSERT'), ('public_profiles','SELECT')),
company_tables as (select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace join pg_attribute a on a.attrelid = c.oid
  where n.nspname = 'public' and c.relkind = 'r' and a.attname = 'company_id' and not a.attisdropped),
checks(nr, kontrola, nalezy) as (
  select 1, 'Všechny tabulky v public a private mají RLS',
    (select string_agg(n.nspname || '.' || c.relname, ', ') from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('public','private') and c.relkind in ('r','p') and not c.relrowsecurity)
  union all select 2, 'Politiky pro anon/PUBLIC jen u záměrně veřejných tabulek',
    (select string_agg(tablename || '.' || policyname, ', ') from pg_policies p where schemaname = 'public' and roles && array['anon','public']::name[]
      and not exists (select 1 from allow_anon_policy a where a.tbl = p.tablename and a.pol = p.policyname))
  union all select 3, 'Každá politika firemní tabulky ověřuje členství nebo uživatele',
    (select string_agg(tablename || '.' || policyname, ', ') from pg_policies p where schemaname = 'public' and tablename in (select relname from company_tables)
      and not (coalesce(qual,'') || coalesce(with_check,'') ~ 'member_role|company_members|auth\.uid|writable|business_root|public_profile_allowed')
      and not exists (select 1 from allow_anon_policy a where a.tbl = p.tablename and a.pol = p.policyname))
  union all select 4, 'SECURITY DEFINER funkce mají nastavený search_path',
    (select string_agg(n.nspname || '.' || p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public','private') and p.prosecdef and not exists (select 1 from unnest(p.proconfig) x where x like 'search_path=%'))
  union all select 5, 'search_path SECURITY DEFINER funkcí je prázdný nebo končí pg_temp (D-3)',
    (select string_agg(n.nspname || '.' || p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace cross join lateral unnest(p.proconfig) x
      where n.nspname in ('public','private') and p.prosecdef and x like 'search_path=%' and x <> 'search_path=""' and x !~ 'pg_temp')
  union all select 6, 'anon smí spustit jen záměrně veřejné funkce',
    (select string_agg(n.nspname || '.' || p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public','private') and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')
        and p.proname not in (select fn from allow_anon_fn))
  union all select 7, 'anon nemá práva na tabulky kromě formulářů a veřejného profilu (D-1)',
    (select string_agg(g.table_name || ':' || g.privilege_type, ', ') from information_schema.role_table_grants g
      where g.grantee = 'anon' and g.table_schema = 'public' and not exists (select 1 from allow_anon_tbl a where a.tbl = g.table_name and a.priv = g.privilege_type))
  union all select 8, 'authenticated nemá TRUNCATE/REFERENCES/TRIGGER (D-1)',
    (select string_agg(distinct g.table_name, ', ') from information_schema.role_table_grants g
      where g.grantee = 'authenticated' and g.table_schema = 'public' and g.privilege_type in ('TRUNCATE','REFERENCES','TRIGGER'))
  union all select 9, 'Člen týmu nemůže změnit svou roli ani firmu (company_members jen display_name)',
    (select string_agg(column_name, ', ') from information_schema.column_privileges where grantee = 'authenticated' and table_schema = 'public'
      and table_name = 'company_members' and privilege_type in ('UPDATE','INSERT') and column_name <> 'display_name')
  union all select 10, 'Tarif a firmy nejde přes API zapsat přímo (subscriptions bez zápisu, companies bez INSERT/DELETE)',
    (select string_agg(t || ':' || pr, ', ') from (values ('subscriptions','insert'),('subscriptions','update'),('subscriptions','delete'),('companies','insert'),('companies','delete')) v(t, pr)
      where has_table_privilege('authenticated', 'public.' || t, pr))
  union all select 11, 'anon nemá přístup do schémat private, vault a cron',
    (select string_agg(s, ', ') from unnest(array['private','vault','cron']) s where has_schema_privilege('anon', s, 'usage'))
  union all select 12, 'Úložiště: veřejný je jen bucket obrázků webu',
    (select string_agg(id, ', ') from storage.buckets where public and id <> 'site-images')
  union all select 13, 'Placené běhy Autopilota jsou vypnuté',
    (select case when paid_runs_enabled then 'paid_runs_enabled = true' end from private.autopilot_platform)
  union all select 14, 'Role anon a authenticated nemají BYPASSRLS',
    (select string_agg(rolname, ', ') from pg_roles where rolbypassrls and rolname in ('anon','authenticated'))
)
select nr, kontrola, case when nalezy is null then 'OK' else 'NÁLEZ' end as stav, coalesce(left(nalezy, 400), '') as detail from checks order by nr;
