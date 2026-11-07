"""UI test profilu firmy a výběru aktivní firmy na zamockovaném Supabase (bez internetu a bez databáze).
Mock napodobuje chování databázových funkcí profile_* (konflikt revize jako chyba PT409, kontrola verze schématu).
Skutečné chování databáze ověřují db/test/10_profile_tests.sql a tests/profile_parity.py.
Spuštění:  python3 tests/profile_ui.py   (potřebuje playwright + chromium)"""
import json, os, sys
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = open(os.path.join(ROOT, 'src', 'onboarding_schema.json'), encoding='utf-8').read()
MOCK = r'''
(function(){
var C=window.__cfg||{},SCHEMA=__SCHEMA__;
var SRV=window.__srv={rev:0,data:null,active:null,versions:[],canWrite:C.canWrite!==false,isRoot:C.isRoot!==false};
window.__log=[];
var D={companies:C.companies,company_members:C.members,subscriptions:[{plan:C.plan||'pro',status:C.plan==='start'?'active':'trial',trial_end:new Date(Date.now()+20*864e5).toISOString()}]};
function qb(t){var o={_op:'sel',select(){return o},eq(){return o},limit(){return o},is(){return o},order(){return o},insert(r){return Promise.resolve({error:null})},update(){o._op='u';return o},delete(){o._op='d';return o},then(f){window.__log.push(['from',t]);return Promise.resolve({data:o._op==='sel'?(D[t]||[]):null,error:null}).then(f)}};return o}
function ok(d){return Promise.resolve({data:d,error:null})}
function err(code,msg,det){return Promise.resolve({data:null,error:{code:code,message:msg,details:det||''}})}
function rpc(n,a){
 window.__log.push(['rpc',n,JSON.parse(JSON.stringify(a||{}))]);
 if(n==='profile_schema_info'){var s=JSON.parse(JSON.stringify(SCHEMA));if(C.badSchema)s.shared.properties.identity.properties.displayName.maxLength=99;return ok({version:1,schema:s})}
 if(n==='profile_get'){
  if(C.forbid)return err('42501','forbidden');
  return ok({company_id:a.cid,root_id:C.rootId||a.cid,is_root:SRV.isRoot,schema_version:1,can_write:SRV.canWrite,
   draft:SRV.data?{revision:SRV.rev,data:JSON.parse(JSON.stringify(SRV.data)),hash:'h'+SRV.rev,updated_at:new Date().toISOString()}:null,
   active:SRV.active,versions:SRV.versions,
   shared_from_root:SRV.isRoot?undefined:{version:1,data:{identity:{displayName:'Hlavní firma',activity:'Opravy'},services:{items:[{name:'Opravy'}]},audience:{description:'Řidiči'}}}})}
 if(n==='profile_save_draft'){
  if(a.schema_version!==1)return err('PT412','schema_mismatch','{"server_version":1}');
  if(a.expected_revision!==SRV.rev)return err('PT409','revision_conflict','{"current_revision": '+SRV.rev+'}');
  var d=JSON.parse(JSON.stringify(a.doc));
  ((d.shared||{}).goals||[]).forEach(function(g){if(g.baselineMinor!=null&&g.growthBp!=null){g.targetMinor=Math.floor((g.baselineMinor*(10000+g.growthBp)+5000)/10000);g.targetSource='calc'}});
  if(JSON.stringify(d)!==JSON.stringify(SRV.data)){SRV.rev+=1;SRV.data=d}
  return ok({revision:SRV.rev,data:SRV.data,hash:'h'+SRV.rev,updated_at:new Date().toISOString()})}
 if(n==='profile_confirm'){
  if(a.expected_revision!==SRV.rev||a.expected_hash!=='h'+SRV.rev)return err('PT409','revision_conflict','{"current_revision": '+SRV.rev+'}');
  var v=SRV.versions.length+1;SRV.versions.unshift({version:v,hash:'h'+SRV.rev,confirmed_at:new Date().toISOString(),by_me:true});SRV.active={version:v,hash:'h'+SRV.rev,confirmed_at:new Date().toISOString(),data:SRV.data};
  return ok({version:v,hash:'h'+SRV.rev,confirmed_at:new Date().toISOString(),unchanged:false})}
 if(n==='company_team')return ok([]);
 if(n==='accept_company_invites')return ok(0);
 return ok({income:0,expenses:0,customers:0,active_jobs:0,reservations_today:0})}
window.supabase={createClient:function(){return{from:qb,rpc:rpc,auth:{getSession:()=>Promise.resolve({data:{session:{access_token:'t'}}}),getUser:()=>Promise.resolve({data:{user:{id:'u1',email:'a@b.cz',user_metadata:{full_name:'Jan Konina'}}}}),onAuthStateChange(){},updateUser:(x)=>Promise.resolve({data:{user:{user_metadata:x.data}},error:null}),signOut(){}}}}};
})();
'''.replace('__SCHEMA__', SCHEMA)

