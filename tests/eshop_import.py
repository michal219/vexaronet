"""Import objednávek z jiného e-shopu (CSV) -> zákazník + zakázka + faktura (demo režim)."""
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
bad=[]
def chk(c,m):
    print(('OK   ' if c else 'FAIL ')+m)
    if not c: bad.append(m)
CSV='Číslo objednávky;Jméno a příjmení;E-mail;Ulice;Město;PSČ;Celkem;Měna\n1001;Jan Test;jan@example.cz;Dlouhá 1;Praha;11000;1210,50;CZK\n1002;Eva Nová;eva@example.cz;Krátká 2;Brno;60200;500;CZK\n1002;Duplicita;dup@example.cz;;;;100;CZK\n1003;;x@example.cz;;;;100;CZK\n1004;Pavel;pavel@example.cz;;;;0;CZK\n'
open('/tmp/ei_test.csv','w',encoding='utf-8').write(CSV)
with sync_playwright() as p:
    b=p.chromium.launch()
    for vw,tag in (({'width':1360,'height':900},'d'),({'width':390,'height':844},'m')):
        pg=b.new_page(viewport=vw);errs=[]
        pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
        pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
        pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(400)
        pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
        pg.evaluate("document.querySelector('#vxapp [data-tab=eshop]').click()");pg.wait_for_timeout(500)
        chk('Import objednávek z jiného e-shopu' in pg.inner_text('#appMain'),f'{tag} karta importu je vidět')
        pg.set_input_files('#eiFile','/tmp/ei_test.csv');pg.click('[data-ei=load]');pg.wait_for_selector('#eiRes .draft')
        t=pg.inner_text('#eiRes')
        chk('K vystavení: 2 faktur' in t,f'{tag} náhled: 2 platné objednávky')
        chk('duplicitní číslo' in t and 'chybí jméno' in t and 'chybí kladná částka' in t,f'{tag} náhled: neplatné řádky přeskočeny s důvodem')
        pg.screenshot(path=f'/tmp/ei_{tag}_1.png')
        pg.click('[data-ei=run]');pg.wait_for_timeout(1800)
        chk('Vystaveno faktur: 2' in pg.inner_text('body'),f'{tag} vystaveny 2 faktury (toast)')
        pg.evaluate("document.querySelector('#vxapp [data-tab=faktury]').click()");pg.wait_for_timeout(500)
        ft=pg.inner_text('#appMain')
        chk('Jan Test' in ft and 'Eva Nová' in ft,f'{tag} faktury v seznamu Fakturace')
        pg.screenshot(path=f'/tmp/ei_{tag}_2.png')
        # opakovaný import nic nevystaví
        pg.evaluate("document.querySelector('#vxapp [data-tab=eshop]').click()");pg.wait_for_timeout(400)
        pg.set_input_files('#eiFile','/tmp/ei_test.csv');pg.click('[data-ei=load]');pg.wait_for_selector('#eiRes .draft')
        chk('už naimportováno' in pg.inner_text('#eiRes') and 'K vystavení: 0' in pg.inner_text('#eiRes'),f'{tag} opakovaný import se přeskočí')
        chk(not errs,f'{tag} bez JS chyb '+str(errs))
        pg.close()
    b.close()
print('HOTOVO' if not bad else 'CHYB: %d'%len(bad))
