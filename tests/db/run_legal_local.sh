#!/usr/bin/env bash
# Odhlášení z marketingu a oznámení DSA (migrace 20261110100000 a 20261110110000) v lokální PostgreSQL pod rolemi anon/authenticated/service_role.
#   PSQL="runuser -u postgres -- psql" tests/db/run_legal_local.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
PSQL="${PSQL:-psql}"; DB="${PGDATABASE:-vx_legal_test}"
q()  { $PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
qa() { $PSQL -X -At -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
M1=db/migrations/20261110100000_marketing_odhlaseni.sql; M2=db/migrations/20261110110000_dsa_oznameni.sql
$PSQL -X -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
q -f db/test/00_local_supabase_shim.sql; q -f db/test/01_base_stub.sql; q -f db/test/04_legal_prestate.sql
SNAP="select md5(string_agg(x, '|' order by x)) from (
  select 'o:' || n.nspname || '.' || c.relname || ':' || c.relkind::text || coalesce(c.relacl::text, '') as x from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('public', 'private')
  union all select 'f:' || p.oid::regprocedure::text || coalesce(p.proacl::text, '') || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'private')
  union all select 'p:' || tablename || policyname from pg_policies) s"
S0=$(qa -c "$SNAP")
echo "== Migrace (poprvé a podruhé)"; q -f $M1; q -f $M2; q -f $M1; q -f $M2
echo "== Testy pod rolemi"
OUT=$($PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" -f db/test/15_legal_tests.sql 2>&1) || { echo "$OUT" | tail -12; echo "TESTY SELHALY"; exit 1; }
echo "   splněných kontrol: $(echo "$OUT" | grep -c 'NOTICE:  ok')"; echo "$OUT" | grep -q PROŠLY || { echo "$OUT" | tail; exit 1; }
echo "== Zpětná migrace vrací původní stav"
q -f db/migrations/20261110110000_dsa_oznameni_rollback.sql; q -f db/migrations/20261110100000_marketing_odhlaseni_rollback.sql
[ "$S0" = "$(qa -c "$SNAP")" ] && echo "   ok  po rollbacku je katalog shodný s výchozím stavem" || { echo "   CHYBA: rollback nevrací původní stav"; exit 1; }
q -f $M1; q -f $M2; echo "   ok  migrace jde po rollbacku znovu aplikovat"
echo "HOTOVO: odhlášení z marketingu a oznámení DSA ověřeny"
