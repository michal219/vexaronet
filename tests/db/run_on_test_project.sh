#!/usr/bin/env bash
# Spustí VŠECHNY databázové testy proti samostatnému testovacímu Supabase projektu.
# Pojistky: odmítne produkční projekt a databázi, která už obsahuje tabulky aplikace.
#
#   export DATABASE_URL='postgresql://postgres.<ref>:<heslo>@<host>:5432/postgres'   # jen ve vašem terminálu
#   tests/db/run_on_test_project.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${DATABASE_URL:?Nastavte DATABASE_URL testovacího projektu (viz docs/TESTOVACI_PROSTREDI.md)}"
PROD_REF="micymdbqgzeckiqyvvkn"
case "$DATABASE_URL" in *"$PROD_REF"*) echo "ODMÍTNUTO: adresa obsahuje identifikátor PRODUKČNÍHO projektu ($PROD_REF)."; exit 3;; esac
P="psql $DATABASE_URL -X -q -v ON_ERROR_STOP=1"
GUARD=$($P -At -c "select count(*) from information_schema.tables where table_schema='public' and table_name in ('customers','jobs','invoices')")
[ "$GUARD" = "0" ] || { echo "ODMÍTNUTO: databáze už obsahuje tabulky aplikace (customers/jobs/invoices). Použijte prázdný testovací projekt."; exit 3; }
step() { echo; echo "== $1"; }
t() { local out; out=$($P -f "$1" 2>&1) || { echo "$out" | tail -15; echo "SELHALO: $1"; exit 1; }
      echo "$out" | grep -q "PROŠLY" && echo "   $1: PROŠLY ($(echo "$out" | grep -c 'NOTICE:  ok') kontrol)" || { echo "$out" | tail -8; echo "SELHALO: $1 (chybí potvrzení PROŠLY)"; exit 1; }; }
step "Základ (companies, členství, předplatné, member_role/writable/business_root/booking_plan_allowed)"; $P -f db/test/01_base_stub.sql
step "Profil firmy: migrace a testy";                  $P -f db/migrations/20261107120000_profil_firmy.sql; t db/test/10_profile_tests.sql
step "Bezpečnostní opravy: výchozí stav, migrace, testy"; $P -f db/test/02_security_prestate.sql; $P -f db/migrations/20261108100000_bezpecnostni_opravy.sql; t db/test/12_security_tests.sql
step "Autopilot: limity, migrace a testy";             $P -f db/migrations/20261108110000_autopilot_limity.sql; t db/test/13_autopilot_tests.sql
echo; echo "VŠE PROŠLO na testovacím projektu. HTTP stavy ověřte ještě: node tests/db/check_http_status.mjs"