ROOT_ID, BR_ID = '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'
CO = [{'id': ROOT_ID, 'name': 'Autoservis Konina', 'industry': 'Autoservis', 'parent_company_id': None, 'created_at': '2026-10-01T00:00:00Z'},
      {'id': BR_ID, 'name': 'Konina Beroun', 'industry': 'Autoservis', 'parent_company_id': ROOT_ID, 'created_at': '2026-10-05T00:00:00Z'}]
def members(order, role='owner'):
    rows = {ROOT_ID: {'company_id': ROOT_ID, 'role': role, 'companies': CO[0]}, BR_ID: {'company_id': BR_ID, 'role': role, 'companies': CO[1]}}
    return [rows[i] for i in order]

fails = []
def check(c, m):
    print(('OK   ' if c else 'FAIL ') + m)
    if not c: fails.append(m)

def open_page(b, cfg, vp=None, store=None):
    pg = b.new_page(viewport=vp or {'width': 1400, 'height': 1000}); pg.errs = []
    pg.on('pageerror', lambda e: pg.errs.append(str(e)))
    pg.add_init_script('window.__cfg=' + json.dumps(cfg) + ';' + ('try{localStorage.setItem("vx_active_company_u1",%s)}catch(e){}' % json.dumps(store) if store else ''))
    pg.route('**/supabase.js', lambda r: r.fulfill(body=MOCK, content_type='text/javascript'))
    pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(500)
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(500)
    return pg
def tab(pg, t): pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()" % t)
def log(pg, name): return pg.evaluate("window.__log.filter(function(x){return x[0]==='rpc'&&x[1]==='%s'})" % name)

