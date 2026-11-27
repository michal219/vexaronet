#!/usr/bin/env python3
"""Vytvoří čistý balíček zdrojového kódu pro kupce: python3 tools/export_source.py [vystup.zip]
Bere jen soubory ve verzi (git), vymění adresu a klíč databáze za zástupné hodnoty, odstraní sestavené soubory, přidá README a návrh licence."""
import subprocess, zipfile, sys, re, os, io
out = sys.argv[1] if len(sys.argv) > 1 else 'vexaronet-zdrojovy-kod.zip'
files = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
SKIP = ('index.html', 'public/', 'tests/shot_', 'version.json', 'tools/export_source.py', '.github/')
README = open('docs/KUPUJICI_README.md', encoding='utf-8').read()
LIC = open('docs/LICENCE_NAVRH.md', encoding='utf-8').read()
# hotová lokální aplikace (bez Supabase) se přibalí jako složka lokalni-aplikace/
subprocess.run([sys.executable, 'tools/export_local.py'], check=True, stdout=subprocess.DEVNULL)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    with zipfile.ZipFile('vexaronet-lokalni.zip') as lz:
        for n in lz.namelist():
            if n.endswith('/'): continue
            z.writestr('vexaronet/lokalni-aplikace/' + n.split('/', 1)[1], lz.read(n))
    for f in files:
        if not f or any(f == s or f.startswith(s) for s in SKIP) or not os.path.isfile(f): continue
        data = open(f, 'rb').read()
        if f == 'build.py':
            t = data.decode('utf-8')
            t = re.sub(r"CFG\.get\('supabase_url', '[^']*'\)", "CFG.get('supabase_url', 'https://VASE-PROJEKT.supabase.co')", t)
            t = re.sub(r"CFG\.get\('supabase_publishable_key', '[^']*'\)", "CFG.get('supabase_publishable_key', 'VAS_PUBLISHABLE_KLIC')", t)
            data = t.encode('utf-8')
        elif f == '_headers':
            data = re.sub(r'(https|wss)://[a-z0-9-]+\.supabase\.co', r'\1://VASE-PROJEKT.supabase.co', data.decode('utf-8')).encode('utf-8')
        z.writestr('vexaronet/' + f, data)
    z.writestr('vexaronet/README_KUPUJICI.md', README)
    z.writestr('vexaronet/LICENCE_NAVRH.md', LIC)
print('Hotovo:', out)
