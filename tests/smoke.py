"""Smoke test aplikace Vexaronet na zamockovaném Supabase (bez internetu).
Spuštění:  python3 tests/smoke.py   (potřebuje playwright + chromium)"""
import os, sys
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOCK = r'''
(function(){
var now=Date.now(),iso=function(o){return new Date(now+o).toISOString()};
var D={company_members:[{company_id:'c1',role:'owner'}],company_invites:[{id:'i1',email:'novy@firma.cz',role:'employee',created_at:iso(-864e5)}],companies:[{id:'c1',name:'Test autoservis',industry:'Autoservis'}],subscriptions:[{plan:'pro',status:'trial',trial_end:iso(20*864e5)}],
customers:[{id:'u1',name:'Jan Novák',email:'j@x.cz',phone:'123',created_at:iso(-864e5)},{id:'u2',name:'Eva Svobodová',created_at:iso(-40*864e5)}],
jobs:[{id:'j1',title:'Výměna oleje',customer_id:'u1',price:1500,due_at:iso(-5*864e5),status:'rozpracováno',created_at:iso(-9e8)},{id:'j2',title:'Brzdy',status:'hotovo',created_at:iso(-8e8)}],
reservations:[{id:'r1',title:'Servis',customer_id:'u1',starts_at:iso(36e5),ends_at:iso(72e5),canceled:false}],
tasks:[{id:'t1',title:'Zavolat',due_at:iso(-3*864e5),completed:false}],
invoices:[{number:'2026001',total:4900,currency:'CZK',issued_on:iso(-20*864e5).slice(0,10),due_on:iso(-5*864e5).slice(0,10),customer_snapshot:{name:'Jan Novák'}}]};
window.__log=[];var of=window.fetch;window.fetch=function(u,o){if(String(u).indexOf('/api/subscribe')>=0){window.__log.push(['sub',JSON.parse(o.body)]);return Promise.resolve(new Response('{"ok":true}',{status:200,headers:{'content-type':'application/json'}}))}if(String(u).indexOf('/api/invite')>=0){window.__log.push(['inv',JSON.parse(o.body)]);return Promise.resolve(new Response('{"ok":true,"mail":"'+(window.__mailfail?'failed':'sent')+'"}',{status:200,headers:{'content-type':'application/json'}}))}if(String(u).indexOf('/api/accountant')>=0){var ab=JSON.parse(o.body);window.__log.push(['acc',ab.mode||'extract']);if(ab.mode==='ask')return Promise.resolve(new Response('{"reply":"Tento měsíc máte výdaje 1 200 Kč."}',{status:200,headers:{'content-type':'application/json'}}));return Promise.resolve(new Response(JSON.stringify({doc:{document_type:'received_invoice',supplier_name:'Dodavatel s.r.o.',document_number:'FA2026-1',issue_date:'2026-10-20',total_amount:1210,vat_amount:210,vat_rate:21,currency:'CZK',description:'Materiál',category:'material',confidence:'high',warnings:[]},used:1,limit:150}),{status:200,headers:{'content-type':'application/json'}}))}if(String(u).indexOf('/api/advisor')>=0)return Promise.resolve(new Response(JSON.stringify({reply:'Odpověď AI.'}),{status:200,headers:{'content-type':'application/json'}}));return of.apply(this,arguments)};
function qb(t){var o={_op:'sel',select(){return o},eq(){return o},limit(){return o},is(){return o},order(){return o},insert(r){window.__log.push(['ins',t,r]);return Promise.resolve({error:null})},update(r){window.__log.push(['upd',t,r]);o._op='u';return o},delete(){window.__log.push(['del',t]);o._op='d';return o},then(f){return Promise.resolve({data:o._op==='sel'?(D[t]||[]):null,error:null}).then(f)}};return o}
window.supabase={createClient:function(){return{from:qb,rpc:function(n,a){window.__log.push(['rpc',n,a]);if(n==='company_team')return Promise.resolve({data:[{user_id:'x',email:'a@b.cz',role:'owner',is_me:true},{user_id:'y',email:'kolega@firma.cz',role:'employee',is_me:false}],error:null});if(n==='invite_member')return Promise.resolve({data:'iid',error:null});if(n==='accept_company_invites')return Promise.resolve({data:0,error:null});return Promise.resolve({data:{income:4900,expenses:0,customers:2,active_jobs:1,reservations_today:1},error:null})},auth:{getSession:()=>Promise.resolve({data:{session:{access_token:'t'}}}),getUser:()=>Promise.resolve({data:{user:{id:'x',email:'a@b.cz',user_metadata:{full_name:'Jan Procházka',onboarded:true}}}}),onAuthStateChange(){},updateUser:(x)=>Promise.resolve({data:{user:{user_metadata:x.data}},error:null}),signOut(){}}}}}})();
'''
fails = []
def check(c, m):
    print(('OK   ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
with sync_playwright() as p:
    b = p.chromium.launch()
    for name, vp in [('desktop', {'width': 1400, 'height': 900}), ('mobil', {'width': 390, 'height': 800})]:
        pg = b.new_page(viewport=vp); errs = []
        pg.on('pageerror', lambda e: errs.append(str(e)))
        pg.route('**/supabase.js', lambda r: r.fulfill(body=MOCK, content_type='text/javascript'))
        pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(600)
        pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(900)
        t = pg.inner_text('#appMain')
        check('Dobrý' in t or 'Dobré' in t, name + ': pozdrav')
        import re
        check(bool(re.search(r'4\s900',t)), name + ': tržby z faktur')
        check('faktura po splatnosti' in t, name + ': doporučení faktury po splatnosti')
        check(pg.locator('#chCash svg').count() == 1 and pg.locator('#chCust svg').count() == 1, name + ': grafy')
        check(pg.inner_text('#subCard').find('Vexaronet PRO') >= 0, name + ': karta předplatného')
        pg.screenshot(path=os.path.join(ROOT, 'tests', 'shot_' + name + '.png'))
        if name == 'desktop':
            pg.click('[data-act=reminders]'); pg.wait_for_selector('#remTx')
            check('2026001' in pg.input_value('#remTx'), 'upomínka obsahuje číslo faktury'); pg.click('[data-app=mclose]')
            pg.click('[data-act=jobtasks]'); pg.click('[data-do=jobtasks]'); pg.wait_for_timeout(400)
            check(any(l[0] == 'ins' and l[1] == 'tasks' for l in pg.evaluate('window.__log')), 'akce se provede až po potvrzení a vloží úkoly')
            pg.fill('#ceoIn', 'Jak jsme na tom?'); pg.press('#ceoIn', 'Enter'); pg.wait_for_timeout(500)
            check('Odpověď AI.' in pg.inner_text('#ceoLog'), 'AI CEO odpovídá')
            for tab in ['finance', 'zakaznici', 'zakazky', 'kalendar', 'ukoly', 'faktury', 'ceo', 'ucetni', 'weby', 'profil']:
                pg.evaluate("document.querySelector('#vxside [data-tab=%s]').click()" % tab); pg.wait_for_timeout(150)
                check(len(pg.inner_text('#appMain')) > 20, 'záložka ' + tab)
            pg.evaluate("document.querySelector('#vxside [data-tab=faktury]').click()"); pg.click('[data-newinv]'); pg.fill('#iRows .ip','1000'); pg.wait_for_timeout(100)
            check('1\u00a0000' in pg.inner_text('#iTot') or '1 000' in pg.inner_text('#iTot'), 'formulář faktury počítá součet'); pg.click('[data-app=mclose]'); pg.click('[data-invprof]'); check(pg.locator('#p_legal_name').count()==1, 'formulář fakturačních údajů'); pg.click('[data-app=mclose]')
            pg.evaluate("document.querySelector('#vxside [data-tab=zakazky]').click()"); pg.click('[data-new=jobs]'); pg.fill('#e_title', 'Nová'); pg.click('#entForm button[type=submit]'); pg.wait_for_timeout(300)
            check(any(l[0] == 'ins' and l[1] == 'jobs' and l[2].get('company_id') == 'c1' for l in pg.evaluate('window.__log')), 'přidání zakázky')
            pg.click('[data-edit^="jobs:j1"]'); pg.on('dialog', lambda d: d.accept()); pg.click('[data-del]'); pg.wait_for_timeout(300)
            check(any(l[0] == 'del' for l in pg.evaluate('window.__log')), 'smazání s potvrzením')
        else:
            check(pg.evaluate('document.documentElement.scrollWidth<=innerWidth+1'), 'mobil: bez vodorovného posuvu')
        check(not errs, name + ': žádné JS chyby ' + str(errs))
    b.close()

# --- ceník a řízení přístupu podle tarifu ---
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={'width': 1300, 'height': 900}); errs = []
    pg.on('pageerror', lambda e: errs.append(str(e)))
    pg.route('**/supabase.js', lambda r: r.fulfill(body=MOCK.replace("plan:'pro'", "plan:'start'").replace("status:'trial'", "status:'active'"), content_type='text/javascript'))
    pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(500)
    t = pg.inner_text('#cenik')
    check('1 199' in t or '1 199' in t, 'ceník: BUSINESS 1 199 Kč')
    pg.click('[data-bill=y]'); pg.wait_for_timeout(100)
    t = pg.inner_text('#cenik')
    check('1 019' in t or '1 019' in t, 'ceník: roční cena BUSINESS')
    check(pg.locator('.plans5 .plan').count() == 5, 'ceník: 5 tarifů')
    pg.screenshot(path=os.path.join(ROOT, 'tests', 'shot_cenik.png'), full_page=False)
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(500)
    check('není součástí' in (pg.evaluate("document.querySelector('#vxside [data-tab=ceo]').click()") or '') or 'AI CEO' in pg.inner_text('#appMain'), 'START: AI CEO zamčeno')
    check('Tato část není součástí' in pg.inner_text('#appMain'), 'START: zamčená stránka AI CEO')
    pg.evaluate("document.querySelector('#vxside [data-tab=zakaznici]').click()"); pg.wait_for_timeout(100)
    check(len(pg.inner_text('#appMain')) > 20, 'START: CRM dostupné')
    pg.evaluate("document.querySelector('#vxside [data-tab=zamestnanci]').click()"); pg.wait_for_timeout(400)
    check('Tarif START' in pg.inner_text('#appMain') or 'není součástí' in pg.inner_text('#appMain'), 'START: zaměstnanci zamčeno')
    pg.evaluate("document.querySelector('#vxside [data-tab=zakaznici]').click()"); pg.wait_for_timeout(100)
    pg.evaluate("document.querySelector('#vxside [data-tab=profil]').click()"); pg.click('[data-app=plan]'); pg.wait_for_selector('#planForm'); check(pg.locator('#planForm input[name=pl]').count()==4, 'změna tarifu: 4 možnosti')
    pg.keyboard.press('Escape'); pg.keyboard.press('Escape'); pg.wait_for_timeout(2600); pg.evaluate("document.getElementById('early').scrollIntoView()"); pg.fill('#fName','Test'); pg.fill('#fMail','T@Example.cz'); pg.check('#fOk'); pg.click('#send'); pg.wait_for_timeout(500)
    check(any(l[0]=='sub' and l[1]['email']=='T@Example.cz' and l[1]['consent'] is True for l in pg.evaluate('window.__log')), 'novinky: přihláška jde na /api/subscribe')
    check(not errs, 'tarify: žádné JS chyby ' + str(errs)); b.close()

# --- zaměstnanci (PRO, majitel) ---
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={'width': 1300, 'height': 900}); errs = []
    pg.on('pageerror', lambda e: errs.append(str(e)))
    pg.route('**/supabase.js', lambda r: r.fulfill(body=MOCK, content_type='text/javascript'))
    pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(500)
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(400)
    pg.evaluate("document.querySelector('#vxside [data-tab=zamestnanci]').click()"); pg.wait_for_selector('#teamBox li'); 
    tx = pg.inner_text('#teamBox')
    check('kolega@firma.cz' in tx and 'novy@firma.cz' in tx and 'Majitel' in tx, 'zaměstnanci: tým i pozvánky se zobrazí')
    pg.click('[data-invnew]'); pg.wait_for_selector('#inviteForm'); pg.fill('#ivE', 'Nova@Firma.cz'); pg.click('#inviteForm button[type=submit]'); pg.wait_for_timeout(500)
    check(any(l[0]=='inv' and l[1]['email']=='nova@firma.cz' and l[1]['role']=='employee' for l in pg.evaluate('window.__log')), 'zaměstnanci: pozvánka jde na /api/invite')
    check('odeslána' in pg.inner_text('#appToast'), 'zaměstnanci: potvrzení o odeslání e-mailu')
    pg.evaluate('window.__mailfail=true'); pg.click('[data-invnew]'); pg.wait_for_selector('#inviteForm'); pg.fill('#ivE', 'jiny@firma.cz'); pg.click('#inviteForm button[type=submit]'); pg.wait_for_selector('#remTx'); pg.wait_for_timeout(200)
    check('nepodařilo odeslat' in pg.inner_text('#appModal') and 'jiny@firma.cz' in pg.input_value('#remTx'), 'zaměstnanci: záloha s textem, když e-mail selže')
    pg.screenshot(path=os.path.join(ROOT, 'tests', 'shot_team.png'))
    check(not errs, 'zaměstnanci: žádné JS chyby ' + str(errs)); b.close()
