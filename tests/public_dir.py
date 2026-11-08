"""Veřejný výstup pro Cloudflare Pages (`public/`): obsahuje jen povolené soubory, nic potřebného nechybí a nic interního tam není.
1) public/ odpovídá čerstvému sestavení (build.py) – v gitu není zastaralý;
2) nejvyšší úroveň je přesně allowlist; žádné .md/.sql/.py, docs/, db/, src/, tests/, tools/, functions/;
3) každý lokální odkaz v HTML, CSS, manifestu a sw.js vede na existující soubor v public/;
4) v public/ není název ani tvar serverového klíče;
5) prohlížeč načte web servírovaný JEN z public/: žádný požadavek na vlastní doménu nevrátí 404, supabase-js se načte (SRI), interní cesty vrací 404.
Spuštění: python3 tests/public_dir.py"""
import filecmp, functools, http.server, os, re, socketserver, subprocess, sys, tempfile, threading
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUB = os.path.join(ROOT, 'public')
fails = []
def check(c, m):
    print(('OK   ' if c else 'FAIL ') + m)
    if not c: fails.append(m)

# 1) čerstvé sestavení do dočasné složky a porovnání s public/ v repozitáři
tmp = tempfile.mkdtemp()
subprocess.run(['cp', '-r', ROOT + '/.', tmp], check=True)
subprocess.run(['rm', '-rf', tmp + '/public'], check=True)
r = subprocess.run([sys.executable, 'build.py'], cwd=tmp, capture_output=True, text=True)
check(r.returncode == 0, 'build.py proběhne')
def same(a, b):
    c = filecmp.dircmp(a, b)
    return not (c.left_only or c.right_only or c.diff_files or c.funny_files) and all(same(os.path.join(a, d), os.path.join(b, d)) for d in c.common_dirs)
check(same(PUB, tmp + '/public'), 'public/ v repozitáři odpovídá čerstvému sestavení (po změně spusťte build.py a commitněte public/)')

# 2) allowlist
TOP = {'index.html', '404.html', 'sw.js', 'manifest.webmanifest', 'robots.txt', 'sitemap.xml', '_headers', '_redirects', '_routes.json',
       'assets', 'podminky', 'ochrana-udaju', 'cookies', 'dsa', 'nahlasit', 'odhlasit'}
check(set(os.listdir(PUB)) == TOP, 'nejvyšší úroveň public/ je přesně allowlist: %s' % sorted(set(os.listdir(PUB)) ^ TOP))
files = [os.path.relpath(os.path.join(d, f), PUB) for d, _, fs in os.walk(PUB) for f in fs]
bad = [f for f in files if re.search(r'\.(md|sql|py|mjs|sh|toml|yml|yaml|env|pem|key)$', f) or f.split('/')[0] in ('docs', 'db', 'src', 'tests', 'tools', 'functions', 'netlify', 'android', 'desktop', '.git')]
check(not bad, 'žádné interní soubory: %s' % bad)

# 3) lokální odkazy
missing = set()
for f in files:
    if not re.search(r'\.(html|css|webmanifest|js)$', f) or f.startswith('assets/vendor/'): continue
    t = open(os.path.join(PUB, f), encoding='utf-8').read()
    refs = re.findall(r'(?:src|href)="([^"#?]+)', t) + re.findall(r'url\(["\']?([^)"\']+)', t) + re.findall(r'"src":\s*"([^"]+)"', t)
    refs += re.findall(r'https://vexaronet\.com(/[^"\'\s?#)]*)', t) + re.findall(r"'(/assets/[^']+)'", t)
    for u in refs:
        if re.match(r'^(https?:|mailto:|tel:|data:|blob:|javascript:|about:|//|#|%23|\\)', u) or '{' in u or '+' in u: continue
        p = u if u.startswith('/') else '/' + os.path.join(os.path.dirname(f), u)
        p = os.path.normpath(p)
        if p.startswith('/api/') or p in ('/', '/cenik'): continue
        if p.endswith('/') or os.path.isdir(PUB + p): p = p.rstrip('/') + '/index.html'
        if not os.path.isfile(PUB + p): missing.add((f, u))
check(not missing, 'všechny lokální odkazy vedou do public/: %s' % sorted(missing)[:10])

# 4) stopy serverového klíče
leak = [f for f in files if not f.endswith(('.png', '.jpg', '.webp', '.woff2')) and re.search(r'SUPABASE_SERVICE_KEY|sb_secret_[A-Za-z0-9]|GEMINI_API_KEY|RESEND_API_KEY', open(os.path.join(PUB, f), encoding='utf-8', errors='ignore').read())]
check(not leak, 'v public/ není název ani hodnota serverového klíče: %s' % leak)

# 5) prohlížeč nad serverem, který servíruje JEN public/
class Q(http.server.SimpleHTTPRequestHandler):
    def log_message(s, *a): pass
srv = socketserver.TCPServer(('127.0.0.1', 0), functools.partial(Q, directory=PUB)); port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = 'http://127.0.0.1:%d' % port
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(); errs = []; nf = []
    pg.on('pageerror', lambda e: errs.append(str(e)))
    pg.on('response', lambda r: nf.append(r.url) if r.url.startswith(base) and r.status >= 400 else None)
    for path in ['/', '/podminky/', '/ochrana-udaju/', '/cookies/', '/dsa/', '/nahlasit/', '/odhlasit/']:
        pg.goto(base + path, wait_until='networkidle'); pg.wait_for_timeout(300)
    pg.goto(base + '/', wait_until='networkidle'); pg.wait_for_timeout(600)
    check(pg.evaluate("typeof window.supabase==='object'&&typeof window.supabase.createClient==='function'"), 'supabase-js se načte z public/ (kontrola SRI prošla)')
    check(pg.evaluate("document.fonts.check('16px Manrope')||document.fonts.size>0"), 'písma jsou k dispozici')
    check(not nf, 'žádný požadavek na vlastní doménu nevrátil chybu: %s' % nf[:5])
    check(not errs, 'bez chyb JS: %s' % errs[:3])
    b.close()
import urllib.request, urllib.error
def status(u):
    try: return urllib.request.urlopen(base + u).status
    except urllib.error.HTTPError as e: return e.code
internal = ['/docs/SECURITY_STATUS.md', '/db/migrations/20261112100000_ai_marketing.sql', '/src/ai_guard.js', '/build.py', '/tests/public_dir.py', '/functions/api/chat.js', '/schema.sql', '/README.md']
st = {u: status(u) for u in internal}
check(all(v == 404 for v in st.values()), 'interní cesty vrací 404: %s' % st)
srv.shutdown()
print('\nSELHALO: %d' % len(fails) if fails else '\nVšechny kontroly prošly.')
sys.exit(1 if fails else 0)
