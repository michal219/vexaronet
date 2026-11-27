#!/usr/bin/env python3
"""Vytvoří balíček zdrojového kódu pro uživatele: python3 tools/export_source.py [vystup.zip]
Obsahuje jen to, co je potřeba pro sestavení a úpravu aplikace, která běží v počítači (bez serveru a bez databáze),
a hotovou sestavenou aplikaci ve složce lokalni-aplikace/."""
import subprocess, zipfile, sys, os, re
out = sys.argv[1] if len(sys.argv) > 1 else 'vexaronet-zdrojovy-kod.zip'
tracked = set(f for f in subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0') if f)
KEEP_FILES = {'build.py', 'base.css', 'VERSION', 'CHANGELOG.md', '_headers', '_redirects', '404.html', 'sw.js', 'manifest.webmanifest',
              'robots.txt', 'sitemap.xml', 'tools/spustit.py', 'tools/export_local.py', 'SPUSTIT.bat', 'spustit.sh',
              'tests/lokalni_verze.py', 'docs/LICENCE.txt'}
KEEP_DIRS = ('src/', 'assets/')
subprocess.run([sys.executable, 'tools/export_local.py'], check=True, stdout=subprocess.DEVNULL)
README = open('docs/KUPUJICI_README.md', encoding='utf-8').read()
LIC = open('docs/LICENCE.txt', encoding='utf-8').read()
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    with zipfile.ZipFile('vexaronet-lokalni.zip') as lz:
        for n in lz.namelist():
            if n.endswith('/'): continue
            z.writestr('vexaronet/lokalni-aplikace/' + n.split('/', 1)[1], lz.read(n))
    for f in sorted(tracked):
        if not (f in KEEP_FILES or f.startswith(KEEP_DIRS)) or not os.path.isfile(f): continue
        data = open(f, 'rb').read()
        if f == 'build.py':
            t = data.decode('utf-8')
            t = re.sub(r"CFG\.get\('supabase_url', '[^']*'\)", "CFG.get('supabase_url', 'https://VASE-PROJEKT.supabase.co')", t)
            t = re.sub(r"CFG\.get\('supabase_publishable_key', '[^']*'\)", "CFG.get('supabase_publishable_key', 'VAS_PUBLISHABLE_KLIC')", t)
            data = t.encode('utf-8')
        elif f == '_headers':
            data = re.sub(r'(https|wss)://[a-z0-9-]+\.supabase\.co', r'\1://VASE-PROJEKT.supabase.co', data.decode('utf-8')).encode('utf-8')
        z.writestr('vexaronet/' + f, data)
    z.writestr('vexaronet/config.local.json', '{"edition": "local"}\n')
    z.writestr('vexaronet/README.md', README)
    z.writestr('vexaronet/LICENCE.txt', LIC)
print('Hotovo:', out)
