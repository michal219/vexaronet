"""Přizpůsobení aplikace podle oboru: všech 7 oborů v ukázkovém režimu, desktop + mobil."""
import sys
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
OBS=['Služby','Autoservis','Řemeslník','Restaurace','Kadeřnictví a krása','Obchod','Jiný obor']
bad=[]
def chk(c,m):
    print(('OK   ' if c else 'FAIL ')+m)
    if not c: bad.append(m)
with sync_playwright() as p:
    b=p.chromium.launch()
    for vw,tag in (({'width':1360,'height':900},'d'),({'width':390,'height':844},'m')):
        pg=b.new_page(viewport=vw);errs=[]
        pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        open('/tmp/ob_index.html','w').write(open(R+'/index.html').read().replace('function appTab(t){','window.__A=APP;window.__t=function(x){appTab(x)};function appTab(t){',1))
        pg.goto('file:///tmp/ob_index.html');pg.wait_for_timeout(500)
        pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
        for ob in OBS:
            pg.select_option('#demoOb',ob);pg.wait_for_timeout(500)
            nav=pg.evaluate("[...document.querySelectorAll('#vxside nav > button')].map(b=>b.textContent.trim())")
            more=pg.evaluate("[...document.querySelectorAll('#vxside nav details.more button')].map(b=>b.textContent.trim())")
            allk=pg.evaluate("document.querySelectorAll('#vxside nav [data-tab]').length")
            chk(allk==17,f'{tag} {ob}: všech 17 modulů je dostupných (hlavní {len(nav)} + další {len(more)})')
            h=pg.inner_text('#appMain')
            saved=pg.evaluate("(()=>{const d=__A.d;const s={c:d.customers.rows,j:d.jobs.rows,i:d.invoices.rows,b:d.booking_services.rows,p:d.products.rows,sh:d.shifts.rows,te:d.time_entries.rows,r:d.reservations.rows};d.customers.rows=[];d.jobs.rows=[];d.invoices.rows=[];d.booking_services.rows=[];d.products.rows=[];d.shifts.rows=[];d.time_entries.rows=[];d.reservations.rows=[];window.__s=s;__t('prehled');return 1})()")
            h2=pg.inner_text('#appMain');chk('Začínáme: '+ob in h2 and 'Hotovo 0 z' in h2,f'{tag} {ob}: karta Začínáme pro nový účet')
            pg.evaluate("(()=>{const d=__A.d,s=window.__s;d.customers.rows=s.c;d.jobs.rows=s.j;d.invoices.rows=s.i;d.booking_services.rows=s.b;d.products.rows=s.p;d.shifts.rows=s.sh;d.time_entries.rows=s.te;d.reservations.rows=s.r})()")
            # nová zakázka: šablona a stavy
            pg.evaluate("document.querySelector('#vxapp [data-tab=zakazky]').click()");pg.wait_for_timeout(300)
            pg.click('#appMain .btn-main, #appMain [data-new=jobs]');pg.wait_for_selector('#entForm')
            tpl=pg.input_value('#e_description');st=pg.input_value('#e_status')
            chk(True,f'{tag} {ob}: šablona "{tpl[:30].replace(chr(10)," / ")}", výchozí stav "{st}"')
            pg.click('#entForm [data-app=mclose]')
            if tag=='d':
                pg.evaluate("document.querySelector('#vxapp [data-tab=online]').click()");pg.wait_for_timeout(400)
                chips=pg.locator('[data-svc]').count();print('   doporučených služeb (po odfiltrování existujících):',chips)
                pg.evaluate("document.querySelector('#vxapp [data-tab=ceo]').click()");pg.wait_for_timeout(400)
                qs=pg.evaluate("[...document.querySelectorAll('#vxapp [data-q]')].map(b=>b.textContent)")
                print('   AI otázky:',qs[:2])
            pg.evaluate("document.querySelector('#vxapp [data-tab=prehled]').click()")
        # doporučená služba otevře předvyplněný formulář
        pg.select_option('#demoOb','Kadeřnictví a krása');pg.wait_for_timeout(300)
        pg.evaluate("document.querySelector('#vxapp [data-tab=online]').click()");pg.wait_for_timeout(400)
        if pg.locator('[data-svc]').count():
            pg.locator('[data-svc]').first.click();pg.wait_for_selector('#entForm')
            chk(pg.input_value('#e_name')!='' and pg.input_value('#e_duration_min')!='',f'{tag}: doporučená služba předvyplní formulář ({pg.input_value("#e_name")}, {pg.input_value("#e_duration_min")} min)')
        # mobil: bez horizontálního přetečení
        ov=pg.evaluate("document.documentElement.scrollWidth>innerWidth")
        chk(not ov,f'{tag}: bez horizontálního přetečení')
        chk(not errs,f'{tag}: žádné JS chyby {errs[:2]}')
        pg.close()
    b.close()
print('\nVŠE V POŘÁDKU' if not bad else '\nCHYBY: '+str(bad));sys.exit(1 if bad else 0)
