-- Zpřísnění práv (nálezy D-1, D-2, D-3 v docs/SECURITY_STATUS.md). NEAPLIKOVÁNO NA PRODUKCI.
-- Mění jen práva, dvě INSERT politiky veřejných formulářů a search_path funkcí. Data ani těla funkcí se nemění.
--  A) anon: odebrat všechna práva na tabulkách ve schématu public, kromě záměrně veřejných:
--       newsletter_subscribers (INSERT), custom_inquiries (INSERT), public_profiles (SELECT).
--     Dnes je anon na ~20 tabulkách arwdDxtm; zápis i čtení blokuje jen RLS (žádná politika pro anon).
--  B) authenticated: odebrat TRUNCATE, REFERENCES a TRIGGER na tabulkách v public (aplikace je nepoužívá; TRUNCATE RLS neomezuje).
--  C) Formuláře: INSERT politiky s limity délky (dnes custom_inquiries WITH CHECK (true)).
--  D) SECURITY DEFINER funkce v public se search_path bez pg_temp: přidat pg_temp na konec (dočasné tabulky už nemohou
--     zastínit tabulky, které funkce používá). Funkce se search_path '' se nemění.
-- Před změnou se vše uloží do private.deploy_backup_20261109_* (pro zpětnou migraci). Opakovatelné.
begin;

create table if not exists private.deploy_backup_20261109_acl (obj text not null, grantee text not null, privilege text not null, primary key (obj, grantee, privilege));
create table if not exists private.deploy_backup_20261109_policy (tbl text not null, policyname text not null, cmd text not null, roles text not null,
  qual text, with_check text, primary key (tbl, policyname));
create table if not exists private.deploy_backup_20261109_config (fn text primary key, search_path text not null);
alter table private.deploy_backup_20261109_acl enable row level security;
alter table private.deploy_backup_20261109_policy enable row level security;
alter table private.deploy_backup_20261109_config enable row level security;
revoke all on private.deploy_backup_20261109_acl, private.deploy_backup_20261109_policy, private.deploy_backup_20261109_config from public, anon, authenticated;

-- záloha: práva anon (vše) a authenticated (jen odebírané druhy) na tabulkách v public
insert into private.deploy_backup_20261109_acl (obj, grantee, privilege)
select c.oid::regclass::text, a.grantee::regrole::text, a.privilege_type
from pg_class c join pg_namespace n on n.oid = c.relnamespace cross join lateral aclexplode(c.relacl) a
where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm')
  and ((a.grantee = 'anon'::regrole) or (a.grantee = 'authenticated'::regrole and a.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')))
on conflict do nothing;

insert into private.deploy_backup_20261109_policy (tbl, policyname, cmd, roles, qual, with_check)
select schemaname || '.' || tablename, policyname, cmd, array_to_string(roles, ','), qual, with_check from pg_policies
where schemaname = 'public' and ((tablename = 'newsletter_subscribers' and policyname = 'anyone can subscribe') or (tablename = 'custom_inquiries' and policyname = 'ci_insert'))
on conflict do nothing;

insert into private.deploy_backup_20261109_config (fn, search_path)
select p.oid::regprocedure::text, substr(x, 13)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace cross join lateral unnest(p.proconfig) x
where n.nspname = 'public' and p.prosecdef and x like 'search_path=%' and substr(x, 13) not in ('""', '') and substr(x, 13) !~ 'pg_temp'
on conflict do nothing;

-- A + B
do $$
declare r record;
begin
  for r in select c.oid::regclass as t, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm') loop
    execute format('revoke all on %s from anon', r.t);
    execute format('revoke truncate, references, trigger on %s from authenticated', r.t);
  end loop;
  if to_regclass('public.newsletter_subscribers') is null or to_regclass('public.custom_inquiries') is null or to_regclass('public.public_profiles') is null then
    raise exception 'Chybí tabulka formulářů nebo veřejného profilu; migrace se neprovede.';
  end if;
end $$;
grant insert on public.newsletter_subscribers, public.custom_inquiries to anon;
grant select on public.public_profiles to anon;

-- C
drop policy if exists "anyone can subscribe" on public.newsletter_subscribers;
create policy "anyone can subscribe" on public.newsletter_subscribers for insert to anon, authenticated with check (
  consent = true and char_length(email) between 5 and 200 and email ~ '^[^@[:space:]]+@[^@[:space:]]+$'
  and coalesce(char_length(name), 0) <= 200 and coalesce(char_length(company), 0) <= 200 and coalesce(char_length(business_type), 0) <= 120
  and coalesce(char_length(interested_plan), 0) <= 60 and coalesce(char_length(message), 0) <= 4000);
drop policy if exists ci_insert on public.custom_inquiries;
create policy ci_insert on public.custom_inquiries for insert to anon, authenticated with check (
  char_length(email) between 5 and 254 and email ~ '^[^@[:space:]]+@[^@[:space:]]+$' and char_length(name) between 1 and 200
  and coalesce(char_length(company), 0) <= 200 and coalesce(char_length(business_type), 0) <= 120 and coalesce(char_length(message), 0) <= 4000);

-- D
do $$
declare r record;
begin
  for r in select fn, search_path from private.deploy_backup_20261109_config loop
    if exists (select 1 from pg_proc p cross join lateral unnest(p.proconfig) x where p.oid = r.fn::regprocedure and x like 'search_path=%' and x !~ 'pg_temp') then
      execute format('alter function %s set search_path = %s, pg_temp', r.fn, r.search_path);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;
