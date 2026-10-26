from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':1000})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    T=lambda t:pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()"%t)
    T('automatizace');pg.wait_for_timeout(500)
    n=pg.locator('#vxapp button[data-au^=one]').count();print('navrhy',n)
    print(pg.inner_text('#vxapp .card2:nth-of-type(2)')[:400].replace('\n',' | '))
    pg.click('#vxapp button[data-au=one\\:0]');pg.wait_for_timeout(600)
    print('toast',pg.inner_text('#appToast'),'| zbývá',pg.locator('#vxapp button[data-au^=one]').count())
    pg.uncheck('#vxapp input[data-au="rule:overdue"]');pg.wait_for_timeout(600)
    print('po vypnuti overdue navrhy',pg.locator('#vxapp button[data-au^=one]').count(),'| vypnuto text',pg.inner_text('#vxapp').count('vypnuto'))
    pg.check('#vxapp input[data-au="rule:overdue"]');pg.wait_for_timeout(500)
    if pg.locator('[data-au=all]').count():
        pg.click('[data-au=all]');pg.wait_for_timeout(700);print('all toast',pg.inner_text('#appToast'))
    T('ukoly');pg.wait_for_timeout(300);print('auto tasks in ukoly',pg.evaluate("document.body.innerText.includes('Ozvat se')||document.body.innerText.includes('Upomenout')"))
    pg.screenshot(path='/tmp/au1.png',full_page=True);print(errs);b.close()
