import os
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
# Demo režim: duplicity zákazníků a slučování (stejná logika jako SQL funkce v schema_crm_duplicity.sql).
# Test jedná jako uživatel: duplicitu, zakázku a poznámku založí přes formuláře.
def start(b,w,h,url):
    pg=b.new_page(viewport={'width':w,'height':h})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    pg.goto(url);pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    return pg,errs
def run(w,h,tag):
    with sync_playwright() as p:
        b=p.chromium.launch();pg,errs=start(b,w,h,'file://'+R+'/index.html')
        T=lambda t:pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()"%t)
        # 1) duplicita k "Novák Auto s.r.o." (u1: info@novakauto.cz, 602 111 222): jiná velikost písmen, mezera, předvolba
        T('zakaznici');pg.wait_for_selector('#lst')
        n0=pg.locator('#lst li').count();print(tag,'customers before',n0)
        pg.click('[data-new="customers"]');pg.wait_for_selector('#entForm')
        pg.fill('#e_name','Novak Auto');pg.fill('#e_email',' INFO@novakauto.cz');pg.fill('#e_phone','+420602111222');pg.fill('#e_ico','12345678');pg.fill('#e_notes','Platí včas')
        pg.click('#entForm button[type=submit]');pg.wait_for_timeout(500)
        T('zakazky');pg.click('[data-new="jobs"]');pg.wait_for_selector('#entForm');pg.fill('#e_title','Zakázka ze starého záznamu')
        pg.select_option('#e_customer_id',label='Novak Auto');pg.click('#entForm button[type=submit]');pg.wait_for_timeout(500)
        T('zakaznici');pg.wait_for_selector('#lst');assert pg.locator('#lst li').count()==n0+1
        pg.locator('#lst li',has_text='Novak Auto').click();pg.wait_for_selector('#entForm');pg.click('[data-crm^="th:"]');pg.wait_for_selector('#cnForm')
        pg.fill('#cnB','Staré volání');pg.click('#cnForm button[type=submit]');pg.wait_for_timeout(500);pg.click('[data-app=mclose]')
        # 2) hledání: jedna skupina (shoda e-mail + telefon + IČO), nesouvisející zákazníci nejsou uvedeni
        T('zakaznici');pg.wait_for_selector('#lst');pg.click('[data-crm="dup"]');pg.wait_for_selector('#cdBox section')
        print('groups',pg.locator('#cdBox section').count(),'|',pg.inner_text('#cdBox section h4'))
        assert pg.locator('#cdBox section').count()==1 and pg.locator('#cdBox section input[type=radio]').count()==2
        h4=pg.inner_text('#cdBox section h4');assert 'e-mail' in h4 and 'telefon' in h4
        assert 'Eva Horáková' not in pg.inner_text('#cdBox')
        pg.screenshot(path='/tmp/crm_dup_%s.png'%tag)
        # 3) první klik jen žádá potvrzení a nic nemění
        pg.check('#cdBox input[value=u1]');pg.click('[data-crm="mg:0"]');pg.wait_for_timeout(200)
        print('btn:',pg.inner_text('[data-crm="mg:0"]'));assert 'Potvrdit' in pg.inner_text('[data-crm="mg:0"]')
        pg.click('#appModal [data-app=mclose]');T('zakaznici');pg.wait_for_selector('#lst');assert pg.locator('#lst li').count()==n0+1,'bez potvrzení se nic nesloučilo'
        # 4) potvrzení: sloučí do u1
        pg.click('[data-crm="dup"]');pg.wait_for_selector('#cdBox section');pg.check('#cdBox input[value=u1]')
        pg.click('[data-crm="mg:0"]');pg.click('[data-crm="mg:0"]')
        pg.wait_for_function("document.querySelector('#cdSt') && /Žádné duplicity/.test(document.querySelector('#cdSt').textContent)",timeout=5000)
        print('after:',pg.inner_text('#cdSt')[:60])
        pg.click('#appModal [data-app=mclose]');T('zakaznici');pg.wait_for_selector('#lst')
        n1=pg.locator('#lst li').count();print('customers after',n1);assert n1==n0
        assert pg.locator('#lst li',has_text='Novak Auto').count()==0,'sloučený záznam zmizel ze seznamu'
        # 5) zachovaný záznam: dostal zakázku, poznámku a záznam o sloučení; vyplněné údaje se nepřepsaly, prázdné se doplnily
        pg.locator('#lst li',has_text='Novák Auto s.r.o.').click();pg.wait_for_selector('#entForm')
        assert pg.input_value('#e_email')=='info@novakauto.cz','zachovaný e-mail se nesmí přepsat'
        assert pg.input_value('#e_ico')=='12345678','prázdné IČO se doplnilo'
        assert 'Platí včas' in pg.input_value('#e_notes'),'poznámka se přidala'
        pg.click('[data-crm^="th:"]');pg.wait_for_selector('#cnForm');tl=pg.inner_text('.mbox .tl');print('timeline:',tl.replace('\n',' | ')[:300])
        assert 'Zakázka ze starého záznamu' in tl and 'Staré volání' in tl and 'Sloučeno se záznamem „Novak Auto“' in tl
        pg.click('[data-app=mclose]')
        print('errors',errs);assert not errs;b.close()
    # 6) databáze ještě nemá migraci: srozumitelná hláška místo rozbité stránky
    src=open(R+'/index.html',encoding='utf-8').read()
    assert src.count("if(n==='crm_find_duplicates'){")==1
    open(R+'/_missingdb.html','w',encoding='utf-8').write(src.replace("if(n==='crm_find_duplicates'){","if(n==='crm_find_duplicates'){return {data:null,error:{message:'Could not find the function public.crm_find_duplicates'}};"))
    try:
        with sync_playwright() as p:
            b=p.chromium.launch();pg,errs=start(b,w,h,'file://'+R+'/_missingdb.html')
            pg.evaluate("document.querySelector('#vxapp [data-tab=zakaznici]').click()");pg.wait_for_selector('#lst')
            pg.click('[data-crm="dup"]');pg.wait_for_selector('#cdSt .draft');t=pg.inner_text('#cdSt');print('missing db:',t[:150])
            assert 'schema_crm_duplicity.sql' in t and not errs;b.close()
    finally:
        os.remove(R+'/_missingdb.html')
run(1360,1000,'d');run(390,800,'m')
