"""UI test průchodu AI Marketing Autopilota v prohlížeči: profil → strategie → návrhy → schválení → publikace → výsledky.
Mock napodobuje DB funkce mkt_* (stavově, s kontrolou otisku obsahu stejným vzorcem jako DB) a endpoint /api/ai-marketing.
Skutečné vynucení oprávnění, limitů a ukládání ověřují tests/db/run_ai_marketing_local.sh a tests/ai_marketing_e2e.test.mjs.
Spuštění: python3 tests/ai_marketing_ui.py"""
import hashlib, http.server, json, os, socketserver, sys, threading
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CID = '11111111-1111-1111-1111-111111111111'
MOCK = r'''
(function(){
var C=window.__cfg||{};window.__log=[];
var S=JSON.parse(sessionStorage.getItem('__mk')||'null')||{profile:!!C.profile,strategy:null,approved:null,posts:[],items:{},results:{},nid:1,web:false};
function save(){sessionStorage.setItem('__mk',JSON.stringify(S))}window.__S=S;window.__save=save;
var D={companies:C.companies,company_members:C.members,subscriptions:[{plan:'pro',status:'trial',trial_end:new Date(Date.now()+20*864e5).toISOString()}],sites:[{id:'s1',company_id:C.cid,slug:'konina',enabled:true,data:{}}]};
function rows(t){return t==='marketing_posts'?S.posts:(D[t]||[])}
function qb(t){var o={_op:'sel',select(){return o},eq(){return o},limit(){return o},is(){return o},order(){return o},gte(){return o},lte(){return o},in(){return o},insert(){return Promise.resolve({error:null})},update(){o._op='u';return o},delete(){o._op='d';return o},upsert(){return Promise.resolve({error:null})},then(f){return Promise.resolve({data:o._op==='sel'?rows(t):null,error:null}).then(f)}};return o}
function ok(d){return Promise.resolve({data:d,error:null})}
function err(m,c){return Promise.resolve({data:null,error:{code:c||'P0001',message:m,details:''}})}
async function sha(t){var b=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(t));return Array.prototype.map.call(new Uint8Array(b),function(x){return ('0'+x.toString(16)).slice(-2)}).join('')}
function post(id){return S.posts.filter(function(p){return p.id===id})[0]}
async function phash(p){return window.__pyhash?window.__pyhash(p):sha((p.title||'')+'\x1f'+(p.body||'')+'\x1f'+(p.channel||''))}
async function state(){var items=[];for(var k in S.items){var i=S.items[k],p=post(k),h=await phash(p);items.push({post_id:k,ai:true,approved:i.ah===h,changed_after_approval:!!i.ah&&i.ah!==h,published_channel:i.ch||null,published_url:i.url||null,published_at:i.at||null,web_publish_on:i.on||null})}
 return {profile:{confirmed:S.profile,version:S.profile?3:null},strategy:S.strategy,approved:S.approved,progress:S.approved?{metric:S.approved.doc.goal.metric,target:S.approved.doc.goal.target,days:S.approved.doc.goal.days,since:new Date().toISOString(),until:new Date(Date.now()+30*864e5).toISOString(),value:4}:null,items:items}}
async function rpc(n,a){
 window.__log.push(['rpc',n,JSON.parse(JSON.stringify(a||{}))]);
 if(n==='mkt_state'){if(C.noDb)return err('Could not find the function public.mkt_state(cid) in the schema cache','PGRST202');return ok(await state())}
 if(n==='mkt_results'){var out=[];for(var k in S.items){var i=S.items[k];if(i.at)out.push({post_id:k,title:post(k).title,channel:i.ch,published_at:i.at,published_url:i.url||null,web_publish_on:i.on||null,window_days:7,
   system:{poptavky:{after:3,before:1,complete:false},zakaznici:{after:1,before:0,complete:false},rezervace:{after:0,before:0,complete:false},objednavky:{after:0,before:0,complete:false}},manual:S.results[k]||[]})}return ok(out)}
 if(n==='mkt_strategy_approve'){if(!S.strategy||a.p_id!==S.strategy.id||a.p_expected_hash!==S.strategy.hash)return err('stale','PT409');S.strategy.status='approved';S.strategy.approved_at=new Date().toISOString();S.approved={id:S.strategy.id,version:S.strategy.version,doc:S.strategy.doc,approved_at:S.strategy.approved_at};save();return ok({id:a.p_id})}
 if(n==='mkt_strategy_edit'){if(a.p_expected_hash!==S.strategy.hash)return err('stale','PT409');var v=S.strategy.status==='approved'?S.strategy.version+1:S.strategy.version;
   S.strategy={id:S.strategy.status==='approved'?'st'+v:S.strategy.id,version:v,status:'draft',source:'manual',doc:a.p_doc,hash:'h'+(S.nid++),profile_version:3,created_at:new Date().toISOString(),approved_at:null};save();return ok({id:S.strategy.id})}
 if(n==='mkt_post_approve'){var p=post(a.p_post);if(!p)return err('not_found','PT404');var h=await phash(p);if(h!==a.p_expected_hash)return err('stale','PT409');S.items[p.id]=Object.assign(S.items[p.id]||{},{ah:h});p.status='planned';save();return ok({post_id:p.id,hash:h})}
 if(n==='mkt_publish'){var p2=post(a.p_post),i2=S.items[a.p_post];if(!i2||i2.ah!==await phash(p2))return err('not_approved','PT412');
   if(a.p_channel==='web'){i2.ch='web';i2.on=a.p_on;i2.at=new Date().toISOString();S.web=true}else{if(a.p_url&&!/^https:\/\//.test(a.p_url))return err('invalid_url','PT422');i2.ch=a.p_channel;i2.url=a.p_url;i2.at=new Date().toISOString()}p2.status='done';save();return ok({post_id:p2.id})}
 if(n==='mkt_unpublish'){var i3=S.items[a.p_post];i3.ch=null;i3.url=null;i3.at=null;i3.on=null;post(a.p_post).status='planned';save();return ok({post_id:a.p_post})}
 if(n==='mkt_result_add'){(S.results[a.p_post]=S.results[a.p_post]||[]).push({metric:a.p_metric,value:a.p_value,from:a.p_from,to:a.p_to,source:a.p_source});save();return ok({id:'r1'})}
 if(n==='public_site')return ok({name:'Autoservis Konina',data:{hero:{title:'Autoservis Konina'}},booking:null});
 if(n==='public_site_news')return ok(C.news||[]);
 if(n==='autopilot_status')return ok({root_id:a.cid,is_root:true,plan_allowed:true,platform_paid_runs_enabled:false,monthly_limit_nusd:250000000,spent_nusd:0,open_reserved_nusd:0,remaining_nusd:250000000,runs_this_month:0,month_start:new Date().toISOString(),paid_runs_possible:false,models:[]});
 if(n==='profile_get')return ok({company_id:a.cid,is_root:true,active:S.profile?{version:3}:null,draft:null,versions:[],can_write:true,schema_version:1});
 if(n==='company_team')return ok([]);if(n==='accept_company_invites')return ok(0);
 return ok({income:0,expenses:0,customers:0,active_jobs:0,reservations_today:0})}
window.supabase={createClient:function(){return{from:qb,rpc:rpc,auth:{getSession:()=>Promise.resolve({data:{session:{access_token:'t'}}}),getUser:()=>Promise.resolve({data:{user:{id:'u1',email:'a@b.cz',user_metadata:{full_name:'Jan Konina'}}}}),onAuthStateChange(){},updateUser:(x)=>Promise.resolve({data:{user:{user_metadata:x.data}},error:null}),signOut(){}}}}};
})();
'''
DOC = {'goal': {'metric': 'poptavky', 'target': 15, 'days': 30}, 'audience': 'Řidiči z Koniny a okolí', 'positioning': 'Rychlý a férový servis s online rezervací', 'tone': 'přátelský',
       'channels': [{'channel': 'Facebook', 'why': 'místní komunita'}], 'themes': [{'title': 'Přezutí pneumatik', 'angle': 'sezóna'}, {'title': 'Výměna výfuku', 'angle': 'bezpečnost'}], 'cadence_per_week': 2}
