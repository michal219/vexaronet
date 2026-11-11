"""UI test vývojové fáze: lišta s odpočtem a volnými místy, uzavřená registrace (jen přihlášení, registrace jen pro pozvané),
výpadek stavu (web dál funguje, rozhoduje server) a hláška při odmítnutí firmy serverem.
Skutečné vynucení limitu ověřuje tests/db/run_registrace_local.sh. Spuštění: python3 tests/registrace_ui.py"""
import datetime, json, os, sys
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOCK = r'''
(function(){var C=window.__cfg||{};window.__log=[];
function ok(d){return Promise.resolve({data:d,error:null})}
function rpc(n,a){window.__log.push(n);
 if(n==='registration_status'){if(C.fail)return Promise.resolve({data:null,error:{message:'Could not find the function'}});return ok(C.st)}
 return ok(null)}
function qb(){var o={select(){return o},eq(){return o},limit(){return o},then(f){return Promise.resolve({data:[],error:null}).then(f)}};return o}
window.supabase={createClient:function(){return{from:qb,rpc:rpc,auth:{getSession:()=>Promise.resolve({data:{session:null}}),getUser:()=>Promise.resolve({data:{user:null}}),onAuthStateChange(){},signUp:()=>Promise.resolve({data:{},error:null})}}}};
})();
'''
fails = []
def check(c, m):
    print(('OK   ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
launch = datetime.date.today() + datetime.timedelta(days=30)
import functools, http.server, socketserver, threading
class Q(http.server.SimpleHTTPRequestHandler):
    def log_message(s, *a): pass
srv = socketserver.TCPServer(('127.0.0.1', 0), functools.partial(Q, directory=ROOT + '/public')); BASE = 'http://127.0.0.1:%d' % srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
def page(b, cfg):
    pg = b.new_page(viewport={'width': 1300, 'height': 900}); pg.errs = []
    pg.on('pageerror', lambda e: pg.errs.append(str(e)))
    pg.add_init_script('window.__cfg=' + json.dumps(cfg) + ';'); pg.add_init_script(MOCK)
    pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript'))
    pg.route('**/api/registration', lambda r: r.fulfill(status=503, body='{"error":"unavailable"}', content_type='application/json') if cfg.get('fail') else r.fulfill(body=json.dumps(cfg['st']), content_type='application/json'))
    pg.goto(BASE + '/index.html'); pg.wait_for_timeout(700); return pg
with sync_playwright() as p:
    b = p.chromium.launch()
    # 1) otevřená registrace
    pg = page(b, {'st': {'limited': True, 'open': True, 'max': 10, 'remaining': 3, 'launch_on': launch.isoformat()}})
    t = pg.inner_text('#regBar')
    check(pg.locator('#regBar').is_visible(), 'lišta vývojové fáze je vidět nahoře na úvodní stránce')
    check('zbývá 30 dní' in t and launch.strftime('%-d. %-m. %Y') in t, 'odpočet do plného spuštění: 30 dní a datum (%s)' % t.split('\n')[0][:80])
    check('3 z 10' in t and 'jen 10 firem' in t and 'zpětnou vazbu' in t, 'počet volných míst 3 z 10 a účel (zpětná vazba)')
    check(pg.locator('#top .cta [data-early]').inner_text().strip() == 'Založit účet zdarma', 'otevřeno: tlačítko registrace zůstává')
    pg.click('#top .cta [data-early]'); pg.wait_for_timeout(300)
    check(pg.locator('#aName').count() == 1 and pg.locator('#regNote').count() == 0, 'otevřeno: otevře se registrační formulář')
    check(not pg.errs, 'bez chyb JS: %s' % pg.errs)
    check('registration_status' not in pg.evaluate('window.__log.join()'), 'stav se nenačítá přímo ze Supabase (jen přes /api/registration)'); pg.close()
    # 2) uzavřená registrace
    pg = page(b, {'st': {'limited': True, 'open': False, 'max': 10, 'remaining': 0, 'launch_on': launch.isoformat()}})
    t = pg.inner_text('#regBar')
    check('Všech 10 míst' in t and 'uzavřená' in t and 'přihlášení funguje' in t, 'uzavřeno: lišta to jasně říká')
    check(all(x.strip() == 'Přihlásit se' for x in pg.locator('[data-early]').all_inner_texts()), 'uzavřeno: všechna tlačítka registrace nabízejí přihlášení')
    pg.click('#top .cta [data-early]'); pg.wait_for_timeout(300)
    check(pg.locator('#aName').count() == 0 and pg.locator('#aPw').count() == 1 and 'uzavřená' in pg.inner_text('#regNote'), 'uzavřeno: místo registrace se otevře přihlášení s vysvětlením')
    pg.click('#regNote [data-auth=signup]'); pg.wait_for_timeout(300)
    check(pg.locator('#aName').count() == 1 and pg.is_checked('#aInv') and pg.is_disabled('#aInv') and 'pozval' in pg.inner_text('#regNote'), 'uzavřeno: registrace jen pro pozvané zaměstnance (volba je zamčená)')
    check(pg.locator('#aCo').is_hidden(), 'uzavřeno: pole pro název nové firmy je skryté')
    pg.click('#authForm ~ * , .bar [data-auth=signup]') if pg.locator('.bar [data-auth=signup]').count() else None; pg.wait_for_timeout(200)
    check(pg.locator('#aName').count() == 0, 'uzavřeno: záložka Registrace vede na přihlášení')
    src = open(ROOT + '/public/index.html', encoding='utf-8').read()
    check("/registration_closed/.test(m))return 'Všech 10 míst pro testovací firmy je obsazeno" in src, 'odmítnutí serverem (registration_closed) má srozumitelnou hlášku')
    check(not pg.errs, 'bez chyb JS: %s' % pg.errs); pg.close()
    # 3) výpadek stavu: odpočet z výchozího data, registrace se neblokuje (rozhoduje server)
    pg = page(b, {'fail': True})
    t = pg.inner_text('#regBar')
    check('Vexaronet je ve vývoji' in t and '9. 12. 2026' in t and 'Volná místa' not in t, 'výpadek stavu: odpočet z výchozího data, bez vymyšleného počtu míst')
    check(pg.locator('#top .cta [data-early]').inner_text().strip() == 'Založit účet zdarma', 'výpadek stavu: registrace se v prohlížeči neblokuje (rozhoduje databáze)')
    check(not pg.errs, 'bez chyb JS: %s' % pg.errs); pg.close()
    # 4) mobil
    pg = b.new_page(viewport={'width': 390, 'height': 800}); pg.add_init_script('window.__cfg=' + json.dumps({'st': {'limited': True, 'open': True, 'max': 10, 'remaining': 7, 'launch_on': launch.isoformat()}}) + ';'); pg.add_init_script(MOCK)
    pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript')); pg.route('**/api/registration', lambda r: r.fulfill(body=json.dumps({'limited': True, 'open': True, 'max': 10, 'remaining': 7, 'launch_on': launch.isoformat()}), content_type='application/json')); pg.goto(BASE + '/index.html'); pg.wait_for_timeout(700)
    w = pg.evaluate('[document.documentElement.scrollWidth, innerWidth]')
    check(w[0] <= w[1] + 1 and pg.locator('#regBar').is_visible(), 'mobil 390 px: lišta se vejde bez vodorovného posouvání %s' % w)
    pg.screenshot(path=os.environ.get('SHOT', '/dev/null') if os.environ.get('SHOT') else ROOT + '/tests/_tmp_reg.png'); pg.close()
    b.close()
try: os.remove(ROOT + '/tests/_tmp_reg.png')
except OSError: pass
print('\nSELHALO: %d' % len(fails) if fails else '\nVšechny kontroly prošly.')
sys.exit(1 if fails else 0)
