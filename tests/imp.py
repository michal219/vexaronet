"""Import a export zákazníků (CSV) v ukázkovém režimu."""
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
bad=[]
def chk(c,m):
    print(('OK   ' if c else 'FAIL ')+m)
    if not c: bad.append(m)
CSV='﻿Firma;E-mail;Telefon;IČO;Adresa\nTruhlárna Nový;novy@truhlarna.cz;777111222;27082440;Dlouhá 1, Plzeň\nAutodíly Bára;bara@autodily.cz;777333444;;Krátká 2, Plzeň\nDuplicita;;;;\n'
open('/tmp/imp1.csv','w',encoding='utf-8').write(CSV)
open('/tmp/imp2.csv','w',encoding='utf-8').write('Cena;Poznámka\n1;a\n')
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':900});errs=[]
    pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    pg.goto('file://'+R+'/index.html');pg.wait_for_timeout(500)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    pg.evaluate("document.querySelector('#vxapp [data-tab=zaznici],#vxapp [data-tab=zakaznici]').click()");pg.wait_for_timeout(300)
    chk(pg.locator('[data-cs=imp]').count()==1,'tlačítko Import je vidět')
    chk(pg.locator('[data-cs="exp:customers"]').count()==1,'tlačítko Export je vidět')
    n0=pg.locator('#lst li').count()
    pg.click('[data-cs=imp]');pg.wait_for_selector('#ciFile')
    pg.set_input_files('#ciFile','/tmp/imp2.csv');pg.click('[data-cs=read]');pg.wait_for_timeout(300)
    chk('sloupec se jménem' in pg.inner_text('#ciSt'),'chybný soubor: srozumitelná chyba')
    pg.set_input_files('#ciFile','/tmp/imp1.csv');pg.click('[data-cs=read]');pg.wait_for_timeout(400)
    t=pg.inner_text('#ciRes');chk('Nalezeno 3' in t or 'Nalezeno 2' in t,'náhled importu: '+t[:60].replace('\n',' '))
    pg.click('[data-cs=go]');pg.wait_for_timeout(900)
    n1=pg.locator('#lst li').count()
    chk(n1>=n0+2,f'po importu přibyli zákazníci ({n0} → {n1})')
    chk('Truhlárna Nový' in pg.inner_text('#appMain'),'importovaný zákazník je v seznamu')
    # opakovaný import = duplicity se přeskočí
    pg.click('[data-cs=imp]');pg.wait_for_selector('#ciFile');pg.set_input_files('#ciFile','/tmp/imp1.csv');pg.click('[data-cs=read]');pg.wait_for_timeout(300)
    chk('Nenašel jsem žádné nové' in pg.inner_text('#ciSt'),'opakovaný import nevytvoří duplicity')
    pg.click('[data-app=mclose]')
    with pg.expect_download() as d:pg.click('[data-cs="exp:customers"]')
    chk(d.value.suggested_filename=='vexaronet-zakaznici.csv','export zákazníků stáhne CSV')
    pg.evaluate("document.querySelector('#vxapp [data-tab=zakazky]').click()");pg.wait_for_timeout(300)
    with pg.expect_download() as d2:pg.click('[data-cs="exp:jobs"]')
    chk(d2.value.suggested_filename=='vexaronet-zakazky.csv','export zakázek stáhne CSV')
    chk(not errs,'žádné JS chyby '+str(errs))
    pg.set_viewport_size({'width':390,'height':844});pg.evaluate("document.querySelector('#vxapp [data-tab=zakaznici]').click()") if pg.locator('#vxapp [data-tab=zakaznici]').count() else None
    chk(pg.evaluate("document.documentElement.scrollWidth<=innerWidth+1"),'mobil bez přetékání')
print('\nVŠE V POŘÁDKU' if not bad else '\nCHYBY: '+str(bad))
