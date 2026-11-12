"""UI test propojení sociálních sítí (Facebook, Instagram): Integrace, hlavička, zveřejnění ze schváleného náhledu, nejasný výsledek, odpojení.
Mock napodobuje RPC social_* a endpoint /api/social. Skutečné vynucení rolí, schválení a šifrování tokenů ověřuje tests/social_e2e.test.mjs.
Spuštění: python3 tests/social_ui.py"""
import hashlib, http.server, json, os, re, socketserver, sys, threading
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CID = '11111111-1111-1111-1111-111111111111'
SRC = open(os.path.join(ROOT, 'tests', 'ai_marketing_ui.py'), encoding='utf-8').read()
MOCK = re.search(r"MOCK = r'''(.*?)'''", SRC, re.S).group(1)
SOCMOCK = r'''
(function(){var C=window.__cfg||{},oc=window.supabase.createClient;
var T=JSON.parse(sessionStorage.getItem('__soc')||'null')||{accounts:C.accounts||[],publications:C.publications||[]};window.__T=T;
function save(){sessionStorage.setItem('__soc',JSON.stringify(T))}window.__socSave=save;
window.supabase.createClient=function(){var c=oc(),r=c.rpc;c.rpc=function(n,a){
 if(n.indexOf('social_')!==0)return r(n,a);window.__log.push(['rpc',n,JSON.parse(JSON.stringify(a||{}))]);
 if(C.noSoc)return Promise.resolve({data:null,error:{code:'PGRST202',message:'Could not find the function public.social_state(cid) in the schema cache'}});
 if(n==='social_state')return Promise.resolve({data:JSON.parse(JSON.stringify(T)),error:null});
 if(n==='social_disconnect'){T.accounts=T.accounts.filter(function(x){return x.id!==a.p_account});save();return Promise.resolve({data:{ok:true},error:null})}
 if(n==='social_publish_resolve'){T.publications.forEach(function(x){if(x.id===a.p_pub)x.status=a.p_published?'published':'failed'});save();return Promise.resolve({data:{status:'x'},error:null})}
 return Promise.resolve({data:null,error:{message:'neznámé '+n}})};return c}})();
'''
CO = [{'id': CID, 'name': 'Autoservis Konina', 'industry': 'Autoservis', 'parent_company_id': None, 'created_at': '2026-10-01T00:00:00Z'}]
def members(role='owner'): return [{'company_id': CID, 'role': role, 'companies': CO[0]}]
ACC = [{'id': 'a-fb', 'provider': 'facebook', 'name': 'Autoservis <img src=x onerror=window.__xss=1>', 'username': None, 'connected_at': '2026-11-12T10:00:00Z', 'last_error': None},
       {'id': 'a-ig', 'provider': 'instagram', 'name': 'Autoservis', 'username': 'autoservis_konina', 'connected_at': '2026-11-12T10:00:00Z', 'last_error': None}]