CO = [{'id': CID, 'name': 'Autoservis Konina', 'industry': 'Autoservis', 'parent_company_id': None, 'created_at': '2026-10-01T00:00:00Z'}]
def members(role='owner'): return [{'company_id': CID, 'role': role, 'companies': CO[0]}]
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
def api_handler(pg):
    def h(route):
        body = json.loads(route.request.post_data or '{}'); API['calls'].append(body)
        mode = API['mode'].pop(0) if API['mode'] else 'ok'
        if mode == 'abort': return route.abort()
        if mode == 'disabled': return route.fulfill(status=403, content_type='application/json', body=json.dumps({'error': 'paid_runs_disabled'}))
        if mode == 'progress': return route.fulfill(status=409, content_type='application/json', body=json.dumps({'error': 'in_progress'}))
        if body['action'] == 'strategy':
            pg.evaluate("""d=>{var S=window.__S;S.strategy={id:'st1',version:1,status:'draft',source:'ai',doc:d,hash:'h0',profile_version:3,created_at:new Date().toISOString(),approved_at:null};window.__save()}""", DOC)
        else:
            pg.evaluate("""td=>{var S=window.__S;S.posts.push({id:'p1',company_id:'%s',title:'Přezujte včas',channel:'Facebook',status:'draft',planned_on:td,body:'Zimní pneumatiky přezujeme rychle, termín si vyberete online. Řidiči <b>pozor</b>.'},
              {id:'p2',company_id:'%s',title:'Tichý výfuk',channel:'Facebook',status:'draft',planned_on:td,body:'Hlučný výfuk vyměníme, objednejte se online na našem webu.'});S.items.p1={};S.items.p2={};window.__save()}""" % (CID, CID), body.get('from'))
        route.fulfill(status=200, content_type='application/json', body=json.dumps({'ok': True, 'run_id': 'r', 'cost_nusd': 1270000}))
    return h