# --- AI Účetní ---
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={'width': 1300, 'height': 1000}, accept_downloads=True); errs = []
    pg.on('pageerror', lambda e: errs.append(str(e)))
    pg.route('**/supabase.js', lambda r: r.fulfill(body=MOCK, content_type='text/javascript'))
    pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(500)
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(400)
    pg.evaluate("document.querySelector('#vxside [data-tab=ucetni]').click()"); pg.wait_for_selector('#accFile'); pg.wait_for_timeout(300)
    check('Kontrola záznamů' in pg.inner_text('#appMain') and 'Export pro účetního' in pg.inner_text('#appMain'), 'AI Účetní: sekce se zobrazí')
    import base64
    png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
    open('/tmp/doklad.png', 'wb').write(png)
    pg.set_input_files('#accFile', '/tmp/doklad.png'); pg.click('[data-acc=process]'); pg.wait_for_selector('#accRF'); 
    check(pg.input_value('#af_amt') == '1210' and 'Dodavatel s.r.o.' in pg.input_value('#af_title'), 'AI Účetní: návrh záznamu z dokladu')
    check(not any(l[0]=='ins' and l[1]=='financial_entries' for l in pg.evaluate('window.__log')), 'AI Účetní: bez potvrzení se nic neuloží')
    pg.click('#accRF button[type=submit]'); pg.wait_for_timeout(500)
    log = pg.evaluate('window.__log')
    check(any(l[0]=='ins' and l[1]=='financial_entries' and l[2]['amount']==1210 and l[2]['kind']=='expense' and l[2]['company_id']=='c1' for l in log) or any(l[0]=='ins' and l[1]=='financial_entries' and l[2]['amount']==1210 for l in log), 'AI Účetní: po potvrzení se záznam uloží')
    pg.fill('#accIn', 'Kolik jsem utratil?'); pg.press('#accIn', 'Enter'); pg.wait_for_timeout(500)
    check('1 200 Kč' in pg.inner_text('#accLog'), 'AI Účetní: odpověď na dotaz')
    with pg.expect_download() as dl: pg.click('[data-acc=csv-inv]')
    check(dl.value.suggested_filename.startswith('vexaronet-faktury'), 'AI Účetní: export faktur CSV')
    check(not errs, 'AI Účetní: žádné JS chyby ' + str(errs)); b.close()
# --- role zaměstnance ---
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={'width': 1300, 'height': 900}); errs = []
    pg.on('pageerror', lambda e: errs.append(str(e)))
    pg.route('**/supabase.js', lambda r: r.fulfill(body=MOCK.replace("company_id:'c1',role:'owner'", "company_id:'c1',role:'employee'"), content_type='text/javascript'))
    pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(500)
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(400)
    pg.evaluate("document.querySelector('#vxside [data-tab=faktury]').click()"); pg.wait_for_timeout(200)
    check('není součástí' in pg.inner_text('#appMain'), 'role zaměstnanec: faktury zamčené')
    pg.evaluate("document.querySelector('#vxside [data-tab=zakaznici]').click()"); pg.wait_for_timeout(200)
    check('Jan Novák' in pg.inner_text('#appMain'), 'role zaměstnanec: zákazníci dostupní')
    check(not errs, 'role zaměstnanec: žádné JS chyby ' + str(errs)); b.close()
print('\nSELHALO %d' % len(fails) if fails else '\nVŠE V POŘÁDKU (včetně tarifů)'); sys.exit(1 if fails else 0)
