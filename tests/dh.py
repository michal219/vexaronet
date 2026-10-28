"""Docházka (online/offline, hodiny) v ukázkovém režimu bez internetu."""
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':1000})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    open('/tmp/dh_index.html','w').write(open(R+'/index.html').read().replace('function appTab(t){','window.__A=APP;window.__t=function(x){appTab(x)};function appTab(t){',1))
    pg.goto('file:///tmp/dh_index.html');pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    pg.evaluate("document.querySelector('#vxapp [data-tab=zamestnanci]').click()");pg.wait_for_selector('#attBox li');pg.wait_for_timeout(600)
    txt=pg.inner_text('#appMain').replace('\n',' | ');print('MG',txt[:900])
    assert 'Online teď' in txt and 'tento měsíc' in txt and 'celkem' in txt
    pg.click('[data-clock=in]');pg.wait_for_timeout(500);print('toast',pg.inner_text('#appToast'));
    assert 'online' in pg.inner_text('#clockCard')
    pg.screenshot(path='/tmp/dh1.png',full_page=True)
    pg.click('[data-clock=force]');pg.wait_for_timeout(500);print('force',pg.inner_text('#attBox').replace('\n',' | ')[:300])
    pg.click('[data-clock=out]');pg.wait_for_timeout(500);assert 'offline' in pg.inner_text('#clockCard');print('out ok')
    # zaměstnanec
    pg.evaluate("__A.role='employee';__A.user.email='mechanik@autoservis-novotny.cz';__A.user.id='u-demo2';__A.team=null;__t('prehled')");pg.wait_for_timeout(500)
    print('EMP dash clock',pg.locator('#clockCard').count(),pg.inner_text('#clockCard').replace('\n',' | ')[:250])
    pg.click('[data-clock=in]');pg.wait_for_timeout(500);print('EMP',pg.inner_text('#clockCard').replace('\n',' | ')[:250])
    pg.evaluate("__t('zamestnanci')");pg.wait_for_timeout(700);emp=pg.inner_text('#appMain').replace('\n',' | ');print('EMP tab',emp[:500])
    assert 'Pozvat' not in emp and 'Moje odpracované hodiny' in emp
    for t in('zakaznici','zakazky'):
        pg.evaluate(f"__t('{t}')");pg.wait_for_timeout(300);assert pg.locator(f'[data-new={"customers" if t=="zakaznici" else "jobs"}]').count()==1,t
    print('EMP může přidávat zákazníky a zakázky');pg.screenshot(path='/tmp/dh2.png',full_page=True)
    print('errors',errs);b.close()
