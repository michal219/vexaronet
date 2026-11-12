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
MODES = ['AI tým (přehled)', 'AI Marketing', 'AI Obchodník', 'AI CEO', 'AI Účetnictví', 'AI Weby a e-shopy', 'AI Automatizace']
fails = []
def check(c, m):
    print(('OK   ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
def open_page(b, cfg, vp=None):
    pg = b.new_page(viewport=vp or {'width': 1400, 'height': 1000}); pg.errs = []
    pg.on('pageerror', lambda e: pg.errs.append(str(e)))
    pg.add_init_script('window.__cfg=' + json.dumps(dict(cfg, companies=CO)) + ';')
    pg.add_init_script(MOCK); pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript'))
    pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(500)
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(500)
    return pg
def tab(pg, t): pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()" % t); pg.wait_for_timeout(350)
def log(pg, n): return pg.evaluate("window.__log.filter(function(x){return x[0]==='rpc'&&x[1]==='%s'})" % n)
def menu(pg): return [t.strip() for t in pg.locator('#vxside .vxd-sub button span').all_inner_texts()]
TABS = ['Přehled', 'Strategie', 'Obsah', 'Kampaně', 'Kalendář', 'Analýza', 'Finance & ROI', 'Integrace']
def dtab(pg, k): pg.click('#apd [data-apd=%s]' % k); pg.wait_for_timeout(350)

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = open_page(b, {'members': members()})
    check(menu(pg) == MODES, 'levé menu: skupina AI Autopilot nabízí přehled AI týmu a šest modulů ve správném pořadí: %s' % menu(pg))
    check(pg.locator('#vxside .vxd-hdr').inner_text().strip().startswith('AI Autopilot'), 'skupina se jmenuje AI Autopilot')
    tab(pg, 'autopilot'); pg.wait_for_selector('#apd')
    check(pg.locator('#vxside .apg.vxd-open').count() == 1, 'při otevřeném Autopilotu je skupina rozbalená')
    check(pg.locator('#vxside .vxd-sub [aria-pressed=true]').inner_text().strip() == 'AI Marketing', 'AI Marketing je zvýrazněn')
    pg.click('#vxside .vxd-hdr'); pg.wait_for_timeout(200)
    check(pg.locator('#vxside .apg.vxd-open').count() == 0, 'skupinu lze sbalit')
    pg.click('#vxside .vxd-hdr'); pg.wait_for_timeout(200)
    check(pg.locator('#vxside .apg.vxd-open').count() == 1, 'a znovu rozbalit')
    t = pg.inner_text('#apd')
    check('AI Marketing Autopilot' in t, 'hlavička dashboardu')
    check([x.strip() for x in pg.locator('#apd .vxd-tabs button').all_inner_texts()] == TABS, 'navigace: %s' % [x.strip() for x in pg.locator('#apd .vxd-tabs button').all_inner_texts()])
    check(pg.locator('#apd .vxd-kpis .vxd-kpi').count() == 5, 'řada pěti karet metrik')
    check('Dnešní plán' in t and 'Aktuální úkoly' in t and 'Marketingový kalendář' in t and 'Marketingová strategie' in t and 'Výsledky marketingu' in t and 'Marketing & Finance' in t, 'jsou všechny bloky přehledu')
    check('Nepřipojeno' in t and 'AI neběží' in t, 'poctivé stavy: „Nepřipojeno“ a „AI neběží“')
    check('Aktivní' not in t and 'Propojeno s financemi' not in t, 'žádný falešný stav „Aktivní“ ani „Propojeno“')
    kp = pg.locator('#apd .vxd-kpi').all_inner_texts()
    check('–' in kp[3] and 'ROAS' in kp[3] and '–' in kp[4], 'ROAS a zisk se bez dat nepočítají (zobrazí se „–“): %s' % [k.replace('\n', ' ') for k in kp[3:]])
    check(pg.locator('#apd .vxd-cal .vxd-day').count() == 7, 'kalendář má sedm dnů')
    # záložky
    for k, lab in [('strategie', 'Strategie'), ('obsah', 'Obsah'), ('kampane', 'Kampaně'), ('kalendar', 'Příspěvky v plánu'), ('analyza', 'Analýza'), ('integrace', 'Integrace')]:
        dtab(pg, k); check(pg.locator('#apd .vxd-tabs [aria-current=page]').get_attribute('data-apd') == k and lab in pg.inner_text('#apd'), 'záložka %s funguje' % k)
    dtab(pg, 'obsah'); check(pg.locator('#mk_topic').count() == 1 and pg.locator('[data-mk=gen]').count() == 1, 'generátor textů je v sekci Obsah')
    dtab(pg, 'prehled'); pg.click('#apd [data-apd-act=connect]'); pg.wait_for_selector('#socList')
    check('Facebook a Instagram' in pg.inner_text('#socList') and 'Nepodporováno' in pg.inner_text('#socList'), 'Připojit otevře Integrace s podporovanými a nepodporovanými sítěmi')
    dtab(pg, 'prehled'); pg.click('#apd [data-apd-act=budget]'); pg.wait_for_selector('.apdm')
    pg.keyboard.press('Escape'); pg.wait_for_timeout(200)
    check(pg.locator('.apdm').count() == 0 and pg.locator('#vxapp').count() == 1, 'Esc zavře dialog a ne celou aplikaci')
    check(not pg.errs, 'bez chyb JS: %s' % pg.errs)
    # moduly z menu
    for nm in ['AI Obchodník', 'AI CEO', 'AI Účetnictví', 'AI Weby a e-shopy', 'AI Automatizace']:
        pg.locator('#vxside .vxd-sub button', has_text=nm).click(); pg.wait_for_timeout(350)
        check(pg.locator('#vxside .vxd-sub [aria-pressed=true]').inner_text().strip() == nm, 'menu: %s je zvýrazněn' % nm)
    check(pg.locator('#apBar').is_visible() and 'AI Automatizace' in pg.locator('#apBar .apb.on').inner_text(), 'na stránkách modulů zůstává horní přepínač režimů')
    pg.evaluate("var x=document.createElement('button');x.dataset.tab='marketing';document.querySelector('#vxapp').appendChild(x)"); tab(pg, 'marketing'); check(pg.locator('#apd .vxd-tabs [aria-current=page]').get_attribute('data-apd') == 'obsah' and pg.locator('#apBar').is_hidden(), 'stará záložka Marketing otevře Obsah dashboardu')
    pg.close()

    # limit nákladů je ve Finance & ROI
    pg = open_page(b, {'members': members()}); tab(pg, 'autopilot'); dtab(pg, 'finance'); pg.wait_for_selector('#apRoot .card2'); pg.wait_for_timeout(300)
    t = pg.inner_text('#appMain')
    check('vypnuté' in t and 'nespouští žádné placené volání' in t, 'Finance & ROI říká, že placené AI běhy jsou vypnuté')
    check('není nastaven' in t, 'limit zatím není nastaven')
    check(pg.locator('.apchk li').count() == 4 and pg.locator('.apchk .apno').count() >= 3, 'připravenost: 4 podmínky, nesplněné jsou označené')
    check('0,30 USD' in t and '2,50 USD' in t and '2026-11-07' in t, 'ceník modelu: 0,30 / 2,50 USD za 1 M tokenů, ověřeno 2026-11-07')
    check(pg.locator('#apRoot .apgrid').count() == 0, 'mřížka režimů se zde neopakuje')
    check('ROAS' in t and 'nelze spočítat' in t, 'vysvětlení ROAS, ROI, výnosů a zisku; bez dat se nepočítají')
    pg.fill('#apLimit', 'abc'); pg.click('#apBudgetForm button[type=submit]'); pg.wait_for_timeout(200)
    check(len(log(pg, 'autopilot_set_budget')) == 0 and pg.inner_text('#apLimitErr') != '', 'neplatná hodnota se neodešle a je vysvětlena')
    pg.fill('#apLimit', '60'); pg.click('#apBudgetForm button[type=submit]'); pg.wait_for_timeout(200)
    check(len(log(pg, 'autopilot_set_budget')) == 0, 'limit nad 50 USD se neodešle')
    pg.click('[data-ap-act=preset]'); check(pg.input_value('#apLimit') == '0,25', 'tlačítko doporučené hodnoty vyplní 0,25')
    pg.click('#apBudgetForm button[type=submit]'); pg.wait_for_timeout(500)
    sb = log(pg, 'autopilot_set_budget')
    check(len(sb) == 1 and sb[0][2]['p_limit_nusd'] == 250000000 and sb[0][2]['cid'] == CO[0]['id'], 'uložení posílá 250 000 000 nUSD a cid aktivní firmy')
    t = pg.inner_text('#appMain').replace(' ', ' ')
    check('0,25 USD' in t and 'Limit:' in t, 'po uložení se zobrazí limit 0,25 USD')
    check(pg.locator('.apchk .apok').count() == 2 and 'Placené AI běhy jsou vypnuté' in t, 'dokud provozovatel placené běhy nepovolí, zůstávají vypnuté i po nastavení limitu')
    pg.click('[data-ap-act=clear]'); pg.wait_for_timeout(500)
    check(log(pg, 'autopilot_set_budget')[-1][2]['p_limit_nusd'] is None and 'není nastaven' in pg.inner_text('#appMain'), 'zrušení limitu')
    check(not pg.errs, 'bez chyb JS: %s' % pg.errs)
    pg.close()

    pg = open_page(b, {'members': members(), 'limit': 250000000, 'spent': 6200000, 'platform': True, 'profileConfirmed': True})
    tab(pg, 'autopilot'); dtab(pg, 'finance'); pg.wait_for_selector('#apRoot .card2'); pg.wait_for_timeout(300)
    t = pg.inner_text('#appMain').replace(' ', ' ')
    check(pg.locator('.apchk .apok').count() == 4 and 'Podmínky jsou splněné' in t and 'žádné placené volání nespouští' in t, 'i při splněných podmínkách Autopilot zatím žádné placené volání nespouští')
    check('0,0062 USD' in t and '2 %' in t, 'spotřeba a využití limitu se zobrazí (0,0062 USD, 2 %)')
    tab(pg, 'autopilot'); pg.wait_for_timeout(400)
    check(pg.inner_text('#apdPill').strip() == 'Aktivní' and pg.locator('#apdPill .vxd-on').count() == 1, 'stav v hlavičce: „Aktivní“ až když platí tarif, limit i povolení provozovatele')
    pg.close()
    pg = open_page(b, {'members': members(), 'limit': 250000000, 'platform': False}); tab(pg, 'autopilot'); pg.wait_for_timeout(500)
    check('Připraveno, AI zatím vypnutá' in pg.inner_text('#apdPill'), 'limit nastaven, ale placené běhy vypnuté: „Připraveno, AI zatím vypnutá“')
    check('Dnešní plán AI' in pg.inner_text('#apd'), 'blok Dnešní plán AI')
    # blokovač reklam (Opera, uBlock, AdBlock) skrývá prvky s třídami jako ad-card, ad-tabs, ad-banner: dashboard je nesmí používat
    pg.add_style_tag(content='[class^="ad-"],[class*=" ad-"],[class^="ads-"],[class*=" ads-"],[id^="ad-"],[class*="advert"],[class*="banner-ad"],[class*="sponsor"]{display:none!important}'); pg.wait_for_timeout(200)
    vis = pg.evaluate("['#apd .vxd-tabs','#apd .vxd-kpis','#apd .vxd-card','#vxside .vxd-sub','#vxside .vxd-agents'].map(function(q){var e=document.querySelector(q);return !!e&&e.offsetParent!==null&&e.getBoundingClientRect().height>10})")
    check(all(vis), 'se zapnutým blokovačem reklam zůstane dashboard i menu AI Autopilota vidět: %s' % vis)
    src = open(ROOT + '/index.html', encoding='utf-8').read()
    import re as _re
    bad = sorted(set(_re.findall(r'(?<![A-Za-z0-9_-])(?:ad|ads|advert|banner|sponsor)-[a-z0-9]+', ' '.join(_re.findall(r'class=\\?["\']([^"\']*)', src)))))
    check(not bad, 'v aplikaci nejsou třídy, které blokovače reklam skrývají: %s' % bad[:8])
    pg.close()

    pg = open_page(b, {'members': members(), 'noDb': True}); tab(pg, 'autopilot'); dtab(pg, 'finance'); pg.wait_for_selector('#apRoot .draft')
    check('aktualizaci databáze' in pg.inner_text('#apRoot'), 'bez migrace: srozumitelné upozornění'); pg.close()
    pg = open_page(b, {'members': members(), 'forbid': True}); tab(pg, 'autopilot'); dtab(pg, 'finance'); pg.wait_for_selector('#apRoot .draft')
    check('oprávnění' in pg.inner_text('#apRoot'), 'bez oprávnění: srozumitelné upozornění'); pg.close()
    pg = open_page(b, {'members': members(), 'isRoot': False}); tab(pg, 'autopilot'); dtab(pg, 'finance'); pg.wait_for_selector('#apRoot .card2')
    check(pg.locator('#apBudgetForm').count() == 0 and 'hlavní firma' in pg.inner_text('#apRoot'), 'pobočka limit nenastavuje, vidí jen stav'); pg.close()

    # role a tarify
    pg = open_page(b, {'members': members('employee')})
    check(pg.locator('#apBar').count() == 0 and pg.locator('#vxside .apg').count() == 0, 'zaměstnanec menu AI Autopilot ani přepínač nevidí'); pg.evaluate("var x=document.createElement('button');x.dataset.tab='autopilot';document.querySelector('#vxapp').appendChild(x)"); tab(pg, 'autopilot')
    check(len(log(pg, 'autopilot_status')) == 0, 'zaměstnanec nevolá server pro stav limitu'); pg.close()
    pg = open_page(b, {'members': members(), 'plan': 'start'})
    check(pg.locator('#apBar .apt.lock').count() >= 0 and pg.locator('#vxside .apg').count() == 1, 'tarif START: skupina je vidět')
    pg.locator('#vxside .vxd-sub button', has_text='AI CEO').click(); pg.wait_for_timeout(300)
    check('není součástí vašeho tarifu' in pg.inner_text('#appMain'), 'tarif START: AI CEO je zamčené (existující pravidlo tarifu zůstává)')
    pg.locator('#vxside .vxd-sub button', has_text='AI Automatizace').click(); pg.wait_for_timeout(300)
    check('není součástí' not in pg.inner_text('#appMain'), 'tarif START: AI Automatizace (pravidla) dostupná')
    pg.close()

    # ukázka
    pg = b.new_page(viewport={'width': 1300, 'height': 900}); pg.errs = []; pg.on('pageerror', lambda e: pg.errs.append(str(e)))
    pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript')); pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]'); pg.wait_for_selector('#vxapp .kpi'); tab(pg, 'autopilot')
    check('Ukázková data' in pg.inner_text('#apd') and not pg.errs, 'ukázka: dashboard je označen jako ukázková data'); pg.close()

    # mobil
    pg = open_page(b, {'members': members()}, vp={'width': 390, 'height': 800}); tab(pg, 'autopilot'); pg.wait_for_selector('#apd')
    w = pg.evaluate("[document.documentElement.scrollWidth, window.innerWidth, document.getElementById('appMain').scrollWidth, document.getElementById('appMain').clientWidth, document.querySelector('#apd .vxd-tabs').scrollWidth, document.querySelector('#apd .vxd-tabs').clientWidth]")
    check(w[0] <= w[1] + 1 and w[2] <= w[3] + 1, 'mobil 390 px: stránka ani obsah se nerozšiřuje do šířky %s' % w)
    check(w[4] > w[5], 'mobil: záložky se posouvají vodorovně uvnitř svého pruhu')
    pg.close()
    b.close()
print('\nSELHALO: %d' % len(fails) if fails else '\nVšechny kontroly prošly.')
sys.exit(1 if fails else 0)
