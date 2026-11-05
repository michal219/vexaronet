from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
# Demo režim: čekací listina v části Online rezervace (přidání, napsání zájemci, změna stavu).
def run(w,h,tag):
    with sync_playwright() as p:
        b=p.chromium.launch();pg=b.new_page(viewport={'width':w,'height':h})
        errs=[];pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
        pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
        pg.evaluate("document.querySelector('#vxapp [data-tab=online]').click()");pg.wait_for_selector('#wlBox')
        box=lambda:pg.inner_text('#wlBox')
        assert 'Marie Svobodová' in box() and 'Výměna oleje' in box(),box()
        href=pg.get_attribute('#wlBox [data-wl^="mail:"]','href');print(tag,'mailto',href[:70]);assert href.startswith('mailto:marie@example.cz?subject=')
        # přidání bez kontaktu se odmítne, s kontaktem projde
        pg.click('[data-new="waitlist"]');pg.wait_for_selector('#entForm');pg.fill('#e_name','Karel Nový');pg.click('#entForm button[type=submit]');pg.wait_for_timeout(300)
        assert 'Vyplňte e-mail nebo telefon' in pg.inner_text('#entSt') or 'Vyplňte e-mail' in pg.inner_text('#appModal'),'bez kontaktu'
        pg.fill('#e_phone','777 123 456');pg.select_option('#e_service_id',label='Přezutí pneumatik');pg.fill('#e_wanted','sobota ráno');pg.click('#entForm button[type=submit]');pg.wait_for_timeout(500)
        pg.wait_for_selector('#wlBox');t=box();print(tag,'after add:',t.replace('\n',' | ')[:200]);assert 'Karel Nový' in t and 'Přezutí' in t and 'sobota ráno' in t
        # Napsat označí jako nabídnuto (mailto se v testu nepotvrdí, jen kliknutí)
        pg.evaluate("document.querySelector('#wlBox [data-wl^=\"mail:\"]').addEventListener('click',e=>e.preventDefault())")
        pg.click('#wlBox [data-wl^="mail:"]');pg.wait_for_function("/Nabídnuto/.test(document.querySelector('#wlBox').textContent)",timeout=4000)
        # Zarezervováno odebere ze seznamu
        n0=pg.locator('#wlBox li').count();pg.click('#wlBox [data-wl^="booked:"]');pg.wait_for_timeout(500);pg.wait_for_selector('#wlBox')
        assert pg.locator('#wlBox li').count()==n0-1,'vyřízený zmizel';assert 'Vyřízených záznamů: 1' in box()
        # smazání úpravou
        pg.click('#wlBox li');pg.wait_for_selector('#entForm');pg.click('#entForm [data-del]') if pg.locator('#entForm [data-del]').count() else None
        pg.screenshot(path='/tmp/waitlist_%s.png'%tag)
        print(tag,'errors',errs);assert not errs;b.close()
run(1360,1000,'d');run(390,800,'m')
