"""UI test horního přepínače AI Autopilota a přehledu limitu na zamockovaném Supabase (bez internetu a bez AI).
Mock napodobuje databázové funkce autopilot_status / autopilot_set_budget a profile_get.
Spuštění: python3 tests/autopilot_ui.py"""
import json, os, sys
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOCK = r'''
(function(){
var C=window.__cfg||{};
var ST=window.__st={limit:C.limit==null?null:C.limit,spent:C.spent||0,platform:!!C.platform,isRoot:C.isRoot!==false,planAllowed:C.planAllowed!==false};
window.__log=[];
var D={companies:C.companies,company_members:C.members,subscriptions:[{plan:C.plan||'pro',status:C.plan==='start'?'active':'trial',trial_end:new Date(Date.now()+20*864e5).toISOString()}]};
function qb(t){var o={_op:'sel',select(){return o},eq(){return o},limit(){return o},is(){return o},order(){return o},insert(){return Promise.resolve({error:null})},update(){o._op='u';return o},delete(){o._op='d';return o},then(f){return Promise.resolve({data:o._op==='sel'?(D[t]||[]):null,error:null}).then(f)}};return o}
function ok(d){return Promise.resolve({data:d,error:null})}
function err(c,m){return Promise.resolve({data:null,error:{code:c,message:m,details:''}})}
function rpc(n,a){
 window.__log.push(['rpc',n,JSON.parse(JSON.stringify(a||{}))]);
 if(n==='autopilot_status'){
  if(C.noDb)return err('PGRST202','Could not find the function public.autopilot_status(cid) in the schema cache');
  if(C.forbid)return err('42501','forbidden');
  var rem=ST.limit==null?null:Math.max(ST.limit-ST.spent,0);
  return ok({root_id:a.cid,is_root:ST.isRoot,plan_allowed:ST.planAllowed,platform_paid_runs_enabled:ST.platform,monthly_limit_nusd:ST.limit,spent_nusd:ST.spent,open_reserved_nusd:0,remaining_nusd:rem,runs_this_month:0,month_start:new Date().toISOString(),paid_runs_possible:false,
   models:[{model:'gemini-3.5-flash-lite',input_nusd_per_token:300,output_nusd_per_token:2500,verified_on:'2026-11-07',source_url:'https://ai.google.dev/gemini-api/docs/pricing'}]})}
 if(n==='autopilot_set_budget'){
  var v=a.p_limit_nusd;if(v!==null&&(v<0||v>50000000000))return err('PT422','validation_failed');
  ST.limit=v;return ok({monthly_limit_nusd:v})}
 if(n==='profile_get'){if(C.noProfile)return err('PGRST202','nope');return ok({company_id:a.cid,is_root:true,active:C.profileConfirmed?{version:1}:null,draft:null,versions:[],can_write:true,schema_version:1})}
 if(n==='company_team')return ok([]);if(n==='accept_company_invites')return ok(0);
 return ok({income:0,expenses:0,customers:0,active_jobs:0,reservations_today:0})}
window.supabase={createClient:function(){return{from:qb,rpc:rpc,auth:{getSession:()=>Promise.resolve({data:{session:{access_token:'t'}}}),getUser:()=>Promise.resolve({data:{user:{id:'u1',email:'a@b.cz',user_metadata:{full_name:'Jan Konina'}}}}),onAuthStateChange(){},updateUser:(x)=>Promise.resolve({data:{user:{user_metadata:x.data}},error:null}),signOut(){}}}}};
})();
'''
CO = [{'id': '11111111-1111-1111-1111-111111111111', 'name': 'Autoservis Konina', 'industry': 'Autoservis', 'parent_company_id': None, 'created_at': '2026-10-01T00:00:00Z'}]
def members(role='owner'): return [{'company_id': CO[0]['id'], 'role': role, 'companies': CO[0]}]
MODES = ['AI Marketing', 'AI Obchodník', 'AI CEO', 'AI Účetnictví', 'AI Weby a e-shopy', 'AI Automatizace']
fails = []
def check(c, m):
    print(('OK   ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def open_page(b, cfg, vp=None):
    pg = b.new_page(viewport=vp or {'width': 1400, 'height': 1000}); pg.errs = []
    pg.on('pageerror', lambda e: pg.errs.append(str(e)))
    pg.add_init_script('window.__cfg=' + json.dumps(dict(cfg, companies=CO)) + ';')
    pg.route('**/supabase.js', lambda r: r.fulfill(body=MOCK, content_type='text/javascript'))
    pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(500)
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(500)
    return pg
def tab(pg, t): pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()" % t); pg.wait_for_timeout(350)
def log(pg, n): return pg.evaluate("window.__log.filter(function(x){return x[0]==='rpc'&&x[1]==='%s'})" % n)
def names(pg): return [t.strip().split('\n')[0] for t in pg.locator('#apBar .apb > span').all_inner_texts()]

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = open_page(b, {'members': members()})
    check(names(pg) == ['Autopilot'] + MODES, 'horní lišta nabízí Autopilot a šest požadovaných režimů ve správném pořadí: %s' % names(pg))
    box = pg.evaluate("(function(){var a=document.getElementById('apBar').getBoundingClientRect(),m=document.getElementById('appMain').getBoundingClientRect(),h=document.querySelector('.vxmain header').getBoundingClientRect();return [h.bottom,a.top,a.bottom,m.top]})()")
    check(box[1] >= box[0] - 1 and box[2] <= box[3] + 1, 'lišta je nahoře, pod hlavičkou a nad obsahem %s' % box)
    pg.screenshot(path='/tmp/claude-0/autopilot_lista.png')

    tab(pg, 'ceo'); check(pg.locator('#apBar .apb.on').inner_text().startswith('AI CEO'), 'AI CEO: režim je zvýrazněn')
    check('Doporučení' in pg.inner_text('#appMain') or 'AI CEO' in pg.inner_text('#appMain'), 'AI CEO: otevřel se modul AI CEO')
    tab(pg, 'ucetni'); check(pg.locator('#apBar .apb.on').inner_text().startswith('AI Účetnictví'), 'AI Účetnictví: režim je zvýrazněn')
    chips = pg.locator('#apSub button').all_inner_texts()
    check(len(chips) >= 3, 'u režimu jsou související moduly: %s' % chips)
    tab(pg, 'finance'); check(pg.locator('#apBar .apb.on').inner_text().startswith('AI Účetnictví'), 'Finance otevřené z AI Účetnictví zůstanou v režimu AI Účetnictví (společná záložka)')
    tab(pg, 'ceo'); tab(pg, 'finance'); check(pg.locator('#apBar .apb.on').inner_text().startswith('AI CEO'), 'Finance otevřené z AI CEO zůstanou v režimu AI CEO')
    for nm, tb in [('AI Marketing', 'marketing'), ('AI Obchodník', 'pripady'), ('AI Weby a e-shopy', 'weby'), ('AI Automatizace', 'automatizace')]:
        pg.locator('#apBar .apb', has_text=nm).first.click(); pg.wait_for_timeout(350)
        check(pg.locator('#apBar .apb.on').inner_text().startswith(nm), 'klik na „%s“ otevře režim a zvýrazní ho' % nm)
    pg.locator('#apBar .apb', has_text='AI Obchodník').first.click(); pg.wait_for_timeout(300)
    check('připravujeme' in pg.inner_text('#apSub'), 'AI Obchodník se netváří jako hotový: ukazuje „připravujeme“')
    check(not pg.errs, 'bez chyb JS: %s' % pg.errs)

    # přehled Autopilota
    pg.locator('#apBar .apb', has_text='Autopilot').first.click(); pg.wait_for_selector('#apRoot .card2'); pg.wait_for_timeout(300)
    t = pg.inner_text('#appMain')
    check('vypnuté' in t and 'nespouští žádné placené volání' in t, 'přehled říká, že placené AI běhy jsou vypnuté')
    check('není nastaven' in t, 'limit zatím není nastaven')
    check(pg.locator('.apchk li').count() == 4 and pg.locator('.apchk .apno').count() >= 3, 'připravenost: 4 podmínky, nesplněné jsou označené')
    check('0,30 USD' in t and '2,50 USD' in t and '2026-11-07' in t, 'ceník modelu: 0,30 / 2,50 USD za 1 M tokenů, ověřeno 2026-11-07')
    check(pg.locator('.apgrid .apcard').count() == 6, 'přehled obsahuje šest režimů')
    # nastavení limitu
    pg.fill('#apLimit', 'abc'); pg.click('#apBudgetForm button[type=submit]'); pg.wait_for_timeout(200)
    check(len(log(pg, 'autopilot_set_budget')) == 0 and pg.inner_text('#apLimitErr') != '', 'neplatná hodnota se neodešle a je vysvětlena')
    pg.fill('#apLimit', '60'); pg.click('#apBudgetForm button[type=submit]'); pg.wait_for_timeout(200)
    check(len(log(pg, 'autopilot_set_budget')) == 0, 'limit nad 50 USD se neodešle')
    pg.click('[data-ap-act=preset]'); check(pg.input_value('#apLimit') == '0,25', 'tlačítko doporučené hodnoty vyplní 0,25')
    pg.click('#apBudgetForm button[type=submit]'); pg.wait_for_timeout(500)
    sb = log(pg, 'autopilot_set_budget')
    check(len(sb) == 1 and sb[0][2]['p_limit_nusd'] == 250000000 and sb[0][2]['cid'] == CO[0]['id'], 'uložení posílá 250 000 000 nUSD a cid aktivní firmy')
    t = pg.inner_text('#appMain').replace(' ', ' ')
    check('0,25 USD' in t and 'Limit:' in t, 'po uložení se zobrazí limit 0,25 USD')
    check(pg.locator('.apchk .apok').count() == 2 and 'Placené AI běhy jsou vypnuté' in t, 'dokud provozovatel placené běhy nepovolí, zůstávají vypnuté i po nastavení limitu')
    pg.click('[data-ap-act=clear]'); pg.wait_for_timeout(500)
    check(log(pg, 'autopilot_set_budget')[-1][2]['p_limit_nusd'] is None and 'není nastaven' in pg.inner_text('#appMain'), 'zrušení limitu')
    check(not pg.errs, 'bez chyb JS: %s' % pg.errs)
    pg.close()

    # všechny podmínky splněné: pořád nic nespouští
    pg = open_page(b, {'members': members(), 'limit': 250000000, 'spent': 6200000, 'platform': True, 'profileConfirmed': True})
    tab(pg, 'autopilot'); pg.wait_for_selector('#apRoot .card2'); pg.wait_for_timeout(300)
    t = pg.inner_text('#appMain').replace(' ', ' ')
    check(pg.locator('.apchk .apok').count() == 4 and 'Podmínky jsou splněné' in t and 'žádné placené volání nespouští' in t, 'i při splněných podmínkách Autopilot zatím žádné placené volání nespouští')
    check('0,0062 USD' in t and '2 %' in t, 'spotřeba a využití limitu se zobrazí (0,0062 USD, 2 %)')
    pg.close()

    # databáze bez migrace, bez oprávnění, pobočka
    pg = open_page(b, {'members': members(), 'noDb': True}); tab(pg, 'autopilot'); pg.wait_for_selector('#apRoot .draft')
    check('aktualizaci databáze' in pg.inner_text('#apRoot') and pg.locator('.apgrid .apcard').count() == 6, 'bez migrace: srozumitelné upozornění, přepínač dál funguje')
    pg.close()
    pg = open_page(b, {'members': members(), 'forbid': True}); tab(pg, 'autopilot'); pg.wait_for_selector('#apRoot .draft')
    check('oprávnění' in pg.inner_text('#apRoot'), 'bez oprávnění: srozumitelné upozornění'); pg.close()
    pg = open_page(b, {'members': members(), 'isRoot': False}); tab(pg, 'autopilot'); pg.wait_for_selector('#apRoot .card2')
    check(pg.locator('#apBudgetForm').count() == 0 and 'hlavní firma' in pg.inner_text('#apRoot'), 'pobočka limit nenastavuje, vidí jen stav'); pg.close()

    # role a tarify
    pg = open_page(b, {'members': members('employee')})
    check(pg.locator('#apBar').count() == 0, 'zaměstnanec přepínač nevidí'); tab(pg, 'autopilot')
    check(len(log(pg, 'autopilot_status')) == 0, 'zaměstnanec nevolá server pro stav limitu'); pg.close()
    pg = open_page(b, {'members': members(), 'plan': 'start'})
    check(pg.locator('#apBar .apt.lock').count() >= 4, 'tarif START: režimy vyžadující PRO jsou označené')
    pg.locator('#apBar .apb', has_text='AI CEO').first.click(); pg.wait_for_timeout(300)
    check('není součástí vašeho tarifu' in pg.inner_text('#appMain'), 'tarif START: AI CEO je zamčené (existující pravidlo tarifu zůstává)')
    pg.locator('#apBar .apb', has_text='AI Automatizace').first.click(); pg.wait_for_timeout(300)
    check('není součástí' not in pg.inner_text('#appMain'), 'tarif START: AI Automatizace (pravidla) dostupná')
    pg.close()

    # ukázka
    pg = b.new_page(viewport={'width': 1300, 'height': 900}); pg.errs = []; pg.on('pageerror', lambda e: pg.errs.append(str(e)))
    pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript')); pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]'); pg.wait_for_selector('#vxapp .kpi'); tab(pg, 'autopilot')
    check(pg.locator('#apBar .apb').count() == 7 and 'V ukázce' in pg.inner_text('#appMain') and not pg.errs, 'ukázka: lišta je, přehled hlásí, že se limit v ukázce nezobrazuje'); pg.close()

    # mobil
    pg = open_page(b, {'members': members()}, vp={'width': 390, 'height': 800}); tab(pg, 'autopilot'); pg.wait_for_selector('#apRoot .card2')
    w = pg.evaluate("[document.documentElement.scrollWidth, window.innerWidth, document.getElementById('apBar').scrollWidth, document.getElementById('apBar').clientWidth]")
    check(w[0] <= w[1] + 1, 'mobil 390 px: stránka se nerozšiřuje do šířky %s' % w)
    check(w[2] > w[3], 'mobil: lišta se posouvá vodorovně sama (nezalamuje se a nevytlačuje stránku)')
    pg.screenshot(path='/tmp/claude-0/autopilot_mobil.png'); pg.close()
    b.close()
print('\nSELHALO: %d' % len(fails) if fails else '\nVŠE V POŘÁDKU')
sys.exit(1 if fails else 0)
