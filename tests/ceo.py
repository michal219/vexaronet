"""AI CEO – etapa 2: skóre zdraví, výhled, cíl, nová doporučení, týdenní report (demo)."""
from playwright.sync_api import sync_playwright
R='/tmp/vexaronet-saas'
with sync_playwright() as p:
    b=p.chromium.launch();pg=b.new_page(viewport={'width':1360,'height':1000})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('dialog',lambda d:d.accept())
    pg.route('**/supabase.js',lambda r:r.fulfill(body='',content_type='text/javascript'))
    open('/tmp/ceo_index.html','w').write(open(R+'/index.html').read().replace('function appTab(t){','window.__A=APP;window.__t=function(x){appTab(x)};window.__s=function(){return summary()};function appTab(t){',1))
    pg.goto('file:///tmp/ceo_index.html');pg.wait_for_timeout(400)
    pg.click('.cta [data-demo]');pg.wait_for_selector('#vxapp .kpi')
    d=pg.inner_text('#appMain');assert 'Zdraví firmy' in d,'dash tile'
    pg.evaluate("__t('ceo')");pg.wait_for_selector('.hring');t=pg.inner_text('#appMain').replace('\n',' | ');print(t[:1500])
    for w in('Zdraví firmy','Platby od zákazníků','Výhled na 30 dní','Měsíční cíl','Týdenní report'):assert w in t,w
    s=pg.evaluate("__s()");print({k:s[k] for k in('skore_zdravi_firmy','cil_mesic_kc','zakaznik_nejvetsi_podil_pct','neaktivni_zakaznici_90d','odpracovane_hodiny_7dni')})
    assert isinstance(s['skore_zdravi_firmy'],int) and 0<=s['skore_zdravi_firmy']<=100
    pg.fill('#goalIn','150000');pg.click('#goalForm button');pg.wait_for_timeout(500)
    t=pg.inner_text('#appMain');assert '150' in t and 'z' in t;print('goal ok',pg.evaluate("__s().cil_mesic_kc"))
    pg.click('[data-act=report]');pg.wait_for_selector('#remTx');rep=pg.input_value('#remTx');print(rep);assert 'Zdraví firmy' in rep and 'Nových' in rep
    pg.screenshot(path='/tmp/ceo1.png');pg.keyboard.press('Escape')
    pg.evaluate("document.querySelector('[data-app=mclose]')&&document.querySelector('[data-app=mclose]').click()")
    pg.evaluate("__t('ceo')");pg.wait_for_timeout(300);pg.screenshot(path='/tmp/ceo2.png',full_page=True)
    pg.set_viewport_size({'width':390,'height':800});pg.wait_for_timeout(300)
    ov=pg.evaluate("document.documentElement.scrollWidth>innerWidth+2");print('mobile overflow',ov);assert not ov
    print('errors',errs);assert not errs;b.close()
