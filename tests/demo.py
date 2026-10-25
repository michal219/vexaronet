from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':1000})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi');
    T=lambda t:pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()"%t)
    T('kalendar');pg.wait_for_timeout(500)
    print('cells',pg.locator('.cd').count(),'chips',pg.locator('.cchip').count())
    pg.screenshot(path='/tmp/cal.png')
    pg.click('[data-calnav="1"]');pg.wait_for_timeout(200);pg.click('[data-calnav="0"]')
    pg.click('[data-calmode="l"]');pg.wait_for_timeout(200);print('list',pg.locator('.dh').count());pg.click('[data-calmode="m"]')
    # směna
    pg.click('[data-new="shifts"]');pg.wait_for_timeout(300)
    pg.fill('#e_person','Petr Mechanik');d=pg.evaluate("(function(){var d=new Date();d.setDate(d.getDate()+1);var s=new Date(d.getTime()-d.getTimezoneOffset()*6e4).toISOString().slice(0,10);return s})()")
    pg.fill('#e_starts_at',d+'T08:00');pg.fill('#e_ends_at',d+'T16:00');pg.click('#entForm button[type=submit]');pg.wait_for_timeout(500)
    print('shift chips',pg.locator('.cchip.cs').count())
    T('online');pg.wait_for_timeout(500);pg.screenshot(path='/tmp/online.png')
    pg.click('[data-bkopen]');pg.wait_for_selector('#vxbook .bkc');pg.click('[data-bks="s2"]')
    pg.click('[data-bkd]');pg.wait_for_selector('[data-bkt]');pg.screenshot(path='/tmp/book1.png')
    pg.click('[data-bkt]');pg.fill('#bk_n','Karel Test');pg.fill('#bk_e','karel@test.cz');pg.check('#bk_c');pg.click('.bkgo');pg.wait_for_timeout(600)
    pg.screenshot(path='/tmp/book2.png');print('done',pg.locator('.bkok').count())
    pg.click('[data-bk=close]');T('kalendar');pg.wait_for_timeout(300)
    pg.click('[data-calmode="l"]');print('online in cal',pg.evaluate("document.body.innerText.includes('Online:')"))
    T('zakaznici');pg.wait_for_timeout(300);print('cust',pg.evaluate("document.body.innerText.includes('Karel Test')"))
    # služba přidat
    T('online');pg.click('[data-new="booking_services"]');pg.fill('#e_name','Test služba');pg.fill('#e_duration_min','20');pg.click('#entForm button[type=submit]');pg.wait_for_timeout(400)
    print('svc',pg.evaluate("document.body.innerText.includes('Test služba')"))
    pg.click('#bookForm button[type=submit]');pg.wait_for_timeout(400);print('saved',pg.evaluate("document.body.innerText.includes('Uloženo')"))
    pg.set_viewport_size({'width':390,'height':800});T('kalendar');pg.wait_for_timeout(400);pg.screenshot(path='/tmp/calm.png')
    print(errs);b.close()
