"""Automatizovaný test XSS a CSP: SKUTEČNÁ aplikace (index.html) se vykreslí s daty, která obsahují útočné řetězce
(zákaznická data, AI odpověď, URL obrázku javascript:), a běží s hlavičkami ze souboru _headers (CSP jako na Cloudflare).
Ověřuje, že se žádný vložený kód nespustí, v DOM nevznikne žádný atribut on*= a CSP neblokuje nic, co aplikace potřebuje.
Data dodává mock Supabase (hranice oprávnění v DB testují tests/db/*). Spuštění: python3 tests/xss_ui.py"""
import http.server, json, os, sys, threading
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load_headers():
    out, cur = {}, None
    for line in open(os.path.join(ROOT, '_headers'), encoding='utf-8'):
        if not line.strip() or line.lstrip().startswith('#'): continue
        if not line.startswith(' '): cur = line.strip(); out[cur] = {}; continue
        k, v = line.strip().split(':', 1); out[cur][k.strip()] = v.strip()
    return out
HDR = load_headers()
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def end_headers(self):
        for k, v in HDR.get('/*', {}).items(): self.send_header(k, v)
        super().end_headers()
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H); PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()

P = '<img src=x onerror="window.__xss=(window.__xss||0)+1">'
Q = '"><svg/onload=window.__xss=(window.__xss||0)+1>'
S = "'+alert(1)+'</script><script>window.__xss=1</script>"
MOCK = r'''
(function(){
var P=%s,Q=%s,S=%s,now=new Date(),iso=function(o){return new Date(now.getTime()+o*864e5).toISOString()},day=function(o){return iso(o).slice(0,10)};
var CO={id:'11111111-1111-1111-1111-111111111111',name:P+' s.r.o.',industry:'Autoservis',parent_company_id:null,created_at:iso(-30)},C=CO.id;
var D={companies:[CO],company_members:[{company_id:C,role:'owner',companies:CO}],subscriptions:[{plan:'business',status:'trial',trial_end:iso(20)}],
 customers:[{id:'cu1',company_id:C,name:P,email:'a@b.cz',phone:Q,notes:S,billing_address:Q,created_at:iso(-3)}],
 jobs:[{id:'j1',company_id:C,customer_id:'cu1',title:P,description:Q,status:'new',stage:S,price:100,due_at:iso(1),created_at:iso(-2)}],
 tasks:[{id:'t1',company_id:C,title:P,description:Q,completed:false,due_at:iso(0)}],
 reservations:[{id:'r1',company_id:C,title:P,starts_at:iso(0),ends_at:iso(0.05),customer_id:'cu1'}],
 financial_entries:[{id:'f1',company_id:C,title:P,kind:'expense',amount:100,entry_date:day(0)}],
 marketing_posts:[{id:'m1',company_id:C,title:P,channel:Q,status:'draft',planned_on:day(0),body:S}],
 deals:[{id:'d1',company_id:C,customer_id:'cu1',title:P,value:100,stage:'new',probability:10,note:Q,created_at:iso(-1)}],
 quotes:[{id:'q1',company_id:C,customer_id:'cu1',title:P,status:'draft',items:[{description:P,quantity:1,unit_gross:10}],total:10,number:Q,currency:'CZK',created_at:iso(-1)}],
 client_notes:[{id:'n1',company_id:C,customer_id:'cu1',kind:'note',body:P,created_at:iso(-1)}],
 products:[{id:'p1',company_id:C,name:P,description:Q,price:10,unit:'ks',image_url:'javascript:window.__xss=1',active:true,shop_visible:true}],
 shifts:[{id:'s1',company_id:C,user_id:'u1',starts_at:iso(0),ends_at:iso(0.2),note:P}],
 booking_services:[{id:'b1',company_id:C,name:P,duration_min:30,price:100,active:true}]};
function qb(t){var o={_op:'sel',select(){return o},eq(){return o},neq(){return o},gte(){return o},lte(){return o},in(){return o},limit(){return o},is(){return o},order(){return o},single(){o._one=true;return o},maybeSingle(){o._one=true;return o},insert(){return Promise.resolve({data:null,error:null})},upsert(){return Promise.resolve({data:null,error:null})},update(){o._op='u';return o},delete(){o._op='d';return o},then(f,r){var d=o._op==='sel'?(D[t]||[]):null;if(o._one)d=d&&d[0]||null;return Promise.resolve({data:d,error:null}).then(f,r)}};return o}
function rpc(n,a){
 if(n==='dashboard_summary')return Promise.resolve({data:{income:0,expenses:100,customers:1,active_jobs:1,reservations_today:1},error:null});
 if(n==='company_team')return Promise.resolve({data:[{user_id:'u1',email:P+'@x.cz',role:'owner',is_me:true}],error:null});
 if(n==='accept_company_invites')return Promise.resolve({data:0,error:null});
 return Promise.resolve({data:null,error:{code:'PGRST202',message:'not found '+P,details:''}})}
window.supabase={createClient:function(){return{from:qb,rpc:rpc,channel:function(){var c={on(){return c},subscribe(){return c}};return c},removeChannel(){},
 storage:{from:function(){return{list:function(){return Promise.resolve({data:[],error:null})},createSignedUrl:function(){return Promise.resolve({data:null,error:null})}}}},
 auth:{getSession:()=>Promise.resolve({data:{session:{access_token:'t',user:{id:'u1'}}}}),getUser:()=>Promise.resolve({data:{user:{id:'u1',email:'a@b.cz',user_metadata:{full_name:P}}}}),onAuthStateChange(){return{data:{subscription:{unsubscribe(){}}}}},updateUser:(x)=>Promise.resolve({data:{user:{user_metadata:x.data||{}}},error:null}),signOut(){return Promise.resolve({})}}}}};
})();
''' % (json.dumps(P), json.dumps(Q), json.dumps(S))
TABS = ['prehled', 'zakaznici', 'pripady', 'nabidky', 'zakazky', 'ukoly', 'faktury', 'finance', 'kalendar', 'online', 'weby', 'marketing',
        'reporty', 'automatizace', 'sklad', 'eshop', 'zamestnanci', 'ceo', 'autopilot', 'firmaprofil']
