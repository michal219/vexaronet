from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':1000})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    pg.evaluate("document.querySelector('#vxapp [data-tab=marketing]').click()");pg.wait_for_timeout(500)
    print('card',pg.locator('#mk_topic').count())
    pg.fill('#mk_topic','Přezutí zimních pneumatik, objednat se dá online.');pg.select_option('#mk_kind','email')
    pg.click('[data-mk=gen]');pg.wait_for_timeout(1500)
    print('st:',pg.inner_text('#mkSt')[:80]);print('out:',pg.input_value('#mk_out')[:60].replace('\n',' | '))
    pg.click('[data-mk=save]');pg.wait_for_timeout(700)
    print('toast',pg.inner_text('#appToast'),'| rows',pg.locator('#vxapp ul.rows li').count())
    pg.click('#vxapp ul.rows li');pg.wait_for_timeout(300);print('edit modal',pg.locator('#e_title').input_value()[:40])
    pg.screenshot(path='/tmp/mk1.png');print(errs);b.close()
