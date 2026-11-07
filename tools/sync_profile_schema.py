#!/usr/bin/env python3
"""Drží databázovou kopii schématu profilu ve shodě se src/onboarding_schema.json.

  python3 tools/sync_profile_schema.py          přepíše blok mezi značkami v migraci
  python3 tools/sync_profile_schema.py --check  jen zkontroluje (konec s kódem 1 při rozdílu)

Zdroj pravdy je src/onboarding_schema.json. Prohlížeč (build.py) i Cloudflare ho čtou přímo,
databáze má kopii v migraci, tento skript hlídá, že se nerozešly.
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = os.path.join(ROOT, 'src', 'onboarding_schema.json')
MIGRATION = os.path.join(ROOT, 'db', 'migrations', '20261107120000_profil_firmy.sql')
BEGIN = '-- BEGIN GENERATED SCHEMA'
END = '-- END GENERATED SCHEMA'


def block(schema):
    body = json.dumps(schema, ensure_ascii=False, indent=1)
    assert '$vxjson$' not in body and '$vxschema$' not in body
    return (BEGIN + ' (neupravovat ručně; python3 tools/sync_profile_schema.py)\n'
            'create or replace function private.profile_schema() returns jsonb\n'
            '  language sql immutable set search_path = \'\' as $vxschema$select $vxjson$\n'
            + body + '\n$vxjson$::jsonb$vxschema$;\n' + END)


def main():
    schema = json.load(open(SCHEMA, encoding='utf-8'))
    sql = open(MIGRATION, encoding='utf-8').read()
    m = re.search(re.escape(BEGIN) + r'.*?' + re.escape(END), sql, re.S)
    if not m:
        print('Chybí značky BEGIN/END GENERATED SCHEMA v migraci.'); return 2
    new = sql[:m.start()] + block(schema) + sql[m.end():]
    if '--check' in sys.argv:
        embedded = re.search(r'\$vxjson\$(.*?)\$vxjson\$', m.group(0), re.S)
        same = embedded and json.loads(embedded.group(1)) == schema
        print('Schéma v migraci je shodné se src/onboarding_schema.json.' if same else
              'ROZDÍL: schéma v migraci se liší od src/onboarding_schema.json. Spusťte tools/sync_profile_schema.py')
        return 0 if same else 1
    if new != sql:
        open(MIGRATION, 'w', encoding='utf-8').write(new)
        print('Migrace aktualizována.')
    else:
        print('Beze změny.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
