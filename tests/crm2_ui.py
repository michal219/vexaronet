from playwright.sync_api import sync_playwright
import subprocess,sys
R='/tmp/vexaronet-saas'
import shutil,os
shutil.rmtree(R,ignore_errors=True);shutil.copytree('/home/claude/vexaronet',R,ignore=shutil.ignore_patterns('.git','node_modules'))
subprocess.run(['python3','build.py'],cwd=R,check=True,capture_output=True)
ok=[];bad=[]
def chk(n,c):
    (ok if c else bad).append(n);print(('OK  ' if c else 'FAIL'),n)
with sync_playwright() as p:
    b=p.chromium.launch()
    for vw,nm in ((1360,'desktop'),(390,'mobil')):
        pg=b.new_page(viewport={'width':vw,'height':900});errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
        pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
        T=lambda t:pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()"%t)
        T('zakaznici');pg.wait_for_selector('#lst');
        chk(nm+' KPI + k vyřízení',pg.locator('.c2due').count()==1 and pg.locator('.ivkpi').count()>=1)
        chk(nm+' stav a štítky',pg.locator('.c2b.lead').count()>=1 and pg.locator('.c2chip.tag').count()>=1)
        pg.click('.c2chip[data-c2="f:st:lead"]');pg.wait_for_timeout(200)
        chk(nm+' filtr potenciální',pg.locator('#lst li').count()==1)
        pg.click('.c2chip[data-c2="f:st:"]');pg.wait_for_timeout(200)
        pg.click('#lst li >> nth=0');pg.wait_for_selector('.c2card')
        chk(nm+' karta klienta',pg.locator('.c2card .ivkpi').count()==1)
        pg.fill('#c2B','Volal ohledně nabídky');pg.select_option('#c2N','7');pg.click('#c2Note button[type=submit]');pg.wait_for_selector('.c2card');pg.wait_for_timeout(300)
        chk(nm+' zápis kontaktu v historii','Volal ohledně nabídky' in pg.inner_text('.c2card'))
        pg.fill('#c2TT','Poslat kalkulaci');pg.click('#c2Task button[type=submit]');pg.wait_for_timeout(500)
        chk(nm+' úkol u klienta','Poslat kalkulaci' in pg.inner_text('.c2card'))
        pg.click('.c2card [data-c2^="tdone"]');pg.wait_for_timeout(500)
        chk(nm+' splnění úkolu','Poslat kalkulaci' in pg.inner_text('.c2card'))
        pg.click('.c2card [data-c2^="edit"]');pg.wait_for_selector('#entForm')
        chk(nm+' formulář má stát, stav, štítky',all(pg.locator('#e_'+k).count() for k in ('country_code','status','tags','next_contact_on','dic')))
        pg.select_option('#e_country_code','DE');pg.fill('#e_dic','de 123 456 789');pg.click('#entForm button[type=submit]');pg.wait_for_timeout(500)
        chk(nm+' DE IČ DPH přijato',pg.locator('#entForm').count()==0)
        pg.click('#lst li >> nth=0');pg.wait_for_selector('.c2card');pg.click('.c2card [data-c2^="edit"]');pg.wait_for_selector('#entForm')
        pg.select_option('#e_country_code','DE');pg.fill('#e_dic','DE12');pg.click('#entForm button[type=submit]');pg.wait_for_timeout(300)
        chk(nm+' špatné IČ DPH odmítnuto','#entForm' and pg.locator('#entForm .st.err').count()==1)
        pg.click('#entForm [data-app=mclose]')
        pg.click('[data-c2=dups]');pg.wait_for_selector('#appModal h3');chk(nm+' okno duplicit',pg.locator('#appModal').count()==1);pg.click('#appModal [data-app=mclose]')
        T('pripady');pg.wait_for_timeout(300)
        chk(nm+' přehled úspěšnosti','Úspěšnost za 90 dní' in pg.inner_text('#vxapp'))
        pg.screenshot(path='/tmp/crm2_%s.png'%nm)
        chk(nm+' bez JS chyb',not errs);print(errs)
    b.close()
print(len(ok),'OK',len(bad),'FAIL');sys.exit(1 if bad else 0)
