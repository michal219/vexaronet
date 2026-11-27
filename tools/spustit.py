#!/usr/bin/env python3
"""Sestaví lokální verzi Vexaronetu ze zdrojového kódu a otevře ji v prohlížeči.
Výsledek: složka Vexaronet-lokalni/ (soubor Vexaronet.html + assets). Potřebuje jen Python 3.
Použití: python3 tools/spustit.py            (sestaví a otevře)
         python3 tools/spustit.py --bez-otevreni"""
import os, re, shutil, subprocess, sys, tempfile, json, webbrowser
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'Vexaronet-lokalni')
T = tempfile.mkdtemp(prefix='vx-local-')
R = T + '/r'
shutil.copytree(ROOT, R, ignore=shutil.ignore_patterns('.git', 'node_modules', '__pycache__', '*.zip', 'Vexaronet-lokalni'))
json.dump({'edition': 'local'}, open(R + '/config.local.json', 'w'))
subprocess.run([sys.executable, R + '/build.py'], check=True, stdout=subprocess.DEVNULL)
html = open(R + '/index.html', encoding='utf-8').read()
html = html.replace('url(/assets/', 'url(assets/').replace('"/assets/', '"assets/')
html = re.sub(r'<link rel="manifest"[^>]*>', '', html)
html = re.sub(r'<link rel="preload"[^>]*fonts[^>]*>', '', html)
shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(OUT)
open(OUT + '/Vexaronet.html', 'w', encoding='utf-8').write(html)
for d, _, fs in os.walk(R + '/assets'):
    for f in fs:
        if 'og-image' in f: continue
        full = os.path.join(d, f)
        dst = os.path.join(OUT, os.path.relpath(full, R))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(full, dst)
shutil.rmtree(T, ignore_errors=True)
print('Hotovo: ' + OUT + os.sep + 'Vexaronet.html')
if '--bez-otevreni' not in sys.argv:
    webbrowser.open('file://' + os.path.join(OUT, 'Vexaronet.html'))
