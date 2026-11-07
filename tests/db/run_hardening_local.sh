#!/usr/bin/env bash
# Zpřísnění práv (migrace 20261109100000): hranice oprávnění pod skutečnými rolemi anon/authenticated v lokální PostgreSQL.
#   PSQL="runuser -u postgres -- psql" tests/db/run_hardening_local.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
PSQL="${PSQL:-psql}"; DB="${PGDATABASE:-vx_hardening_test}"
q()  { $PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
qa() { $PSQL -X -At -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
MIG=db/migrations/20261109100000_zprisneni_prav.sql
$PSQL -X -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
q -f db/test/00_local_supabase_shim.sql; q -f db/test/01_base_stub.sql; q -f db/test/03_hardening_prestate.sql

# Dotčené: práva tabulek v public, dvě politiky formulářů, nastavení funkcí v public. Zbytek: vše ostatní.
TOUCHED="select md5(string_agg(x, '|' order by x)) from (
  select 't:' || c.oid::regclass::text || ':' || (select coalesce(string_agg(a.grantee::regrole::text || '/' || a.privilege_type, ',' order by a.grantee::regrole::text || a.privilege_type), '') from aclexplode(c.relacl) a) as x
    from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r'
  union all select 'p:' || tablename || policyname || cmd || array_to_string(roles, ',') || coalesce(qual, '') || coalesce(with_check, '') from pg_policies where tablename in ('newsletter_subscribers', 'custom_inquiries')
  union all select 'c:' || p.oid::regprocedure::text || ':' || coalesce(array_to_string(p.proconfig, ';'), '') from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public') s"
REST="select md5(string_agg(x, '|' order by x)) from (
  select 't:' || c.oid::regclass::text || ':' || coalesce(c.relacl::text, '') || c.relrowsecurity as x from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('private', 'auth') and c.relkind = 'r' and c.relname not like 'deploy_backup_20261109%'
  union all select 'f:' || p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'private')
  union all select 'p:' || tablename || policyname || coalesce(qual, '') || coalesce(with_check, '') from pg_policies where tablename not in ('newsletter_subscribers', 'custom_inquiries')
  union all select 'd:' || count(*)::text from public.newsletter_subscribers) s"
T0=$(qa -c "$TOUCHED"); R0=$(qa -c "$REST")

echo "== Výchozí stav odpovídá produkci (před opravou)"
PRE=$(qa -c "select has_table_privilege('anon','public.products','truncate')::text || ',' || (select with_check from pg_policies where policyname='ci_insert') || ',' ||
  (select x from pg_proc p, unnest(p.proconfig) x where p.oid='public.public_book(text,uuid,timestamptz,text,text,text)'::regprocedure)")
[ "$PRE" = "true,true,search_path=public" ] && echo "   ok  anon má TRUNCATE na products, poptávky bez kontroly, public_book bez pg_temp" || { echo "   CHYBA: $PRE"; exit 1; }

echo "== Migrace (poprvé a podruhé)"; q -f $MIG; q -f $MIG
echo "== Hranice oprávnění pod rolemi anon / authenticated"
OUT=$($PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" -f db/test/14_hardening_tests.sql 2>&1) || { echo "$OUT" | tail -12; echo "TESTY SELHALY"; exit 1; }
echo "   splněných kontrol: $(echo "$OUT" | grep -c 'NOTICE:  ok')"; echo "$OUT" | grep -q PROŠLY || { echo "$OUT" | tail; exit 1; }
echo "== Nic dalšího se nezměnilo (funkce a jejich práva, ostatní politiky, private, data)"
[ "$R0" = "$(qa -c "$REST")" ] && echo "   ok  otisk zbytku databáze je shodný před i po" || { echo "   CHYBA: změnilo se i něco mimo dotčené objekty"; exit 1; }
echo "== Zpětná migrace vrací přesně původní stav"
q -f db/migrations/20261109100000_zprisneni_prav_rollback.sql
[ "$T0" = "$(qa -c "$TOUCHED")" ] && echo "   ok  práva, politiky formulářů a search_path jsou po rollbacku shodné s původními" || { echo "   CHYBA: rollback nevrací původní stav"; exit 1; }
[ "$R0" = "$(qa -c "$REST")" ] && echo "   ok  zbytek databáze se rollbackem nezměnil" || { echo "   CHYBA: rollback změnil i jiné objekty"; exit 1; }
echo "HOTOVO: zpřísnění práv ověřeno"
