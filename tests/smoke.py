"""Smoke test aplikace Vexaronet na zamockovaném Supabase (bez internetu).
Spuštění:  python3 tests/smoke.py   (potřebuje playwright + chromium)"""
import os, sys
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOCK = r'''
(function(){
var now=Date.now(),iso=function(o){return new Date(now+o).toISOString()};
var D={company_members:[{company_id:'c1',role:'owner'}],companies:[{id:'c1',name:'Test autoservis',industry:'Autoservis'}],subscriptions:[{plan:'pro',status:'trial',trial_end:iso(20*864e5)}],
customers:[{id:'u1',name:'Jan Novák',email:'j@x.cz',phone:'123',created_at:iso(-864e5)},{id:'u2',name:'Eva Svobodová',created_at:iso(-40*864e5)}],
jobs:[{id:'j1',title:'Výměna oleje',customer_id:'u1',price:1500,due_at:iso(-5*864e5),status:'rozpracováno',created_at:iso(-9e8)},{id:'j2',title:'Brzdy',status:'hotovo',created_at:iso(-8e8)}],
reservations:[{id:'r1',title:'Servis',customer_id:'u1',starts_at:iso(36e5),ends_at:iso(72e5),canceled:false}],
tasks:[{id:'t1',title:'Zavolat',due_at:iso(-3*864e5),completed:false}],
invoices:[{number:'2026001',total:4900,currency:'CZK',issued_on:iso(-20*864e5).slice(0,10),due_on:iso(-5*864e5).slice(0,10),customer_snapshot:{name:'Jan Novák'}}]};
window.__log=[];var of=window.fetch;window.fetch=function(u){if(String(u).indexOf('/api/advisor')>=0)return Promise.resolve(new Response(JSON.stringify({reply:'Odpověď AI.'}),{status:200,headers:{'content-type':'application/json'}}));return of.apply(this,arguments)};
function qb(t){var o={_op:'sel',select(){return o},eq(){return o},limit(){return o},insert(r){window.__log.push(['ins',t,r]);return Promise.resolve({error:null})},update(r){window.__log.push(['upd',t,r]);o._op='u';return o},delete(){window.__log.push(['del',t]);o._op='d';return o},then(f){return Promise.resolve({data:o._op==='sel'?(D[t]||[]):null,error:null}).then(f)}};return o}
window.supabase={createClient:function(){return{from:qb,rpc:function(){return Promise.resolve({data:{income:4900,expenses:0,customers:2,active_jobs:1,reservations_today:1},error:null})},auth:{getSession:()=>Promise.resolve({data:{session:{access_token:'t'}}}),getUser:()=>Promise.resolve({data:{user:{id:'x',email:'a@b.cz',user_metadata:{full_name:'Jan Procházka',onboarded:true}}}}),onAuthStateChange(){},updateUser:(x)=>Promise.resolve({data:{user:{user_metadata:x.data}},error:null}),signOut(){}}}}}})();
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
    pg.evaluate("document.querySelector('#vxside [data-tab=profil]').click()"); pg.click('[data-app=plan]'); pg.wait_for_selector('#planForm'); check(pg.locator('#planForm input[name=pl]').count()==4, 'změna tarifu: 4 možnosti')
    pg.keyboard.press('Escape'); pg.keyboard.press('Escape'); pg.wait_for_timeout(2600); pg.evaluate("document.getElementById('early').scrollIntoView()"); pg.fill('#fName','Test'); pg.fill('#fMail','T@Example.cz'); pg.check('#fOk'); pg.click('#send'); pg.wait_for_timeout(500)
    check(any(l[0]=='ins' and l[1]=='newsletter_subscribers' and l[2]['email']=='t@example.cz' for l in pg.evaluate('window.__log')), 'novinky: přihláška se uloží do Supabase')
    check(not errs, 'tarify: žádné JS chyby ' + str(errs)); b.close()
print('\nSELHALO %d' % len(fails) if fails else '\nVŠE V POŘÁDKU (včetně tarifů)'); sys.exit(1 if fails else 0)