def open_page(b, cfg, url=BASE, ctx=None):
    ctx = ctx or b.new_context(viewport={'width': 1400, 'height': 1000})
    pg = ctx.new_page(); pg.errs = []
    pg.on('pageerror', lambda e: pg.errs.append(str(e)))
    pg.add_init_script('window.__cfg=' + json.dumps(dict(cfg, companies=CO, cid=CID)) + ';')
    pg.add_init_script(MOCK); pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript'))
    pg.route('**/api/ai-marketing', api_handler(pg))
    pg.expose_function('__pyhash', lambda p: hashlib.sha256(((p.get('title') or '') + '\x1f' + (p.get('body') or '') + '\x1f' + (p.get('channel') or '')).encode('utf-8')).hexdigest())
    pg.goto(url); pg.wait_for_timeout(500)
    return pg
def login(pg):
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(400)
    pg.evaluate("var x=document.createElement('button');x.dataset.tab='autopilot';x.id='__ap';document.querySelector('#vxapp').appendChild(x);x.click()"); pg.wait_for_selector('#apd'); pg.wait_for_timeout(400)
def dtab(pg, k): pg.click('#apd [data-apd=%s]' % k); pg.wait_for_timeout(450)
def log(pg, n): return pg.evaluate("window.__log.filter(function(x){return x[1]==='%s'}).map(function(x){return x[2]})" % n)
def toast(pg): return pg.inner_text('#appToast')

