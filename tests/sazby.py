"""Hodinová sazba a výdělek za měsíc v ukázkovém režimu."""
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':1000})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    open('/tmp/sz_index.html','w').write(open(R+'/index.html').read().replace('function appTab(t){','window.__A=APP;window.__t=function(x){appTab(x)};function appTab(t){',1))
    pg.goto('file:///tmp/sz_index.html');pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    pg.evaluate("document.querySelector('#vxapp [data-tab=zamestnanci]').click()");pg.wait_for_selector('#attBox li');pg.wait_for_timeout(700)
    t=pg.inner_text('#attBox').replace('\n',' | ');print(t[:700])
    assert 'výdělek tento měsíc' in t and 'Hodinové sazby' in t
    inp=pg.locator('[data-rate=u-demo2]');assert inp.input_value()=='300'
    inp.fill('400');inp.dispatch_event('change');pg.wait_for_timeout(500)
    t2=pg.inner_text('#attBox');assert pg.locator('[data-rate=u-demo2]').input_value()=='400';print('after',t2.replace('\n',' | ')[:500])
    pg.screenshot(path='/tmp/sz.png',full_page=True)
    pg.evaluate("__A.role='employee';__A.user.email='mechanik@autoservis-novotny.cz';__A.user.id='u-demo2';__A.team=null;__t('zamestnanci')");pg.wait_for_timeout(700)
    e=pg.inner_text('#attBox');print('EMP',e.replace('\n',' | ')[:300]);assert 'Hodinové sazby' not in e and 'výdělek' in e
    print('errors',errs);assert not errs;b.close()
