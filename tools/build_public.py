#!/usr/bin/env python3
"""Sestaví složku public/: jen soubory, které web skutečně servíruje.

Cloudflare Pages má jako výstupní adresář nastavenou složku `public`, takže interní soubory
(docs/, db/, src/, tests/, tools/, schema*.sql, *.md, build.py, android/, desktop/, netlify*)
se na web nedostanou. Pages Functions zůstávají ve `functions/` v kořeni repozitáře
a importy `../../src/*.js` se dál sbalí při nasazení (nejsou to veřejné soubory).

Skript používá jen standardní knihovnu (bez Node), aby šel spustit jako build příkaz
Cloudflare Pages: `python3 tools/build_public.py`. Spouští ho i konec `build.py`.
Vstup jsou už vygenerované soubory v kořeni (index.html, právní stránky), které jsou v gitu.

Nový veřejný soubor nebo složku je potřeba přidat do PUBLIC níže, jinak na webu nebude.
"""
import os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, os.environ.get('VX_PUBLIC_DIR', 'public'))

# Seznam povolených veřejných cest (relativně ke kořeni repozitáře).
PUBLIC = [
    # aplikace a web (index.html generuje build.py)
    'index.html', '404.html', 'manifest.webmanifest', 'sw.js', 'robots.txt', 'sitemap.xml',
    # konfigurace Cloudflare Pages (hlavičky zabezpečení, přesměrování); musí být ve výstupní složce
    '_headers', '_redirects',
    # ikony, obrázky, fonty, lokální knihovny (supabase-js s SRI, rrweb)
    'assets',
    # statické stránky, které generuje build.py
    'podminky', 'ochrana-udaju', 'cookies', 'dsa', 'nahlasit', 'odhlasit',
]
# base.css se do index.html vkládá při sestavení (build.py), samostatně ho web nenačítá.


def build():
    for p in PUBLIC:
        if not os.path.exists(os.path.join(ROOT, p)):
            sys.exit('build_public: chybí %s (spusťte nejdřív python3 build.py)' % p)
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    for p in PUBLIC:
        src, dst = os.path.join(ROOT, p), os.path.join(OUT, p)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
    check()
    n = sum(len(f) for _, _, f in os.walk(OUT))
    print('public/: %d souborů' % n)


def check():
    """Každá lokální cesta, na kterou odkazují stránky, musí ve public/ existovat."""
    pages = ['index.html', '404.html', 'sw.js', 'manifest.webmanifest'] + \
        [p + '/index.html' for p in PUBLIC if os.path.isfile(os.path.join(OUT, p, 'index.html'))]
    missing = set()
    for pg in pages:
        txt = open(os.path.join(OUT, pg), encoding='utf-8').read()
        for m in re.finditer(r'''(?:src|href|content)=["'](/?(?:assets/|manifest|sw\.js)[^"'?#]*)|url\((/assets/[^)?#]+)\)|["'](/assets/[^"'?#]+)["']''', txt):
            u = (m.group(1) or m.group(2) or m.group(3)).lstrip('/')
            if not os.path.exists(os.path.join(OUT, u)):
                missing.add('%s → /%s' % (pg, u))
    if missing:
        sys.exit('build_public: odkazované soubory chybí ve public/:\n  ' + '\n  '.join(sorted(missing)))


if __name__ == '__main__':
    build()
