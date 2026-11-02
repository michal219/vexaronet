from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
def run(w,h,tag):
    with sync_playwright() as p:
        b=p.chromium.launch();pg=b.new_page(viewport={'width':w,'height':h})
        errs=[];pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
        pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
        T=lambda t:pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()"%t)
        T('pripady');pg.wait_for_selector('.kbn');print(tag,'cards',pg.locator('.kbd').count(),'kpi',pg.inner_text('.ivkpi').replace('\n',' ')[:120])
        assert pg.locator('.kbd').count()==4
        pg.click('[data-crm="mv:d3:1"]');pg.wait_for_timeout(300);print('moved: kontakt cards',pg.locator('.kbc').nth(1).locator('.kbd').count());assert pg.locator('.kbc').nth(1).locator('.kbd').count()==1
        pg.click('[data-new="deals"]');pg.wait_for_selector('#entForm');pg.fill('#e_title','Nový test');pg.fill('#e_value','5000');pg.select_option('#e_stage','new');pg.click('#entForm button[type=submit]');pg.wait_for_timeout(400)
        assert pg.locator('.kbd').count()==5
        pg.click('[data-crm="qd:d2"]');pg.wait_for_selector('#qeForm');pg.fill('#qeRows .ier .id','Test položka');pg.fill('#qeRows .ier .ip','1000');pg.wait_for_timeout(200)
        print('preview',pg.inner_text('.ivtot b'));pg.screenshot(path='/tmp/crm_q_%s.png'%tag);pg.click('#qeForm button[type=submit]');pg.wait_for_timeout(500)
        T('nabidky');pg.wait_for_selector('.ivl');n=pg.locator('.ivl li').count();print('quotes',n);assert n==2
        pg.click('[data-crm^="qv:"]');pg.wait_for_selector('.ivd');print('title',pg.inner_text('.ivd h2'),'qr',pg.locator('.ivd .qrb').count());assert pg.locator('.ivd .qrb').count()==0;pg.click('[data-app=mclose]')
        pg.click('[data-crm^="qi:"]');pg.wait_for_selector('#invEd');print('invoice prefilled',pg.input_value('#ieRows .ier .id'));pg.click('[data-app=mclose]')
        T('zakaznici');pg.click('#lst li');pg.wait_for_selector('#entForm');pg.click('[data-crm^="th:"]');pg.wait_for_selector('#cnForm')
        pg.fill('#cnB','Test poznámka');pg.click('#cnForm button[type=submit]');pg.wait_for_timeout(500);print('timeline',pg.locator('.mbox .tl li').count());assert 'Test poznámka' in pg.inner_text('.mbox')
        pg.screenshot(path='/tmp/crm_t_%s.png'%tag);pg.click('[data-app=mclose]');T('pripady');pg.screenshot(path='/tmp/crm_p_%s.png'%tag)
        print('errors',errs);assert not errs;b.close()
run(1360,1000,'d');run(390,800,'m')
