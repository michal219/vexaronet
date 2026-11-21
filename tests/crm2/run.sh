#!/bin/bash
# Lokální test migrace schema_crm.sql + schema_crm2.sql. Použití: tests/crm2/run.sh (potřebuje běžící PG na portu 54330)
set -e; cd "$(dirname "$0")/../.."
P="/usr/lib/postgresql/16/bin/psql -h /tmp/pgcrm -p 54330 -v ON_ERROR_STOP=1 -q -X"
su postgres -c "$P -d postgres -c 'drop database if exists crm2'" ; su postgres -c "$P -d postgres -c 'create database crm2'"
for f in tests/crm2/base.sql schema_crm.sql schema_crm2.sql; do su postgres -c "$P -d crm2 -f $PWD/$f" >/dev/null; done
su postgres -c "$P -d crm2 -f $PWD/schema_crm2.sql" >/dev/null && echo "migrace je opakovatelná (2. běh bez chyby)"
su postgres -c "/usr/lib/postgresql/16/bin/psql -h /tmp/pgcrm -p 54330 -d crm2 -X -A -t -v ON_ERROR_STOP=0 -f $PWD/tests/crm2/test.sql"
