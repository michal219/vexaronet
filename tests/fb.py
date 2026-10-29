"""Tlačítko Něco nefunguje? v ukázkovém režimu."""
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':1000})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    open('/tmp/fb_index.html','w').write(open(R+'/index.html').read().replace('function appTab(t){','window.__A=APP;window.__D=function(){return DS&&DD};function appTab(t){',1))
    pg.goto('file:///tmp/fb_index.html');pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    pg.click('[data-app=fb]');pg.wait_for_selector('#fbForm')
    pg.fill('#fbM','Test: nejde mi odeslat fakturu');pg.click('#fbForm button[type=submit]');pg.wait_for_timeout(600)
    print('toast',pg.inner_text('#appToast'));assert 'Děkujeme' in pg.inner_text('#appToast')
    assert pg.locator('#fbForm').count()==0
    print('errors',errs);assert not errs;b.close()