with sync_playwright() as p:
    b = p.chromium.launch()

    # ---- 1) hlavní firma: vyplnění, automatické ukládání, výpočet cíle, potvrzení -----------------
    pg = open_page(b, {'companies': CO, 'members': members([BR_ID, ROOT_ID])})
    check([x[2]['cid'] for x in log(pg, 'profile_get')] == [], 'profil se nenačítá, dokud ho uživatel neotevře')
    tab(pg, 'firmaprofil'); pg.wait_for_selector('#fp_shared_identity_displayName'); pg.wait_for_timeout(300)
    check(log(pg, 'profile_get')[0][2]['cid'] == ROOT_ID, 'aktivní firma = hlavní firma i když DB vrátí členství v opačném pořadí')
    check(pg.locator('#fp_local_geography_city').count() == 1 and pg.locator('#fp_shared_audience_description').count() == 1, 'hlavní firma vidí společné i lokální sekce')
    pg.fill('#fp_shared_identity_displayName', '  Autoservis Konina  ')
    pg.fill('#fp_shared_identity_website', 'vexaronet.com'); pg.wait_for_timeout(1900)
    check(len(log(pg, 'profile_save_draft')) == 0, 'neplatná adresa webu se neodešle na server')
    check('formát' in pg.inner_text('[data-fe="shared.identity.website"]').lower(), 'u pole webu je vidět chyba formátu')
    pg.fill('#fp_shared_identity_website', '')
    pg.fill('#fp_shared_identity_activity', 'autoservis, výměna a úprava výfuků')
    pg.click('[data-fp=add][data-base="shared.services.items"]'); pg.wait_for_selector('#fp_shared_services_items_0_name')
    pg.fill('#fp_shared_services_items_0_name', 'Výměna a úpravy výfuků')
    pg.fill('#fp_shared_audience_description', 'Řidiči v okolí Prahy')
    pg.fill('#fp_shared_financialContext_revenueMinor', '146 000'); pg.select_option('#fp_shared_financialContext_revenueCurrency', 'CZK'); pg.select_option('#fp_shared_financialContext_revenuePeriod', 'month')
    pg.fill('#fp_shared_goals_0_baselineMinor', '146000'); pg.fill('#fp_shared_goals_0_growthBp', '35'); pg.fill('#fp_shared_goals_0_dueDate', '2027-05-07')
    pg.check('input[data-multi="shared.channels"][value=facebook]'); pg.check('input[data-multi="shared.channels"][value=instagram]')
    pg.fill('#fp_local_geography_city', 'Praha')
    calc = pg.inner_text('#fpCalc').replace(' ', ' ')
    check('197 100' in calc and '51 100' in calc, 'náhled cíle: 146 000 Kč + 35 % = 197 100 Kč, rozdíl 51 100 Kč (' + calc[:60] + ')')
    check('scénář' in calc.lower(), 'náhled cíle říká, že jde o scénář, ne slib')
    pg.wait_for_timeout(2000)
    saves = log(pg, 'profile_save_draft')
    check(len(saves) == 1, 'změny se uložily jedním automatickým uložením (%d)' % len(saves))
    a = saves[0][2] if saves else {}
    d = a.get('doc', {}); sh = d.get('shared', {})
    check(a.get('expected_revision') == 0 and a.get('schema_version') == 1 and a.get('cid') == ROOT_ID, 'uložení nese cid aktivní firmy, očekávanou revizi 0 a verzi schématu')
    check(sh.get('identity', {}).get('displayName') == 'Autoservis Konina', 'text je před odesláním ořezaný')
    check(sh.get('financialContext', {}).get('revenueMinor') == 14600000, 'tržby 146 000 Kč se posílají jako 14 600 000 haléřů')
    check(sh.get('goals', [{}])[0].get('growthBp') == 3500 and sh['goals'][0].get('baselineMinor') == 14600000, 'růst 35 % = 3 500 bazických bodů')
    check([c['channel'] for c in sh.get('channels', [])] == ['facebook', 'instagram'], 'kanály jsou jen uvedené, bez příznaku připojení')
    check('Uloženo' in pg.inner_text('#fpSave'), 'stav: Uloženo (' + pg.inner_text('#fpSave') + ')')
    check(not pg.is_disabled('#fpConfirm'), 'tlačítko Potvrdit je po vyplnění povinných údajů aktivní')
    pg.click('#fpConfirm'); pg.wait_for_timeout(600)
    cf = log(pg, 'profile_confirm')
    check(len(cf) == 1 and cf[0][2]['expected_revision'] == 1 and cf[0][2]['expected_hash'] == 'h1', 'potvrzení posílá přesnou revizi a otisk, které uživatel vidí')
    check('Potvrzeno: verze 1' in pg.inner_text('#fpState'), 'po potvrzení je vidět platná verze 1')

    # ---- 2) konflikt revize: nikdy tiché přepsání ---------------------------------------------------
    pg.evaluate("window.__srv.rev=7;window.__srv.data.shared.identity.displayName='Změna od kolegy'")
    pg.fill('#fp_shared_identity_displayName', 'Moje změna'); pg.wait_for_timeout(2000)
    check(pg.locator('#fpConflict .draft').count() == 1 and 'někdo jiný' in pg.inner_text('#fpConflict'), 'konflikt je viditelný a vysvětlený')
    check(pg.evaluate("window.__srv.data.shared.identity.displayName") == 'Změna od kolegy', 'konflikt nepřepsal data na serveru')
    check(len(log(pg, 'profile_save_draft')) == 2, 'po konfliktu se automaticky nezkouší znovu')
    pg.click('[data-fp=reload]'); pg.wait_for_timeout(500)
    check(pg.input_value('#fp_shared_identity_displayName') == 'Změna od kolegy', 'Načíst novější: formulář ukazuje verzi ze serveru')
    pg.fill('#fp_shared_identity_displayName', 'Moje změna 2'); pg.wait_for_timeout(2000)
    check('Moje změna 2' in pg.evaluate("JSON.stringify(window.__srv.data)"), 'po načtení novější verze se ukládá dál (revize 7 → 8)')
    pg.evaluate("window.__srv.rev=20"); pg.fill('#fp_shared_identity_displayName', 'Přepis'); pg.wait_for_timeout(2000)
    pg.click('[data-fp=overwrite]'); pg.wait_for_timeout(600)
    ow = log(pg, 'profile_save_draft')[-1][2]
    check(ow['expected_revision'] == 20 and ow['doc']['shared']['identity']['displayName'] == 'Přepis', 'Přepsat mojí verzí: výslovná volba uživatele, s aktuální revizí ze serveru')
    check(not pg.errs, 'žádné chyby JS: %s' % pg.errs)
    pg.close()

    # ---- 3) verze formuláře se liší od databáze -> ukládání vypnuto ---------------------------------
    pg = open_page(b, {'companies': CO, 'members': members([ROOT_ID]), 'badSchema': True})
    tab(pg, 'firmaprofil'); pg.wait_for_selector('#fpRoot .card2'); pg.wait_for_timeout(300)
    check('jinou verzi formuláře' in pg.inner_text('#fpRoot'), 'nesoulad schématu aplikace a DB zobrazí varování')
    check(pg.is_disabled('#fp_shared_identity_displayName') and pg.is_disabled('#fpConfirm'), 'při nesouladu je formulář i potvrzení zakázáno')
    check(len(log(pg, 'profile_save_draft')) == 0, 'při nesouladu se nic neukládá')
    pg.close()

    # ---- 4) jen pro čtení (prošlá zkouška) -----------------------------------------------------------
    pg = open_page(b, {'companies': CO, 'members': members([ROOT_ID]), 'canWrite': False})
    tab(pg, 'firmaprofil'); pg.wait_for_selector('#fp_shared_identity_displayName'); pg.wait_for_timeout(300)
    check('jen pro čtení' in pg.inner_text('#fpRoot') and pg.is_disabled('#fp_shared_identity_displayName'), 'bez zapisovatelného předplatného je profil jen ke čtení')
    pg.close()

    # ---- 5) zaměstnanec profil nevidí, tarif START ho má --------------------------------------------
    pg = open_page(b, {'companies': CO, 'members': members([ROOT_ID], 'employee')})
    tab(pg, 'firmaprofil'); pg.wait_for_timeout(500)
    check(len(log(pg, 'profile_get')) == 0 and 'není součástí' in pg.inner_text('#appMain'), 'zaměstnanec k profilu nemá přístup (a nevolá se server)')
    pg.close()
    pg = open_page(b, {'companies': CO, 'members': members([ROOT_ID]), 'plan': 'start'})
    tab(pg, 'firmaprofil'); pg.wait_for_selector('#fp_shared_identity_displayName')
    check(pg.locator('#fp_shared_identity_displayName').count() == 1, 'ruční profil je dostupný i v tarifu START')
    pg.close()

    # ---- 6) pobočka: jen lokální sekce, společné údaje jen ke čtení ----------------------------------
    pg = open_page(b, {'companies': CO, 'members': members([ROOT_ID, BR_ID]), 'isRoot': False, 'rootId': ROOT_ID}, store=BR_ID)
    tab(pg, 'firmaprofil'); pg.wait_for_selector('#fp_local_geography_city'); pg.wait_for_timeout(300)
    check(log(pg, 'profile_get')[0][2]['cid'] == BR_ID, 'uložená volba aktivní firmy (pobočka) se použije')
    check(pg.locator('#fp_shared_identity_displayName').count() == 0 and 'Společné údaje hlavní firmy' in pg.inner_text('#fpRoot') and 'Hlavní firma' in pg.inner_text('#fpRoot'), 'pobočka nemůže upravit společné údaje, vidí je jen ke čtení')
    pg.fill('#fp_local_geography_city', 'Beroun'); pg.wait_for_timeout(2000)
    br = log(pg, 'profile_save_draft')
    check(len(br) == 1 and list(br[0][2]['doc'].keys()) == ['local'] and br[0][2]['cid'] == BR_ID, 'pobočka ukládá jen sekci local')
    # přepnutí firmy v Nastavení
    tab(pg, 'profil'); pg.wait_for_selector('#coSel')
    check(pg.locator('#coSel option').count() == 2, 'Nastavení nabízí přepínač firem, když má účet více členství')
    pg.select_option('#coSel', ROOT_ID); pg.click('#coForm button[type=submit]'); pg.wait_for_timeout(900)
    check(pg.evaluate("localStorage.getItem('vx_active_company_u1')") == ROOT_ID, 'volba aktivní firmy se uložila')
    pg.close()

    # uložená volba, která už neplatí, se ignoruje
    pg = open_page(b, {'companies': CO, 'members': members([BR_ID, ROOT_ID])}, store='99999999-9999-9999-9999-999999999999')
    tab(pg, 'firmaprofil'); pg.wait_for_selector('#fpRoot .card2')
    check(log(pg, 'profile_get')[0][2]['cid'] == ROOT_ID, 'neplatná uložená volba firmy se ignoruje (padá na hlavní firmu)')
    pg.close()

    # ---- 7) mobil: bez vodorovného posunu ------------------------------------------------------------
    pg = open_page(b, {'companies': CO, 'members': members([ROOT_ID])}, vp={'width': 390, 'height': 800})
    tab(pg, 'firmaprofil'); pg.wait_for_selector('#fp_shared_identity_displayName'); pg.wait_for_timeout(300)
    pg.click('[data-fp=add][data-base="shared.services.items"]'); pg.wait_for_selector('#fp_shared_services_items_0_name')
    w = pg.evaluate("[document.documentElement.scrollWidth, window.innerWidth, document.getElementById('appMain').scrollWidth, document.getElementById('appMain').clientWidth]")
    check(w[0] <= w[1] + 1 and w[2] <= w[3] + 1, 'mobil 390 px: žádný vodorovný posun %s' % w)
    pg.screenshot(path='/tmp/claude-0/profil_mobil.png')
    pg.close()
    b.close()

print('\nSELHALO: %d' % len(fails) if fails else '\nVŠE V POŘÁDKU')
sys.exit(1 if fails else 0)
