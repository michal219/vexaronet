"""Přejmenovaná vstupní tlačítka dema: text, otevření ukázky, čitelnost na 320/375/390/1360."""
from playwright.sync_api import sync_playwright
B='http://localhost:8765/'
bad=[]
def chk(c,m):
    print(('OK   ' if c else 'FAIL ')+m)
    if not c: bad.append(m)
with sync_playwright() as p:
    b=p.chromium.launch()
    for w in (320,375,390,1360):
        pg=b.new_page(viewport={'width':w,'height':800});pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'));pg.route('**/fonts.g*',lambda r:r.abort())
        pg.goto(B);pg.wait_for_timeout(500)
        chk('Vyzkoušet demo' not in pg.inner_text('body')+pg.content(),f'{w} starý text zmizel')
        btns=pg.locator('[data-demo]')
        n=btns.count();chk(n==5,f'{w} 5 vstupních tlačítek ({n})')
        for i in range(n):
            bt=btns.nth(i)
            if not bt.is_visible(): continue
            t=bt.inner_text().strip();bb=bt.bounding_box()
            clip=bt.evaluate("e=>e.scrollWidth>e.clientWidth+1")
            chk(t=='▶ Ukázka, jak to vypadá' and not clip and bb['x']>=0 and bb['x']+bb['width']<=w,f'{w} tlačítko {i}: text, bez ořezu, v okně ({int(bb["width"])}x{int(bb["height"])})')
        chk(not pg.evaluate("document.documentElement.scrollWidth>innerWidth"),f'{w} bez vodorovného posunu')
        pg.locator('.hero .cta [data-demo]').first.scroll_into_view_if_needed() if pg.locator('.hero .cta [data-demo]').count() else None
        if w==375: pg.screenshot(path='/tmp/btn_375.png')
        if w==320: pg.screenshot(path='/tmp/btn_320.png')
        if w==390:
            pg.screenshot(path='/tmp/btn_390.png')
        # každé viditelné tlačítko otevře ukázku
        for i in range(n):
            pg.goto(B);pg.wait_for_timeout(300)
            bt=pg.locator('[data-demo]').nth(i)
            if not bt.is_visible():
                if w<=760: pg.evaluate("document.querySelector('#burger,.burger,[aria-controls=mnav]')?.click()");pg.wait_for_timeout(300)
                if not bt.is_visible(): continue
            bt.click();
            try: pg.wait_for_selector('#vxapp .kpi',timeout=5000);ok=pg.locator('.demobar').count()==1 and 'DEMO' in pg.inner_text('.demobar')
            except Exception: ok=False
            chk(ok,f'{w} tlačítko {i} otevře ukázkovou aplikaci s lištou DEMO')
        pg.close()
    b.close()
print('HOTOVO' if not bad else 'CHYB: %d'%len(bad))