def ph(p): return hashlib.sha256(((p.get('title') or '') + '\x1f' + (p.get('body') or '') + '\x1f' + (p.get('channel') or '')).encode('utf-8')).hexdigest()
P1 = {'id': 'p1', 'company_id': CID, 'title': 'Přezujte včas', 'channel': 'Instagram', 'status': 'planned', 'planned_on': None, 'body': 'Zimní pneumatiky přezujeme rychle.'}
P2 = {'id': 'p2', 'company_id': CID, 'title': 'Tichý výfuk', 'channel': 'Facebook', 'status': 'draft', 'planned_on': None, 'body': 'Hlučný výfuk vyměníme.'}
fails = []
def check(c, m):
    print(('OK   ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
class Q(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def log_message(s, *a): pass
srv = socketserver.TCPServer(('127.0.0.1', 0), Q); PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = 'http://127.0.0.1:%d/index.html' % PORT
API = {'calls': [], 'mode': []}
def api(route):
    body = json.loads(route.request.post_data or '{}'); API['calls'].append(dict(body, _auth=route.request.headers.get('authorization')))
    mode = API['mode'].pop(0) if API['mode'] else 'ok'
    if mode == 'not_configured': return route.fulfill(status=503, content_type='application/json', body=json.dumps({'error': 'not_configured'}))
    if mode == 'unknown': return route.fulfill(status=504, content_type='application/json', body=json.dumps({'error': 'unknown_outcome'}))
    if mode == 'evil': return route.fulfill(status=200, content_type='application/json', body=json.dumps({'url': 'https://evil.example/phish'}))
    if body.get('op') == 'begin': return route.fulfill(status=200, content_type='application/json', body=json.dumps({'url': 'https://www.facebook.com/v27.0/dialog/oauth?client_id=1&state=s'}))
    route.fulfill(status=200, content_type='application/json', body=json.dumps({'ok': True, 'status': 'published', 'permalink': 'https://www.instagram.com/p/abc/'}))
def open_page(b, cfg, url=BASE, posts=True):
    ctx = b.new_context(viewport={'width': 1400, 'height': 1000}); pg = ctx.new_page(); pg.errs = []; pg.dialogs = []
    pg.on('pageerror', lambda e: pg.errs.append(str(e)))
    pg.on('dialog', lambda d: (pg.dialogs.append(d.message), d.accept()))
    today = __import__('datetime').date.today().isoformat()
    ps = [dict(P1, planned_on=today), dict(P2, planned_on=today)] if posts else []
    seed = {'profile': True, 'strategy': None, 'approved': None, 'posts': ps, 'items': {'p1': {'ah': ph(P1)}, 'p2': {}} if posts else {}, 'results': {}, 'nid': 1, 'web': False}
    pg.add_init_script('window.__cfg=' + json.dumps(dict(cfg, companies=CO, cid=CID, profile=True)) + ';if(!sessionStorage.getItem("__mk"))sessionStorage.setItem("__mk",' + json.dumps(json.dumps(seed)) + ');')
    pg.add_init_script(MOCK); pg.add_init_script(SOCMOCK)
    pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript'))
    pg.route('**/api/social', api); pg.route('https://www.facebook.com/**', lambda r: r.fulfill(body='<title>Meta</title>', content_type='text/html'))
    pg.expose_function('__pyhash', ph)
    pg.goto(url); pg.wait_for_timeout(500)
    return pg
def login(pg):
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(400)
    pg.evaluate("var x=document.createElement('button');x.dataset.tab='autopilot';x.id='__ap';document.querySelector('#vxapp').appendChild(x);x.click()"); pg.wait_for_selector('#apd'); pg.wait_for_timeout(500)
def dtab(pg, k): pg.click('#apd [data-apd=%s]' % k); pg.wait_for_timeout(500)
def log(pg, n): return pg.evaluate("window.__log.filter(function(x){return x[1]==='%s'}).map(function(x){return x[2]})" % n)
def toast(pg): return pg.inner_text('#appToast')

with sync_playwright() as p:
    b = p.chromium.launch()
    # 1) databázová část ještě není nasazená
    pg = open_page(b, {'members': members(), 'noSoc': True}); login(pg)
    check('Nepřipojeno' in pg.inner_text('#socHead'), 'hlavička bez účtů: „Nepřipojeno“')
    pg.click('#socHead [data-apd-act=connect]'); pg.wait_for_timeout(500)
    t = pg.inner_text('#socList')
    check('ještě není v databázi nasazené' in t and pg.locator('#socList [data-apd-act=soc-connect]').is_disabled(), 'bez nasazené databáze: poctivá hláška a vypnuté tlačítko')
    check(API['calls'] == [], 'bez nasazené databáze se server nevolá'); pg.context.close()

    # 2) žádný účet: zahájení propojení
    pg = open_page(b, {'members': members()}); login(pg); dtab(pg, 'integrace')
    t = pg.inner_text('#socList')
    check('Zatím není propojená žádná stránka' in t and 'TikTok' in t and t.count('Nepodporováno') == 4, 'prázdný stav a poctivě označené nepodporované sítě')
    check('Nic nepublikuje sám' in t and 'zašifrovaně' in t and 'profesionální účet' in t, 'vysvětlení rozsahu přístupu a podmínek')
    API['mode'] = ['not_configured']; pg.click('#socList [data-apd-act=soc-connect]'); pg.wait_for_selector('.apdm')
    check('není provozovatelem nastavené' in pg.inner_text('.apdm'), 'nenastavená aplikace Meta: srozumitelná hláška')
    check(API['calls'][-1]['op'] == 'begin' and API['calls'][-1]['cid'] == CID and API['calls'][-1]['_auth'] == 'Bearer t', 'zahájení posílá firmu a přihlášení')
    pg.click('.apdm [data-apdm]'); API['mode'] = ['evil']; pg.click('#socList [data-apd-act=soc-connect]'); pg.wait_for_selector('.apdm')
    check('evil.example' not in pg.url, 'cizí adresa ze serveru se neotevře (jen facebook.com)')
    pg.click('.apdm [data-apdm]'); pg.click('#socList [data-apd-act=soc-connect]'); pg.wait_for_url('https://www.facebook.com/**')
    check(pg.url.startswith('https://www.facebook.com/v27.0/dialog/oauth'), 'přesměrování na přihlášení u Meta'); check(pg.errs == [], 'bez chyb skriptu'); pg.context.close()

    # 3) návrat z Meta: hláška a vyčištěná adresa
    pg = open_page(b, {'members': members(), 'accounts': ACC}, url=BASE + '?social=connected'); pg.wait_for_selector('#socList'); pg.wait_for_timeout(500)
    check('social=' not in pg.url and 'Účty jsou propojené' in toast(pg), 'návrat z Meta: otevře Integrace, ukáže hlášku a parametr zmizí z adresy')
    pg2 = open_page(b, {'members': members()}, url=BASE + '?social=<script>'); pg2.wait_for_timeout(1000)
    check('social=' not in pg2.url and pg2.errs == [], 'neznámá hodnota parametru se ignoruje'); pg2.context.close()

    # 4) propojené účty: hlavička, seznam, escapování
    check('Propojeno: 2' in pg.inner_text('#socHead') and 'Spravovat' in pg.inner_text('#socHead'), 'hlavička ukazuje počet propojených účtů')
    dtab(pg, 'integrace'); t = pg.inner_text('#socList')
    check('@autoservis_konina' in t and pg.locator('#socList [data-apd-act=soc-disconnect]').count() == 2, 'seznam účtů s možností odpojit')
    check(pg.evaluate('window.__xss') is None and pg.locator('#socList img').count() == 0, 'název účtu je escapovaný')
    # 5) zveřejnění schváleného příspěvku
    dtab(pg, 'kalendar'); pg.click('#apd [data-apd-act=prev][data-id=p2]'); pg.wait_for_selector('.apdm')
    check(pg.locator('.apdm [data-mkm=soc]').count() == 0, 'neschválený příspěvek nejde zveřejnit na síť'); pg.click('.apdm [data-apdm]')
    pg.click('#apd [data-apd-act=prev][data-id=p1]'); pg.wait_for_selector('.apdm [data-mkm=soc]')
    check(pg.eval_on_selector('#mkm_acc', 'e=>e.value') == 'a-ig' and pg.is_visible('#mkm_img'), 'kanál Instagram předvybere účet Instagramu a ukáže pole obrázku')
    pg.select_option('#mkm_acc', 'a-fb'); check(not pg.is_visible('#mkm_img'), 'Facebook obrázek nevyžaduje'); pg.select_option('#mkm_acc', 'a-ig')
    n0 = len(API['calls']); pg.click('.apdm [data-mkm=soc]'); pg.wait_for_timeout(300)
    check(len(API['calls']) == n0 and 'vyžaduje obrázek' in toast(pg), 'Instagram bez obrázku: nic se neodešle')
    pg.fill('#mkm_img', 'https://cdn.example/a.jpg'); pg.click('.apdm [data-mkm=soc]'); pg.wait_for_timeout(800)
    c = API['calls'][-1]
    check(c['op'] == 'publish' and c['post'] == 'p1' and c['account'] == 'a-ig' and c['image_url'] == 'https://cdn.example/a.jpg', 'zveřejnění posílá příspěvek, účet a obrázek')
    check(any('nyní veřejně' in d for d in pg.dialogs), 'před zveřejněním se ptá na potvrzení')
    check('zveřejněný' in toast(pg) and pg.locator('.apdm').count() == 0, 'po úspěchu hláška a zavřený náhled')
    # 6) nejasný výsledek
    pg.evaluate("window.__T.publications=[{id:'pub1',post_id:'p1',account_id:'a-fb',provider:'facebook',account:'Autoservis',status:'unknown'}];window.__socSave()")
    dtab(pg, 'integrace'); dtab(pg, 'kalendar'); pg.click('#apd [data-apd-act=prev][data-id=p1]'); pg.wait_for_selector('.apdm [data-mkm=soc-no]')
    check('Nejasný výsledek' in pg.inner_text('.apdm') and pg.locator('.apdm [data-mkm=soc]').count() == 0, 'nejasný výsledek: místo nového pokusu se ptá, zda příspěvek vyšel')
    pg.click('.apdm [data-mkm=soc-no]'); pg.wait_for_timeout(600)
    r = log(pg, 'social_publish_resolve'); check(len(r) == 1 and r[0]['p_pub'] == 'pub1' and r[0]['p_published'] is False, 'rozhodnutí člověka se uloží')
    # 7) odpojení
    dtab(pg, 'integrace'); pg.click('#socList [data-apd-act=soc-disconnect][data-id=a-ig]'); pg.wait_for_timeout(700)
    d = log(pg, 'social_disconnect'); check(len(d) == 1 and d[0]['p_account'] == 'a-ig' and pg.locator('#socList [data-apd-act=soc-disconnect]').count() == 1, 'odpojení po potvrzení a seznam se obnoví')
    check(pg.errs == [], 'bez chyb skriptu: ' + '; '.join(pg.errs)); pg.context.close()

    # 8) zaměstnanec se k propojení vůbec nedostane a stav účtů se pro něj nenačítá
    pg = open_page(b, {'members': members('employee'), 'accounts': ACC}); pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(400)
    pg.evaluate("var x=document.createElement('button');x.dataset.tab='autopilot';document.querySelector('#vxapp').appendChild(x);x.click()"); pg.wait_for_timeout(600)
    check(pg.locator('#socList').count() == 0 and pg.locator('[data-apd-act=soc-connect]').count() == 0 and log(pg, 'social_state') == [], 'zaměstnanec propojení nevidí a stav účtů se nenačítá'); pg.context.close()

    # 9) ukázka: nic se nevolá
    ctx = b.new_context(viewport={'width': 1400, 'height': 1000}); pg = ctx.new_page(); n0 = len(API['calls'])
    pg.route('**/api/social', api); pg.route('**/api/registration', lambda r: r.fulfill(status=503, body='{}', content_type='application/json'))
    pg.goto(BASE); pg.wait_for_timeout(600); pg.click('#top .cta [data-demo]'); pg.wait_for_selector('#vxapp .kpi')
    pg.evaluate("document.querySelector('#vxapp [data-tab=autopilot]').click()"); pg.wait_for_selector('#apd'); dtab(pg, 'integrace')
    pg.click('#socList [data-apd-act=soc-connect]'); pg.wait_for_timeout(400)
    check(len(API['calls']) == n0 and 'Ukázka' in pg.inner_text('#appToast'), 'ukázka: propojení se nespouští'); ctx.close()
    b.close()
srv.shutdown()
print('\nsocial_ui: ok=%s fail=%d' % ('ano' if not fails else 'ne', len(fails)))
if fails: sys.exit(1)
print('Všechny kontroly prošly.')
