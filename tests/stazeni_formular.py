"""Stažení: bez e-mailu a souhlasů se nic nestáhne, soubory nejsou veřejně dostupné, funkce /api/stahnout vydává zip až po uložení e-mailu."""
from playwright.sync_api import sync_playwright
import sys, subprocess, time, os, json
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ok = []; bad = []
def chk(n, c): (ok if c else bad).append(n); print('OK  ' if c else 'FAIL', n)
# --- funkce (Node, falešné Supabase a ASSETS) ---
js = r'''
const fs = await import('fs'); fs.copyFileSync(process.argv[2], '/tmp/stahnout_fn.mjs'); const m = await import('file:///tmp/stahnout_fn.mjs');
const calls = []; let sbStatus = 201;
globalThis.fetch = async (u, o) => { calls.push([String(u), o && o.body]); return new Response('', { status: sbStatus }); };
const env = { ASSETS: { fetch: async (u) => new Response('ZIPDATA', { status: 200 }) } };
const mk = (b) => new Request('https://x.test/api/stahnout', { method: 'POST', headers: { 'content-type': 'application/json', 'cf-connecting-ip': '1.1.1.' + Math.floor(Math.random() * 250) }, body: JSON.stringify(b) });
const good = { email: 'A@B.cz', file: 'lokalni', consent: true, license: true, age: true };
const out = {};
let r = await m.onRequest({ request: mk(good), env }); out.ok = [r.status, r.headers.get('content-disposition'), await r.text(), calls.length];
for (const k of ['consent', 'license', 'age']) { calls.length = 0; r = await m.onRequest({ request: mk({ ...good, [k]: false }), env }); out['bez_' + k] = [r.status, calls.length]; }
calls.length = 0; r = await m.onRequest({ request: mk({ ...good, email: 'zle' }), env }); out.zly_email = [r.status, calls.length];
calls.length = 0; r = await m.onRequest({ request: mk({ ...good, file: '../x' }), env }); out.zly_soubor = [r.status, calls.length];
sbStatus = 409; r = await m.onRequest({ request: mk(good), env }); out.duplicita = r.status;
sbStatus = 500; r = await m.onRequest({ request: mk(good), env }); out.db_chyba = [r.status, (await r.text()).includes('ZIPDATA')];
console.log(JSON.stringify(out));
'''
open('/tmp/fn_test.mjs', 'w').write(js)
o = json.loads(subprocess.run(['node', '/tmp/fn_test.mjs', R + '/functions/api/stahnout.js'], capture_output=True, text=True).stdout or '{}')
chk('funkce vydá zip po uložení e-mailu', o.get('ok', [0])[0] == 200 and o['ok'][2] == 'ZIPDATA' and 'Vexaronet-lokalni.zip' in o['ok'][1] and o['ok'][3] == 1)
chk('funkce bez souhlasu, licence nebo věku nevydá nic', all(o.get('bez_' + k) == [400, 0] for k in ('consent', 'license', 'age')))
chk('funkce odmítne špatný e-mail a název souboru', o.get('zly_email') == [400, 0] and o.get('zly_soubor') == [400, 0])
chk('duplicitní e-mail soubor dostane', o.get('duplicita') == 200)
chk('při chybě databáze se soubor nevydá', o.get('db_chyba') == [502, False])
# přímý přístup je blokovaný
routes = json.load(open(R + '/public/_routes.json'))['include']
chk('/stazeni/* jde přes middleware (404)', '/stazeni/*' in routes)
# --- formulář v prohlížeči ---
srv = subprocess.Popen([sys.executable, '-m', 'http.server', '8765', '-d', R + '/public'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); time.sleep(1)
with sync_playwright() as p:
    b = p.chromium.launch()
    for vw, nm in ((1360, 'desktop'), (390, 'mobil')):
        pg = b.new_page(viewport={'width': vw, 'height': 900}, accept_downloads=True); errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        calls = []
        pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript'))
        def dl(r):
            calls.append(r.request.post_data); r.fulfill(status=200, content_type='application/zip', body=b'PK-test')
        pg.route('**/api/stahnout', dl)
        pg.goto('http://localhost:8765/index.html'); pg.wait_for_timeout(3000)
        chk(nm + ' v HTML nejsou přímé odkazy na zip', pg.eval_on_selector_all('a[href*="stazeni"]', 'e=>e.length') == 0)
        pg.evaluate("document.getElementById('dlForm').scrollIntoView()")
        pg.fill('#dlMail', 'test@example.invalid')
        pg.click('#dlGo'); pg.wait_for_timeout(300); chk(nm + ' bez licence nejde', not calls)
        pg.check('[name=lic]'); pg.click('#dlGo'); pg.wait_for_timeout(300); chk(nm + ' bez souhlasu s novinkami nejde', not calls)
        pg.check('[name=souhlas]'); pg.click('#dlGo'); pg.wait_for_timeout(300); chk(nm + ' bez věku nejde', not calls)
        pg.check('[name=vek]')
        with pg.expect_download() as d: pg.click('#dlGo')
        chk(nm + ' aplikace se stáhne', d.value.suggested_filename == 'Vexaronet-lokalni.zip' and len(calls) == 1 and '"consent":true' in calls[0] and '"file":"lokalni"' in calls[0])
        with pg.expect_download() as d2: pg.click('button[data-f=zdroj]')
        chk(nm + ' zdrojový kód se stáhne', d2.value.suggested_filename == 'Vexaronet-zdrojovy-kod.zip')
        chk(nm + ' bez vodorovného posunu', pg.evaluate('document.documentElement.scrollWidth') <= vw + 1)
        chk(nm + ' bez JS chyb', not errs); print(errs)
    b.close()
srv.terminate(); print(len(ok), 'OK', len(bad), 'FAIL'); sys.exit(1 if bad else 0)
