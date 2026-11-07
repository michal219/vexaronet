#!/usr/bin/env bash
# Ověření vynucování nákladového limitu Autopilota v lokální PostgreSQL. Žádné volání AI.
#   PSQL="runuser -u postgres -- psql" tests/db/run_autopilot_local.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
PSQL="${PSQL:-psql}"; DB="${PGDATABASE:-vx_autopilot_test}"
q()  { $PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
qa() { $PSQL -X -At -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
M=db/migrations/20261108110000_autopilot_limity.sql
$PSQL -X -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
q -f db/test/00_local_supabase_shim.sql; q -f db/test/01_base_stub.sql; q -f db/migrations/20261107120000_profil_firmy.sql
SIG="select md5(string_agg(x, '|' order by x)) from (select 'f:' || p.oid::regprocedure::text || md5(p.prosrc) as x from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public','private') and p.proname not like 'ap\_%' and p.proname not like 'autopilot\_%'
  union all select 't:' || c.oid::regclass::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('public','private') and c.relkind = 'r' and c.relname not like 'autopilot\_%' and c.relname <> 'ai_model_prices') s"
S0=$(qa -c "$SIG")
echo "== Migrace (poprvé a podruhé)"; q -f $M; q -f $M
[ "$S0" = "$(qa -c "$SIG")" ] && echo "   ok  migrace je čistě přídavná (ostatní funkce a tabulky beze změny)" || { echo "   CHYBA: migrace změnila existující objekty"; exit 1; }
[ "$(qa -c "select paid_runs_enabled from private.autopilot_platform")" = "f" ] && echo "   ok  po migraci jsou placené běhy platformně vypnuté" || { echo "CHYBA"; exit 1; }
q -c "update private.autopilot_platform set paid_runs_enabled = true"; q -f $M
[ "$(qa -c "select paid_runs_enabled from private.autopilot_platform")" = "t" ] && echo "   ok  opakovaná migrace nepřepíše platformní vypínač" || { echo "CHYBA: migrace přepsala vypínač"; exit 1; }
q -c "update private.autopilot_platform set paid_runs_enabled = false"
echo "== Testy vynucování limitu"
OUT=$($PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" -f db/test/13_autopilot_tests.sql 2>&1) || { echo "$OUT" | tail -14; echo "TESTY SELHALY"; exit 1; }
echo "   splněných kontrol: $(echo "$OUT" | grep -c 'NOTICE:  ok')"; echo "$OUT" | grep -q PROŠLY || { echo "$OUT" | tail; exit 1; }
echo "== Zpětná migrace"
q -f db/migrations/20261108110000_autopilot_limity_rollback.sql
LEFT=$(qa -c "select (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and (p.proname like 'ap\_%' or p.proname like 'autopilot\_%')) + (select count(*) from pg_class where relname like 'autopilot\_%' or relname = 'ai_model_prices')")
[ "$LEFT" = "0" ] && echo "   ok  po rollbacku nezůstal žádný objekt Autopilota" || { echo "   CHYBA: zůstalo $LEFT objektů"; exit 1; }
[ "$S0" = "$(qa -c "$SIG")" ] && echo "   ok  zbytek databáze beze změny"
q -f $M; echo "== HOTOVO: vynucování limitu ověřeno lokálně"
