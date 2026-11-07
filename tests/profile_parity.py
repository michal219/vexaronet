#!/usr/bin/env python3
"""Shoda validace a pravidel profilu firmy mezi JavaScriptem aplikace (prohlížeč i Cloudflare) a databází.

Stejné vektory (tests/vectors/profile_validation.json) se vyhodnotí
  1) kódem aplikace: src/jsonschema_mini.js + src/profile_core.js (přes Node),
  2) databázovými funkcemi z migrace (přes psql).
Výsledky musí být přesně shodné. Navíc se hlídá, že kopie schématu v migraci je shodná
se src/onboarding_schema.json.

Použití: PSQL="psql" PGDATABASE=vx_profil_test python3 tests/profile_parity.py
(PSQL může být i "runuser -u postgres -- psql"). Databáze musí mít použitou migraci.
"""
import json, os, shlex, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PSQL = shlex.split(os.environ.get('PSQL', 'psql'))


def js_results():
    r = subprocess.run(['node', os.path.join(ROOT, 'tests', 'profile_vectors.js')], capture_output=True, text=True)
    if r.returncode:
        print(r.stderr); sys.exit(2)
    return json.loads(r.stdout)


def lit(x):
    s = json.dumps(x, ensure_ascii=False)
    assert '$vx$' not in s
    return '$vx$' + s + '$vx$::jsonb'


def pg_results(vectors):
    parts = []
    for i, v in enumerate(vectors):
        k, root = v['kind'], 'true' if v.get('root', True) else 'false'
        if k == 'validate':    e = 'to_jsonb(private.vx_profile_validate(%s, %s))' % (lit(v['doc']), root)
        elif k == 'incomplete': e = 'to_jsonb(private.vx_incomplete(%s, %s))' % (lit(v['doc']), root)
        elif k == 'derive':    e = 'private.vx_apply_derived(%s)' % lit(v['doc'])
        elif k == 'trim':      e = 'private.vx_trim(%s)' % lit(v['doc'])
        elif k == 'target':    e = 'to_jsonb(private.vx_goal_target(%d, %d))' % (v['b'], v['bp'])
        else: raise SystemExit('neznámý druh ' + k)
        parts.append("select %d || '|' || (%s)::text" % (i, e))
    sql = ' union all '.join(parts) + ';'
    r = subprocess.run(PSQL + ['-X', '-At', '-v', 'ON_ERROR_STOP=1'], input=sql, capture_output=True, text=True)
    if r.returncode:
        print(r.stderr); sys.exit(2)
    out = {}
    for line in r.stdout.splitlines():
        i, _, js = line.partition('|')
        out[int(i)] = json.loads(js)
    return [out[i] for i in range(len(vectors))]


def main():
    vectors = json.load(open(os.path.join(ROOT, 'tests', 'vectors', 'profile_validation.json'), encoding='utf-8'))
    chk = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'sync_profile_schema.py'), '--check'], capture_output=True, text=True)
    print(chk.stdout.strip())
    bad = chk.returncode != 0
    js, pg = js_results(), pg_results(vectors)
    for v, a, b in zip(vectors, js, pg):
        if a != b:
            bad = True
            print('ROZDÍL  %s [%s]\n   JS: %s\n   DB: %s' % (v['name'], v['kind'], json.dumps(a, ensure_ascii=False), json.dumps(b, ensure_ascii=False)))
        if v['kind'] == 'target' and a != v['ref']:
            bad = True
            print('ROZDÍL proti referenčnímu výpočtu v Pythonu: %s JS=%s ref=%s' % (v['name'], a, v['ref']))
    n = sum(1 for a, b in zip(js, pg) if a == b)
    print('Shoda JS ↔ DB: %d z %d vektorů' % (n, len(vectors)))
    sys.exit(1 if bad else 0)


main()
