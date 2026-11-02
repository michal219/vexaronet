from playwright.sync_api import sync_playwright
import re,sys
R='/tmp/vexaronet-saas'
def run(w,h,tag):
    with sync_playwright() as p:
        b=p.chromium.launch();pg=b.new_page(viewport={'width':w,'height':h})
        errs=[];pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
        pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
        pg.evaluate("document.querySelector('#vxapp [data-tab=faktury]').click()");pg.wait_for_selector('.ivkpi')
        n0=pg.locator('.ivl li').count();print(tag,'rows',n0,'kpi',pg.locator('.ivkpi>div').count())
        assert n0==8
        pg.click('[data-ie="f:late"]');pg.wait_for_timeout(100);print('late filter',pg.locator('.ivl li').count())
        pg.click('[data-ie="f:all"]');pg.fill('#ivQ','Pekárna');pg.wait_for_timeout(200);print('search',pg.locator('.ivl li').count());assert pg.locator('.ivl li').count()==2
        pg.fill('#ivQ','');pg.wait_for_timeout(100)
        pg.click('[data-invview]');pg.wait_for_selector('.ivd');print('detail qr',pg.locator('.ivd .qrb svg').count(),'num',pg.inner_text('.ivd .ivn'))
        pg.screenshot(path='/tmp/fi_detail_%s.png'%tag);pg.click('[data-app=mclose]')
        pg.click('[data-newinv]');pg.wait_for_selector('#invEd')
        pg.fill('#ieN','Test Odběratel s.r.o.');pg.fill('#ieA','Ulice 1, 110 00 Praha')
        pg.fill('#ieRows .ier .id','Servisní práce');pg.fill('#ieRows .ier .ip','1210')
        pg.wait_for_timeout(200);t=pg.inner_text('.ivtot b');print('preview total',t);assert '1' in t and '210' in t
        pg.screenshot(path='/tmp/fi_edit_%s.png'%tag)
        pg.click('[data-save=draft]');pg.wait_for_timeout(500)
        print('after draft rows',pg.locator('.ivl li').count(),'drafts',pg.locator('.ivkpi>div').nth(3).inner_text().replace('\n',' '))
        assert pg.locator('.ivl li').count()==9
        pg.click('[data-ie="f:draft"]');pg.click('[data-ie^="edit:"]');pg.wait_for_selector('#invEd');pg.fill('#ieRows .ier .ip','2420');pg.click('[data-save=issue]');pg.wait_for_timeout(500)
        pg.click('[data-ie="f:all"]');txt=pg.inner_text('#appMain');print('issued',re.findall(r'20\d{6}',txt)[:3]);assert pg.locator('.ivl li').count()==9
        pg.click('.ivl li:first-child [data-invview]');pg.wait_for_selector('.ivd');q=pg.locator('.ivd .qrb svg').count();print('new inv qr',q,pg.inner_text('.ivtot b'));assert q==1
        pg.click('[data-app=mclose]')
        print('errors',errs);assert not errs
        b.close()
run(1360,1000,'d');run(390,800,'m')
