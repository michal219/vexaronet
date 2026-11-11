#!/usr/bin/env bash
# Limit registrace firem (migrace 20261114100000) v lokální PostgreSQL.
#   PSQL="runuser -u postgres -- psql" tests/db/run_registrace_local.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
PSQL="${PSQL:-psql}"; DB="${PGDATABASE:-vx_registrace_test}"
q()  { $PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
qa() { $PSQL -X -At -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
M=db/migrations/20261114100000_registrace_limit.sql
$PSQL -X -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
q -f db/test/00_local_supabase_shim.sql 2>/dev/null; q -f db/test/01_base_stub.sql 2>/dev/null
SNAP="select md5(string_agg(x, '|' order by x)) from (
  select 'o:' || n.nspname || '.' || c.relname || coalesce(c.relacl::text, '') as x from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('public', 'private')
  union all select 'f:' || p.oid::regprocedure::text || coalesce(p.proacl::text, '') from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'private')
  union all select 't:' || tgname from pg_trigger where not tgisinternal) s"
S0=$(qa -c "$SNAP")
echo "== Migrace (poprvé a podruhé)"; q -f $M 2>/dev/null; q -f $M 2>/dev/null
echo "== Testy"
OUT=$($PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" -f db/test/17_registrace_tests.sql 2>&1) || { echo "$OUT" | tail -8; echo "TESTY SELHALY"; exit 1; }
echo "   splněných kontrol: $(echo "$OUT" | grep -c 'NOTICE:  ok')"; echo "$OUT" | grep -q PROŠLY || { echo "$OUT" | tail; exit 1; }
echo "== Zpětná migrace"
q -f db/migrations/20261114100000_registrace_limit_rollback.sql 2>/dev/null
[ "$S0" = "$(qa -c "$SNAP")" ] && echo "   ok  po rollbacku je katalog shodný s výchozím stavem" || { echo "   CHYBA: rollback nevrací původní stav"; exit 1; }
q -f $M 2>/dev/null; echo "   ok  migrace jde znovu aplikovat"
echo "HOTOVO: limit registrace ověřen v DB"
