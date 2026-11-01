"""Právní dokumenty: skutečné adresy, nová karta, obnovení, mobil, zachování rozepsané registrace (lokální server na :8765 z /tmp/vexaronet-saas)."""
from playwright.sync_api import sync_playwright
B='http://localhost:8765'
bad=[]
def chk(c,m):
    print(('OK   ' if c else 'FAIL ')+m)
    if not c: bad.append(m)
DOCS={'podminky':('Obchodní podmínky','Obchodní podmínky'),'ochrana-udaju':('Ochrana osobních údajů','Ochrana osobních údajů'),'cookies':('Informace o cookies','Informace o cookies')}
with sync_playwright() as p:
    b=p.chromium.launch()
    for w in (375,390,1360):
        pg=b.new_page(viewport={'width':w,'height':800})
        for k,(t,h) in DOCS.items():
            for u in ('/'+k,'/'+k+'/'):
                pg.goto(B+u);pg.wait_for_timeout(250)
                chk(t in pg.title() and pg.locator('h1').first.inner_text().startswith(h) and pg.locator('#cenik').count()==0,f'{w} {u}: titulek+h1, ne úvodní stránka')
            pg.reload();chk(pg.locator('h1').count()==1 and pg.locator('h1').first.inner_text().startswith(h),f'{w} /{k}/ po obnovení')
            chk(not pg.evaluate("document.documentElement.scrollWidth>innerWidth"),f'{w} /{k}/ bez vodorovného posunu')
        pg.close()
    pg=b.new_page(viewport={'width':390,'height':800});pg.on('dialog',lambda d:d.accept())
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'));pg.route('**/fonts.g*',lambda r:r.abort())
    pg.goto(B+'/');pg.wait_for_timeout(500);t0=pg.title()
    pg.evaluate("document.querySelector('[data-early=start]')?.click()");pg.wait_for_timeout(400)
    if not pg.locator('#authForm').count(): pg.click('text=Založit účet zdarma >> nth=0');pg.wait_for_timeout(400)
    pg.fill('#aName','Test Uživatel');pg.fill('#aMail','t@example.cz')
    for k,(t,h) in (('podminky',DOCS['podminky']),('ochrana-udaju',DOCS['ochrana-udaju'])):
        with pg.context.expect_page() as np_: pg.click(f'[data-legal-link={k}]')
        q=np_.value;q.wait_for_load_state();chk(q.url.rstrip('/').endswith('/'+k) and q.locator('h1').first.inner_text().startswith(h) and t in q.title(),f'registrace -> {k}: správná cílová stránka v nové kartě')
        q.close()
        chk(pg.input_value('#aName')=='Test Uživatel' and pg.input_value('#aMail')=='t@example.cz' and pg.title()==t0,f'registrace po otevření {k}: údaje i titulek zachovány')
    pg.keyboard.press('Escape');pg.wait_for_timeout(300)
    # patička, newsletter, poptávka
    for k,(t,h) in DOCS.items():
        pg.evaluate(f"document.querySelector('[data-legal={k}]').click()");pg.wait_for_timeout(300)
        chk(h in pg.inner_text('dialog'),f'patička -> dialog {k}')
        pg.keyboard.press('Escape');pg.wait_for_timeout(200)
    hrefs=pg.eval_on_selector_all('#fOkT a','e=>e.map(x=>x.getAttribute("href"))');chk(hrefs==['/ochrana-udaju/'],f'newsletter odkaz {hrefs}')
    pg.evaluate("document.querySelector('[data-custom],#sendB')&&0");
    txt=pg.evaluate("(function(){var a=document.querySelectorAll('a[href=\"/ochrana-udaju/\"]');return a.length})()");chk(txt>=1,'odkaz na zásady ve formuláři (newsletter/poptávka)')
    pg.close();b.close()
print('HOTOVO' if not bad else 'CHYB: %d'%len(bad))
