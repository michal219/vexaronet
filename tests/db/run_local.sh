#!/usr/bin/env bash
# Lokální ověření migrace profilu firmy v oddělené (zahazovací) PostgreSQL databáze.
# Není to Supabase: auth, role a výchozí práva napodobuje db/test/00_local_supabase_shim.sql.
# Věci specifické pro Supabase (PostgREST, mapování na HTTP 409) ověřuje až bezplatný testovací projekt,
# viz docs/TESTOVACI_PROSTREDI.md.
#
#   PSQL="runuser -u postgres -- psql" tests/db/run_local.sh      (jako root)
#   tests/db/run_local.sh                                          (běžný uživatel s právem zakládat databáze)
set -euo pipefail
cd "$(dirname "$0")/../.."
PSQL="${PSQL:-psql}"
export PSQL
DB="${PGDATABASE:-vx_profil_test}"
q()  { $PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
qa() { $PSQL -X -At -v ON_ERROR_STOP=1 -d "$DB" "$@"; }

$PSQL -X -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
q -f db/test/00_local_supabase_shim.sql
q -f db/test/01_base_stub.sql

echo "== Věrnost základu: otisk funkcí opsaných z živé databáze musí odpovídat snapshotu"
for fn in "member_role(cid uuid)" "writable(cid uuid)" "business_root(cid uuid)"; do
  want=$(grep -F "private.$fn " db/snapshot/2026-11-07_manifest.txt | awk '{print $NF}')
  got=$(qa -c "select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='${fn%%(*}'")
  [ "$want" = "$got" ] && echo "   ok  private.${fn%%(*}  $got" || { echo "   CHYBA private.${fn%%(*}: snapshot=$want lokálně=$got"; exit 1; }
done

echo "== Kopie schématu v migraci je shodná se src/onboarding_schema.json"
python3 tools/sync_profile_schema.py --check

# otisk všeho, co už existovalo před migrací (musí zůstat beze změny = migrace je jen přidává)
BASELINE_SQL="select md5(coalesce((select string_agg(pg_get_functiondef(p.oid), '' order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','auth') and p.prokind='f'),''))
 || md5(coalesce((select string_agg(c.relname || coalesce(c.relacl::text,'') || c.relrowsecurity::text, ',' order by n.nspname, c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth') and c.relkind='r'),''))
 || md5(coalesce((select string_agg(tablename || policyname || coalesce(qual,''), ',' order by tablename, policyname) from pg_policies),''))"
BEFORE=$(qa -c "$BASELINE_SQL")

echo "== Migrace (poprvé)"
q -f db/migrations/20261107120000_profil_firmy.sql
echo "== Migrace (podruhé; musí být opakovatelná)"
q -f db/migrations/20261107120000_profil_firmy.sql

echo "== Migrace nic existujícího nezměnila (po odečtení nových objektů)"
# nové objekty se vyloučí podle jmen; zbytek musí mít stejný otisk
AFTER=$(qa -c "select md5(coalesce((select string_agg(pg_get_functiondef(p.oid), '' order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','auth') and p.prokind='f' and p.proname not like 'vx\_%' and p.proname not like 'profile\_%'),''))
 || md5(coalesce((select string_agg(c.relname || coalesce(c.relacl::text,'') || c.relrowsecurity::text, ',' order by n.nspname, c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth') and c.relkind='r' and c.relname not like 'company\_profile\_%' and c.relname not like 'company\_active\_profile'),''))
 || md5(coalesce((select string_agg(tablename || policyname || coalesce(qual,''), ',' order by tablename, policyname) from pg_policies),''))")
[ "$BEFORE" = "$AFTER" ] && echo "   ok  funkce, tabulky, práva i politiky mimo nové objekty jsou beze změny" || { echo "   CHYBA: migrace změnila existující objekty"; exit 1; }

echo "== SQL testy (role, oprávnění, konflikty, verzování, pobočky, práva)"
OUT=$($PSQL -X -q -v ON_ERROR_STOP=1 -d "$DB" -f db/test/10_profile_tests.sql 2>&1) || { echo "$OUT" | tail -15; echo "SQL TESTY SELHALY"; exit 1; }
echo "   splněných kontrol: $(echo "$OUT" | grep -c 'NOTICE:  ok')"
echo "$OUT" | grep -q "PROŠLY" || { echo "$OUT" | tail -5; echo "SQL TESTY SELHALY"; exit 1; }
echo "   VŠECHNY SQL TESTY PROFILU PROŠLY (transakce vrácena)"

echo "== Shoda validace JS ↔ DB"
PGDATABASE="$DB" python3 tests/profile_parity.py

echo "== Zpětná migrace (rollback) a znovu dopředu"
q -f db/migrations/20261107120000_profil_firmy_rollback.sql
LEFT=$(qa -c "select (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and (p.proname like 'vx\_%' or p.proname like 'profile\_%')) + (select count(*) from pg_class where relname like 'company\_profile\_%' or relname = 'company_active_profile')")
[ "$LEFT" = "0" ] && echo "   ok  po rollbacku nezůstal žádný nový objekt" || { echo "   CHYBA: po rollbacku zůstalo $LEFT objektů"; exit 1; }
AFTER_RB=$(qa -c "$BASELINE_SQL")
[ "$BEFORE" = "$AFTER_RB" ] && echo "   ok  stav po rollbacku je shodný se stavem před migrací" || { echo "   CHYBA: stav po rollbacku se liší od původního"; exit 1; }
q -f db/migrations/20261107120000_profil_firmy.sql
echo "== HOTOVO: lokální ověření prošlo"
