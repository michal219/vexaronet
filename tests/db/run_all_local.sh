#!/usr/bin/env bash
# Všechny lokální databázové testy za sebou (profil firmy, bezpečnostní opravy, limity Autopilota, zpřísnění práv).
#   PSQL="runuser -u postgres -- psql" tests/db/run_all_local.sh
set -euo pipefail
cd "$(dirname "$0")"
./run_local.sh && ./run_security_local.sh && ./run_autopilot_local.sh && ./run_hardening_local.sh && echo && echo "VŠECHNY LOKÁLNÍ DATABÁZOVÉ TESTY PROŠLY"
