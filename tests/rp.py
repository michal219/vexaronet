from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':1000},accept_downloads=True)
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    pg.evaluate("document.querySelector('#vxapp [data-tab=reporty]').click()");pg.wait_for_timeout(600)
    print('kpis',pg.locator('#vxapp .kpi').count(),'charts',pg.locator('#vxapp svg').count())
    for v in ['y','m1','all']:
        pg.select_option('#rpP',v);pg.wait_for_timeout(300);print(v,[t.replace('\n',' ') for t in pg.locator('#vxapp .kpi').all_inner_texts()][:2])
    with pg.expect_download() as d:pg.click('[data-rp=csv]')
    path=d.value.path();print(open(path,encoding='utf-8-sig').read()[:240].replace('\n',' | '))
    pg.click('[data-rp=ai]');pg.wait_for_timeout(1500);print('ai',pg.inner_text('#rpAi')[:70])
    pg.screenshot(path='/tmp/rp1.png',full_page=True);print(errs);b.close()
