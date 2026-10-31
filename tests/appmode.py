"""Režim nainstalované aplikace (?app=1): bez webu a ceníku, jen přihlášení."""
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
bad=[]
def chk(c,m):
    print(('OK   ' if c else 'FAIL ')+m)
    if not c: bad.append(m)
with sync_playwright() as p:
    b=p.chromium.launch()
    html=open(R+'/index.html').read().replace('function showAuth(mode){','window.__sa=function(m){showAuth(m)};function showAuth(mode){',1)
    open('/tmp/am_index.html','w').write(html)
    for vw,tag in (({'width':390,'height':844},'m'),({'width':1360,'height':900},'d')):
        pg=b.new_page(viewport=vw);errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        pg.goto('file:///tmp/am_index.html?app=1');pg.wait_for_timeout(900)
        chk(pg.evaluate("document.documentElement.classList.contains('appmode')"),f'{tag} režim aplikace zapnut')
        chk(not pg.is_visible('main#obsah') and not pg.is_visible('footer') and not pg.is_visible('header.nav'),f'{tag} web (úvod, ceník, patička) je skrytý')
        chk(pg.is_visible('#appSplash') and 'Přihlásit' in pg.inner_text('#appSplash'),f'{tag} je vidět obrazovka s přihlášením')
        pg.evaluate("__sa('signup')");pg.wait_for_selector('#authForm')
        chk(pg.locator('[data-auth=signup]').count()==0 and pg.locator('#aPlan').count()==0,f'{tag} žádná registrace ani výběr tarifu')
        chk(pg.locator('#aPass').count()+pg.locator('input[type=password]').count()>0,f'{tag} je tam heslo (přihlášení)')
        chk(not errs,f'{tag} bez chyb {errs}');pg.close()
    pg=b.new_page();pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(600)
    chk(pg.is_visible('main#obsah') and not pg.evaluate("document.documentElement.classList.contains('appmode')"),'běžný web zůstává beze změny')
    pg.close();b.close()
print('HOTOVO' if not bad else 'CHYBY');raise SystemExit(1 if bad else 0)
