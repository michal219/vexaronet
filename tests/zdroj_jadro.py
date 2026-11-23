"""Edice zdrojového kódu: v menu jen jádro, žádné AI/e-shop/sklad, bez JS chyb při průchodu všemi záložkami."""
import os,shutil,subprocess,sys,tempfile
from playwright.sync_api import sync_playwright
SRC=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T=tempfile.mkdtemp(prefix='vx-src-')
shutil.copytree(SRC,T+'/r',ignore=shutil.ignore_patterns('.git','node_modules','__pycache__'))
open(T+'/r/config.local.json','w').write('{"edition":"source"}')
subprocess.run([sys.executable,T+'/r/build.py'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
OFF={'eshop','sklad','pobocky','weby','marketing','ceo','ucetni','aitym','autopilot','automatizace','online'}
CORE={'prehled','zakaznici','pripady','nabidky','zakazky','ukoly','faktury','finance','kalendar','reporty','zamestnanci','firmaprofil'}
bad=[]
def chk(n,c):
    print(('OK  ' if c else 'FAIL'),n)
    if not c:bad.append(n)
with sync_playwright() as p:
    b=p.chromium.launch()
    for vw,h,nm in((1360,900,'desktop'),(390,844,'mobil')):
        pg=b.new_page(viewport={'width':vw,'height':h});errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        pg.goto('file://'+T+'/r/index.html');pg.wait_for_timeout(500)
        pg.click('[data-demo]:visible >> nth=0');pg.wait_for_selector('#vxapp .kpi');pg.wait_for_timeout(700)
        tabs=set(pg.evaluate("[...document.querySelectorAll('#vxapp nav [data-tab], #vxapp aside [data-tab]')].map(b=>b.dataset.tab)"))
        chk(nm+' v menu nejsou vypnuté moduly',not (tabs&OFF))
        chk(nm+' v menu je jádro',CORE<=tabs|{'ucetni'} and {'zakaznici','zakazky','faktury','kalendar'}<=tabs)
        chk(nm+' bez AI CEO vyhledávání a doporučení',pg.evaluate("getComputedStyle(document.getElementById('gsForm')).display")=='none' and pg.locator('.recs').count()==0)
        for t in sorted(tabs-{'profil'}):
            pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()"%t);pg.wait_for_timeout(200)
            if 'nepodařilo' in pg.inner_text('#appMain'):chk(nm+' záložka '+t+' se zobrazí',False)
        chk(nm+' bez JS chyb',not errs)
    b.close()
shutil.rmtree(T,ignore_errors=True)
print('FAIL' if bad else 'vše OK');sys.exit(1 if bad else 0)
