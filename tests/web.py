from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':1000})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    pg.evaluate("document.querySelector('#vxapp [data-tab=weby]').click()");pg.wait_for_timeout(600)
    print('form',pg.locator('#webForm').count(),'frame',pg.locator('#webFr').count())
    pg.fill('#w_ai','Rodinný autoservis v Plzni, děláme servis, pneuservis a diagnostiku pro řidiče a malé firmy.')
    pg.click('[data-web=ai]');pg.wait_for_timeout(1800)
    print('ai st:',pg.inner_text('#webAiSt')[:90]);print('title:',pg.input_value('#w_ht'),'| svc1:',pg.input_value('#w_sn0'))
    pg.fill('#w_cp','602 111 222');pg.fill('#w_ce','info@servis.cz');pg.fill('#w_col','#e8590c') if False else None
    pg.wait_for_timeout(300)
    src=pg.eval_on_selector('#webFr','e=>e.srcdoc')
    print('srcdoc has title',('Servis' in src or 'servis' in src),'tel',('tel:602111222' in src),'svc',('Pneuservis' in src))
    pg.screenshot(path='/tmp/web1.png')
    pg.click('#webForm button[type=submit]');pg.wait_for_timeout(700)
    print('toast',pg.inner_text('#appToast'),'| link card',pg.locator('.bklink').count())
    pg.check('#w_on');pg.click('#webForm button[type=submit]');pg.wait_for_timeout(700);print('toast2',pg.inner_text('#appToast'))
    pg.click('[data-web=open]');pg.wait_for_selector('#vxsite iframe');pg.wait_for_timeout(300)
    fr=pg.frame_locator('#vxsite iframe');print('full page h1:',fr.locator('h1').inner_text())
    pg.screenshot(path='/tmp/web2.png')
    # xss
    pg.click('.vxsx');pg.fill('#w_ht','<img src=x onerror=alert(1)>');pg.wait_for_timeout(200)
    src=pg.eval_on_selector('#webFr','e=>e.srcdoc');print('escaped',('<img src=x' not in src))
    print(errs);b.close()
