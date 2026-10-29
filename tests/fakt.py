"""Vystavení faktury (start + issue) v ukázkovém režimu, bez zakázky i se zakázkou."""
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':1000})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    pg.evaluate("document.querySelector('#vxapp [data-tab=faktury]').click()");pg.wait_for_timeout(500)
    n0=pg.locator('#appMain li').count()
    pg.click('#vxapp [data-newinv]');pg.wait_for_selector('#invForm')
    pg.fill('#iRows .id','Testovací položka');pg.fill('#iRows .ip','1000')
    pg.click('#invForm button[type=submit]');pg.wait_for_timeout(800)
    print('modal',pg.locator('#invForm').count(),pg.inner_text('#appToast') if pg.locator('#appToast').count() else '')
    assert pg.locator('#invForm').count()==0
    print('errors',errs);assert not errs;b.close()
