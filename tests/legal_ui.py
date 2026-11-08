"""Právní soulad v prohlížeči (docs/PRAVNI_SOULAD.md): SKUTEČNÁ aplikace s hlavičkami z _headers, skutečný síťový provoz.
  1) žádný požadavek na cizí servery při načtení (fonty, CDN)
  2) souhlas: nic se neodesílá před souhlasem, po odmítnutí ani po odvolání; odmítnutí je stejně snadné jako přijetí
  3) maskování nahrávání relací ověřené na obsahu SKUTEČNĚ odeslaných požadavků (testovací cíl na stejném serveru)
  4) věk při registraci, 5) objednávky (žádost o tarif, e-shop), 6) formulář DSA a odhlášení z novinek
Data aplikace dodává simulace Supabase; databázové hranice ověřují tests/db/run_legal_local.sh a tests/legal_e2e.test.mjs.
Spuštění: python3 tests/legal_ui.py"""
import http.server, json, os, sys, threading, time
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HDR = {}
cur = None
for line in open(os.path.join(ROOT, '_headers'), encoding='utf-8'):
    if not line.strip() or line.lstrip().startswith('#'): continue
    if not line.startswith(' '): cur = line.strip(); HDR[cur] = {}; continue
    k, v = line.strip().split(':', 1); HDR[cur][k.strip()] = v.strip()
