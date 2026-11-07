#!/usr/bin/env bash
# Ověření dopadů bezpečnostních oprav v lokální PostgreSQL (kopie výchozího stavu podle auditu).
#   PSQL="runuser -u postgres -- psql" tests/db/run_security_local.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
PSQL="${PSQL:-psql}"; DB="${PGDATABASE:-vx_security_test}"
q()  { $PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
qa() { $PSQL -X -At -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
MIG=db/migrations/20261108100000_bezpecnostni_opravy.sql
$PSQL -X -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
q -f db/test/00_local_supabase_shim.sql; q -f db/test/01_base_stub.sql; q -f db/test/02_security_prestate.sql

TOUCHED="select md5(string_agg(x, '|' order by x)) from (
  select 't:' || c.oid::regclass::text || ':' || (select coalesce(string_agg(a.grantee::text || '/' || a.privilege_type || '/' || a.is_grantable::text, ',' order by a.grantee::text || a.privilege_type), '') from aclexplode(c.relacl) a) || ':' || c.relrowsecurity as x from pg_class c
   where c.oid in ('private.platform_admins'::regclass, 'private.ai_requests'::regclass, 'private.feedback_mail_delivery'::regclass, 'private.push_deliveries'::regclass,
                   'public.ai_usage'::regclass, 'public.company_invites'::regclass, 'public.plan_requests'::regclass)
  union all select 'f:' || p.oid::regprocedure::text || ':' || (select coalesce(string_agg(a.grantee::text || '/' || a.privilege_type || '/' || a.is_grantable::text, ',' order by a.grantee::text || a.privilege_type), '') from aclexplode(p.proacl) a) from pg_proc p
   where p.oid in ('public.clock_in(uuid,uuid)'::regprocedure, 'public.clock_out(uuid,uuid)'::regprocedure, 'public.shop_cancel_order(uuid)'::regprocedure)) s"
REST="select md5(string_agg(x, '|' order by x)) from (
  select 't:' || c.oid::regclass::text || ':' || (select coalesce(string_agg(a.grantee::text || '/' || a.privilege_type || '/' || a.is_grantable::text, ',' order by a.grantee::text || a.privilege_type), '') from aclexplode(c.relacl) a) || ':' || c.relrowsecurity as x from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'private', 'auth') and c.relkind = 'r' and c.oid not in ('private.platform_admins'::regclass, 'private.ai_requests'::regclass, 'private.feedback_mail_delivery'::regclass, 'private.push_deliveries'::regclass, 'public.ai_usage'::regclass, 'public.company_invites'::regclass, 'public.plan_requests'::regclass)
  union all select 'f:' || p.oid::regprocedure::text || ':' || (select coalesce(string_agg(a.grantee::text || '/' || a.privilege_type || '/' || a.is_grantable::text, ',' order by a.grantee::text || a.privilege_type), '') from aclexplode(p.proacl) a) || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private') and p.oid not in ('public.clock_in(uuid,uuid)'::regprocedure, 'public.clock_out(uuid,uuid)'::regprocedure, 'public.shop_cancel_order(uuid)'::regprocedure)
  union all select 'p:' || tablename || policyname || coalesce(qual, '') || coalesce(with_check, '') from pg_policies) s"
T0=$(qa -c "$TOUCHED"); R0=$(qa -c "$REST")

echo "== Výchozí stav odpovídá auditu (před opravou)"
PRE=$(qa -c "select (select count(*) from pg_class where oid in ('private.platform_admins'::regclass,'private.ai_requests'::regclass,'private.feedback_mail_delivery'::regclass,'private.push_deliveries'::regclass) and not relrowsecurity)
  || ',' || has_table_privilege('anon','public.ai_usage','truncate')::text || ',' || has_function_privilege('anon','public.clock_in(uuid,uuid)','execute')::text")
[ "$PRE" = "4,true,true" ] && echo "   ok  RLS vypnuté na 4 tabulkách, anon má TRUNCATE na ai_usage a EXECUTE na clock_in" || { echo "   CHYBA: $PRE"; exit 1; }

echo "== Migrace (poprvé a podruhé)"; q -f $MIG; q -f $MIG
echo "== Testy dopadů"
OUT=$($PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" -f db/test/12_security_tests.sql 2>&1) || { echo "$OUT" | tail -12; echo "TESTY SELHALY"; exit 1; }
echo "   splněných kontrol: $(echo "$OUT" | grep -c 'NOTICE:  ok')"; echo "$OUT" | grep -q PROŠLY || { echo "$OUT" | tail; exit 1; }
echo "== Nic dalšího se nezměnilo (ostatní tabulky, práva, funkce a politiky)"
[ "$R0" = "$(qa -c "$REST")" ] && echo "   ok  otisk zbytku databáze je shodný před i po" || { echo "   CHYBA: změnilo se i něco mimo 10 objektů"; exit 1; }
echo "== Zpětná migrace vrací přesně původní práva"
q -f db/migrations/20261108100000_bezpecnostni_opravy_rollback.sql
[ "$T0" = "$(qa -c "$TOUCHED")" ] && echo "   ok  práva a RLS všech 10 objektů jsou po rollbacku shodná s původními" || { echo "   CHYBA: rollback nevrací původní stav"; exit 1; }
[ "$R0" = "$(qa -c "$REST")" ] && echo "   ok  zbytek databáze beze změny"
q -f $MIG; echo "== HOTOVO: bezpečnostní opravy ověřeny lokálně"
