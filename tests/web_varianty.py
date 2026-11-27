from playwright.sync_api import sync_playwright
import sys
R='/home/claude/vexaronet'
ok=[];bad=[]
def chk(n,c):
    (ok if c else bad).append(n);print(('OK  ' if c else 'FAIL'),n)
with sync_playwright() as p:
    b=p.chromium.launch()
    for vw,nm in ((1360,'desktop'),(390,'mobil')):
        pg=b.new_page(viewport={'width':vw,'height':900});errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(1500)
        h=pg.inner_text('#h1').replace('\xa0',' ')
        chk(nm+' nadpis s odpočtem','zdarma' in h)
        chk(nm+' bez lišty limitu firem',pg.locator('#regBar').count()==0)
        chk(nm+' dvě volby zdarma v úvodu',pg.locator('.vpick .vp').count()==2 and '350' not in pg.inner_text('.vpick'))
        chk(nm+' bez vodorovného posunu',pg.evaluate('document.documentElement.scrollWidth')<=vw+1)
        chk(nm+' dvě karty variant',pg.locator('.variants .vcard').count()==2)
        t=pg.inner_text('.variants')
        chk(nm+' zdarma ke stažení a online bez vymyšlené ceny','0 €' in t and '350' not in t and 'cena zatím neurčena' in t and 'Kč' not in t)
        hr=pg.eval_on_selector_all('a[download]','e=>e.map(x=>x.getAttribute("href"))')
        chk(nm+' odkazy ke stažení',all(x.startswith('/stazeni/') for x in hr) and len(hr)>=3)
        for k,txt in (('online','online'),('start','startu')):
            pg.evaluate("k=>document.querySelector('[data-namiru='+k+']').click()",k);pg.wait_for_timeout(800)
            chk(nm+' formulář předvyplněn: '+k,txt in (pg.input_value('#fPlan')+pg.input_value('#fMsg')).lower())
            pg.evaluate("document.getElementById('fPlan').value='';document.getElementById('fMsg').value=''")
        chk(nm+' bez JS chyb',not errs);print(errs)
    b.close()
print(len(ok),'OK',len(bad),'FAIL');sys.exit(1 if bad else 0)
