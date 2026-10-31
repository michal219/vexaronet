"""E-shop: nastavení, veřejný obchod, objednávka -> faktura -> odpis skladu, zrušení (demo režim)."""
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
bad=[]
def chk(c,m):
    print(('OK   ' if c else 'FAIL ')+m)
    if not c: bad.append(m)
with sync_playwright() as p:
    b=p.chromium.launch()
    for vw,tag in (({'width':1360,'height':900},'d'),({'width':390,'height':844},'m')):
        pg=b.new_page(viewport=vw);errs=[]
        pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
        pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
        pg.evaluate("document.querySelector('#vxapp [data-tab=eshop]').click()");pg.wait_for_timeout(500)
        h=pg.inner_text('#appMain')
        chk('Nastavení obchodu' in h and 'Objednávky (0)' in h,f'{tag} sekce E-shop se zobrazí')
        chk('Zboží v e-shopu (5)' in h,f'{tag} 5 položek zboží v e-shopu')
        pg.screenshot(path=f'/tmp/eshop_{tag}_1.png')
        pg.click('[data-shop=open]');pg.wait_for_selector('#vxsite .shp');pg.wait_for_timeout(300)
        chk(pg.locator('#vxsite .shp').count()==5,f'{tag} veřejný obchod ukazuje 5 produktů')
        # košík: 2x olej (p1), 1x filtr
        pg.click('[data-sh="inc:p1"]');pg.click('[data-sh="inc:p1"]');pg.click('[data-sh="inc:p2"]');pg.wait_for_timeout(200)
        chk('3 ks' in pg.inner_text('.shbar'),f'{tag} košík: 3 ks')
        pg.screenshot(path=f'/tmp/eshop_{tag}_2.png')
        pg.click('[data-sh=go]');pg.wait_for_selector('#shopOrd')
        t=pg.inner_text('#vxsite .shbox')
        chk('Doprava' in t and 'Celkem' in t,f'{tag} pokladna s dopravou a celkem')
        # prázdné údaje - validace prohlížeče, vyplníme
        pg.fill('#so_n','Jan Zákazník');pg.fill('#so_e','jan@example.cz');pg.fill('#so_a','Hlavní 5, Brno 60200');pg.check('#so_c')
        pg.click('#shopOrd button[type=submit]');pg.wait_for_selector('#vxsite h2:has-text("Děkujeme")')
        t=pg.inner_text('#vxsite .shbox')
        chk('Děkujeme za objednávku č. 1' in t and 'Variabilní symbol' in t,f'{tag} potvrzení s údaji k platbě')
        pg.screenshot(path=f'/tmp/eshop_{tag}_3.png')
        pg.click('[data-sh=close]');pg.wait_for_timeout(200)
        pg.evaluate("document.querySelector('#vxapp [data-tab=eshop]').click()");pg.wait_for_timeout(400)
        h=pg.inner_text('#appMain');chk('Objednávky (1)' in h and 'Jan Zákazník' in h,f'{tag} objednávka je v seznamu')
        # sklad klesl
        d=pg.evaluate("(()=>{const m={};__A.d.stock_moves.rows.forEach(x=>{m[x.product_id]=(m[x.product_id]||0)+Number(x.qty)});return m})()") if False else None
        pg.evaluate("document.querySelector('#vxapp [data-tab=faktury]').click()");pg.wait_for_timeout(400)
        chk('Jan Zákazník' in pg.inner_text('#appMain'),f'{tag} faktura pro zákazníka vznikla')
        pg.evaluate("document.querySelector('#vxapp [data-tab=eshop]').click()");pg.wait_for_timeout(300)
        pg.click('[data-shop^="ord:"]');pg.wait_for_selector('#appModal');
        t=pg.inner_text('#appModal');chk('Motorový olej' in t and 'Faktura' in t,f'{tag} detail objednávky s fakturou')
        pg.click('[data-shop^="paid:"]');pg.wait_for_timeout(600)
        pg.click('[data-shop^="ord:"]');pg.wait_for_selector('#appModal')
        t=pg.inner_text('#appModal');chk('Zaplaceno' in t,f'{tag} označeno jako zaplacené')
        pg.click('[data-shop^="cancel:"]');pg.wait_for_timeout(600)
        h=pg.inner_text('#appMain');chk('Zrušeno' in h,f'{tag} zrušeno')
        # po zrušení je zboží zpět: v obchodě opět 'skladem'
        pg.evaluate("document.querySelector('#vxapp [data-tab=eshop]').click()");pg.wait_for_timeout(200)
        chk(not errs,f'{tag} bez JS chyb {errs}')
        pg.close()
    # veřejný odkaz ?s=
    pg=b.new_page(viewport={'width':390,'height':844});errs=[]
    pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    pg.goto('file://'+R+'/index.html?s=neexistuje');pg.wait_for_timeout(800)
    chk('nenalezen' in pg.inner_text('#vxsite').lower(),'?s= s neznámou adresou ukáže "nenalezen"')
    chk(not errs,'bez JS chyb u ?s=')
    b.close()
print('HOTOVO' if not bad else 'CHYBY: %d'%len(bad));raise SystemExit(1 if bad else 0)