fails = []
def check(c, m):
    print(('OK   ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
PROBE = "[window.__xss||0, document.querySelectorAll('#vxapp [onerror],#vxapp [onload],#vxapp script:not([src])').length, (window.__csp||[]).slice()]"
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': 1400, 'height': 1000}); errs = []
    pg.on('pageerror', lambda e: errs.append(str(e)))
    pg.add_init_script("document.addEventListener('securitypolicyviolation',function(e){(window.__csp=window.__csp||[]).push(e.violatedDirective+' '+e.blockedURI)})")
    pg.add_init_script(MOCK)
    pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript'))
    pg.route('**/fonts.g*', lambda r: r.abort())
    pg.route('**/api/**', lambda r: r.fulfill(status=200, content_type='application/json', body=json.dumps({'reply': P + Q + S, 'text': P + S})))
    pg.goto('http://127.0.0.1:%d/index.html' % PORT); pg.wait_for_timeout(600)
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp'); pg.wait_for_timeout(900)
    for t in TABS:
        if pg.locator('#vxapp [data-tab=%s]' % t).count() == 0: continue
        pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()" % t); pg.wait_for_timeout(450)
        x = pg.evaluate(PROBE)
        check(x[0] == 0 and x[1] == 0, '%s: žádný vložený kód se nespustil ani nevznikl v DOM %s' % (t, x[:2]))
        if t in ('zakaznici', 'zakazky', 'ukoly', 'pripady') or (t == 'autopilot' and pg.locator('#apd').count()):
            check('<img src=x onerror' in pg.inner_text('#appMain'), '%s: útočný řetězec se opravdu vykreslil, ale jako text' % t)
    # detail zákazníka, náhled příspěvku, chat s AI CEO (odpověď AI obsahuje HTML)
    pg.evaluate("document.querySelector('#vxapp [data-tab=zakaznici]').click()"); pg.wait_for_timeout(300)
    if pg.locator('#vxapp [data-edit^="customers:"]').count():
        pg.locator('#vxapp [data-edit^="customers:"]').first.click(); pg.wait_for_timeout(400)
        check(pg.evaluate(PROBE)[0] == 0, 'detail zákazníka: bez spuštění')
        pg.keyboard.press('Escape'); pg.wait_for_timeout(200)
    pg.evaluate("var x=document.createElement('button');x.dataset.tab='autopilot';document.querySelector('#vxapp').appendChild(x);x.click()"); pg.wait_for_timeout(500)
    if pg.locator('#apd [data-apd=prehled]').count(): pg.click('#apd [data-apd=prehled]'); pg.wait_for_timeout(400)
    if pg.locator('#apd [data-apd-act=prev]').count():
        pg.locator('#apd [data-apd-act=prev]').first.click(); pg.wait_for_timeout(300)
        check(pg.evaluate(PROBE)[0] == 0 and S in pg.inner_text('.apdm'), 'náhled příspěvku zobrazí kód jako text')
        pg.keyboard.press('Escape')
    pg.evaluate("document.querySelector('#vxapp [data-tab=ceo]').click()"); pg.wait_for_timeout(400)
    if pg.locator('#ceoIn, #vxapp form input[type=text], #vxapp textarea').count():
        inp = pg.locator('#ceoIn, #vxapp .aif input').first
        inp.fill('Ahoj ' + P); inp.press('Enter'); pg.wait_for_timeout(900)
        x = pg.evaluate(PROBE)
        check(x[0] == 0 and x[1] == 0, 'AI CEO: HTML v dotazu i v odpovědi AI se nespustí %s' % x[:2])
    x = pg.evaluate(PROBE)
    check(x[0] == 0, 'celkem: window.__xss nebylo nastaveno')
    check(not x[2], 'CSP z _headers nic z aplikace nezablokovala: %s' % x[2])
    hdr = pg.request.get('http://127.0.0.1:%d/index.html' % PORT).headers
    check("frame-ancestors 'none'" in hdr.get('content-security-policy', '') and hdr.get('x-frame-options') == 'DENY', 'stránku nelze vložit do cizího rámu (clickjacking)')
    check(not [e for e in errs if 'xss' in e.lower()], 'bez chyb souvisejících s vloženým kódem: %s' % errs[:3])
    print('JS chyby stránky (pro informaci):', errs[:5])
    b.close()
srv.shutdown()
print('\nSELHALO: %d' % len(fails) if fails else '\nVšechny kontroly prošly.')
sys.exit(1 if fails else 0)
