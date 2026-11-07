"""UI test AI Autopilota v ukázkovém režimu (počítač i mobil)."""
import sys
from playwright.sync_api import sync_playwright
R = '/tmp/vexaronet-saas'
res = []
def ok(n, c): res.append((n, bool(c))); print(('OK   ' if c else 'FAIL ') + n)
with sync_playwright() as p:
    b = p.chromium.launch()
    for name, vp in [('desktop', {'width': 1360, 'height': 1000}), ('mobil', {'width': 390, 'height': 844})]:
        pg = b.new_page(viewport=vp); errs = []
        pg.on('pageerror', lambda e: errs.append(str(e)))
        pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript'))
        pg.goto('file://' + R + '/index.html'); pg.wait_for_timeout(400)
        pg.click('.cta [data-demo]'); pg.wait_for_selector('#vxapp .kpi')
        ok(f'{name}: v menu je AI Autopilot', pg.locator('#vxapp [data-tab=autopilot]').count() >= 1)
        pg.evaluate("document.querySelector('#vxapp [data-tab=autopilot]').click()"); pg.wait_for_timeout(600)
        ok(f'{name}: 6 modulů v přepínači', pg.locator('#vxapp .apmods button').count() == 6)
        ok(f'{name}: stav AI zaměstnance', 'AI marketingový zaměstnanec' in pg.inner_text('#apBody'))
        ok(f'{name}: tlačítko okamžitého pozastavení', pg.locator('[data-ap="pause:1"]').count() == 1)
        ok(f'{name}: chat a příklady příkazů', pg.locator('#apChatIn').count() == 1 and pg.locator('[data-ap=ex]').count() == 5)
        pg.locator('[data-ap=ex]').first.click(); ok(f'{name}: příklad se vloží do chatu', 'strategii' in pg.input_value('#apChatIn'))
        pg.click('#apChatF button[type=submit]'); pg.wait_for_timeout(300)
        ok(f'{name}: v ukázce se nic nespouští (toast)', 'ukázce' in pg.inner_text('#appToast'))
        for sub, txt in [('schvalovani', 'samostatné schválení'), ('kalendar', 'Instagram'), ('kampane', 'Zimní servis'), ('videa', 'nejsou připojené'), ('analytika', 'Nejsou data'), ('historie', 'tokenů'), ('nastaveni', 'nepřipojeno')]:
            pg.click(f'[data-ap="sub:{sub}"]'); pg.wait_for_timeout(250)
            t = pg.inner_text('#apBody')
            ok(f'{name}: část {sub} se zobrazí', txt in t)
            sw = pg.evaluate('document.documentElement.scrollWidth'); ok(f'{name}: {sub} bez vodorovného přetečení ({sw})', sw <= vp['width'] + 1)
            if name == 'desktop': pg.screenshot(path=f'/tmp/ap_{sub}.png', full_page=False)
        pg.click('[data-ap="sub:prehled"]'); pg.wait_for_timeout(200)
        if name == 'desktop': pg.screenshot(path='/tmp/ap_prehled.png', full_page=True)
        else: pg.screenshot(path='/tmp/ap_mobil.png', full_page=False)
        pg.click('[data-ap="mod:ceo"]'); pg.wait_for_timeout(200)
        ok(f'{name}: modul AI CEO odkazuje na existující modul', pg.locator('#apBody [data-tab=ceo]').count() == 1)
        pg.click('[data-ap="mod:marketing"]'); pg.wait_for_timeout(300)
        pg.click('[data-ap="sub:nastaveni"]'); pg.click('[data-ap=onb]'); pg.wait_for_timeout(200)
        ok(f'{name}: onboarding má všech 10 oblastí', all(pg.locator(f'#apo_{k}').count() == 1 for k in ['business_name', 'industry', 'offer', 'location', 'audience', 'competitors', 'website', 'budget_monthly', 'goals', 'tone']) and pg.locator('input[name=apo_ch]').count() == 6)
        ok(f'{name}: žádné chyby JS {errs[:2]}', not errs)
        pg.close()
    b.close()
print(f"\n{sum(1 for _, c in res if c)}/{len(res)} prošlo"); sys.exit(0 if all(c for _, c in res) else 1)