COLLECT = []
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def end_headers(self):
        for k, v in HDR.get('/*', {}).items(): self.send_header(k, v)
        super().end_headers()
    def do_POST(self):
        n = int(self.headers.get('content-length') or 0); body = self.rfile.read(n).decode('utf-8', 'replace')
        if self.path.startswith('/__collect/'):
            COLLECT.append((time.time(), self.path, body)); self.send_response(204); self.end_headers(); return
        self.send_response(404); self.end_headers()
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H); PORT = srv.server_address[1]; BASE = 'http://127.0.0.1:%d' % PORT
threading.Thread(target=srv.serve_forever, daemon=True).start()
fails = []
def check(c, m):
    print(('OK   ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
SECRETS = ['tajny.uzivatel@example.cz', 'Jan Tajný', 'Heslo-TAJNE-123', 'Tajná zpráva chatu 777', 'TAJNA-FIRMA-XYZ']
MOCK = r'''(function(){window.__signup=null;var CO={id:'c1',name:'Firma',industry:'Služby',parent_company_id:null};
var D={companies:[CO],company_members:[{company_id:'c1',role:'owner',companies:CO}],subscriptions:[{plan:'pro',status:'trial',trial_end:new Date(Date.now()+20*864e5).toISOString()}]};
function qb(t){var o={_op:'sel',select(){return o},eq(){return o},neq(){return o},gte(){return o},in(){return o},limit(){return o},is(){return o},order(){return o},single(){o._one=1;return o},maybeSingle(){o._one=1;return o},insert(x){window.__ins=(window.__ins||[]).concat([[t,x]]);return Promise.resolve({data:null,error:null})},update(){o._op='u';return o},delete(){o._op='d';return o},then(f,r){var d=o._op==='sel'?(D[t]||[]):null;if(o._one)d=d&&d[0]||null;return Promise.resolve({data:d,error:null}).then(f,r)}};return o}
function rpc(n,a){if(n==='public_shop')return Promise.resolve({data:{name:'Pekárna Test',title:'Pekárna Test',contact_email:'pekarna@test.cz',shipping_fee:50,payment_text:'Převodem',products:[{id:'p1',name:'Chléb',price:40,unit:'ks',available:9}]},error:null});
 if(n==='public_site')return Promise.resolve({data:{name:'Firma Test',data:{hero:{title:'Web firmy'}},booking:null},error:null});
 return Promise.resolve({data:null,error:{code:'PGRST202',message:'x'}})}
var sess=window.__loggedIn?{access_token:'t',user:{id:'u1'}}:null;
window.supabase={createClient:function(){return{from:qb,rpc:rpc,channel:function(){var c={on(){return c},subscribe(){return c}};return c},removeChannel(){},
 auth:{getSession:()=>Promise.resolve({data:{session:sess}}),getUser:()=>Promise.resolve({data:{user:sess?{id:'u1',email:'a@b.cz',user_metadata:{full_name:'Jan'}}:null}}),
  onAuthStateChange(){return{data:{subscription:{unsubscribe(){}}}}},signUp:(x)=>{window.__signup=x;return Promise.resolve({data:{user:{id:'n1'},session:null},error:null})},
  updateUser:(x)=>Promise.resolve({data:{user:{user_metadata:x.data||{}}},error:null}),signOut(){return Promise.resolve({})},signInWithPassword:()=>Promise.resolve({data:{},error:{message:'x'}})}}}};})();'''
def page(b, cfg=None, logged=False, vp=None, real_sb=False):
    pg = b.new_page(viewport=vp or {'width': 1300, 'height': 900}); pg.reqs = []; pg.errs = []
    pg.on('request', lambda r: pg.reqs.append(r.url)); pg.on('pageerror', lambda e: pg.errs.append(str(e)))
    if cfg: pg.add_init_script('window.VX_OPTIONAL_CFG=' + json.dumps(cfg) + ';')
    if logged: pg.add_init_script('window.__loggedIn=true;')
    pg.add_init_script(MOCK)
    if not real_sb: pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript'))   # simulace místo skutečné knihovny
    return pg
def foreign(pg): return sorted({urlparse(u).hostname for u in pg.reqs if urlparse(u).hostname not in ('127.0.0.1', None) and not u.startswith('data:')})

with sync_playwright() as p:
    b = p.chromium.launch()
    # ---------- 1) síťový provoz při načtení ----------
    pg = page(b, real_sb=True); pg.goto(BASE + '/'); pg.wait_for_timeout(1500)
    check(foreign(pg) == [], 'načtení webu: žádný požadavek na cizí server (fonty, CDN): %s' % foreign(pg))
    check(any('/assets/fonts/' in u and u.endswith('.woff2') for u in pg.reqs), 'fonty se načítají z vlastního serveru')
    check(any('/assets/vendor/supabase-js-2.45.4/supabase.js' in u for u in pg.reqs), 'knihovna přihlášení z vlastního serveru (s kontrolním součtem)')
    fam = pg.evaluate("getComputedStyle(document.querySelector('h1')).fontFamily")
    check(pg.evaluate("document.fonts.check('700 20px Sora')") and 'Sora' in fam, 'nadpisy používají lokální Soru: %s' % fam)
    # produkční konfigurace: nic nepovinného, žádná lišta
    check(pg.locator('#vxcBanner').count() == 0, 'produkce (nic nepovinného není zapnuté): lišta se nezobrazí')
    pg.click('[data-privacy]'); pg.wait_for_timeout(200)
    check('nepoužívá žádnou nepovinnou analytiku' in pg.inner_text('#vxcDlg'), 'Nastavení soukromí říká, že nepovinné služby nejsou používány')
    pg.keyboard.press('Escape'); check(pg.locator('#vxcDlg').count() == 0, 'dialog zavře Esc')
    pg.close()

    # ---------- 2) a 3) souhlas a maskování ----------
    CFG = {'analytics': {'endpoint': '/__collect/a'}, 'recording': {'endpoint': '/__collect/r'}}
    COLLECT.clear()
    pg = page(b, CFG); pg.goto(BASE + '/?utm=tajne-parametry#top'); pg.wait_for_timeout(2500)
    check(pg.locator('#vxcBanner').count() == 1, 's nepovinnými službami se zobrazí lišta')
    rb = pg.locator('#vxcBanner [data-vxc=reject]').bounding_box(); ab = pg.locator('#vxcBanner [data-vxc=accept]').bounding_box()
    check(abs(rb['width'] - ab['width']) < 2 and abs(rb['height'] - ab['height']) < 2 and pg.evaluate("getComputedStyle(document.querySelector('#vxcBanner [data-vxc=reject]')).backgroundColor===getComputedStyle(document.querySelector('#vxcBanner [data-vxc=accept]')).backgroundColor"),
          'Odmítnout a Přijmout jsou stejně velká a stejně výrazná tlačítka na první úrovni')
    check(len(COLLECT) == 0 and not any('rrweb' in u for u in pg.reqs), 'před souhlasem: nic neodesláno, skript nahrávání se ani nestáhl')
    pg.click('#vxcBanner [data-vxc=reject]'); pg.wait_for_timeout(300)
    pg.fill('#form input[name=email]', SECRETS[0]); pg.mouse.wheel(0, 1500); pg.wait_for_timeout(5000)
    check(len(COLLECT) == 0 and not any('rrweb' in u for u in pg.reqs), 'po odmítnutí: žádný požadavek analytiky ani nahrávání (5 s aktivity)')
    pg.reload(); pg.wait_for_timeout(2000)
    check(pg.locator('#vxcBanner').count() == 0 and len(COLLECT) == 0, 'volba se pamatuje; po obnovení stránky se nic nespustí')
    # přijetí v nastavení
    pg.click('[data-privacy]'); pg.wait_for_timeout(200); pg.click('#vxcDlg [data-vxc=accept]'); pg.wait_for_timeout(1500)
    an = [c for c in COLLECT if c[1] == '/__collect/a']
    check(len(an) >= 1 and json.loads(an[0][2])['path'] == '/' and 'tajne' not in an[0][2], 'po souhlasu: analytika posílá jen cestu bez parametrů: %s' % (an[0][2] if an else None))
    # aktivita s tajnými údaji
    pg.click('[data-fmode=custom]'); pg.wait_for_timeout(200)
    pg.fill('#form input[name=email]', SECRETS[0]); pg.fill('#form input[name=jmeno]', SECRETS[1]); pg.fill('#form input[name=firma]', SECRETS[4])
    pg.evaluate("document.getElementById('openChat')&&document.getElementById('openChat').click()"); pg.wait_for_timeout(300)
    if pg.locator('#chatIn').count(): pg.fill('#chatIn', SECRETS[3])
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_timeout(500)
    if pg.locator('#aPw').count(): pg.fill('#aPw', SECRETS[2]); pg.fill('#aMail', SECRETS[0])
    pg.keyboard.press('Escape'); pg.mouse.wheel(0, 2000); pg.wait_for_timeout(5500)
    rec = [c for c in COLLECT if c[1] == '/__collect/r']
    allrec = ''.join(c[2] for c in rec)
    check(len(rec) >= 1 and len(allrec) > 1000, 'nahrávání po souhlasu opravdu odesílá data (%d požadavků, %d B)' % (len(rec), len(allrec)))
    evs = [e for c in rec for e in json.loads(c[2])['events']]
    check(any(e.get('type') == 2 for e in evs) and sum(1 for e in evs if e.get('type') == 3) >= 3, 'záznam obsahuje snímek stránky i průběžné události po psaní (%d událostí)' % len(evs))
    leaked = [s for s in SECRETS if s in allrec or json.dumps(s)[1:-1] in allrec]
    check(not leaked, 'v odeslaných záznamech NENÍ obsah polí, heslo, jméno, e-mail ani zpráva chatu: %s' % leaked)
    check('Zákazníci, zakázky' not in allrec and 'Přehled firmy ve Vexaronetu' not in allrec and 'Hlavní navigace' not in allrec, 'texty stránky i textové atributy (alt, aria-label) jsou v záznamu maskované')
    check('tajne-parametry' not in allrec, 'adresa stránky v záznamu je bez parametrů')
    # odvolání
    pg.click('[data-privacy]'); pg.wait_for_timeout(200); pg.click('#vxcDlg [data-vxc=reject]'); pg.wait_for_timeout(300)
    n0 = len(COLLECT); pg.fill('#form input[name=email]', 'po.odvolani@example.cz'); pg.mouse.wheel(0, -1500); pg.wait_for_timeout(6000)
    check(len(COLLECT) == n0, 'po odvolání se sběr hned zastaví (6 s aktivity, 0 nových požadavků)')
    check(pg.evaluate("JSON.parse(localStorage.getItem('vx_consent_v1')).recording===false"), 'odvolání je uložené')
    pg.close()

    # ---------- 1) věk při registraci ----------
    pg = page(b); pg.goto(BASE + '/'); pg.wait_for_timeout(800)
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_timeout(300); pg.click('[data-auth=signup]'); pg.wait_for_timeout(300)
    check('18 let' in pg.inner_text('#aAgeT'), 'registrace firmy: potvrzení 18+')
    pg.fill('#aName', 'Test Uživatel'); pg.fill('#aMail', 'novy@example.cz'); pg.fill('#aPw', 'Heslo12345'); pg.check('#aOk'); pg.wait_for_timeout(2600)
    pg.click('#aGo'); pg.wait_for_timeout(500)
    check(pg.evaluate('window.__signup') is None and 'starší 18 let' in pg.inner_text('#aSt'), 'bez potvrzení věku se účet nezaloží a vysvětlí se postup pro nezletilé')
    pg.check('#aInv'); pg.wait_for_timeout(200)
    check('15 let' in pg.inner_text('#aAgeT'), 'pozvaný zaměstnanec: potvrzení 15+ (ukončená povinná školní docházka)')
    pg.check('#aAge'); pg.click('#aGo'); pg.wait_for_timeout(800)
    su = pg.evaluate('window.__signup')
    md = (su or {}).get('options', {}).get('data', {})
    check(md.get('age_group') == '15+' and 'birth' not in json.dumps(md).lower() and 'datum' not in json.dumps(md).lower(), 'ukládá se jen věková kategorie, ne datum narození: %s' % {k: md.get(k) for k in ('age_group', 'age_confirmed_at')})
    pg.close()
    pg = page(b); pg.goto(BASE + '/#early'); pg.wait_for_timeout(2700)
    pg.fill('#form input[name=email]', 'odber@example.cz'); pg.check('#fOk'); pg.click('#send'); pg.wait_for_timeout(300)
    check('15 let' in pg.inner_text('#form'), 'odběr novinek (souhlas): bez potvrzení 15+ se neodešle')
    pg.close()

    # ---------- 5) objednávky ----------
    pg = page(b, logged=True); pg.goto(BASE + '/'); pg.wait_for_timeout(800); pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp', timeout=8000); pg.wait_for_timeout(800)
    pg.evaluate("document.querySelector('#vxapp [data-app=plan]')?document.querySelector('#vxapp [data-app=plan]').click():(function(){var x=document.createElement('button');x.dataset.app='plan';document.querySelector('#vxapp').appendChild(x);x.click()})()")
    pg.wait_for_timeout(400)
    t = pg.inner_text('#planForm') if pg.locator('#planForm').count() else ''
    check(pg.inner_text('#plGo') == 'Odeslat nezávaznou žádost' if pg.locator('#plGo').count() else False, 'žádost o tarif nepředstírá závaznou objednávku (tlačítko „Odeslat nezávaznou žádost“)')
    import re as _re
    check(bool(_re.search(r'\d[\d ]* Kč / měsíc', t)) and 'automaticky neobnovuje' in t and 'ukončit' in t, 'před odesláním je vidět cena, období, (ne)obnovování a ukončení')
    pg.check('#planForm input[value=start]') if pg.locator('#planForm input[value=start]').count() else None; pg.wait_for_timeout(100)
    if pg.locator('#planForm input[value=start]').count(): check('START' in pg.inner_text('#plGo'), 'u přechodu na START tlačítko říká, co se stane')
    pg.close()
    pg = page(b); pg.goto(BASE + '/?s=pekarna-test'); pg.wait_for_timeout(1500)
    pg.click('[data-sh^="inc:"]'); pg.wait_for_timeout(200); pg.click('[data-sh=go]'); pg.wait_for_timeout(400)
    btn = pg.locator('#vxsite button[type=submit]').inner_text() if pg.locator('#vxsite button[type=submit]').count() else ''
    box = pg.inner_text('#vxsite')
    check(btn == 'Objednávka zavazující k platbě', 'e-shop: poslední tlačítko je „Objednávka zavazující k platbě“ (§ 1826a odst. 2 obč. zák.): %r' % btn)
    check('Celkem k úhradě' in box and '90' in box and 'zavazujete se zaplatit' in box and 'Pekárna Test' in box, 'těsně před tlačítkem: zboží, doprava, celková cena, prodejce a povinnost zaplatit')
    check(pg.locator('#so_c').count() == 0, 'pro vyřízení objednávky se nevyžaduje „souhlas“ (zpracování je plnění smlouvy)')
    check(pg.locator('#vxRep').count() == 1 and '/nahlasit/?u=' in pg.get_attribute('#vxRep', 'href'), 'na veřejném obchodě je odkaz „Nahlásit obsah“ s adresou stránky')
    pg.close()

    # ---------- 6) DSA formulář a odhlášení ----------
    pg = page(b); sent = []
    pg.route('**/api/dsa-notice', lambda r: (sent.append(json.loads(r.request.post_data)), r.fulfill(status=200, content_type='application/json', body=json.dumps({'ok': True, 'ref': 'DSA-20261110-ABCDEF12', 'ack': 'sent'}))))
    pg.goto(BASE + '/nahlasit/?u=' + 'https%3A%2F%2Fvexaronet.com%2F%3Fw%3Ddemo-web'); pg.wait_for_timeout(300)
    check(pg.input_value('#u') == 'https://vexaronet.com/?w=demo-web', 'formulář DSA předvyplní označený obsah z odkazu')
    pg.click('#go'); pg.wait_for_timeout(200)
    check(len(sent) == 0 and pg.is_visible('#st'), 'neúplné oznámení se neodešle')
    pg.select_option('#c', 'podvod'); pg.fill('#x', 'Web vybírá zálohy za služby, které nedodá; je to podvod.'); pg.fill('#n', 'Jana'); pg.fill('#e', 'jana@example.cz'); pg.fill('#d', 'sekce Služby')
    pg.click('#go'); pg.wait_for_timeout(200); check(len(sent) == 0 and 'dobré víře' in pg.inner_text('#st'), 'bez prohlášení o dobré víře se neodešle')
    pg.check('#g'); pg.click('#go'); pg.wait_for_timeout(500)
    check(len(sent) == 1 and sent[0]['urls'] == ['https://vexaronet.com/?w=demo-web'] and sent[0]['good_faith'] is True and sent[0]['details'] == 'sekce Služby', 'odešle se URL, místo, druh, vysvětlení, jméno, e-mail a prohlášení')
    check('DSA-20261110-ABCDEF12' in pg.inner_text('#st'), 'oznamovatel uvidí referenční číslo')
    check(foreign(pg) == [], 'stránka DSA nevolá cizí servery')
    pg.close()
    pg = page(b); got = []
    pg.route('**/api/unsubscribe', lambda r: (got.append(json.loads(r.request.post_data)), r.fulfill(status=200, content_type='application/json', body='{"ok":true}')))
    T = 'ab' * 32; pg.goto(BASE + '/odhlasit/?t=' + T); pg.wait_for_timeout(300)
    check('?t=' not in pg.url, 'token zmizí z adresního řádku hned po načtení (nezůstane v historii)')
    check(len(got) == 0, 'samotné otevření stránky nic neodhlásí')
    pg.click('#go'); pg.wait_for_timeout(400)
    check(got == [{'token': T}] and 'odhlášeni' in pg.inner_text('#st'), 'odhlášení jedním tlačítkem, bez přihlášení, posílá jen token')
    pg.close()
    b.close()
srv.shutdown()
print('\nSELHALO: %d' % len(fails) if fails else '\nVšechny kontroly prošly.')
sys.exit(1 if fails else 0)
