"""Lokální verze: sestaví balíček, otevře ho ze souboru a ověří prázdná data, ukládání, restart, zálohu, obnovu a fakturu."""
import json, os, subprocess, sys, tempfile, zipfile
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
subprocess.run([sys.executable, ROOT + '/tools/export_local.py'], check=True, stdout=subprocess.DEVNULL)
T = tempfile.mkdtemp(prefix='vx-lt-'); zipfile.ZipFile(ROOT + '/vexaronet-lokalni.zip').extractall(T); os.remove(ROOT + '/vexaronet-lokalni.zip')
F = 'file://' + T + '/Vexaronet/Vexaronet.html'
bad = []
def chk(n, c):
    print(('OK  ' if c else 'FAIL'), n)
    if not c: bad.append(n)
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(viewport={'width': 1360, 'height': 900}, accept_downloads=True); pg = ctx.new_page()
    errs = []; reqs = []
    pg.on('pageerror', lambda e: errs.append(str(e))); pg.on('request', lambda r: reqs.append(r.url)); pg.on('dialog', lambda d: d.accept())
    pg.goto(F); pg.wait_for_selector('#vxapp', timeout=10000); pg.wait_for_timeout(1200)
    T_ = lambda t: pg.evaluate("document.querySelector('#vxapp [data-tab=%s]').click()" % t)
    chk('aplikace naběhne bez webu a bez demo lišty', pg.locator('.demobar').count() == 0 and pg.locator('.lbox').count() == 1)
    chk('žádná ukázková data', pg.evaluate("JSON.parse(localStorage.getItem('vxlocal1')||'{\"customers\":[]}').customers.length") == 0)
    T_('zakaznici'); pg.wait_for_timeout(400); pg.click('#appMain button:has-text("Nový zákazník")'); pg.wait_for_selector('#entForm')
    pg.fill('#e_name', 'Test Zákazník s.r.o.'); pg.click('#entForm button[type=submit]'); pg.wait_for_timeout(500)
    pg.reload(); pg.wait_for_selector('#vxapp'); pg.wait_for_timeout(800); T_('zakaznici'); pg.wait_for_timeout(400)
    chk('zákazník přežije restart', 'Test Zákazník s.r.o.' in pg.inner_text('#appMain'))
    pg.click('#appMain button:has-text("Nový zákazník")'); pg.wait_for_selector('#entForm'); pg.fill('#e_name', 'Druhý'); pg.click('#entForm button[type=submit]'); pg.wait_for_timeout(500)
    ids = pg.evaluate("JSON.parse(localStorage.getItem('vxlocal1')).customers.map(c=>c.id)"); chk('id po restartu nekolidují', len(ids) == 2 and len(set(ids)) == 2)
    T_('faktury'); pg.wait_for_timeout(400); pg.click('#appMain button:has-text("Fakturační údaje")'); pg.wait_for_selector('#p_legal_name')
    pg.fill('#p_legal_name', 'Moje Firma s.r.o.'); pg.fill('#p_ico', '12345678'); pg.fill('#p_address_text', 'Ulice 1, Praha'); pg.fill('#p_bank_account', '123456789/0100')
    pg.click('#appModal button[type=submit]'); pg.wait_for_timeout(700); pg.click('#appMain button:has-text("Nová faktura")'); pg.wait_for_timeout(600)
    pg.select_option('#ieC', label='Test Zákazník s.r.o.'); pg.wait_for_timeout(200); pg.fill('#ieA', 'Ulice 2, Brno')
    pg.fill('#appModal input.id', 'Servisní práce'); pg.fill('#appModal input.iq', '2'); pg.fill('#appModal input.ip', '1500')
    pg.click('#appModal button.pri:has-text("Vystavit")'); pg.wait_for_timeout(900)
    inv = json.loads(pg.evaluate("localStorage.getItem('vxlocal1')"))['invoices']
    chk('faktura vystavena s číslem a součtem', len(inv) == 1 and inv[0]['total'] == 3000 and str(inv[0]['number']).endswith('0001'))
    chk('upozornění na zjednodušené faktury', 'zjednodušené' in pg.inner_text('#appMain'))
    with pg.expect_download() as dl: pg.click('[data-app=lbak]')
    path = T + '/zaloha.json'; dl.value.save_as(path)
    pg.evaluate("localStorage.removeItem('vxlocal1')"); pg.reload(); pg.wait_for_selector('#vxapp'); pg.wait_for_timeout(600); T_('zakaznici'); pg.wait_for_timeout(300)
    chk('po smazání dat je prázdno', 'Test Zákazník s.r.o.' not in pg.inner_text('#appMain'))
    pg.set_input_files('#lresf', path); pg.wait_for_timeout(1500); pg.wait_for_selector('#vxapp'); pg.wait_for_timeout(600); T_('zakaznici'); pg.wait_for_timeout(300)
    chk('obnova ze zálohy vrátí data', 'Test Zákazník s.r.o.' in pg.inner_text('#appMain') and 'Druhý' in pg.inner_text('#appMain'))
    ext = [u for u in reqs if not u.startswith(('file://', 'data:', 'blob:'))]
    chk('žádný požadavek mimo počítač', not ext); chk('bez JS chyb', not errs)
    b.close()
sys.exit(1 if bad else 0)