with sync_playwright() as p:
    b = p.chromium.launch()
    # 1) nepotvrzený profil: strategie se nenabízí
    pg = open_page(b, {'members': members(), 'profile': False}); login(pg); dtab(pg, 'strategie')
    t = pg.inner_text('#apd')
    check('Profil firmy není potvrzený' in t and pg.locator('#apd [data-apd-act=mk-gen-strategy]').count() == 0, 'bez potvrzeného profilu nelze spustit návrh strategie')
    check(len(log(pg, 'mkt_state')) >= 1 and log(pg, 'mkt_state')[0]['cid'] == CID, 'stav se čte z DB pro aktivní firmu')
    pg.context.close()

    # 2) potvrzený profil → návrh strategie (nejdřív vypnuté placené běhy, pak úspěch)
    pg = open_page(b, {'members': members(), 'profile': True}); login(pg); dtab(pg, 'strategie')
    check('Strategie zatím není nastavená' in pg.inner_text('#apd') and 'verze 3' in pg.inner_text('#apd'), 'prázdný stav uvádí verzi potvrzeného profilu')
    API['mode'] = ['disabled']; pg.click('#apd [data-apd-act=mk-gen-strategy]'); pg.wait_for_timeout(500)
    check('nejsou zapnuté' in toast(pg) and 'Nic se neúčtovalo' in toast(pg), 'vypnuté placené běhy: srozumitelná hláška')
    check(pg.evaluate("localStorage.getItem('vxmk:%s:strategy')" % CID) is None, 'po definitivní chybě nezůstává rozpracovaný požadavek')
    k1 = API['calls'][-1]['key']
    pg.click('#apd [data-apd-act=mk-gen-strategy]'); pg.wait_for_timeout(700)
    c = API['calls'][-1]
    check(c['action'] == 'strategy' and c['cid'] == CID and c['key'] != k1 and 8 <= len(c['key']) <= 120 and 'profile' not in c, 'požadavek nese akci, firmu a nový idempotenční klíč, žádná data profilu z prohlížeče')
    t = pg.inner_text('#apd')
    check('Koncept – čeká na schválení' in t and '15 poptávek za 30 dní' in t and 'Přezutí pneumatik' in t, 'uložený koncept strategie se zobrazí')
    # úprava: neplatná se neodešle, platná uloží s otiskem
    pg.click('#apd [data-apd-act=mk-edit-strategy]'); pg.wait_for_selector('#mkSf')
    pg.fill('#mk_au', 'krátké'); pg.click('#mkSf [type=submit]'); pg.wait_for_timeout(200)
    check('cílové zákazníky' in pg.inner_text('#mkSfMsg') and len(log(pg, 'mkt_strategy_edit')) == 0, 'neplatná úprava se neodešle a je vysvětlena')
    pg.fill('#mk_au', 'Řidiči z Koniny, kteří chtějí rychlý servis'); pg.fill('#mk_gt', '20'); pg.click('#mkSf [type=submit]'); pg.wait_for_timeout(500)
    e = log(pg, 'mkt_strategy_edit')
    check(len(e) == 1 and e[0]['p_expected_hash'] == 'h0' and e[0]['p_doc']['goal']['target'] == 20 and set(e[0]['p_doc']) <= {'goal', 'audience', 'positioning', 'tone', 'channels', 'themes', 'cadence_per_week', 'notes'}, 'úprava posílá otisk zobrazené verze a jen povolená pole')
    check('20 poptávek' in pg.inner_text('#apd') and 'ruční úprava' in pg.inner_text('#apd'), 'upravená strategie se zobrazí')
    pg.click('#apd [data-apd-act=mk-appr-strategy]'); pg.wait_for_timeout(500)
    a = log(pg, 'mkt_strategy_approve')
    check(len(a) == 1 and a[0]['p_id'] == 'st1' and a[0]['p_expected_hash'].startswith('h'), 'schválení posílá id a otisk')
    check('Schváleno' in pg.inner_text('#apd') and 'Plnění cíle: 4 z 20' in pg.inner_text('#apd'), 'schválená strategie ukazuje plnění cíle ze skutečných dat')
    dtab(pg, 'prehled'); check('20 poptávek za 30 dní' in pg.inner_text('#apd') and pg.locator('#apd .vxd-bar[aria-valuenow="20"]').count() == 1, 'karta strategie v přehledu ukazuje cíl a plnění (4/20 = 20 %)')

    # 3) obsah: dávka návrhů; přerušené spojení a obnovení stránky použije stejný klíč
    dtab(pg, 'obsah'); check(pg.locator('#apd [data-apd-act=mk-gen-posts]').count() == 1 and pg.locator('#mk_topic').count() == 1, 'v Obsahu je dávka ze strategie i původní generátor')
    pg.fill('#mk_pc', '2'); API['mode'] = ['abort']; pg.click('#apd [data-apd-act=mk-gen-posts]'); pg.wait_for_timeout(600)
    pend = pg.evaluate("JSON.parse(localStorage.getItem('vxmk:%s:posts'))" % CID)
    check(pend and pend['extra']['count'] == 2 and 'přerušilo' in toast(pg), 'přerušené spojení: požadavek zůstane rozpracovaný se stejným klíčem')
    pg.reload(); pg.wait_for_timeout(500); login(pg); dtab(pg, 'obsah')
    check('nebyl dokončen' in pg.inner_text('#apd'), 'po obnovení stránky je vidět nedokončený požadavek')
    API['mode'] = ['progress']; pg.click('#apd [data-apd-act=mk-resume]'); pg.wait_for_timeout(500)
    check(API['calls'][-1]['key'] == pend['key'] and 'zpracovává' in toast(pg), 'kontrola posílá stejný klíč; běžící požadavek se jen oznámí')
    pg.click('#apd [data-apd-act=mk-resume]'); pg.wait_for_timeout(900)
    c = API['calls'][-1]
    check(c['key'] == pend['key'] and c['action'] == 'posts' and c['count'] == 2, 'dokončení stejným klíčem a se stejnými parametry')
    check(pg.evaluate("localStorage.getItem('vxmk:%s:posts')" % CID) is None, 'po úspěchu se rozpracovaný požadavek smaže')

    # 4) schválení příspěvku na serveru s otiskem (stejný vzorec jako DB)
    dtab(pg, 'prehled'); check(pg.locator('#apd .vxd-tk li').count() == 2, 'nové koncepty jsou v Aktuálních úkolech')
    pg.click('#apd [data-apd-act=appr][data-id=p1]'); pg.wait_for_timeout(700)
    ap = log(pg, 'mkt_post_approve')
    check(len(ap) == 1 and ap[0]['p_post'] == 'p1' and len(ap[0]['p_expected_hash']) == 64 and 'schválený' in toast(pg), 'schválení přes mkt_post_approve s otiskem shodným s DB (SHA-256)')
    check(pg.evaluate("window.__S.posts[0].status") == 'planned' and pg.locator('#apd .vxd-tk li').count() == 1, 'schválený příspěvek je naplánovaný a zmizí z konceptů')
    # 5) publikace: web firmy a ruční záznam
    dtab(pg, 'kalendar'); pg.click('#apd [data-apd-act=prev][data-id=p1]'); pg.wait_for_selector('.apdm')
    check('<b>' not in pg.inner_html('.apdm pre') or '&lt;b&gt;' in pg.inner_html('.apdm pre'), 'text příspěvku je v náhledu escapovaný')
    pg.fill('#mkm_url', 'http://x.cz'); pg.click('.apdm [data-mkm=manual]'); pg.wait_for_timeout(300)
    check(len(log(pg, 'mkt_publish')) == 0 and 'https' in toast(pg), 'odkaz bez https se neodešle')
    pg.click('.apdm [data-mkm=web]'); pg.wait_for_timeout(700)
    pb = log(pg, 'mkt_publish')
    check(len(pb) == 1 and pb[0]['p_channel'] == 'web' and pb[0]['p_on'] and pg.locator('.apdm').count() == 0, 'zveřejnění na webu firmy (kanál web, datum)')
    pg.click('#apd [data-apd-act=prev][data-id=p2]'); pg.wait_for_selector('.apdm')
    check(pg.locator('.apdm [data-mkm=appr]').count() == 1 and pg.locator('.apdm [data-mkm=web]').count() == 0, 'neschválený příspěvek nabízí jen schválení, ne publikaci')
    pg.keyboard.press('Escape'); pg.wait_for_timeout(200)
    # 6) výsledky
    dtab(pg, 'analyza'); t = pg.inner_text('#apd')
    check('Výsledky zveřejněných příspěvků' in t and 'Přezujte včas' in t and 'Poptávky' in t and 'před: 1' in t and 'souvislost' in t, 'Analýza ukazuje výsledky po/před zveřejněním s upozorněním na souvislost')
    pg.click('#apd details summary'); pg.fill('#mkr_v_p1', '350'); pg.click('#apd [data-apd-act=mk-res-add][data-id=p1]'); pg.wait_for_timeout(300)
    check(len(log(pg, 'mkt_result_add')) == 0 and 'zdroj' in toast(pg), 'výsledek bez zdroje se neuloží')
    pg.fill('#mkr_s_p1', 'statistiky Facebooku'); pg.click('#apd [data-apd-act=mk-res-add][data-id=p1]'); pg.wait_for_timeout(600)
    r = log(pg, 'mkt_result_add')
    check(len(r) == 1 and r[0]['p_value'] == 350 and r[0]['p_metric'] == 'dosah' and r[0]['p_source'] == 'statistiky Facebooku', 'ručně zadaný výsledek se uloží i se zdrojem')
    check('350' in pg.inner_text('#apd') and 'statistiky Facebooku' in pg.inner_text('#apd'), 'uložený výsledek se zobrazí')
    # zrušení publikace
    dtab(pg, 'kalendar'); pg.click('#apd [data-apd-act=prev][data-id=p1]'); pg.wait_for_selector('.apdm'); pg.click('.apdm [data-mkm=unpub]'); pg.wait_for_timeout(600)
    check(len(log(pg, 'mkt_unpublish')) == 1, 'zveřejnění lze zrušit')
    check(not pg.errs, 'bez chyb JS: %s' % pg.errs)
    pg.context.close()

    # 7) bez migrace v DB: srozumitelná hláška, žádné tlačítko AI
    pg = open_page(b, {'members': members(), 'profile': True, 'noDb': True}); login(pg); dtab(pg, 'strategie')
    check('ještě není v databázi nasazený' in pg.inner_text('#apd') and pg.locator('#apd [data-apd-act=mk-gen-strategy]').count() == 0, 'bez migrace: hláška a žádné tlačítko AI')
    check(not pg.errs, 'bez chyb JS: %s' % pg.errs); pg.context.close()
    # 8) zaměstnanec: nečte stav AI marketingu
    pg = open_page(b, {'members': members('employee'), 'profile': True}); pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(500)
    check(len(log(pg, 'mkt_state')) == 0, 'zaměstnanec stav AI marketingu nenačítá'); pg.context.close()
    # 9) veřejný web firmy: sekce Novinky jen z public_site_news, escapovaná
    pg = open_page(b, {'members': members(), 'news': [{'title': 'Přezutí <script>x</script>', 'body': 'Termíny online.\nDruhý řádek', 'date': '2026-11-08'}]}, url=BASE + '?w=konina')
    pg.wait_for_selector('#vxsite iframe'); pg.wait_for_timeout(400)
    sd = pg.evaluate("document.querySelector('#vxsite iframe').srcdoc")
    check('id="novinky"' in sd and 'Novinky' in sd and '8. 11. 2026' in sd and 'Termíny online.<br>Druhý řádek' in sd, 'veřejný web firmy má sekci Novinky se schválenými příspěvky')
    check('<script>x</script>' not in sd and '&lt;script&gt;' in sd, 'text novinek je escapovaný')
    pg.context.close()
    pg = open_page(b, {'members': members()}, url=BASE + '?w=konina'); pg.wait_for_selector('#vxsite iframe'); pg.wait_for_timeout(400)
    check('id="novinky"' not in pg.evaluate("document.querySelector('#vxsite iframe').srcdoc"), 'bez novinek se sekce nezobrazí'); pg.context.close()
    # 10) ukázka: AI marketing se nespouští
    ctx = b.new_context(viewport={'width': 1300, 'height': 900}); pg = ctx.new_page(); pg.errs = []; pg.on('pageerror', lambda e: pg.errs.append(str(e)))
    pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript')); pg.goto(BASE); pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]'); pg.wait_for_selector('#vxapp .kpi')
    pg.evaluate("var x=document.createElement('button');x.dataset.tab='autopilot';document.querySelector('#vxapp').appendChild(x);x.click()"); pg.wait_for_selector('#apd'); dtab(pg, 'strategie')
    t = pg.inner_text('#apd')
    check('Schváleno' in t and '20 nových zákazníků za 30 dní' in t and 'Plnění cíle: 12 z 20' in t and 'Ukázková data' in t, 'ukázka: vzorová schválená strategie s plněním cíle, označená jako ukázková data')
    pg.click('#apd [data-apd-act=mk-gen-strategy]'); pg.wait_for_timeout(300)
    check('Ukázka: akce se neprovádí' in pg.inner_text('#appToast') and not pg.errs, 'ukázka: tlačítka AI nic nespouštějí, bez chyb JS %s' % pg.errs)
    pg.click('#apd [data-apd=prehled]'); pg.wait_for_timeout(500); t = pg.inner_text('#apd')
    check('Aktivní (ukázka)' in t and '3 čekají na schválení' in t and '4 150' in t.replace('\u00a0', ' ') and pg.locator('#apd .vxd-plan li').count() >= 3 and pg.locator('#apd .vxd-cal .vxd-it').count() >= 3, 'ukázka: naplněný přehled (stav, plán AI, 3 koncepty, kalendář, zhlédnutí ze vzorových výsledků)'); ctx.close()
    b.close()
srv.shutdown()
print('\nSELHALO: %d' % len(fails) if fails else '\nVšechny kontroly prošly.')
sys.exit(1 if fails else 0)
