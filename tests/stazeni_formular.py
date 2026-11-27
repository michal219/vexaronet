from playwright.sync_api import sync_playwright
import sys,subprocess,time,os
R=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
srv=subprocess.Popen([sys.executable,'-m','http.server','8765','-d',R+'/public'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);time.sleep(1)
with sync_playwright() as p:
    b=p.chromium.launch();ok=[];bad=[]
    def chk(n,c):(ok if c else bad).append(n);print('OK  ' if c else 'FAIL',n)
    for vw,nm in((1360,'desktop'),(390,'mobil')):
        pg=b.new_page(viewport={'width':vw,'height':900});errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
        calls=[]
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        def sub(r):
            calls.append(r.request.post_data);r.fulfill(status=200,content_type='application/json',body='{"ok":true}')
        pg.route('**/api/subscribe',sub)
        pg.goto('http://localhost:8765/index.html');pg.wait_for_timeout(3000)
        chk(nm+' před zadáním nejsou odkazy ke stažení',pg.locator('a[download]:visible').count()==0 and pg.eval_on_selector_all('a[href*="stazeni"]','e=>e.length')==0)
        pg.evaluate("document.getElementById('dlForm').scrollIntoView()")
        pg.fill('#dlMail','test@example.invalid')
        pg.click('#dlGo');pg.wait_for_timeout(300);chk(nm+' bez licence nejde',pg.locator('#dlSt.err').count()==1 and not calls)
        pg.check('[name=lic]');pg.click('#dlGo');pg.wait_for_timeout(300);chk(nm+' bez souhlasu s novinkami nejde',not calls)
        pg.check('[name=souhlas]');pg.click('#dlGo');pg.wait_for_timeout(300);chk(nm+' bez věku nejde',not calls)
        pg.check('[name=vek]');pg.click('#dlGo');pg.wait_for_timeout(800)
        chk(nm+' odesláno na /api/subscribe se souhlasem',len(calls)==1 and '"consent":true' in calls[0] and 'test@example.invalid' in calls[0])
        hr=pg.eval_on_selector_all('#dlOk a[download]','e=>e.map(x=>x.getAttribute("href"))')
        chk(nm+' po zadání jsou 2 odkazy',sorted(hr)==['/stazeni/Vexaronet-lokalni.zip','/stazeni/Vexaronet-zdrojovy-kod.zip'])
        chk(nm+' bez vodorovného posunu',pg.evaluate('document.documentElement.scrollWidth')<=vw+1)
        if vw==1360: pg.locator('#cenik').screenshot(path='/tmp/dl_desk.png')
        chk(nm+' bez JS chyb',not errs);print(errs)
    b.close()
srv.terminate();print(len(ok),'OK',len(bad),'FAIL');sys.exit(1 if bad else 0)
