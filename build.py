#!/usr/bin/env python3
import json, html, re
D = '/tmp/vexaronet-saas/'
css = open(D + 'base.css', encoding='utf-8').read()
esc = lambda s: html.escape(s, quote=True)

IC = {
 'ai': '<rect x="5" y="5" width="14" height="14" rx="3.5"/><path d="M9.5 10h.01M14.5 10h.01"/><path d="M9.5 14.5c1.4 1 3.6 1 5 0"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>',
 'fin': '<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="M3 10h18M7 15h3"/>',
 'biz': '<circle cx="9" cy="8" r="3.2"/><path d="M3.5 19c.6-3.3 2.8-5 5.5-5s4.9 1.7 5.5 5"/><path d="M16 6.5a3 3 0 010 5.6M18 14.2c1.6.7 2.6 2.2 3 4.3"/>',
 'web': '<rect x="3" y="4" width="18" height="15" rx="2.5"/><path d="M3 9h18"/><path d="M8 14.5l2.2 2.2L15 12"/>',
 'mkt': '<path d="M4 20V10M10 20V4M16 20v-8M22 20H2"/>',
 'auto': '<path d="M13 3L5 14h6l-1 7 8-11h-6z"/>',
}
MODS = [
 dict(id='ai', stage=5, name='AI centrum', short='Poradce, účetní, obchodník, krizový manažer, Autopilot a podpora 24/7 na jednom místě.',
      items=['AI podnikatelský poradce','AI účetní','AI obchodník','AI krizový manažer','AI Autopilot, který propojuje moduly a automatizuje opakované činnosti','AI zákaznická podpora 24/7','AI analýza podnikání a návrhy na zlepšení']),
 dict(id='fin', stage=4, name='Finance a účetnictví', short='Faktury, QR platby, výdaje, DPH, pohledávky a párování plateb.',
      items=['Vystavování a správa faktur','PDF faktury a QR platby','Evidence příjmů, výdajů a DPH','Pohledávky a závazky','Párování bankovních plateb','Upomínky neuhrazených faktur','Účetní deník a hlavní kniha','AI rozpoznávání faktur a účtenek','Finanční statistiky a grafy']),
 dict(id='biz', stage=3, name='Řízení firmy', short='CRM, zakázky, úkoly, zaměstnanci, kalendář, rezervace a sklad.',
      items=['CRM a databáze zákazníků','Správa zakázek, úkolů a projektů','Zaměstnanci, role a oprávnění','Kalendář a rezervace','Připomínky a notifikace','Firemní komunikace a e-mail','Skladové hospodářství']),
 dict(id='web', stage=6, name='Jednoduché weby', short='AI generátor jednoduchých firemních webů s úpravou vzhledu a vlastní doménou.',
      items=['AI generátor jednoduchých webů podle textového zadání','Úprava barev, písem, sekcí, obrázků a pozadí','Vlastní domény','Veřejný odkaz na vytvořený web','Responzivní zobrazení','Jde o jednoduché weby (prezentace firmy), ne o složité projekty']),
 dict(id='mkt', stage=7, name='Marketing a analytika', short='Kampaně, slevové kódy, veřejné profily, recenze a přehledy.',
      items=['Marketingové kampaně','Slevové kódy','Veřejné firemní profily','Hodnocení a recenze','Statistiky návštěvnosti, zakázek a tržeb','Jednoduchý i pokročilý analytický režim','Interaktivní grafy a přehledy podle dostupných dat']),
 dict(id='auto', stage=5, name='Automatizace', short='Objednávky, faktury a připomínky se zpracují samy. Vy jen schvalujete.',
      items=['Automatické zpracování poptávek a zakázek','Automatické vystavování faktur','Připomínky rezervací','Automatizované pracovní postupy','Propojení jednotlivých modulů','Tvorba jednoduchých vlastních aplikací']),
]
STAGES = [
 ('Úvodní stránka a designový systém', 'Hotová a nasazená úvodní stránka s ukázkou aplikace.', 'done'),
 ('Registrace, přihlášení a databáze', 'Registrace, přihlášení, obnova hesla, firemní účty a 30denní zkušební období fungují.', 'done'),
 ('Dashboard, CRM, zakázky a kalendář', 'Dashboard, zákazníci, zakázky, kalendář a úkoly už fungují. Zaměstnanci a role se doplní.', 'next'),
 ('Finance a fakturace', 'Faktury, QR platby, výdaje, pohledávky. Vyžaduje odbornou kontrolu účetním.', 'plan'),
 ('AI centrum a automatizace', 'Asistenti a Autopilot se schvalováním akcí. Vyžaduje API klíč AI poskytovatele.', 'plan'),
 ('Tvorba jednoduchých webů', 'Generátor jednoduchých webů, úprava vzhledu a domény. Vyžaduje externí služby.', 'plan'),
 ('Marketing, analytika a další moduly', 'Kampaně, slevy, profily, recenze a přehledy.', 'plan'),
 ('Předplatné, zabezpečení a testování', 'Tarify, zkušební období, platební brána, audit zabezpečení.', 'plan'),
]
BIZ = {
 'Služby': ['Zakázky','Kalendář','Faktury','CRM'],
 'Autoservis': ['Zakázky a vozidla','Rezervace','Sklad dílů','Faktury'],
 'Řemeslník': ['Zakázky','Kalendář','Sklad materiálu','Faktury'],
 'Restaurace': ['Rezervace stolů','Sklad surovin','Zaměstnanci','Hodnocení'],
 'Jiný obor': ['CRM','Kalendář','Faktury','Úkoly'],
}
PLANS = [
 # key, název, měsíčně, ročně za měsíc, ročně za rok, podtitul, hot, tlačítko, odrážky
 ('start','VEXARONET START',0,0,0,'Pro začínající OSVČ a malé podnikatele.',False,'Začít zdarma',
  ['CRM do 50 zákazníků','Až 10 faktur měsíčně a 10 zakázek','Kalendář a úkoly','Jednoduchý finanční přehled','1 uživatel','Bez AI CEO a AI účetnictví']),
 ('accountant','VEXARONET AI ÚČETNÍ',399,339,4068,'Samostatný účetní systém pro OSVČ a s.r.o. (připravujeme).',False,'Vyzkoušet 30 dní zdarma',
  ['Neomezené vystavování faktur','Evidence příjmů a výdajů','Účetnictví a DPH (připravujeme)','100 AI vytěžených dokladů měsíčně','1 uživatel + 1 externí účetní','Bez CRM a AI CEO']),
 ('pro','VEXARONET PRO',699,594,7128,'Kompletní All-in-One platforma pro malé firmy.',True,'Vyzkoušet 30 dní zdarma',
  ['Vše z AI Účetní','Neomezené CRM, zakázky a kalendář','AI CEO: doporučení a chat nad daty','3 uživatelé, 1 firma','150 AI dokladů a 500 AI akcí měsíčně','1 web (připravujeme)']),
 ('business','VEXARONET BUSINESS',1199,1019,12228,'Pro rostoucí společnosti.',False,'Vyzkoušet 30 dní zdarma',
  ['Vše z PRO','Až 10 uživatelů a 3 weby','Pokročilý AI CEO a predikce (připravujeme)','500 AI dokladů a 2 000 AI akcí měsíčně','Role, oprávnění a schvalování','Prioritní podpora']),
 ('enterprise','VEXARONET ENTERPRISE',None,None,None,'Pro větší společnosti a náročné provozy.',False,'Požádat o nabídku',
  ['Individuální počet uživatelů a limity','Více společností a poboček','Vlastní integrace a automatizace','Individuální onboarding','Dohodnutá podpora a SLA','Cena podle nabídky']),
]
# řádky porovnání: popisek, [start, účetní, pro, business, enterprise], stav ('now' = už funguje, 'soon' = připravujeme)
Y='✓'; N='—'
CMP = [
 ('Základ', None, None),
 ('Uživatelé', ['1','1 + 1 externí účetní','3','10','individuálně'], 'soon'),
 ('Firmy', ['1','1','1','1','více firem a poboček'], 'soon'),
 ('CRM, zakázky a kalendář', None, None),
 ('Zákazníci', ['max. 50',N,'neomezeně','neomezeně','neomezeně'], 'now'),
 ('Zakázky', ['max. 10',N,'neomezeně','neomezeně','neomezeně'], 'now'),
 ('Úkoly a termíny', [Y,N,Y,Y,Y], 'now'),
 ('Kalendář a plánování', [Y,N,Y,Y,Y], 'now'),
 ('Online rezervace a synchronizace kalendářů', [N,N,Y,Y,Y], 'soon'),
 ('Obchodní příležitosti, historie komunikace, segmentace', [N,N,Y,Y,Y], 'soon'),
 ('Finance a účetnictví', None, None),
 ('Vystavování faktur', ['10 měsíčně','neomezeně','neomezeně','neomezeně','neomezeně'], 'now'),
 ('Evidence příjmů a výdajů, jednoduchý přehled', [Y,Y,Y,Y,Y], 'now'),
 ('Přijaté faktury a AI vytěžování dokladů', [N,'100 / měsíc','150 / měsíc','500 / měsíc','individuálně'], 'soon'),
 ('Bankovní transakce a párování plateb', [N,Y,Y,Y,Y], 'soon'),
 ('Daňová evidence, podvojné účetnictví, deník, hlavní kniha, výkazy', [N,Y,Y,Y,Y], 'soon'),
 ('DPH a daňové podklady', [N,Y,Y,Y,Y], 'soon'),
 ('Majetek, odpisy a mzdová agenda', [N,Y,Y,Y,Y], 'soon'),
 ('Přístup externího účetního, auditní záznamy, archivace', [N,Y,Y,Y,Y], 'soon'),
 ('AI', None, None),
 ('AI CEO: doporučení a chat nad firemními daty', [N,N,Y,'pokročilý','rozšířený'], 'now'),
 ('AI účetní poradce a kontrola nesrovnalostí', [N,Y,Y,Y,Y], 'soon'),
 ('AI akce měsíčně', [N,N,'500','2 000','individuálně'], 'soon'),
 ('AI Autopilot (akce vždy po schválení)', [N,N,Y,'rozšířený',Y], 'soon'),
 ('Weby, sklad a ostatní', None, None),
 ('Weby a e-shopy (editor, AI generátor, produkty, objednávky)', [N,N,'1 web nebo e-shop','3','individuálně'], 'soon'),
 ('Sklad, zaměstnanci, marketingové kampaně, automatizace', [N,N,Y,'pokročilé',Y], 'soon'),
 ('Vlastní reporty, role a oprávnění, schvalovací procesy', [N,N,N,Y,Y], 'soon'),
 ('API integrace', [N,N,N,Y,Y], 'soon'),
 ('Základní veřejný firemní profil a ruční export dat', [Y,Y,Y,Y,Y], 'soon'),
 ('Podpora', ['základní','základní','základní','prioritní','dohodnutá (SLA)'], 'soon'),
]

def svg(k): return f'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{IC[k]}</svg>'

mods_html = '\n'.join(f'''<article class="svc" data-r="up" style="--d:{i*0.06:.2f}s" data-glow>
  <div class="svc-ic">{svg(m['id'])}</div><h3>{esc(m['name'])}</h3><p>{esc(m['short'])}</p>
  <div class="svc-foot"><span class="from">Etapa {m['stage']} · {'základ k dispozici' if m['id']=='biz' else 'plánováno'}</span><a class="more" href="#modul-{m['id']}" data-mod="{m['id']}" aria-label="Zjistit více: {esc(m['name'])}">Zjistit více <i aria-hidden="true"></i></a></div>
</article>''' for i, m in enumerate(MODS))

def kc(n): return f'{n:,}'.replace(',', ' ')
def plan_card(k,n,m,ym,yy,d,hot,btn,bul):
    if m is None: price='<b class="pp">Individuální cena</b>'; sub='<span class="pn">Cena na základě nabídky</span>'
    elif m==0: price='<b class="pp">0 Kč</b>'; sub='<span class="pn">zdarma, bez časového omezení</span>'
    else:
        price=f'<b class="pp" data-m="{kc(m)}" data-y="{kc(ym)}">{kc(m)} Kč</b>'
        sub=f'<span class="pn" data-m="měsíčně, bez DPH" data-y="měsíčně při roční platbě ({kc(yy)} Kč/rok), bez DPH">měsíčně, bez DPH</span>'
    cta=(f'<a class="btn btn-ghost" href="mailto:info@vexaronet.com?subject=Vexaronet%20ENTERPRISE">{btn}</a>' if k=='enterprise'
         else f'<button class="btn {"btn-main" if hot else "btn-ghost"}" type="button" data-early="{k}">{btn}</button>')
    return f'''<article class="plan{' hot' if hot else ''}" data-glow>{'<span class="ribbon">Nejvýhodnější</span>' if hot else ''}
  <h3>{n.replace('VEXARONET ','')}</h3><p class="note">{esc(d)}</p><div class="price">{price} <span class="per">Kč / měsíc</span></div>{sub}
  <ul class="ticks">{''.join('<li>'+esc(b)+'</li>' for b in bul)}</ul>{cta}</article>'''.replace(' <span class="per">Kč / měsíc</span>','')
cards='\n'.join(plan_card(*x) for x in PLANS)
def cell(v): return f'<td>{v}</td>'
rows=''
for lab,vals,st in CMP:
    if vals is None: rows+=f'<tr class="grp"><th colspan="6">{esc(lab)}</th></tr>'; continue
    badge='' if st=='now' else ' <em class="soonb">připravujeme</em>'
    rows+=f'<tr><th scope="row">{esc(lab)}{badge}</th>'+''.join(cell(esc(v)) for v in vals)+'</tr>'
plans_html=f'''<div class="bill" role="group" aria-label="Způsob platby"><button type="button" class="chipb" data-bill="m" aria-pressed="true">Měsíčně</button><button type="button" class="chipb" data-bill="y" aria-pressed="false">Ročně <small>sleva asi 15 %</small></button></div>
  <div class="plans5">{cards}</div>
  <h3 class="cmpt">Podrobné porovnání funkcí</h3>
  <div class="cmpw"><table class="cmp"><thead><tr><th>Funkce</th><th>START</th><th>AI Účetní</th><th class="hotc">PRO</th><th>BUSINESS</th><th>ENTERPRISE</th></tr></thead><tbody>{rows}</tbody></table></div>
  <p class="disc">Funkce označené „připravujeme“ zatím nejsou dostupné a nejsou součástí aktuální verze. Uvedený limit se uplatní, až bude funkce hotová.</p>
  <div class="pnotes">
   <div><h4>Ceny a DPH</h4><p>Všechny ceny jsou měsíční a uvedené bez DPH. Při roční platbě je sleva přibližně 15 %. Doména, hosting, platební transakce a služby třetích stran mohou být zpoplatněny zvlášť, jejich ceny zobrazíme před objednávkou.</p></div>
   <div><h4>30 dní zdarma</h4><p>Všechny placené tarify mají 30 dní zdarma pro nové zákazníky, jednou na firmu. Po skončení vás upozorníme a nabídneme výběr tarifu. Bez zaplacení se nic automaticky nestrhává, můžete přejít na START a vaše data zůstanou zachována. Konkrétní lhůty uchování dat uvedeme v podmínkách.</p></div>
   <div><h4>Platby zatím nejsou spuštěné</h4><p>Platební brána zatím není připojená, takže předplatné zatím nejde zaplatit. Zkušební období a tarif START fungují. Změnu tarifu zatím vyřizujeme e-mailem na info@vexaronet.com.</p></div>
  </div>'''

stages_html = '\n'.join(f'''<div class="step" data-r="up">
  <div class="dot" aria-hidden="true">{i}</div>
  <div class="step-b st-{s}"><h3>{esc(t)} <span class="tagst">{ {'done':'Hotovo','next':'Rozpracováno','plan':'Plánováno'}[s] }</span></h3><p>{esc(d)}</p></div>
</div>''' for i, (t, d, s) in enumerate(STAGES, 1))

biz_chips = ''.join(f'<button type="button" class="chipb" data-biz="{esc(k)}" aria-pressed="{"true" if i==0 else "false"}">{esc(k)}</button>' for i, k in enumerate(BIZ))
biz_opts = '\n'.join(f'<option>{esc(k)}</option>' for k in BIZ)
keys = ''.join('<div class="kr">' + ''.join(f'<i style="flex:{w}"></i>' for w in r) + '</div>' for r in [[1]*14,[1]*13+[1.6],[1.6]+[1]*12+[1.4],[2.1]+[1]*10+[2.1],[1.2]*3+[6.2]+[1.2]*3])

extra_css = r'''

/* --- ceník --- */
.plans5 .plan{position:relative}.plans5 .ribbon{position:absolute;top:-12px;left:50%;transform:translateX(-50%);background:var(--grad);color:#fff;font-size:.72rem;font-weight:700;padding:3px 12px;border-radius:99px;white-space:nowrap}.plans5 .price{min-height:2.2em;display:flex;align-items:flex-end}.plans5 .price b.pp:not([data-m]){font-size:1.2rem;white-space:normal}.plans5 .plan.hot{border-color:rgba(130,160,255,.7)}
.bill{display:flex;gap:10px;justify-content:center;margin:0 0 24px;flex-wrap:wrap}.bill small{opacity:.8;font-weight:500}
.plans5{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:14px;align-items:stretch}
@media(max-width:1180px){.plans5{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:820px){.plans5{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:560px){.plans5{grid-template-columns:1fr}}
.plans5 .plan{padding:22px}.plans5 .plan h3{font-size:1.1rem}.plans5 .price b{font-size:1.6rem;white-space:nowrap}.plans5 .pn{font-size:.8rem;color:var(--mut);min-height:2.4em}.plans5 .note{font-size:.88rem;color:var(--mut);min-height:3.2em}
.plans5 .ticks li{font-size:.88rem}.plans5 .btn{width:100%;justify-content:center;text-align:center}
.cmpt{text-align:center;margin:44px 0 14px}.cmpw{overflow-x:auto;border:1px solid var(--line);border-radius:var(--r);background:var(--glass)}
.cmp{width:100%;border-collapse:collapse;min-width:760px;font-size:.9rem}.cmp th,.cmp td{padding:10px 12px;border-bottom:1px solid var(--line);text-align:center}
.cmp thead th{position:sticky;top:0;background:var(--ink);z-index:1}.cmp th[scope=row],.cmp thead th:first-child{text-align:left;font-weight:500}
.cmp .grp th{text-align:left;background:rgba(110,140,255,.12);font-weight:700;letter-spacing:.04em;text-transform:uppercase;font-size:.78rem}.cmp .hotc{color:#8fb2ff}
.soonb{font-style:normal;font-size:.68rem;border:1px solid var(--line);border-radius:99px;padding:1px 7px;color:var(--mut);white-space:nowrap}
.pnotes{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px;margin-top:26px}.pnotes>div{padding:18px;border-radius:16px;border:1px solid var(--line);background:var(--glass)}.pnotes h4{margin:0 0 6px}.pnotes p{margin:0;color:var(--mut);font-size:.9rem}
/* --- aplikace --- */
body:has(#vxapp) #chatFab,body:has(#vxapp) #chat{display:none!important}
.vxapp{--ink:#080d2b;--glass:rgba(22,30,82,.55);--line:rgba(130,150,255,.2);position:fixed;inset:0;z-index:1000;background:radial-gradient(900px 500px at 85% -10%,rgba(120,80,255,.22),transparent),radial-gradient(700px 500px at 0% 100%,rgba(60,110,255,.14),transparent),var(--ink);color:var(--text);display:flex;font-family:var(--fb)}
[data-theme=light] .vxapp{--ink:#eef1ff;--glass:rgba(255,255,255,.85);--line:rgba(60,80,200,.18)}
.vxapp button,.vxapp input,.vxapp select,.vxapp textarea{font:inherit}
.vxapp .pri{background:linear-gradient(135deg,#7a5cff,#6b4bf2);color:#fff;border:0;border-radius:12px;padding:10px 16px;cursor:pointer;display:inline-flex;gap:8px;align-items:center;font-weight:600;min-height:40px;box-shadow:0 8px 22px rgba(110,76,255,.35);transition:.2s}
.vxapp .pri:hover{transform:translateY(-1px);filter:brightness(1.1)}.vxapp .pri.sm{padding:8px 14px;white-space:nowrap}
.vxapp>aside{width:244px;flex:none;border-right:1px solid var(--line);display:flex;flex-direction:column;padding:16px 12px;overflow:auto;background:var(--glass);backdrop-filter:blur(14px)}
.vlogo{display:flex;gap:10px;align-items:center;padding:4px 10px 18px}.vlogo b{display:block;font-size:1.2rem;font-weight:800;letter-spacing:.04em;line-height:1.1}.vlogo small{color:var(--mut);font-size:.95rem}
.vxapp aside nav{display:flex;flex-direction:column;gap:3px;flex:1}
.vxapp aside nav button,.vxapp .sfoot>button{display:flex;align-items:center;gap:12px;background:none;border:0;color:var(--mut);padding:7px 12px;border-radius:12px;cursor:pointer;text-align:left;min-height:38px;transition:.2s;width:100%;font-size:.93rem}
.vxapp aside button:hover{background:rgba(110,140,255,.12);color:var(--text)}
.vxapp aside button[aria-pressed=true]{background:linear-gradient(135deg,#5b45e0,#4a3bc4);color:#fff;font-weight:700;box-shadow:0 6px 18px rgba(90,70,220,.35)}
.vxapp aside .soon{opacity:.7}.vxapp aside em{margin-left:auto;font-size:.65rem;font-style:normal;border:1px solid var(--line);border-radius:99px;padding:1px 7px}
.subc{margin-top:12px;padding:14px;border-radius:14px;border:1px solid var(--line);background:rgba(110,76,255,.1);display:grid;gap:2px}.subc small{color:var(--mut)}.subc b{color:#ffcf6e}
.subc button{margin-top:8px;background:none;border:1px solid var(--line);color:inherit;border-radius:10px;padding:8px;cursor:pointer}
.vxmain{flex:1;display:flex;flex-direction:column;min-width:0}
.vxmain header{display:flex;align-items:center;gap:10px;padding:12px 20px;min-height:68px}
.gs{flex:1;max-width:620px;display:flex;align-items:center;gap:10px;padding:0 14px;border-radius:14px;border:1px solid var(--line);background:var(--glass);height:46px}
.gs input{flex:1;background:none;border:0;color:inherit;outline:0;min-width:0}.gs kbd{font-size:.72rem;border:1px solid var(--line);border-radius:6px;padding:2px 6px;color:var(--mut)}.gs .si{color:var(--mut);display:grid}
.vxmain header>.bellw{margin-left:auto}
.vxapp .ib{width:42px;height:42px;border-radius:50%;border:1px solid var(--line);background:none;color:inherit;display:grid;place-items:center;cursor:pointer;position:relative;flex:none}
.vxapp .ib.av{background:linear-gradient(135deg,#6e8cff,#a278ff);color:#fff;font-weight:800;border:0}
.usr{display:flex;gap:10px;align-items:center;background:none;border:0;color:inherit;cursor:pointer;text-align:left}.usr .un{display:grid;line-height:1.2}.usr small{color:var(--mut)}
.vxapp .burger{display:none}
.vxapp .bdg{position:absolute;top:-2px;right:-2px;min-width:18px;height:18px;border-radius:9px;background:#ff5a73;color:#fff;font-size:.7rem;font-style:normal;display:grid;place-items:center;padding:0 4px}
.vxapp .bellw,.vxapp .qw{position:relative}.vxapp .pop{display:none;position:absolute;right:0;top:50px;width:min(340px,86vw);max-height:60vh;overflow:auto;background:var(--ink);border:1px solid var(--line);border-radius:14px;padding:12px;box-shadow:0 20px 50px rgba(0,0,0,.4);z-index:5}
.vxapp .pop.on{display:block}.vxapp .pop h4{margin:0 0 8px}
.vxapp .qpop{width:200px;top:48px;padding:6px}.vxapp .qpop button{display:block;width:100%;text-align:left;background:none;border:0;color:inherit;padding:10px;border-radius:8px;cursor:pointer}.vxapp .qpop button:hover{background:rgba(110,140,255,.15)}
.vxapp .nt{display:block;width:100%;text-align:left;border:0;border-left:3px solid #6e8cff;padding:8px 10px;margin:6px 0;color:inherit;cursor:pointer;border-radius:0 8px 8px 0;background:rgba(110,140,255,.08)}
.vxapp .nt.bad{border-color:#ff5a73}.vxapp .nt.warn{border-color:#ffb347}
.vxapp main{flex:1;overflow:auto;padding:6px 20px 70px}
.vxapp main>*{max-width:1280px;margin-left:auto;margin-right:auto}
.vxapp h3{margin:0 0 10px;font-size:1.02rem}.vxapp h2{margin:0}.vxapp .mut,.vxapp small{color:var(--mut)}.vxapp .fine{font-size:.78rem;margin:10px 0 0}
.dgrid{display:grid;grid-template-columns:minmax(0,1fr) 320px;gap:16px;align-items:start}
.dl{display:grid;gap:16px;min-width:0}.dr{position:sticky;top:0;margin:0!important}
.db4{grid-column:1/-1;display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:16px}.db4>.card2{margin:0}
.greet{display:flex;gap:16px;align-items:flex-start;flex-wrap:wrap}.greet>div:first-child{flex:1;min-width:220px}.greet h2{font-size:2rem}
.gd{text-align:right;color:var(--text);font-size:.9rem;line-height:1.4}
.kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}@media(max-width:1250px){.kpis{grid-template-columns:repeat(2,minmax(0,1fr))}}
.kpi{position:relative;text-align:left;display:grid;grid-template-columns:auto 1fr;gap:6px 12px;align-items:center;padding:16px;border-radius:16px;border:1px solid var(--line);background:var(--glass);color:inherit;animation:fin .5s both}
button.kpi{cursor:pointer;transition:.2s}button.kpi:hover{transform:translateY(-3px);border-color:rgba(130,160,255,.6)}
.kt small{display:block;font-size:.8rem}.kt b{font-size:1.3rem;white-space:nowrap}.ceop p{font-size:.9rem;margin:6px 0}.ks{grid-column:1/-1;display:flex;gap:8px;align-items:center;font-size:.8rem;min-height:30px;flex-wrap:wrap}
.ks .up{color:#3ddc97;font-style:normal;font-weight:700}.ks .dn2{color:#ff6b81;font-style:normal;font-weight:700}
.spk{margin-left:auto;display:flex;gap:3px;align-items:flex-end;height:30px}.spk i{width:5px;border-radius:2px;display:block;animation:grow .7s both;transform-origin:bottom}.sg{background:#3ddc97}.sr{background:#ff5a73}.sp{background:#a278ff}
.prog{flex:1;height:6px;border-radius:3px;background:rgba(130,150,255,.2);overflow:hidden;min-width:60px}.prog i{display:block;height:100%;background:linear-gradient(90deg,#6e8cff,#a278ff);border-radius:3px}
.ki{width:42px;height:42px;border-radius:12px;display:grid;place-items:center;color:#fff;flex:none}
.ki.g{background:linear-gradient(135deg,#1fc58a,#13a06f)}.ki.r{background:linear-gradient(135deg,#ff5a73,#e03a56)}.ki.b{background:linear-gradient(135deg,#3b82f6,#2563eb)}.ki.p{background:linear-gradient(135deg,#8b5cf6,#6d3df0)}.ki.o{background:linear-gradient(135deg,#ffb347,#f59e0b)}
.vxapp .card2{padding:18px;border-radius:18px;border:1px solid var(--line);background:var(--glass);margin-bottom:16px;backdrop-filter:blur(10px)}
.recs .rh{display:flex;gap:12px;align-items:center;margin-bottom:12px}.recs .rh h3{margin:0;flex:1;font-size:1.15rem}
.rl{display:grid;gap:10px}.rec{display:flex;gap:14px;align-items:center;padding:12px 14px;border-radius:14px;border:1px solid var(--line);background:rgba(110,140,255,.06);flex-wrap:wrap}
.rt{flex:1;min-width:200px}.rt b{display:block}.rt small{display:block;margin-top:2px}.ra{display:flex;gap:8px;flex-wrap:wrap}
.ceop{text-align:left}.orb{margin:-4px 0 0}.ceop h3{font-size:1.4rem;margin:0}.ceop .chatl{height:150px;margin:12px 0 8px}
.qp{display:grid;gap:6px;margin-bottom:10px}.qp button{text-align:left;background:rgba(110,140,255,.08);border:1px solid var(--line);color:inherit;padding:9px 12px;border-radius:10px;cursor:pointer;transition:.2s}.qp button:hover{background:rgba(110,140,255,.2)}
.vxapp .aif{display:flex;gap:8px}.vxapp .aif input{flex:1;min-width:0;padding:11px 14px;border-radius:12px;border:1px solid var(--line);background:rgba(110,140,255,.06);color:inherit}
.sendb{width:44px;border-radius:12px;border:0;background:linear-gradient(135deg,#7a5cff,#6b4bf2);color:#fff;cursor:pointer;display:grid;place-items:center}
.vxapp .chatl{overflow:auto;display:flex;flex-direction:column;gap:8px;padding:4px}
.vxapp .msg{max-width:92%;padding:9px 13px;border-radius:14px;line-height:1.45;white-space:pre-wrap;font-size:.92rem}.vxapp .msg.bot{background:rgba(110,140,255,.16);align-self:flex-start}.vxapp .msg.me{background:linear-gradient(135deg,#6e8cff,#a278ff);color:#fff;align-self:flex-end}.vxapp .msg.err{color:#ff8fa0}
.dr0 .chatl{height:360px}
.accrf{margin-top:14px;padding-top:12px;border-top:1px solid var(--line)}.accrf h4{margin:0 0 8px}.accrf details{margin:10px 0}.accrf summary{cursor:pointer;color:var(--mut,#9aa3c7)}#accRes .draft{margin:8px 0}
.ev{list-style:none;margin:0;padding:0;display:grid;gap:8px}.ev button{display:flex;gap:12px;align-items:center;width:100%;text-align:left;background:none;border:0;color:inherit;cursor:pointer;padding:6px;border-radius:10px}.ev button:hover{background:rgba(110,140,255,.1)}
.evd{width:62px;flex:none}.evd b{display:block;color:#6e8cff;font-size:.85rem}.evd small{font-size:.8rem}
.qg{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.qg button{position:relative;display:grid;gap:6px;justify-items:center;text-align:center;font-size:.78rem;padding:10px 4px;border-radius:12px;border:1px solid var(--line);background:rgba(110,140,255,.06);color:inherit;cursor:pointer;transition:.2s}
.qg button:hover{transform:translateY(-2px);border-color:rgba(130,160,255,.6)}.qg .qs{opacity:.65}.qg em{position:absolute;top:4px;right:4px;font-size:.6rem;font-style:normal;color:var(--mut)}
.vxapp .tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px}
.vxapp .two{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}.vxapp .two>.card2{margin:0}.vxapp .two{margin-bottom:16px}
.vxapp .rows{list-style:none;margin:0;padding:0;display:grid;gap:8px}
.vxapp .rows li{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;align-items:center;padding:12px 14px;border-radius:12px;border:1px solid var(--line);background:rgba(110,140,255,.06)}
.vxapp .rows.big li[data-edit]{cursor:pointer;transition:.2s}.vxapp .rows.big li[data-edit]:hover{border-color:rgba(130,160,255,.6)}
.vxapp .rows li.off{opacity:.55}.vxapp .rows small{display:block}.vxapp .rows li>span{color:var(--mut);font-size:.9rem}
.vxapp .irow{display:grid;grid-template-columns:1fr 64px 56px 100px 64px 24px;gap:6px;margin-bottom:6px}.vxapp .irow input,.vxapp .irow select{padding:8px;border-radius:8px;border:1px solid var(--line);background:var(--glass);color:inherit;min-width:0}@media(max-width:520px){.vxapp .irow{grid-template-columns:1fr 1fr}.vxapp .irow .id{grid-column:1/-1}}.beta{font-size:.6rem;font-weight:800;letter-spacing:.08em;background:#ffb347;color:#2a1a00;border-radius:6px;padding:1px 6px;margin-left:4px;vertical-align:middle}.betab{display:flex;gap:12px;justify-content:space-between;align-items:center;padding:10px 14px;margin:8px 0 12px;border-radius:12px;border:1px solid rgba(255,179,71,.5);background:rgba(255,179,71,.1);font-size:.9rem}.ready{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:16px 0}.ready h4{margin:0 0 6px}.ready .soonl li{opacity:.75}@media(max-width:520px){.ready{grid-template-columns:1fr}}.vxapp .inc{color:#3ddc97!important}.vxapp .late{color:#ff6b81!important;font-weight:700}.vxapp .stt{font-style:normal;padding:2px 8px;border-radius:99px;border:1px solid var(--line)}
.vxapp .bar2{display:flex;gap:10px;justify-content:space-between;margin:10px 0 14px;flex-wrap:wrap}
.vxapp .srch{flex:1;min-width:180px;max-width:360px;padding:10px 14px;border-radius:12px;border:1px solid var(--line);background:var(--glass);color:inherit}
.vxapp .lnk{background:none;border:0;text-decoration:underline;padding:0;color:inherit;cursor:pointer}
.vxapp .dh{margin:18px 0 8px;color:var(--mut)}.vxapp .dh.today{color:#6e8cff;font-weight:800}.vxapp .dh.past{opacity:.6}
.vxapp .chart{width:100%;height:auto}.vxapp .gl{stroke:var(--line)}.vxapp .ax{fill:var(--mut);font-size:11px}
.vxapp .bar{transform-box:fill-box;transform-origin:bottom;animation:grow .7s cubic-bezier(.2,.8,.2,1) both}.vxapp .b1{fill:#6e8cff}.vxapp .b2{fill:#2fd08f}.vxapp .b3{fill:#ff5a73}
@keyframes grow{from{transform:scaleY(0)}}
.vxapp .leg{display:flex;gap:16px;font-size:.85rem;color:var(--mut)}.vxapp .leg i{display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:6px}.vxapp .sb1{background:#6e8cff}.vxapp .sb2{background:#2fd08f}.vxapp .sb3{background:#ff5a73}
.vxapp .dn{display:flex;gap:14px;align-items:center;flex-wrap:wrap}.vxapp .seg{animation:segin .9s both}@keyframes segin{from{opacity:0}}
.vxapp .dnt{fill:var(--text);font-size:15px;font-weight:800}.vxapp .leg2{list-style:none;margin:0;padding:0;display:grid;gap:6px;font-size:.85rem}.vxapp .leg2 i{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:8px}
.vxapp .chks{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:8px;margin:12px 0}.vxapp fieldset{border:0;padding:0;margin:10px 0}
.vxapp .amodal{position:absolute;inset:0;background:rgba(0,0,0,.6);display:none;place-items:center;padding:16px;z-index:10;overflow:auto}.vxapp .amodal.on{display:grid}
.vxapp .mbox{width:min(600px,100%);background:var(--ink);border:1px solid var(--line);border-radius:18px;padding:20px;max-height:92vh;overflow:auto}
.vxapp textarea{width:100%;box-sizing:border-box;border-radius:12px;border:1px solid var(--line);background:var(--glass);color:inherit;padding:10px}
.vxapp .toast{position:fixed;left:50%;bottom:24px;transform:translate(-50%,30px);opacity:0;pointer-events:none;padding:12px 18px;border-radius:12px;background:#1e2a5a;color:#fff;transition:.3s;z-index:20;max-width:90vw}
.vxapp .toast.on{opacity:1;transform:translate(-50%,0)}.vxapp .toast.err{background:#a3243a}.vxapp .toast.ok{background:#1d7a55}
.vxapp .scrim{display:none}.vxapp .note{font-size:.92rem}.vxapp .dact{display:flex;gap:10px;flex-wrap:wrap;margin-top:14px}
@media(max-width:1100px){.dgrid{grid-template-columns:minmax(0,1fr)}.dr{position:static}.usr .un{display:none}}
@media(max-width:820px){
 .vxapp>aside{position:fixed;inset:0 auto 0 0;z-index:30;transform:translateX(-100%);transition:.3s;background:var(--ink)}
 .vxapp.side>aside{transform:none}.vxapp.side .scrim{display:block;position:fixed;inset:0;z-index:25;background:rgba(0,0,0,.5)}
 .vxapp .burger{display:grid}.vxmain header{padding:8px 12px;gap:6px}.vxapp main{padding:6px 12px 70px}.gs kbd,.webb{display:none}.greet h2{font-size:1.5rem}.gd{text-align:left}.qg{grid-template-columns:repeat(2,1fr)}
}
@media(prefers-reduced-motion:reduce){.vxapp .bar,.vxapp .seg,.vxapp .kpi,.spk i{animation:none}}
'''

tpl = r'''<!doctype html>
<html lang="cs" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Vexaronet – zakázky, rezervace a faktury pro malé firmy</title>
<meta name="description" content="Česká aplikace pro živnostníky a malé firmy: zákazníci, zakázky, kalendář se směnami, online rezervace, faktury a AI asistenti na jednom místě. Vyzkoušejte demo bez registrace.">
<meta name="theme-color" content="#03040a">
<link rel="canonical" href="https://vexaronet.com/">
<meta property="og:type" content="website"><meta property="og:locale" content="cs_CZ"><meta property="og:site_name" content="Vexaronet">
<meta property="og:title" content="Vexaronet – zakázky, rezervace a faktury pro malé firmy"><meta property="og:description" content="Zákazníci, zakázky, kalendář, online rezervace a faktury na jednom místě. Vyzkoušejte demo bez registrace.">
<meta property="og:url" content="https://vexaronet.com/"><meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Cdefs%3E%3ClinearGradient id='g' x1='0' y1='0' x2='1' y2='1'%3E%3Cstop offset='0' stop-color='%233b7bff'/%3E%3Cstop offset='1' stop-color='%238b5cf6'/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width='32' height='32' rx='8' fill='%2303040a'/%3E%3Cpath d='M7 9l9 15 9-15' fill='none' stroke='url(%23g)' stroke-width='3.4' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E">
<script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"Organization","name":"Vexaronet","url":"https://vexaronet.com/","email":"info@vexaronet.com"},{"@type":"WebSite","name":"Vexaronet","url":"https://vexaronet.com/","inLanguage":"cs"}]}</script>
<script>try{var t=localStorage.getItem('vx-theme');if(t==='light'||t==='dark')document.documentElement.setAttribute('data-theme',t)}catch(e){}</script>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700&family=Sora:wght@500;600;700;800&display=swap" rel="stylesheet">
<style>@@CSS@@</style>
</head>
<body>
<a class="skip" href="#obsah">Přeskočit na obsah</a>
<div class="bg" aria-hidden="true"><div class="b b1"></div><div class="b b2"></div><div class="b b3"></div><div class="grid"></div><div class="hot"></div><div class="vig"></div></div>

<header class="nav" id="nav"><div class="in">
  <a class="logo" href="#top" aria-label="Vexaronet – úvod"><svg viewBox="0 0 32 32" aria-hidden="true"><defs><linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5b9bff"/><stop offset="1" stop-color="#8b5cf6"/></linearGradient></defs><rect width="32" height="32" rx="9" fill="#0a0e24" stroke="rgba(150,175,255,.35)"/><path d="M7.5 9.5l8.5 14 8.5-14" fill="none" stroke="url(#lg)" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/></svg><span>Vexaronet<small>AI platforma</small></span></a>
  <nav class="links" aria-label="Hlavní navigace"><a href="#funkce">Funkce</a><a href="#ukazka">Ukázka</a><a href="#cenik">Ceník</a><a href="#postup">Vývoj</a><a href="#early">Novinky e-mailem</a></nav>
  <div class="nav-r">
    <button class="themeb" id="theme" type="button" aria-label="Přepnout světlý a tmavý režim"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 14.5A8 8 0 019.5 4 8 8 0 1020 14.5z"/></svg></button>
    <button class="btn btn-ghost btn-sm" id="acc" type="button">Přihlásit</button>
    <button class="btn btn-ghost btn-sm" type="button" data-early="">30 dní zdarma</button>
    <button class="btn btn-main btn-sm btn-demo" type="button" data-demo="1">▶ Vyzkoušet bez registrace</button>
    <button class="burger" id="burger" aria-label="Otevřít menu" aria-expanded="false" aria-controls="mnav"><i></i></button>
  </div>
</div></header>
<nav class="mnav" id="mnav" aria-label="Mobilní navigace"><a href="#funkce" style="--i:1">Funkce</a><a href="#ukazka" style="--i:2">Ukázka</a><a href="#cenik" style="--i:3">Ceník</a><a href="#postup" style="--i:4">Vývoj</a><a href="#early" style="--i:5">Novinky</a><a href="#prihlaseni" style="--i:6">Přihlásit se</a><a href="#demo" data-demo="1" style="--i:7">▶ Vyzkoušet bez registrace</a></nav>

<main id="obsah">
<section class="hero" id="top"><div class="wrap">
  <div>
    <span class="eyebrow fade">AI platforma pro podnikatele</span>
    <h1 id="h1">Celé podnikání v jednom systému. Řízené AI.</h1>
    <p class="sub fade d2">Vexaronet spojí faktury, zákazníky, zakázky, jednoduché weby, marketing a automatizaci na jednom místě. AI připravuje práci za vás, důležité kroky vždy schvalujete vy.</p>
    <div class="cta fade d3"><button class="btn btn-main btn-demo" type="button" data-demo="1">▶ Vyzkoušet bez registrace</button><button class="btn btn-ghost" type="button" data-early="">Vyzkoušet 30 dní zdarma</button><a class="btn btn-ghost" href="#funkce">Prohlédnout funkce</a></div>
    <div class="chips fade d3"><span>30 dní zdarma</span><span>START zdarma</span><span>Světlý i tmavý režim</span></div>
  </div>
  <div class="scene" id="scene"><div class="fit" id="fit"><div class="stage" id="stage"><div class="laptop" id="laptop">
    <div class="sh"></div>
    <div class="lid"><div class="screen"><button type="button" class="shotb" id="shotB" data-zoom="1" aria-label="Zvětšit ukázku přehledu v účtu"><img src="assets/prehled.webp" width="2160" height="1314" alt="Přehled firmy ve Vexaronetu: ukazatele, doporučení AI CEO a chat s AI CEO (ukázková data)" fetchpriority="high"></button><span class="sample">Ukázková data · kliknutím zvětšíte</span></div></div>
    <div class="base"><div class="keys">@@KEYS@@</div><div class="pad"></div></div><div class="edge"></div>
  </div>
  <div class="fl d">AI Autopilot</div><div class="fl e">Faktury a CRM</div>
  </div></div></div>
</div></section>

<div class="strip" aria-hidden="true"><div class="tr">
 <span>AI centrum</span><span>Faktury a účetnictví</span><span>CRM a zakázky</span><span>Jednoduché weby</span><span>Marketing</span><span>Automatizace</span>
 <span>AI centrum</span><span>Faktury a účetnictví</span><span>CRM a zakázky</span><span>Jednoduché weby</span><span>Marketing</span><span>Automatizace</span>
</div></div>

<section id="ucet"><div class="wrap">
  <div class="sec-h c" data-r="up"><span class="eyebrow">Přehled v účtu</span><h2>Takhle vypadá <span class="grad">váš účet</span></h2><p class="lead">Po přihlášení uvidíte na jednom místě ukazatele firmy, doporučení AI CEO a jeho chat. Obrázek je ze skutečné aplikace, jen s ukázkovými daty. Kliknutím ho zvětšíte.</p></div>
  <button type="button" class="appshot" data-zoom="1" data-r="up" aria-label="Zvětšit ukázku přehledu v účtu"><img src="assets/prehled.webp" width="2160" height="1314" loading="lazy" alt="Přehled firmy ve Vexaronetu: tržby, nezaplacené faktury, aktivní zakázky, doporučení AI CEO a chat s AI CEO (ukázková data)"></button>
  <div class="cta" style="justify-content:center;margin-top:22px"><button class="btn btn-main btn-demo" type="button" data-demo="1">▶ Vyzkoušet bez registrace</button></div>
  <p class="mut fine" style="text-align:center;margin-top:12px">Ukázková data. Aplikace je v rozpracované beta verzi, hotové části fungují se skutečnými daty, nehotové jsou označené „brzy“.</p>
</div></section>

<section id="funkce"><div class="wrap">
  <div class="sec-h" data-r="up"><span class="eyebrow">Funkce platformy</span><h2>Šest oblastí, <span class="grad">jeden systém</span></h2><p class="lead">Takhle je platforma navržená. Moduly se budou stavět po etapách a u každého je uvedeno, v jaké fázi je. Zatím není hotový žádný z nich, tento web je návrh úvodní stránky.</p></div>
  <div class="svcs">@@MODS@@</div>
</div></section>

<section id="ukazka"><div class="wrap">
  <div class="sec-h c" data-r="up"><span class="eyebrow">Interaktivní ukázka</span><h2>Takhle to <span class="grad">bude fungovat</span></h2><p class="lead">Dvě krátké ukázky principu. Jde o demonstraci s vymyšlenými daty, ne o skutečnou aplikaci.</p></div>
  <div class="demo">
    <div class="panel" data-r="up"><span class="tag-demo">Ukázka</span><h3>Dashboard podle oboru</h3><p class="sm">Při registraci vyberete typ podnikání a nabídka modulů se přizpůsobí.</p>
      <div class="bar" id="bizbar" role="group" aria-label="Typ podnikání">@@BIZ@@</div><div class="mods" id="mods"></div></div>
    <div class="panel" data-r="up" style="--d:.1s"><span class="tag-demo">Ukázka</span><h3>AI připraví, vy schválíte</h3><p class="sm">Důležité finanční, obchodní a externí akce bude AI provádět jen po schválení uživatelem.</p>
      <div class="act" id="a1"><b>Odeslat upomínku 3 klientům</b><small>Faktury po splatnosti, celkem 18 400 Kč (ukázka)</small><div class="bts"><button class="btn btn-main btn-sm" type="button" data-ap="ok">Schválit</button><button class="btn btn-ghost btn-sm" type="button" data-ap="no">Zamítnout</button></div><div class="res" hidden></div></div>
      <div class="act" id="a2"><b>Vystavit fakturu za zakázku č. 41</b><small>Částka 6 500 Kč (ukázka)</small><div class="bts"><button class="btn btn-main btn-sm" type="button" data-ap="ok">Schválit</button><button class="btn btn-ghost btn-sm" type="button" data-ap="no">Zamítnout</button></div><div class="res" hidden></div></div>
    </div>
  </div>
  <div class="warn" data-r="up"><b>Důležité upozornění:</b> účetnictví, daně a fakturace pro jednotlivé země nejsou legislativně ověřené. Před ostrým použitím bude nutná kontrola odborníkem. Funkce závislé na externích službách (platby, doprava, AI, domény) vyžadují jejich napojení a klíče.</div>
</div></section>

<section id="cenik"><div class="wrap">
  <div class="sec-h c" data-r="up"><span class="eyebrow">Ceník</span><h2>Jednoduchý ceník, <span class="grad">30 dní zdarma</span></h2><p class="lead">Začněte zdarma s tarifem START, nebo vyzkoušejte placené tarify 30 dní bez poplatku. Všechny ceny jsou měsíční bez DPH.</p></div>
  @@PLANS@@
</div></section>

<section id="postup"><div class="wrap">
  <div class="sec-h c" data-r="up"><span class="eyebrow">Postup vývoje</span><h2>Osm etap <span class="grad">k hotové platformě</span></h2><p class="lead">Stavíme po částech a každou etapu otestujeme. Stav je uveden otevřeně.</p></div>
  <div class="tl" id="tl"><div class="tl-f"></div>@@STAGES@@</div>
</div></section>

<section id="early"><div class="wrap contact">
  <div data-r="up"><span class="eyebrow">Novinky a stav vývoje</span><h2>Aplikace <span class="grad">se právě staví</span></h2><p class="lead">Vexaronet je rozpracovaná beta verze. Část už funguje a můžete ji vyzkoušet. Zbytek přidáváme po etapách. Nechte nám e-mail a napíšeme vám, až bude hotová další část.</p><div class="ready"><div><h4>Už funguje</h4><ul class="ticks"><li>Registrace, přihlášení, obnova hesla</li><li>Přehled firmy s grafy</li><li>Zákazníci, zakázky, kalendář, úkoly</li><li>Faktury a příjmy a výdaje (základ)</li><li>AI CEO: doporučení a chat</li></ul></div><div><h4>Připravujeme</h4><ul class="ticks soonl"><li>AI Účetní (po odborné kontrole)</li><li>Odesílání faktur a PDF</li><li>Jednoduché weby</li><li>Marketing a zaměstnanci</li><li>Automatizace</li></ul></div></div>
    <div class="ci"><a href="mailto:info@vexaronet.com"><small>E-mail</small><b>info@vexaronet.com</b></a><button type="button" class="btn btn-ghost" id="openChat" style="justify-content:flex-start">Zeptat se AI asistenta</button></div></div>
  <form class="card" id="form" name="early-access" data-r="up" novalidate>
    <p class="hp" aria-hidden="true"><label>Nevyplňovat <input name="bot-field" tabindex="-1" autocomplete="off"></label></p>
    <div class="fg">
      <div class="f"><label for="fName">Jméno <i>*</i></label><input id="fName" name="jmeno" required autocomplete="name"></div>
      <div class="f"><label for="fMail">E-mail <i>*</i></label><input id="fMail" name="email" type="email" required autocomplete="email" inputmode="email"></div>
      <div class="f"><label for="fCo">Firma (nepovinné)</label><input id="fCo" name="firma" autocomplete="organization"></div>
      <div class="f"><label for="fBiz">Typ podnikání</label><select id="fBiz" name="obor"><option value="">Vyberte</option>@@BIZOPTS@@</select></div>
      <div class="f full"><label for="fPlan">Zajímá mě tarif</label><select id="fPlan" name="tarif"><option value="">Zatím nevím</option><option>START (zdarma)</option><option>AI Účetní</option><option>PRO</option><option>BUSINESS</option><option>ENTERPRISE</option></select></div>
      <div class="f full"><label for="fMsg">Co by měla platforma umět především? (nepovinné)</label><textarea id="fMsg" name="zprava"></textarea></div>
      <div class="f full"><label class="chk"><input type="checkbox" name="souhlas" id="fOk" required><span>Souhlasím se zpracováním e-mailu a údajů za účelem informování o spuštění. <a href="#ochrana-udaju">Zásady ochrany osobních údajů</a> <i>*</i></span></label></div>
      <div class="f full"><button class="btn btn-main" type="submit" id="send">Odebírat novinky</button></div>
    </div>
    <div class="st" id="st" role="status" aria-live="polite"></div>
  </form>
</div></section>
</main>


<footer><div class="wrap">
  <div class="fg2">
    <div><a class="logo" href="#top" style="padding:0"><svg viewBox="0 0 32 32" aria-hidden="true"><rect width="32" height="32" rx="9" fill="#0a0e24" stroke="rgba(150,175,255,.35)"/><path d="M7.5 9.5l8.5 14 8.5-14" fill="none" stroke="url(#lg)" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/></svg><span>Vexaronet<small>AI platforma</small></span></a><p style="color:var(--mut);margin-top:14px;max-width:320px;font-size:.93rem">AI platforma pro podnikatele a firmy. Připravujeme pro ČR, Slovensko a postupně celou EU.</p></div>
    <div><h4>Navigace</h4><a href="#funkce">Funkce</a><a href="#ukazka">Ukázka</a><a href="#cenik">Ceník</a><a href="#postup">Vývoj</a><a href="#early">Novinky e-mailem</a></div>
    <div><h4>Informace</h4><button type="button" class="fl2" data-legal="ochrana-udaju">Ochrana osobních údajů</button><button type="button" class="fl2" data-legal="cookies">Cookies</button><a href="mailto:info@vexaronet.com">info@vexaronet.com</a></div>
  </div>
  <div class="copy"><span>© <span id="yr">2026</span> Vexaronet</span><span>vexaronet.com</span></div>
</div></footer>

<button class="fab" id="chatFab" type="button" aria-expanded="false" aria-controls="chat"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 5h16v11H9l-5 4z"/></svg><span class="t">AI asistent</span><i class="pulse"></i></button>
<div class="aichat" id="chat" role="dialog" aria-label="AI asistent Vexaronet"><div class="ch"><div><b>AI asistent</b><small>Odpovídá automaticky, jde o AI</small></div><button type="button" id="chatX" aria-label="Zavřít chat">✕</button></div><div id="chatBody" aria-live="polite"></div><div id="chatSugg"></div><form id="chatForm"><textarea id="chatIn" rows="1" placeholder="Napište dotaz…" aria-label="Vaše zpráva" maxlength="1000"></textarea><button type="submit" aria-label="Odeslat">➤</button></form><p class="ainote">Asistent může chybovat. Závazné jsou informace od týmu.</p></div>
<dialog id="dlg" aria-labelledby="dT"><div class="dlg" id="dBody"></div></dialog>
<noscript><style>[data-r]{opacity:1!important;transform:none!important}.hero h1 .w>span{transform:none}.fade{opacity:1;transform:none}</style></noscript>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js" defer></script>
<script type="application/json" id="modData">@@MODDATA@@</script>
<script type="application/json" id="bizData">@@BIZDATA@@</script>
<script>
(function(){'use strict';
var $=function(s,r){return (r||document).querySelector(s)},$$=function(s,r){return Array.prototype.slice.call((r||document).querySelectorAll(s))};
var RM=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
var MOD=JSON.parse($('#modData').textContent),BIZ=JSON.parse($('#bizData').textContent);
$('#yr').textContent=new Date().getFullYear();
function esc(s){return String(s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
(function(){var h=$('#h1');var t=h.textContent.trim();h.setAttribute('aria-label',t);var i=0;h.innerHTML=t.split(' ').map(function(w){i++;return '<span class="w" aria-hidden="true"><span style="--i:'+i+'">'+w+'</span></span>'}).join(' ')})();

/* motiv */
$('#theme').addEventListener('click',function(){var r=document.documentElement,n=r.getAttribute('data-theme')==='light'?'dark':'light';r.setAttribute('data-theme',n);try{localStorage.setItem('vx-theme',n)}catch(e){}});

/* scroll */
var nav=$('#nav'),pars=$$('[data-par]'),tl=$('#tl'),steps=$$('.step');
function onScroll(){var y=window.scrollY;nav.classList.toggle('sc',y>20);document.documentElement.style.setProperty('--gy',(-y*.3)+'px');
 if(!RM)pars.forEach(function(p){p.style.transform='translate3d(0,'+(y*parseFloat(p.dataset.par))+'px,0)'});
 var r=tl.getBoundingClientRect(),vh=window.innerHeight;tl.style.setProperty('--p',Math.min(1,Math.max(0,(vh*.6-r.top)/r.height)).toFixed(3));
 steps.forEach(function(s){s.classList.toggle('act',s.getBoundingClientRect().top<vh*.62)});
 var cur='';['funkce','ukazka','cenik','postup','early'].forEach(function(id){var e=document.getElementById(id);if(e&&e.getBoundingClientRect().top<vh*.4)cur=id});
 $$('.links a').forEach(function(a){a.classList.toggle('on',a.getAttribute('href')==='#'+cur)})}
var tick=false;window.addEventListener('scroll',function(){if(!tick){tick=true;requestAnimationFrame(function(){onScroll();tick=false})}},{passive:true});onScroll();
if(!RM)window.addEventListener('pointermove',function(e){var d=document.documentElement.style;d.setProperty('--cx',e.clientX+'px');d.setProperty('--cy',e.clientY+'px')},{passive:true});
document.addEventListener('pointermove',function(e){var c=e.target.closest&&e.target.closest('[data-glow]');if(c){var b=c.getBoundingClientRect();c.style.setProperty('--mx',(e.clientX-b.left)+'px');c.style.setProperty('--my',(e.clientY-b.top)+'px')}},{passive:true});

/* reveal */
var rv=$$('[data-r]');if('IntersectionObserver' in window&&!RM){var io=new IntersectionObserver(function(es){es.forEach(function(e){if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}})},{threshold:.12,rootMargin:'0px 0px -6% 0px'});rv.forEach(function(e){io.observe(e)})}else rv.forEach(function(e){e.classList.add('in')});

/* menu */
var bur=$('#burger'),mn=$('#mnav');
function menu(o){bur.setAttribute('aria-expanded',o);bur.setAttribute('aria-label',o?'Zavřít menu':'Otevřít menu');mn.classList.toggle('on',o);document.body.style.overflow=o?'hidden':''}
bur.addEventListener('click',function(){menu(bur.getAttribute('aria-expanded')!=='true')});$$('a',mn).forEach(function(a){a.addEventListener('click',function(){menu(false)})});
document.addEventListener('keydown',function(e){if(e.key==='Escape')menu(false)});

/* notebook */
var scene=$('#scene'),lap=$('#laptop');
function resize(){var s=Math.min(1,scene.clientWidth/640);document.documentElement.style.setProperty('--s',s.toFixed(3));scene.style.height=(540*s)+'px'}resize();window.addEventListener('resize',resize);
var tx=0,ty=0,cx=0,cy=0,last=0,t0=performance.now(),vis=true;
$('.hero').addEventListener('pointermove',function(e){var b=scene.getBoundingClientRect();tx=Math.max(-1.4,Math.min(1.4,(e.clientX-(b.left+b.width/2))/(b.width/2)));ty=Math.max(-1.4,Math.min(1.4,(e.clientY-(b.top+b.height/2))/(b.height/2)));last=performance.now()});
if('IntersectionObserver' in window)new IntersectionObserver(function(e){vis=e[0].isIntersecting}).observe(scene);
function loop(now){if(vis){var idle=now-last>2500,gx=idle?Math.sin((now-t0)/2400)*.8:tx,gy=idle?Math.cos((now-t0)/3100)*.35:ty;cx+=(gx-cx)*.07;cy+=(gy-cy)*.07;lap.style.setProperty('--ry',(cx*12).toFixed(2));lap.style.setProperty('--rx',(-cy*7).toFixed(2))}requestAnimationFrame(loop)}
if(!RM)requestAnimationFrame(loop);


/* zvětšení ukázky přehledu */
(function(){var zs=$$('[data-zoom]');if(!zs.length)return;var z=null,from=null;
function close(){if(z){z.classList.remove('on');document.documentElement.style.overflow='';if(from)from.focus()}}
zs.forEach(function(zb){zb.addEventListener('click',function(){from=zb;if(!z){z=document.createElement('div');z.id='zoomShot';z.setAttribute('role','dialog');z.setAttribute('aria-modal','true');z.setAttribute('aria-label','Ukázka přehledu v účtu');z.innerHTML='<button type="button" class="zx" aria-label="Zavřít">×</button><img src="assets/prehled.webp" alt="Přehled firmy ve Vexaronetu (ukázková data)"><p>Ukázková data. Takto vypadá přehled po přihlášení do účtu.</p>';document.body.appendChild(z);z.addEventListener('click',close)}
z.classList.add('on');document.documentElement.style.overflow='hidden'})});
document.addEventListener('keydown',function(e){if(e.key==='Escape'&&z&&z.classList.contains('on'))close()})})();

/* ukázka: obor */
var mods=$('#mods');
function showBiz(k){mods.innerHTML=BIZ[k].map(function(m,i){return '<div style="animation-delay:'+(i*.07)+'s">'+esc(m)+'</div>'}).join('')}
$('#bizbar').addEventListener('click',function(e){var b=e.target.closest('button');if(!b)return;$$('#bizbar button').forEach(function(x){x.setAttribute('aria-pressed',x===b)});showBiz(b.dataset.biz)});showBiz(Object.keys(BIZ)[0]);
/* ukázka: schvalování */
$$('.act').forEach(function(a){a.addEventListener('click',function(e){var b=e.target.closest('[data-ap]');if(!b)return;var ok=b.dataset.ap==='ok';a.classList.remove('ok','no');a.classList.add(ok?'ok':'no');$('.bts',a).hidden=true;var r=$('.res',a);r.hidden=false;r.textContent=ok?'Schváleno uživatelem. V ostré verzi by se akce provedla. Tady jde jen o ukázku, nic se neodeslalo.':'Zamítnuto. AI akci neprovede.'})});

/* dialogy */
var dlg=$('#dlg'),dB=$('#dBody'),lastFocus=null;
function openD(h){lastFocus=document.activeElement;dB.innerHTML='<button class="dx" type="button" aria-label="Zavřít">×</button>'+h;if(!dlg.open){if(dlg.showModal)dlg.showModal();else dlg.setAttribute('open','')}$('.dx',dB).focus();dB.scrollTop=0}
function closeDlg(){if(dlg.open)dlg.close()}
dlg.addEventListener('click',function(e){if(e.target===dlg||e.target.closest('.dx')||e.target.closest('[data-close]'))closeDlg()});
dlg.addEventListener('close',function(){if(/^#(modul|ochrana|cookies|prihlaseni)/.test(location.hash))history.replaceState(null,'',location.pathname+location.search);if(lastFocus&&lastFocus.focus)lastFocus.focus({preventScroll:true})});
function showMod(id){var m=MOD[id];if(!m)return;openD('<span class="eyebrow">Modul · etapa '+m.stage+'</span><h2 id="dT">'+esc(m.name)+'</h2><p>'+esc(m.short)+'</p><h3>Plánované funkce</h3><ul class="ticks">'+m.items.map(function(i){return '<li>'+esc(i)+'</li>'}).join('')+'</ul><div class="draft">Stav: plánováno. Modul zatím není vytvořený a nejde ho použít. Důležité akce AI budou vyžadovat schválení uživatele.</div><div class="dact"><button class="btn btn-main" type="button" data-early="">Chci early access</button><button class="btn btn-ghost" type="button" data-app="mclose">Zavřít</button></div>')}
var LEGAL={'ochrana-udaju':'<span class="eyebrow">Právní informace</span><h2 id="dT">Ochrana osobních údajů</h2><div class="draft">Pracovní návrh textu. Před zveřejněním je nutné ho zkontrolovat a doplnit skutečnými údaji provozovatele.</div><h3>Správce údajů</h3><p>[Doplňte: jméno / obchodní firma, IČO, sídlo, kontaktní e-mail]</p><h3>Jaké údaje zpracováváme</h3><p>Údaje z formuláře early access: jméno, e-mail, firma, typ podnikání, zpráva.</p><h3>Účel a právní základ</h3><p>Informování o spuštění platformy. [Doplňte právní základ a dobu uchování.]</p><h3>Příjemci</h3><p>Poskytovatelé technických služeb: hosting a síť – Cloudflare; databáze a přihlášení – Supabase; odesílání e-mailů – Resend; AI asistent – Google (jazykový model). [Doplňte úplný seznam a sídla poskytovatelů.]</p><h3>Vaše práva</h3><p>Přístup, oprava, výmaz, omezení, námitka a stížnost u dozorového úřadu. [Doplňte kontakt.]</p>','cookies':'<span class="eyebrow">Právní informace</span><h2 id="dT">Informace o cookies</h2><div class="draft">Pracovní návrh textu. Před zveřejněním ho zkontrolujte.</div><p>Web nepoužívá analytické ani reklamní cookies. Prohlížeč si lokálně pamatuje zvolený světlý nebo tmavý režim a historii chatu v rámci karty (úložiště prohlížeče, ne cookies).</p>'};
function showLegal(k){if(LEGAL[k])openD(LEGAL[k]+'<div class="dact"><button class="btn btn-ghost" type="button" data-app="mclose">Zavřít</button></div>')}
function route(){var h=location.hash,m;if(h==='#prihlaseni')showAuth('login');else if(m=h.match(/^#modul-(\w+)/))showMod(m[1]);else if(h==='#ochrana-udaju'||h==='#cookies')showLegal(h.slice(1))}
document.addEventListener('click',function(e){
 var a=e.target.closest('[data-mod]');if(a){e.preventDefault();history.replaceState(null,'','#modul-'+a.dataset.mod);showMod(a.dataset.mod);return}
 var l=e.target.closest('[data-legal]');if(l){history.replaceState(null,'','#'+l.dataset.legal);showLegal(l.dataset.legal);return}
 var lk=e.target.closest('a[href="#ochrana-udaju"]');if(lk){e.preventDefault();history.replaceState(null,'','#ochrana-udaju');showLegal('ochrana-udaju');return}
 var p=e.target.closest('[data-early]');if(p){e.preventDefault();showAuth('signup');if(p.dataset.early&&$('#aPlan'))$('#aPlan').value=p.dataset.early}});
document.addEventListener('click',function(e){var b=e.target.closest('[data-bill]');if(!b)return;var y=b.dataset.bill==='y';[].forEach.call(document.querySelectorAll('[data-bill]'),function(x){x.setAttribute('aria-pressed',x===b)});[].forEach.call(document.querySelectorAll('.pp[data-m]'),function(el){el.textContent=(y?el.dataset.y:el.dataset.m)+' Kč'});[].forEach.call(document.querySelectorAll('.pn[data-m]'),function(el){el.textContent=y?el.dataset.y:el.dataset.m})});
window.addEventListener('hashchange',route);setTimeout(route,0);
if(location.pathname.replace(/\/$/,'')==='/cenik')setTimeout(function(){var c=document.getElementById('cenik');if(c)c.scrollIntoView()},400);

/* formulář */
var form=$('#form'),st=$('#st'),sendB=$('#send'),loadT=Date.now();
function msg(t,c){st.className='st '+c;st.textContent=t}
form.addEventListener('submit',function(e){e.preventDefault();var f=form.elements;
 if(!f.jmeno.value.trim()||!f.email.value.trim()){msg('Vyplňte prosím jméno a e-mail.','err');return}
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.email.value.trim())){msg('Zkontrolujte prosím formát e-mailu.','err');return}
 if(!f.souhlas.checked){msg('Pro odeslání je nutný souhlas se zpracováním údajů.','err');return}
 if(f['bot-field'].value||Date.now()-loadT<2500){msg('Odeslání se nepodařilo ověřit. Zkuste to prosím znovu.','err');return}
 sendB.disabled=true;sendB.textContent='Odesílám…';st.className='st';
 fetch('/api/subscribe',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:f.email.value.trim(),name:f.jmeno.value.trim(),company:f.firma.value.trim(),business_type:f.obor.value,interested_plan:f.tarif.value,message:f.zprava.value.trim(),consent:true,hp:f['bot-field'].value})}).then(function(r){if(!r.ok)throw new Error(r.status);return r.json()}).then(function(d){msg((d&&d.duplicate?'Tento e-mail už novinky odebírá. Děkujeme!':'Děkujeme, e-mail jsme uložili. O novinkách vám dáme vědět.')+(d&&d.mail&&d.mail!=='sent'&&!d.duplicate?' [diagnostika e-mailu: '+d.mail+']':''),'ok');form.reset()}).catch(function(er){msg('Odeslání se teď nepodařilo (chyba '+((er&&er.message)||'síť')+'). Napište nám prosím na info@vexaronet.com.','err')}).then(function(){sendB.disabled=false;sendB.textContent='Odebírat novinky'})});


/* ===== Supabase: registrace a přihlášení ===== */
var SB_URL='https://micymdbqgzeckiqyvvkn.supabase.co';
var SB_KEY='sb_publishable_Owl1zZ5ZoGJVPxkjRVAOJw_8O6mLDwW'; /* veřejný (publishable) klíč, smí být ve webu */
var PLAN_OPTS=[['pro','Vexaronet PRO – 699 Kč / měsíc'],['accountant','AI Účetní – 399 Kč / měsíc'],['business','Vexaronet BUSINESS – 1 199 Kč / měsíc'],['start','START – zdarma']];
var PLAN_ALLOWED=['start','accountant','pro','business','enterprise'],LEGACY={'VEXARONET PRO':'pro','AI ÚČETNÍ':'accountant','STARTER':'start','PRO':'pro','BUSINESS':'business'};
function planVal(x){x=LEGACY[x]||x;return PLAN_ALLOWED.indexOf(x)>=0?x:'pro'}
var TERMS_VERSION='2026-10';
var sb=null;
function getSb(){if(DEMO)return demoSb();if(sb)return sb;if(window.supabase&&window.supabase.createClient){sb=window.supabase.createClient(SB_URL,SB_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}})}return sb}
var accB=$('#acc');
function setAcc(on){accB.textContent=on?'Otevřít účet':'Přihlásit'}
window.addEventListener('load',function(){var c=getSb();if(c)c.auth.getSession().then(function(r){setAcc(!!(r.data&&r.data.session))}).catch(function(){});if(c)c.auth.onAuthStateChange(function(ev,ses){setAcc(!!ses);if(ev==='PASSWORD_RECOVERY')setTimeout(function(){showAuth('newpw')},0)})});
function authForm(mode){
 var plans=PLAN_OPTS.map(function(p){return '<option value="'+p[0]+'">'+p[1]+'</option>'}).join('');
 var biz=Object.keys(BIZ).map(function(b){return '<option>'+esc(b)+'</option>'}).join('');
 var tabs='<div class="bar" role="tablist"><button type="button" class="chipb" data-auth="login" aria-pressed="'+(mode==='login')+'">Přihlášení</button><button type="button" class="chipb" data-auth="signup" aria-pressed="'+(mode==='signup')+'">Registrace na 30 dní zdarma</button></div>';
 if(mode==='reset')return '<span class="eyebrow">Účet</span><h2 id="dT">Obnovení hesla</h2><p>Zadejte e-mail a pošleme vám odkaz pro nastavení nového hesla.</p><form id="authForm" novalidate><div class="fg"><div class="f full"><label for="aMail">E-mail <i>*</i></label><input id="aMail" type="email" autocomplete="email" required></div><div class="f full"><button class="btn btn-main" type="submit" id="aGo">Poslat odkaz</button> <button class="btn btn-ghost" type="button" data-auth="login">Zpět na přihlášení</button></div></div><div class="st" id="aSt" role="status" aria-live="polite"></div></form>';
 if(mode==='newpw')return '<span class="eyebrow">Účet</span><h2 id="dT">Nové heslo</h2><form id="authForm" novalidate><div class="fg"><div class="f full"><label for="aPw">Nové heslo (alespoň 8 znaků) <i>*</i></label><input id="aPw" type="password" autocomplete="new-password" minlength="8" required></div><div class="f full"><button class="btn btn-main" type="submit" id="aGo">Uložit heslo</button></div></div><div class="st" id="aSt" role="status" aria-live="polite"></div></form>';
 var feats=FEATS_SU.map(function(f){return '<label class="chk"><input type="checkbox" name="aFt" value="'+f[0]+'"><span>'+f[1]+'</span></label>'}).join('');
 return '<span class="eyebrow">Účet</span><h2 id="dT">'+(mode==='login'?'Přihlášení':'Vyzkoušet 30 dní zdarma')+'</h2>'+tabs
 +'<form id="authForm" novalidate><div class="fg">'
 +(mode==='signup'?'<div class="f"><label for="aName">Jméno a příjmení <i>*</i></label><input id="aName" autocomplete="name" required></div><div class="f"><label for="aCo">Název firmy <i>*</i></label><input id="aCo" autocomplete="organization" required></div><div class="f full"><label class="chk"><input type="checkbox" id="aInv"><span>Jsem pozvaný/á do firmy svého zaměstnavatele (firmu zakládat nechci). Registruji se e-mailem, na který pozvánka přišla.</span></label></div><div class="f"><label for="aCt">Stát</label><select id="aCt"><option>Česko</option><option>Slovensko</option><option>Jiná země</option></select></div><div class="f"><label for="aBiz">Obor podnikání</label><select id="aBiz">'+biz+'</select></div><div class="f full"><label for="aPlan">Tarif (placené tarify 30 dní zdarma, bez platební karty)</label><select id="aPlan">'+plans+'</select></div><div class="f full"><label>Které funkce chcete používat?</label><div class="chks">'+feats+'</div></div>':'')
 +'<div class="f '+(mode==='login'?'full':'')+'"><label for="aMail">E-mail <i>*</i></label><input id="aMail" type="email" autocomplete="email" required></div>'
 +'<div class="f '+(mode==='login'?'full':'')+'"><label for="aPw">Heslo <i>*</i></label><input id="aPw" type="password" autocomplete="'+(mode==='login'?'current-password':'new-password')+'" minlength="8" required></div>'
 +(mode==='signup'?'<div class="f full"><label class="chk"><input type="checkbox" id="aOk"><span>Souhlasím s podmínkami a se zpracováním osobních údajů. <i>*</i></span></label></div>':'')
 +'<div class="f full"><button class="btn btn-main" type="submit" id="aGo">'+(mode==='login'?'Přihlásit se':'Založit účet na 30 dní zdarma')+'</button>'+(mode==='login'?' <button class="btn btn-ghost" type="button" data-auth="reset">Zapomenuté heslo</button>':'')+'</div></div><div class="st" id="aSt" role="status" aria-live="polite"></div></form>';
}
var FEATS_SU=[['zakaznici','Zákazníci (CRM)'],['zakazky','Zakázky a úkoly'],['kalendar','Kalendář a rezervace'],['faktury','Faktury a finance'],['ai','AI poradce'],['zamestnanci','Zaměstnanci'],['weby','Jednoduchý web'],['marketing','Marketing'],['automatizace','Automatizace']];
function showAuth(mode){openD(authForm(mode||'login'))}
function aMsg(t,c){var e=$('#aSt');if(e){e.className='st '+c;e.textContent=t}}
function niceErr(e){var m=(e&&e.message)||String(e);if(/check constraint|violates/i.test(m))return 'Vybraný tarif zatím není v databázi povolený. Napište na info@vexaronet.com.';if(/Invalid login/i.test(m))return 'Nesprávný e-mail nebo heslo.';if(/already registered|already been/i.test(m))return 'Tento e-mail už je zaregistrovaný. Přihlaste se.';if(/Email not confirmed/i.test(m))return 'E-mail zatím není potvrzený. Klikněte na odkaz v e-mailu, který jsme poslali.';if(/rate limit/i.test(m))return 'Příliš mnoho pokusů. Zkuste to později.';return 'Chyba: '+m}
async function ensureCompany(c,user){
 var r=await c.from('company_members').select('company_id').eq('user_id',user.id).limit(1);
 if(r.error)throw r.error;
 if(r.data&&r.data.length)return r.data[0].company_id;
 try{var ai=await c.rpc('accept_company_invites');if(!ai.error&&ai.data>0){var r3=await c.from('company_members').select('company_id').eq('user_id',user.id).limit(1);if(r3.data&&r3.data.length)return r3.data[0].company_id}}catch(x){}
 var md=user.user_metadata||{};if(!md.company_name)return null;
 var a=await c.rpc('record_registration_acceptance',{version:TERMS_VERSION,accepted:true});if(a.error)throw a.error;
 var k=await c.rpc('create_company_for_plan',{company_name:md.company_name,company_industry:md.industry||'',selected_plan:planVal(md.plan)});
 if(k.error)throw k.error;
 var r2=await c.from('company_members').select('company_id').eq('user_id',user.id).limit(1);
 return r2.data&&r2.data[0]?r2.data[0].company_id:(typeof k.data==='string'?k.data:null)}
function kv(o){if(o==null)return '<p>Žádná data.</p>';if(typeof o!=='object')return '<p>'+esc(o)+'</p>';var rows=Array.isArray(o)?o.map(function(x,i){return [i+1,x]}):Object.keys(o).map(function(k){return [k,o[k]]});return '<ul class="ticks">'+rows.map(function(r){var v=r[1];return '<li><b>'+esc(r[0])+':</b> '+esc(typeof v==='object'?JSON.stringify(v):v)+'</li>'}).join('')+'</ul>'}
async function showAccount(){
 var c=getSb();openD('<span class="eyebrow">Účet</span><h2 id="dT">Můj účet</h2><p>Načítám…</p>');
 try{
  var u=(await c.auth.getUser()).data.user;if(!u){showAuth('login');return}
  var cid=await ensureCompany(c,u);var h='<span class="eyebrow">Účet</span><h2 id="dT">Můj účet</h2><p>'+esc(u.email)+'</p>';
  if(!cid){h+='<div class="draft">K účtu zatím není přiřazená žádná firma.</div>'}
  else{
   var co=await c.from('companies').select('name,industry').eq('id',cid).limit(1);
   var sub=await c.from('subscriptions').select('plan,status,trial_end,paid_until').eq('company_id',cid).limit(1);
   if(co.data&&co.data[0])h+='<h3>Firma</h3><p>'+esc(co.data[0].name)+(co.data[0].industry?' ('+esc(co.data[0].industry)+')':'')+'</p>';
   if(sub.data&&sub.data[0]){var s=sub.data[0],left='';if(s.trial_end){var d=Math.ceil((new Date(s.trial_end)-new Date())/864e5);left=d>0?'Zbývá '+d+' dní zkušebního období.':'Zkušební období skončilo.'}h+='<h3>Předplatné</h3><p>Tarif: '+esc(s.plan)+', stav: '+esc(s.status)+'. '+left+'</p>'}
   var ds=await c.rpc('dashboard_summary',{cid:cid});
   h+='<h3>Přehled firmy (data z databáze)</h3>'+(ds.error?'<p>Přehled se nepodařilo načíst: '+esc(ds.error.message)+'</p>':kv(ds.data));
  }
  h+='<div class="dact"><button class="btn btn-main" type="button" id="openApp">Otevřít aplikaci</button><button class="btn btn-ghost" type="button" id="logout">Odhlásit se</button></div>';
  dB.innerHTML='<button class="dx" type="button" aria-label="Zavřít">×</button>'+h;
 }catch(e){dB.innerHTML='<button class="dx" type="button" aria-label="Zavřít">×</button><span class="eyebrow">Účet</span><h2 id="dT">Můj účet</h2><div class="draft">'+esc(niceErr(e))+'</div><div class="dact"><button class="btn btn-ghost" type="button" id="logout">Odhlásit se</button></div>'}}
accB.addEventListener('click',async function(){var c=getSb();if(!c){showAuth('login');setTimeout(function(){aMsg('Přihlášení se nepodařilo načíst. Zkontrolujte připojení.','err')},50);return}var r=await c.auth.getSession();if(r.data&&r.data.session)openApp();else showAuth('login')});
$('#mnav').addEventListener('click',function(e){if(e.target.getAttribute('href')==='#prihlaseni'){e.preventDefault();menu(false);var c=getSb();if(c)c.auth.getSession().then(function(r){if(r.data&&r.data.session)openApp();else showAuth('login')});else showAuth('login')}});
document.addEventListener('click',async function(e){
 var t=e.target.closest('[data-auth]');if(t){showAuth(t.dataset.auth);return}
 if(e.target.closest('#logout')){var c=getSb();if(c)await c.auth.signOut();closeDlg()}});
document.addEventListener('submit',async function(e){
 if(e.target.id!=='authForm')return;e.preventDefault();var c=getSb();
 if(!c){aMsg('Služba přihlášení není dostupná. Zkuste to později.','err');return}
 var signup=!!$('#aName'),reset=!$('#aPw'),newpw=!$('#aMail'),mail=newpw?'':$('#aMail').value.trim(),pw=reset?'':$('#aPw').value,b=$('#aGo');
 if(!newpw&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mail)){aMsg('Zkontrolujte formát e-mailu.','err');return}
 if(!reset&&pw.length<8){aMsg('Heslo musí mít alespoň 8 znaků.','err');return}
 if(signup&&(!$('#aName').value.trim()||(!$('#aCo').value.trim()&&!$('#aInv').checked))){aMsg('Vyplňte jméno a název firmy (pozvaní zaškrtnou pole o pozvánce).','err');return}
 if(signup&&!$('#aOk').checked){aMsg('Pro registraci je nutný souhlas s podmínkami.','err');return}
 b.disabled=true;aMsg('Zpracovávám…','ok');
 try{
  if(reset){var rr=await c.auth.resetPasswordForEmail(mail,{redirectTo:location.origin+'/'});if(rr.error)throw rr.error;aMsg('Pokud je e-mail zaregistrovaný, poslali jsme na něj odkaz pro nové heslo.','ok')}
  else if(newpw){var up=await c.auth.updateUser({password:pw});if(up.error)throw up.error;history.replaceState(null,'',location.pathname);await openApp()}
  else if(signup){
   var ft=[].map.call(document.querySelectorAll('input[name=aFt]:checked'),function(x){return x.value});
   var r=await c.auth.signUp({email:mail,password:pw,options:{emailRedirectTo:location.origin+'/',data:{full_name:$('#aName').value.trim(),company_name:$('#aInv').checked?'':$('#aCo').value.trim(),invited:$('#aInv').checked,industry:$('#aBiz').value,plan:$('#aPlan').value,country:$('#aCt').value,features:ft,onboarded:true}}});
   if(r.error)throw r.error;
   if(r.data&&r.data.session){await openApp()}else{aMsg('Účet je vytvořený. Poslali jsme vám e-mail, potvrďte ho a pak se přihlaste. 30denní zkušební období začne po prvním přihlášení.','ok')}
  }else{
   var l=await c.auth.signInWithPassword({email:mail,password:pw});if(l.error)throw l.error;await openApp()}
 }catch(err){aMsg(niceErr(err),'err')}
 b.disabled=false});

/* ===== Aplikace po přihlášení ===== */
var APP={cid:null,co:'',ind:'',tab:'prehled',user:null,meta:{},role:null,sub:null,d:null,chat:[],busy:false};
var FEATS=[['zakaznici','Zákazníci (CRM)'],['zakazky','Zakázky a úkoly'],['kalendar','Kalendář a rezervace'],['faktury','Faktury a finance'],['ai','AI CEO'],['zamestnanci','Zaměstnanci'],['weby','Jednoduchý web'],['marketing','Marketing'],['automatizace','Automatizace']];
var COUNTRIES=['Česko','Slovensko','Jiná země'];
var IC={online:'M12 3a9 9 0 100 18 9 9 0 000-18zM3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18',prehled:'M3 12l9-8 9 8M5 10v10h5v-6h4v6h5V10',zakaznici:'M16 11a4 4 0 10-8 0 4 4 0 008 0zM4 21c0-4 4-6 8-6s8 2 8 6',zakazky:'M4 7h16v13H4zM9 7V4h6v3',kalendar:'M4 6h16v14H4zM4 10h16M8 3v4M16 3v4',ukoly:'M5 12l4 4 10-10',faktury:'M6 3h9l4 4v14H6zM9 12h7M9 16h7',ceo:'M12 3l2 5 5 2-5 2-2 5-2-5-5-2 5-2z',ucetni:'M6 3h12v18H6zM9 7h6M9 11h6M9 15h3',zamestnanci:'M8 11a3 3 0 100-6 3 3 0 000 6zM16 12a3 3 0 100-6M2 20c0-3 3-5 6-5s6 2 6 5M16 15c3 0 6 1 6 5',weby:'M3 5h18v14H3zM3 9h18',marketing:'M4 14V10l12-5v14zM16 9a3 3 0 010 6',automatizace:'M13 2L4 14h7l-1 8 9-12h-7z',sklad:'M3 8l9-5 9 5v10l-9 5-9-5zM3 8l9 5 9-5',finance:'M4 19V9M10 19V5M16 19v-7M22 19H2',reporty:'M5 20V10M12 20V4M19 20v-8',profil:'M12 15a3 3 0 100-6 3 3 0 000 6zM19 12l2-1-2-4-2 1-2-1V5h-4v2l-2 1-2-1-2 4 2 1v2l-2 1 2 4 2-1 2 1v2h4v-2l2-1 2 1 2-4-2-1z',bell:'M6 17V11a6 6 0 1112 0v6l2 2H4zM10 21h4',menu:'M4 6h16M4 12h16M4 18h16',sun:'M12 8a4 4 0 100 8 4 4 0 000-8zM12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M5 19l1.5-1.5M17.5 6.5L19 5',plus:'M12 5v14M5 12h14',search:'M11 18a7 7 0 100-14 7 7 0 000 14zM21 21l-5-5',send:'M3 11l18-8-8 18-2-8z',warn:'M12 4l9 16H3zM12 10v4M12 17v1',tr:'M4 17l6-6 4 4 6-8'};
function ico(k,s){return '<svg viewBox="0 0 24 24" width="'+(s||20)+'" height="'+(s||20)+'" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="'+IC[k]+'"/></svg>'}
var NAV=[['prehled','Přehled'],['ceo','AI CEO'],['ucetni','AI Účetní'],['zakaznici','CRM a zákazníci'],['zakazky','Zakázky a projekty'],['ukoly','Úkoly'],['faktury','Fakturace'],['finance','Finance'],['kalendar','Kalendář a rezervace'],['online','Online rezervace'],['weby','Jednoduchý web'],['marketing','Marketing'],['zamestnanci','Zaměstnanci']];
var SOON={sklad:['Sklad a produkty','Evidence skladu materiálu a produktů.',6],reporty:['Reporty','Přehledy výkonnosti firmy.',7],automatizace:['Automatizace','Pracovní postupy propojující moduly.',5]};
var PLANN={start:'START',starter:'START',accountant:'AI Účetní',ucetni:'AI Účetní',pro:'Vexaronet PRO',business:'Vexaronet BUSINESS',enterprise:'ENTERPRISE'},STATN={demo:'ukázka',trial:'zkušební období',active:'aktivní',past_due:'po splatnosti',canceled:'zrušeno',expired:'vypršelo'};
var PLANLIM={start:'CRM max. 50 zákazníků, 10 zakázek, 10 faktur měsíčně, 1 uživatel. Bez AI CEO.',accountant:'1 uživatel + 1 externí účetní, 100 AI vytěžených dokladů měsíčně (funkce se připravují).',pro:'3 uživatelé, 150 AI dokladů a 500 AI akcí měsíčně, 1 web nebo e-shop, 1 firma (limity se uplatní s příslušnými funkcemi).',business:'10 uživatelů, 500 AI dokladů a 2 000 AI akcí měsíčně, 3 weby nebo e-shopy (limity se uplatní s příslušnými funkcemi).',enterprise:'Individuální limity podle dohody.'};
function effPlan(){var s=APP.sub;if(!s)return 'start';var p=String(s.plan||'').toLowerCase();if(p==='starter')p='start';if(p==='ucetni')p='accountant';if(p==='start')return p;var ended=(s.status==='trial'&&s.trial_end&&new Date(s.trial_end)<new Date())||s.status==='expired'||s.status==='canceled';return ended?'start':p}
function hasCeo(){return ['pro','business','enterprise'].indexOf(effPlan())>=0}
var TEAMLIM={start:1,accountant:2,pro:3,business:10,enterprise:1000},ROLEN={owner:'Majitel',admin:'Správce',employee:'Zaměstnanec'};
function allowed(t){var p=effPlan();if(APP.role==='employee'&&['prehled','zakaznici','zakazky','ukoly','kalendar','profil'].indexOf(t)<0)return false;if(p==='start')return ['prehled','zakaznici','zakazky','ukoly','faktury','finance','kalendar','online','profil'].indexOf(t)>=0;if(p==='accountant')return ['prehled','ucetni','faktury','finance','zamestnanci','profil'].indexOf(t)>=0;return true}
function limitMsg(k){if(effPlan()!=='start')return '';var d=APP.d;if(k==='customers'&&d.customers.rows.length>=50)return 'Tarif START umožňuje nejvýše 50 zákazníků.';if(k==='jobs'&&d.jobs.rows.length>=10)return 'Tarif START umožňuje evidovat nejvýše 10 zakázek.';if(k==='invoices'){var m=new Date(new Date().getFullYear(),new Date().getMonth(),1);if(d.invoices.rows.filter(function(x){return new Date(x.issued_on||x.created_at)>=m}).length>=10)return 'Tarif START umožňuje nejvýše 10 faktur měsíčně.'}return ''}
function fD(s,t){if(!s)return '–';var d=new Date(s);if(isNaN(d))return esc(s);return t?d.toLocaleString('cs-CZ',{day:'numeric',month:'numeric',year:'numeric',hour:'2-digit',minute:'2-digit'}):d.toLocaleDateString('cs-CZ')}
function fM(n,cur){if(n==null||n==='')return '–';return Number(n).toLocaleString('cs-CZ',{maximumFractionDigits:2})+' '+esc(!cur||cur==='CZK'?'Kč':cur)}
function custName(r){if(!r)return '';return r.name||r.company_name||[r.first_name,r.last_name].filter(Boolean).join(' ')||r.full_name||r.email||'(bez jména)'}
function loc(s){var d=new Date(s);if(isNaN(d))return '';d=new Date(d-d.getTimezoneOffset()*6e4);return d.toISOString().slice(0,16)}
function locD(s){var d=new Date(s);if(isNaN(d))return '';d=new Date(d-d.getTimezoneOffset()*6e4);return d.toISOString().slice(0,10)}
function A(id){return document.getElementById(id)}
function toast(t,c){var e=A('appToast');if(!e)return;e.textContent=t;e.className='toast on '+(c||'');clearTimeout(toast.t);toast.t=setTimeout(function(){e.className='toast'},4200)}
function dayStart(o){var d=new Date();d.setHours(0,0,0,0);d.setDate(d.getDate()+(o||0));return d}
var DONE=/done|hotov|dokon|complet|closed|cancel|zruš|zaplac|paid/i;


/* ===== Ukázka bez registrace (DEMO) ===== */
var DEMO=false,DS=null,DD=null;
function demoData(){
 var n=Date.now(),D86=864e5,iso=function(o){return new Date(n+o*D86).toISOString()},day=function(o){return iso(o).slice(0,10)},at=function(o,h){var d=new Date(n+o*D86);d.setHours(h,0,0,0);return d.toISOString()};
 var C='demo',cs=[['u1','Novák Auto s.r.o.','info@novakauto.cz','602 111 222',-200],['u2','Stavby Dvořák','dvorak@stavbydvorak.cz','603 222 333',-170],['u3','Kavárna U Lípy','kavarna@ulipy.cz','604 333 444',-120],['u4','Pekárna Svoboda','svoboda@pekarna.cz','605 444 555',-80],['u5','Eva Horáková','eva.horakova@email.cz','606 555 666',-30],['u6','Truhlářství Marek','marek@truhlarstvi.cz','607 666 777',-9]].map(function(x){return {id:x[0],company_id:C,name:x[1],email:x[2],phone:x[3],created_at:iso(x[4])}});
 var js=[['j1','Pravidelný servis flotily (5 vozidel)','u1',48500,3,'rozpracováno'],['j2','Výměna brzd a kotoučů','u5',9800,1,'rozpracováno'],['j3','Diagnostika a oprava elektroinstalace','u2',15200,6,'nové'],['j4','Sezónní přezutí pneumatik','u3',3600,-4,'hotovo'],['j5','Výměna rozvodů','u4',22400,10,'nové'],['j6','Příprava vozu k STK','u6',4200,-12,'hotovo'],['j7','Výměna spojky','u2',18900,-17,'hotovo'],['j8','Pravidelná kontrola brzd','u1',6400,14,'nové'],['j9','Oprava klimatizace','u3',7800,19,'nové']].map(function(x){return {id:x[0],company_id:C,title:x[1],customer_id:x[2],price:x[3],due_at:at(x[4],12),status:x[5],created_at:iso(-20)}});
 var rs=[['r1','Prohlídka vozu – Eva Horáková','u5',0,9],['r2','Přezutí – Kavárna U Lípy','u3',0,13],['r3','Servis dodávky – Stavby Dvořák','u2',1,8],['r4','Diagnostika – Novák Auto','u1',2,10],['r5','Příjem vozu – Pekárna Svoboda','u4',4,11],['r6','Přezutí – Truhlářství Marek','u6',-9,10],['r7','Výměna oleje – Eva Horáková','u5',-5,14],['r8','Diagnostika – Stavby Dvořák','u2',6,9],['r9','Prohlídka vozu – Kavárna U Lípy','u3',8,15],['r10','Servis flotily – Novák Auto','u1',9,8],['r11','Přezutí – Pekárna Svoboda','u4',12,13],['r12','Servis dodávky – Stavby Dvořák','u2',-22,9],['r13','Diagnostika – Novák Auto','u1',-18,11],['r14','Přezutí – Kavárna U Lípy','u3',-15,14],['r15','Výměna oleje – Pekárna Svoboda','u4',-13,10],['r16','Prohlídka vozu – Truhlářství Marek','u6',-2,15],['r17','Servis – Eva Horáková','u5',15,9],['r18','Přezutí – Stavby Dvořák','u2',17,13],['r19','Diagnostika – Novák Auto','u1',20,10]].map(function(x){return {id:x[0],company_id:C,title:x[1],customer_id:x[2],starts_at:at(x[3],x[4]),ends_at:at(x[3],x[4]+1),canceled:false,created_at:iso(-3)}});
 var ts=[['t1','Zavolat Novák Auto ohledně termínu servisu flotily',1,false],['t2','Objednat brzdové kotouče',0,false],['t3','Poslat nabídku Truhlářství Marek',3,false],['t4','Připomenout neuhrazenou fakturu Kavárně U Lípy',-2,false],['t5','Zkontrolovat sklad olejů',-5,true]].map(function(x){return {id:x[0],company_id:C,title:x[1],due_at:at(x[2],16),completed:x[3],created_at:iso(-6)}});
 var sup={legal_name:'Autoservis Novotný s.r.o.',ico:'12345678',dic:'CZ12345678',address_text:'Dlouhá 12, 110 00 Praha 1',bank_account:'123456789/0100',email:'info@autoservis-novotny.cz',country_code:'CZ',default_due_days:14,default_currency:'CZK'};
 var iv=[[18400,150,1,'Novák Auto s.r.o.'],[24500,120,1,'Stavby Dvořák'],[31200,95,1,'Kavárna U Lípy'],[19800,70,1,'Novák Auto s.r.o.'],[42600,45,1,'Stavby Dvořák'],[27900,25,1,'Pekárna Svoboda'],[38400,16,0,'Kavárna U Lípy'],[15200,6,0,'Pekárna Svoboda']].map(function(x,i){var d=x[1];return {id:'v'+i,company_id:C,number:'2026'+('000'+(i+1)).slice(-3),total:x[0],currency:'CZK',issued_on:day(-d),due_on:day(-d+14),paid_at:x[2]?iso(-d+9):null,customer_snapshot:{name:x[3],email:"fakturace@"+x[3].toLowerCase().replace(/[^a-z]/g,"")+".cz",ico:"2"+(1000000+i*137).toString().slice(0,7),billing_address:"Praha"},supplier_snapshot:sup,items:[{description:'Servisní práce',quantity:1,unit:'ks',unit_gross:Math.round(x[0]*0.6),vat_rate:21},{description:'Náhradní díly a materiál',quantity:1,unit:'ks',unit_gross:x[0]-Math.round(x[0]*0.6),vat_rate:21}],created_at:iso(-d)}});
 var fe=[];[[-150,'Servisní zakázky','income',48200],[-120,'Servisní zakázky','income',52400],[-95,'Servisní zakázky','income',61300],[-70,'Servisní zakázky','income',57800],[-45,'Servisní zakázky','income',64900],[-12,'Servisní zakázky','income',58400]].forEach(function(x,i){fe.push({id:'f'+i,company_id:C,title:x[1],amount:x[3],kind:x[2],entry_date:day(x[0]),created_at:iso(x[0])})});
 [[-150,'Nájem dílny',-18000],[-120,'Náhradní díly – Autodíly CZ',-21400],[-95,'Nájem dílny',-18000],[-70,'Náhradní díly – Autodíly CZ',-24300],[-45,'Energie a pojištění',-9800],[-30,'Nájem dílny',-18000],[-14,'Náhradní díly – Autodíly CZ',-19600],[-8,'Pohonné hmoty',-4200]].forEach(function(x,i){fe.push({id:'g'+i,company_id:C,title:x[1],amount:Math.abs(x[2]),kind:'expense',entry_date:day(x[0]),created_at:iso(x[0])})});
 var DSH=[];[['Petr Mechanik',8,16],['Jana Recepční',8,16],['Michal Novotný',9,17]].forEach(function(p,pi){for(var o=-28;o<=28;o++){var dd=new Date(n+o*D86),w=dd.getDay();if(w===0||w===6)continue;if(pi===1&&(o%2))continue;if(pi===2&&w!==2&&w!==4)continue;DSH.push({id:'sh'+pi+'_'+o,company_id:C,person:p[0],starts_at:at(o,p[1]),ends_at:at(o,p[2]),note:'',created_at:iso(-20)})}});
 return {company_members:[{company_id:C,user_id:'demo-user',role:'owner'}],company_invites:[],companies:[{id:C,name:'Autoservis Novotný',industry:'Autoservis'}],subscriptions:[{company_id:C,plan:'business',status:'demo'}],customers:cs,jobs:js,reservations:rs,tasks:ts,invoices:iv,financial_entries:fe,plan_requests:[],ai_usage:[],shifts:DSH,booking_profiles:[{company_id:C,slug:'autoservis-novotny',enabled:true,title:'Autoservis Novotný – online rezervace',description:'Objednejte se na servis, pneuservis nebo prohlídku vozu. Vyberte službu a volný termín.',address:'Dlouhá 12, Praha 1',phone:'602 000 000',hours:{1:{o:'08:00',c:'17:00'},2:{o:'08:00',c:'17:00'},3:{o:'08:00',c:'17:00'},4:{o:'08:00',c:'17:00'},5:{o:'08:00',c:'16:00'},6:{o:'09:00',c:'12:00'}},slot_minutes:30,capacity:2}],booking_services:[{id:'s1',company_id:C,name:'Prohlídka vozu',duration_min:30,price:0,active:true},{id:'s2',company_id:C,name:'Výměna oleje a filtrů',duration_min:60,price:1290,active:true},{id:'s3',company_id:C,name:'Přezutí pneumatik',duration_min:45,price:790,active:true},{id:'s4',company_id:C,name:'Diagnostika závad',duration_min:90,price:1490,active:true}]};
}
function demoSb(){
 if(DS)return DS;DD=demoData();var D=DD,seq=100;
 function qb(t){var q={op:'sel',f:[],pl:null,cnt:false,head:false};
  var o={select:function(c,opt){if(opt&&opt.count)q.cnt=true;if(opt&&opt.head)q.head=true;return o},eq:function(k,v){q.f.push(function(r){return r[k]===v});return o},is:function(k,v){q.f.push(function(r){return v===null?r[k]==null:r[k]===v});return o},gte:function(k,v){q.f.push(function(r){return String(r[k]||'')>=String(v)});return o},order:function(){return o},limit:function(){return o},
   upsert:function(r,opt){q.op='ups';q.pl=r;q.k=(opt&&opt.onConflict)||'id';return o},insert:function(r){q.op='ins';q.pl=r;return o},update:function(r){q.op='upd';q.pl=r;return o},delete:function(){q.op='del';return o},
   then:function(res,rej){return Promise.resolve().then(function(){var tb=D[t]||(D[t]=[]),m=function(r){return q.f.every(function(f){return f(r)})},data=null;
    if(q.op==='ins'){var a=Array.isArray(q.pl)?q.pl:[q.pl];data=a.map(function(r){var x=Object.assign({id:'n'+(++seq),created_at:new Date().toISOString()},r);tb.push(x);return x})}
    else if(q.op==='ups'){var ex=tb.filter(function(r){return r[q.k]===q.pl[q.k]})[0];if(ex){Object.assign(ex,q.pl)}else tb.push(Object.assign({id:'n'+(++seq)},q.pl));data=[q.pl]}
    else if(q.op==='upd'){data=tb.filter(m);data.forEach(function(r){Object.assign(r,q.pl)})}
    else if(q.op==='del'){D[t]=tb.filter(function(r){return !m(r)})}
    else{data=tb.filter(m);if(q.head)return {data:null,count:data.length,error:null}}
    return {data:data,error:null,count:data?data.length:0}}).then(res,rej)}};
  return o}
 function ds(){var d=new Date(),m0=new Date(d.getFullYear(),d.getMonth(),1),t0=new Date();t0.setHours(0,0,0,0);var t1=new Date(t0.getTime()+864e5),fe=D.financial_entries,inc=0,ex=0;
  fe.forEach(function(r){if(new Date(r.entry_date)>=m0){if(r.kind==='income')inc+=Number(r.amount)||0;else ex+=Math.abs(Number(r.amount)||0)}});
  D.invoices.forEach(function(r){if(r.paid_at&&new Date(r.paid_at)>=m0)inc+=Number(r.total)||0});
  return {income:inc,expenses:ex,customers:D.customers.length,active_jobs:D.jobs.filter(function(j){return !/hotov|done|zruš/i.test(j.status||'')}).length,reservations_today:D.reservations.filter(function(r){var s=new Date(r.starts_at);return !r.canceled&&s>=t0&&s<t1}).length}}
 function rpc(n,a){return Promise.resolve().then(function(){
  if(n==='dashboard_summary')return {data:ds(),error:null};
  if(n==='public_booking_info'){var pr=D.booking_profiles.filter(function(x){return x.slug===a.p_slug&&x.enabled})[0];if(!pr)return {data:null,error:null};return {data:{name:D.companies[0].name,title:pr.title,description:pr.description,address:pr.address,phone:pr.phone,hours:pr.hours,services:D.booking_services.filter(function(x){return x.active!==false}).map(function(x){return {id:x.id,name:x.name,duration_min:x.duration_min,price:x.price}})},error:null}}
  if(n==='public_slots')return {data:dslots(a.p_service,a.p_day),error:null};
  if(n==='public_book'){var st=new Date(a.p_start),dy=st.getFullYear()+'-'+(st.getMonth()+1)+'-'+st.getDate(),ok=dslots(a.p_service,dy).some(function(x){return new Date(x).getTime()===st.getTime()});if(!ok)return {data:null,error:{message:'slot_taken'}};
   var sv=D.booking_services.filter(function(x){return x.id===a.p_service})[0],cu=D.customers.filter(function(x){return String(x.email).toLowerCase()===String(a.p_email).toLowerCase()})[0];if(!cu){cu={id:'n'+(++seq),company_id:'demo',name:a.p_name,email:a.p_email,phone:a.p_phone,created_at:new Date().toISOString()};D.customers.push(cu)}
   var en=new Date(st.getTime()+sv.duration_min*6e4);D.reservations.push({id:'n'+(++seq),company_id:'demo',title:'Online: '+sv.name+' - '+a.p_name,customer_id:cu.id,starts_at:st.toISOString(),ends_at:en.toISOString(),canceled:false,created_at:new Date().toISOString()});return {data:{ok:true,start:st.toISOString(),end:en.toISOString(),service:sv.name,business:D.companies[0].name},error:null}}
  if(n==='company_team')return {data:[{user_id:'demo-user',email:'novotny@autoservis-novotny.cz',role:'owner',is_me:true},{user_id:'u-demo2',email:'mechanik@autoservis-novotny.cz',role:'employee',is_me:false}],error:null};
  if(n==='cancel_invite'){D.company_invites=D.company_invites.filter(function(x){return x.id!==a.invite_id});return {data:true,error:null}}
  if(n==='remove_member'||n==='accept_company_invites')return {data:0,error:null};
  if(n==='invoice_action'){var doc=a.doc||{};
   if(a.action==='paid'){D.invoices.forEach(function(x){if(x.id===doc.id)x.paid_at=new Date().toISOString()});return {data:{ok:true},error:null}}
   if(a.action==='profile'){var sp=Object.assign({},doc);D.invoices.forEach(function(x){x.supplier_snapshot=sp});return {data:{ok:true},error:null}}
   if(a.action==='issue'){var tot=0;(doc.items||[]).forEach(function(i){tot+=(i.quantity||0)*(i.unit_gross||0)});var no='2026'+('000'+(D.invoices.length+1)).slice(-3),sp2=(D.invoices[0]||{}).supplier_snapshot||{};
    D.invoices.push({id:'v'+(++seq),company_id:'demo',number:no,total:Math.round(tot*100)/100,currency:doc.currency||'CZK',issued_on:doc.issued_on,due_on:doc.due_on,paid_at:null,customer_snapshot:{name:(doc.customer||{}).name},supplier_snapshot:sp2,items:doc.items,created_at:new Date().toISOString()});return {data:{number:no},error:null}}}
  return {data:null,error:null}})}
 function dslots(sid,day){var pr=D.booking_profiles[0],sv=D.booking_services.filter(function(x){return x.id===sid})[0],out=[];if(!pr||!sv||!pr.enabled)return out;var p=String(day).split('-'),d0=new Date(+p[0],+p[1]-1,+p[2]),dw=d0.getDay()||7,h=pr.hours[dw];if(!h)return out;var o=h.o.split(':'),c=h.c.split(':'),t=new Date(d0);t.setHours(+o[0],+o[1],0,0);var lim=new Date(d0);lim.setHours(+c[0],+c[1],0,0);var dur=sv.duration_min*6e4,st=pr.slot_minutes*6e4;while(t.getTime()+dur<=lim.getTime()){if(t.getTime()>Date.now()+72e5){var busy=D.reservations.filter(function(r){return !r.canceled&&new Date(r.starts_at)<t.getTime()+dur&&new Date(r.ends_at)>t.getTime()}).length;if(busy<pr.capacity)out.push(t.toISOString())}t=new Date(t.getTime()+st)}return out}
 var meta={full_name:'Michal Novotný',onboarded:true,features:['zakaznici','zakazky','kalendar','faktury','ai','zamestnanci'],country:'Česko'};
 DS={from:qb,rpc:rpc,auth:{getSession:function(){return Promise.resolve({data:{session:{access_token:'demo'}}})},getUser:function(){return Promise.resolve({data:{user:{id:'demo-user',email:'novotny@autoservis-novotny.cz',user_metadata:meta}}})},onAuthStateChange:function(){},updateUser:function(x){Object.assign(meta,x.data||{});return Promise.resolve({data:{user:{user_metadata:meta}},error:null})},signOut:function(){return Promise.resolve()}}};
 return DS}
function dresp(o,st){return Promise.resolve(new Response(JSON.stringify(o),{status:st||200,headers:{'content-type':'application/json'}}))}
function dfetch(u,o){
 if(!DEMO)return fetch(u,o);
 var b={};try{b=JSON.parse(o.body)}catch(e){}
 if(String(u).indexOf('/api/invite')>=0){DD.company_invites.push({id:'i'+Date.now(),company_id:'demo',email:b.email,role:b.role,created_at:new Date().toISOString(),accepted_at:null});return dresp({ok:true,mail:'demo'})}
 if(String(u).indexOf('/api/advisor')>=0){var q=((b.messages||[]).slice(-1)[0]||{}).content||'',s=b.summary||{};return new Promise(function(r){setTimeout(r,700)}).then(function(){return dresp({reply:'Ukázková odpověď (v ostrém účtu odpovídá AI podle vašich skutečných dat).\n\nPodle dat v ukázce máte '+(s.neuhrazene_faktury!=null?s.neuhrazene_faktury+' neuhrazených faktur. ':'rozpracované zakázky a neuhrazené faktury. ')+'Doporučuji: 1) připomenout se Kavárně U Lípy, faktura je po splatnosti, 2) potvrdit termín servisu flotily s Novák Auto, 3) objednat díly na výměnu brzd. Chcete, abych k tomu připravil úkoly? (Akce vždy provedu až po vašem potvrzení.)'})})}
 if(String(u).indexOf('/api/marketing')>=0){var T={social:'Zimní pneumatiky? Objednejte přezutí online a ušetřete si čekání. Stačí vybrat termín a my se postaráme o zbytek. [doplnit cenu]\n\nRezervace na našem webu. #servis #pneuservis #přezutí',email:'Předmět: Je čas přezout? Objednejte se online\n\nDobrý den,\nblíží se zima a s ní i čas na zimní pneumatiky. Termín si můžete vybrat online na našem webu, a to během pár kliknutí.\n\nTěšíme se na vás,\n[doplnit jméno]',ad:'Nadpisy:\n1) Přezutí online\n2) Objednejte si termín\n3) Servis bez čekání\n\nPopisy:\n1) Vyberte volný termín online. [doplnit cenu]\n2) Zimní pneumatiky? Postaráme se o ně rychle a férově.',plan:'Po: Příspěvek (Instagram) – tip na kontrolu pneumatik\nSt: Příspěvek (Facebook) – před a po z dílny\nPá: Newsletter – připomenutí přezutí',review:'Dobrý den, děkujeme za zpětnou vazbu. Mrzí nás, že jste nebyl(a) úplně spokojen(a), a rádi věc společně vyřešíme. Ozvěte se nám prosím na [doplnit kontakt].'};return new Promise(function(r){setTimeout(r,800)}).then(function(){return dresp({demo:true,text:T[b.kind]||T.social})})}
 if(String(u).indexOf('/api/web-ai')>=0){var nm0=b.name||'Naše firma';return new Promise(function(r){setTimeout(r,900)}).then(function(){return dresp({demo:true,site:{hero:{title:nm0+': spolehlivý servis bez zbytečných starostí',subtitle:'Postaráme se o vaše auto rychle, férově a s jasným vysvětlením, co a proč děláme.',cta:'Objednat se'},about:{title:'O nás',text:'Jsme malá provozovna, která se věnuje servisu vozidel pro místní řidiče i firmy. Víme, že auto je pro vás nástroj, a proto klademe důraz na jasnou domluvu a dodržení termínů.'},services:[{name:'Servis a opravy',desc:'Běžné opravy, výměna dílů a kontrola stavu vozu.'},{name:'Pneuservis',desc:'Přezutí, vyvážení a uskladnění pneumatik.'},{name:'Diagnostika',desc:'Zjištění příčiny závady a návrh řešení.'}]}})})}
 if(String(u).indexOf('/api/accountant')>=0){
  if(b.mode==='ask'){var m=b.summary||{};return new Promise(function(r){setTimeout(r,600)}).then(function(){return dresp({reply:'Ukázková odpověď z čísel v evidenci: tento měsíc máte příjmy '+(m.prijmy_tento_mesic_kc||0).toLocaleString('cs-CZ')+' Kč a výdaje '+(m.vydaje_tento_mesic_kc||0).toLocaleString('cs-CZ')+' Kč. Minulý měsíc to bylo '+(m.prijmy_minuly_mesic_kc||0).toLocaleString('cs-CZ')+' Kč příjmů a '+(m.vydaje_minuly_mesic_kc||0).toLocaleString('cs-CZ')+' Kč výdajů. Nejde o účetní ani daňovou radu.'})})}
  return new Promise(function(r){setTimeout(r,1200)}).then(function(){return dresp({doc:{document_type:'received_invoice',supplier_name:'Autodíly CZ s.r.o.',supplier_ico:'87654321',document_number:'FA-2026-0418',issue_date:new Date().toISOString().slice(0,10),total_amount:12100,vat_amount:2100,vat_rate:21,currency:'CZK',description:'Brzdové kotouče a destičky',category:'material',confidence:'high',warnings:['Ukázka: nahraný soubor se nezpracovává, jde o vzorový doklad. V ostrém účtu AI vytěží údaje z vašeho souboru.']},used:1,limit:500})})}
 return dresp({error:'demo'},400)}
window.addEventListener('load',function(){var rq=null;try{rq=new URLSearchParams(location.search).get('r')}catch(e){}if(rq&&/^[a-zA-Z0-9-]{3,41}$/.test(rq))bookOpen(rq.toLowerCase(),false);var wq=null;try{wq=new URLSearchParams(location.search).get('w')}catch(e){}if(wq&&/^[a-zA-Z0-9-]{3,41}$/.test(wq))webOpen(wq.toLowerCase(),false)});
function startDemo(){DEMO=true;DS=null;APP.betaHidden=true;openApp()}

async function openApp(){
 var c=getSb();if(!c)return;closeDlg();
 var u=(await c.auth.getUser()).data.user;if(!u){showAuth('login');return}
 var cid;try{cid=DEMO?'demo':await ensureCompany(c,u)}catch(e){openD('<h2 id="dT">Aplikace</h2><div class="draft">'+esc(niceErr(e))+'</div>');return}
 if(!cid){openD('<h2 id="dT">Aplikace</h2><div class="draft">K účtu zatím není přiřazená žádná firma. Pokud jste pozvaní, požádejte majitele firmy, ať vám pozvánku pošle na přesně tento e-mail, a pak se znovu přihlaste. Jinak se odhlaste a založte si vlastní účet.</div><div class="dact"><button class="btn btn-ghost" type="button" id="logout">Odhlásit se</button></div>');return}
 APP.cid=cid;APP.user=u;APP.meta=u.user_metadata||{};
 var R=await Promise.all([c.from('companies').select('*').eq('id',cid).limit(1),c.from('company_members').select('*').eq('company_id',cid).eq('user_id',u.id).limit(1),c.from('subscriptions').select('*').eq('company_id',cid).limit(1)]);
 var cr=R[0].data&&R[0].data[0]||{};APP.co=cr.name||'Moje firma';APP.ind=cr.industry||APP.meta.industry||'';
 APP.role=R[1].data&&R[1].data[0]&&R[1].data[0].role||null;APP.sub=R[2].data&&R[2].data[0]||null;
 var el=A('vxapp');if(el)el.remove();
 el=document.createElement('div');el.id='vxapp';el.className='vxapp';
 var nm=(APP.meta.full_name||u.email||'').trim(),ini=nm.split(/\s+/).map(function(w){return w.charAt(0)}).join('').slice(0,2).toUpperCase()||'V';
 function nb(t){return '<button type="button" data-tab="'+t[0]+'">'+ico(t[0])+'<span>'+t[1]+'</span></button>'}
 el.innerHTML='<aside id="vxside"><div class="vlogo"><svg viewBox="0 0 32 32" width="34" height="34" aria-hidden="true"><path d="M5 7l11 19L27 7" fill="none" stroke="#8b6cff" stroke-width="4" stroke-linejoin="round" stroke-linecap="round"/></svg><div><b>VEXARONET</b><small>AI CEO <span class="beta">BETA</span></small></div></div><nav>'+NAV.map(nb).join('')+Object.keys(SOON).map(function(k){return '<button type="button" data-tab="'+k+'" class="soon">'+ico(k)+'<span>'+SOON[k][0]+'</span><em>brzy</em></button>'}).join('')+'</nav><div class="sfoot"><button type="button" data-tab="profil">'+ico('profil')+'<span>Nastavení</span></button><div class="subc" id="subCard"></div></div></aside><div class="scrim" data-app="side"></div>'
 +'<div class="vxmain"><header><button type="button" class="ib burger" data-app="side" aria-label="Menu">'+ico('menu')+'</button><form class="gs" id="gsForm" autocomplete="off"><span class="si">'+ico('search',18)+'</span><input id="gsIn" placeholder="Zeptejte se AI CEO nebo napište, co potřebujete…" maxlength="400" aria-label="Zeptat se AI CEO"><kbd>Ctrl + K</kbd></form><div class="bellw"><button type="button" class="ib" data-app="bell" aria-label="Notifikace">'+ico('bell')+'<i class="bdg" id="appBdg"></i></button><div class="pop" id="appBell"></div></div><button type="button" class="ib" data-app="theme" aria-label="Světlý a tmavý režim">'+ico('sun')+'</button><button type="button" class="usr" data-tab="profil"><span class="ib av">'+esc(ini)+'</span><span class="un"><b>'+esc(nm.split('@')[0])+'</b><small>'+esc(APP.co)+'</small></span></button><button type="button" class="btn btn-ghost btn-sm webb" data-app="close">Web</button></header><main id="appMain"></main></div><div class="toast" id="appToast" role="status"></div>';
 if(DEMO)el.insertAdjacentHTML('beforeend','<div class="demobar" role="status"><span><b>DEMO</b> ukázková data, nic se neukládá</span><button type="button" class="btn btn-main btn-sm" data-demo-signup="1">Založit účet zdarma</button><button type="button" class="btn btn-ghost btn-sm" data-app="close">Ukončit ukázku</button></div>');document.body.appendChild(el);document.documentElement.style.overflow='hidden';
 await refresh(true);if(!allowed(APP.tab))APP.tab='profil';appTab(APP.tab)}
function closeApp(){DEMO=false;var el=A('vxapp');if(el)el.remove();document.documentElement.style.overflow=''}
function subCard(){var s=APP.sub,e=A('subCard');if(!e)return;if(!s){e.innerHTML='';return}
 var nm=PLANN[(s.plan||'').toLowerCase()]||s.plan,t=STATN[s.status]||s.status,x='';
 if(s.status==='trial'&&s.trial_end){var d=Math.ceil((new Date(s.trial_end)-new Date())/864e5);x=d>0?'Zbývá '+d+' '+(d===1?'den':(d<5?'dny':'dní'))+' zdarma':'Zkušební období skončilo'}else if(s.paid_until)x='Platné do '+fD(s.paid_until);
 e.innerHTML='<b>'+esc(nm)+'</b><small>'+esc(t.charAt(0).toUpperCase()+t.slice(1))+'</small><small>'+esc(x)+'</small><button type="button" data-tab="profil">Správa předplatného</button>'}
async function qt(t){var r=await getSb().from(t).select('*').eq('company_id',APP.cid);return r.error?{err:r.error.message,rows:[]}:{rows:r.data||[]}}
async function refresh(first){
 var c=getSb(),R=await Promise.all([qt('customers'),qt('jobs'),qt('reservations'),qt('tasks'),qt('invoices'),c.rpc('dashboard_summary',{cid:APP.cid}),qt('financial_entries'),qt('shifts'),qt('booking_profiles'),qt('booking_services'),qt('sites'),qt('marketing_posts')]);
 R[0].rows=R[0].rows.filter(function(x){return !x.archived});
 APP.d={customers:R[0],jobs:R[1],reservations:R[2],tasks:R[3],invoices:R[4],ds:R[5].error?{err:R[5].error.message}:(R[5].data||{}),fe:R[6],shifts:R[7],booking_profiles:R[8],booking_services:R[9],sites:R[10],marketing_posts:R[11]};
 if(A('vxapp')){subCard();renderBell()}}
function appTab(t){
 APP.tab=t;var el=A('vxapp');if(!el)return;el.classList.remove('side');
 [].forEach.call(el.querySelectorAll('[data-tab]'),function(b){b.setAttribute('aria-pressed',b.dataset.tab===t)});
 var m=A('appMain');try{m.innerHTML=!allowed(t)?lockView(t):(VIEWS[t]?VIEWS[t]():soonView(t))}catch(e){m.innerHTML='<div class="draft">Stránku se nepodařilo zobrazit: '+esc(e.message)+'</div>'}
 m.scrollTop=0;if(allowed(t)&&AFTER[t])AFTER[t]()}
function lockView(t){return '<div class="card2 soonc"><span class="eyebrow">Váš tarif: '+esc(PLANN[effPlan()]||effPlan())+'</span><h2>Tato část není součástí vašeho tarifu</h2><p>AI CEO a rozšířené moduly jsou ve Vexaronet PRO (699 Kč měsíčně bez DPH) a vyšších tarifech.</p><div class="dact"><a class="btn btn-main btn-sm" href="/cenik">Zobrazit ceník</a><button class="btn btn-ghost btn-sm" type="button" data-app="plan">Změnit tarif</button></div><p class="mut fine">Platební brána zatím není připojená. Žádost o vyšší tarif vyřídíme ručně.</p></div>'}
function errBox(x){return x.err?'<div class="draft">Data se nepodařilo načíst: '+esc(x.err)+'</div>':''}
function soonView(t){var s=SOON[t];return '<div class="card2 soonc"><span class="eyebrow">Etapa '+s[2]+' · připravujeme</span><h2>'+esc(s[0])+'</h2><p>'+esc(s[1])+'</p><div class="draft">Tento modul zatím není hotový ani připojený. Nic zde neukládáme ani nepředstíráme. Ozveme se, až bude k dispozici.</div></div>'}

/* ---- notifikace z reálných dat ---- */
function notes(){
 var d=APP.d,n=[],now=new Date(),t0=dayStart(0),t1=dayStart(1),t2=dayStart(2);
 d.tasks.rows.forEach(function(x){if(x.completed||!x.due_at)return;var s=new Date(x.due_at);if(s<t0)n.push(['bad','Úkol po termínu: '+x.title,'ukoly']);else if(s<t1)n.push(['warn','Úkol na dnes: '+x.title,'ukoly'])});
 d.reservations.rows.forEach(function(x){if(x.canceled)return;var s=new Date(x.starts_at);if(s>=now&&s<t2)n.push(['info','Rezervace '+(s<t1?'dnes':'zítra')+' '+fD(x.starts_at,1)+': '+(x.title||''),'kalendar'])});
 d.invoices.rows.forEach(function(x){if(x.paid_at||!x.due_on)return;if(new Date(x.due_on)<t0)n.push(['bad','Faktura po splatnosti: '+(x.number||'')+' ('+fM(x.total,x.currency)+')','faktury'])});
 d.jobs.rows.forEach(function(x){if(!x.due_at||DONE.test(x.status||''))return;var s=new Date(x.due_at);if(s<t0)n.push(['bad','Zakázka po termínu: '+x.title,'zakazky'])});
 return n.slice(0,25)}
function renderBell(){var n=notes(),b=A('appBdg'),p=A('appBell');if(!b)return;b.textContent=n.length>9?'9+':n.length;b.style.display=n.length?'':'none';p.innerHTML='<h4>Notifikace</h4>'+(n.length?n.map(function(x){return '<button type="button" class="nt '+x[0]+'" data-tab="'+x[2]+'">'+esc(x[1])+'</button>'}).join(''):'<p class="mut">Nic zásadního. Vše je v pořádku.</p>')}

/* ---- grafy (SVG, vlastní kód) ---- */
function barChart(labels,sa,sb2,na,nb,c1,c2){c1=c1||'b1';c2=c2||'b2';
 var W=560,H=230,L=46,B=28,T=14,max=Math.max(1,Math.max.apply(null,sa.concat(sb2))),n=labels.length,gw=(W-L-8)/n,bw=Math.min(26,gw/3),h=H-B-T,g='';
 for(var i=0;i<=4;i++){var y=T+h-h*i/4;g+='<line x1="'+L+'" x2="'+W+'" y1="'+y+'" y2="'+y+'" class="gl"/><text x="'+(L-6)+'" y="'+(y+4)+'" text-anchor="end" class="ax">'+Math.round(max*i/4).toLocaleString('cs-CZ')+'</text>'}
 labels.forEach(function(lb,i){var x=L+gw*i+gw/2,a=h*sa[i]/max,b=h*sb2[i]/max;
  g+='<rect class="bar '+c1+'" style="animation-delay:'+(i*70)+'ms" x="'+(x-bw-2)+'" y="'+(T+h-a)+'" width="'+bw+'" height="'+a+'" rx="4"><title>'+esc(lb)+' · '+esc(na)+': '+fM(sa[i])+'</title></rect><rect class="bar '+c2+'" style="animation-delay:'+(i*70+40)+'ms" x="'+(x+2)+'" y="'+(T+h-b)+'" width="'+bw+'" height="'+b+'" rx="4"><title>'+esc(lb)+' · '+esc(nb)+': '+fM(sb2[i])+'</title></rect><text x="'+x+'" y="'+(H-8)+'" text-anchor="middle" class="ax">'+esc(lb)+'</text>'});
 return '<svg viewBox="0 0 '+W+' '+H+'" class="chart" role="img" aria-label="Graf: '+esc(na)+' a '+esc(nb)+' podle měsíců">'+g+'</svg><div class="leg"><span><i class="s'+c1+'"></i>'+esc(na)+'</span><span><i class="s'+c2+'"></i>'+esc(nb)+'</span></div>'}
var PAL=['#6e8cff','#a278ff','#3ddc97','#ffb347','#ff6b81','#59c8ff'];
function donut(items,center){
 var tot=items.reduce(function(s,x){return s+x[1]},0);if(!tot)return '<p class="mut">Zatím žádná data.</p>';
 var C=2*Math.PI*52,off=0,seg='';
 items.forEach(function(x,i){var len=C*x[1]/tot;seg+='<circle class="seg" r="52" cx="70" cy="70" fill="none" stroke="'+PAL[i%PAL.length]+'" stroke-width="22" stroke-dasharray="'+len+' '+(C-len)+'" stroke-dashoffset="'+(-off)+'" transform="rotate(-90 70 70)" style="animation-delay:'+(i*120)+'ms"><title>'+esc(x[0])+': '+x[1]+'</title></circle>';off+=len});
 return '<div class="dn"><svg viewBox="0 0 140 140" width="150" height="150" role="img" aria-label="Zakázky podle stavu">'+seg+'<text x="70" y="75" text-anchor="middle" class="dnt">'+(center||tot)+'</text></svg><ul class="leg2">'+items.map(function(x,i){return '<li><i style="background:'+PAL[i%PAL.length]+'"></i>'+esc(x[0])+' <b>'+x[1]+'</b></li>'}).join('')+'</ul></div>'}
function monthsBack(n){var o=[],d=new Date();d.setDate(1);d.setHours(0,0,0,0);for(var i=n-1;i>=0;i--){var m=new Date(d.getFullYear(),d.getMonth()-i,1);o.push(m)}return o}
function onboard(){
 if(APP.meta.onboarded)return '';
 return '<div class="card2 onb"><h3>Dokončete nastavení firmy</h3><p class="mut">Podle odpovědí vám přizpůsobíme rychlé akce na přehledu.</p><form id="onbForm"><div class="fg"><div class="f"><label for="oC">Stát</label><select id="oC">'+COUNTRIES.map(function(x){return '<option>'+x+'</option>'}).join('')+'</select></div></div><fieldset><legend>Které funkce budete používat?</legend><div class="chks">'+FEATS.map(function(f){return '<label class="chk"><input type="checkbox" name="ft" value="'+f[0]+'"><span>'+f[1]+'</span></label>'}).join('')+'</div></fieldset><button class="btn btn-main btn-sm" type="submit">Uložit nastavení</button></form></div>'}
function plural(n,a,b,c){return n===1?a:(n>=2&&n<=4?b:c)}
function mkey(d){return d.getFullYear()*12+d.getMonth()}
function finSeries(ms){
 var rows=APP.d.fe&&APP.d.fe.rows||[],inc=ms.map(function(){return 0}),exp=inc.slice(),src='faktury';
 if(rows.length){var k=Object.keys(rows[0]),pick=function(a){return a.filter(function(x){return k.indexOf(x)>=0})[0]},am=pick(['amount','total','value','amount_czk']),dt=pick(['entry_date','occurred_on','booked_on','date','paid_at','issued_on','created_at']),ty=pick(['type','kind','direction','entry_type']);
  if(am&&dt&&ty){var ok=false;rows.forEach(function(r){var d=new Date(r[dt]);if(isNaN(d))return;var i=ms.map(function(m){return mkey(m)}).indexOf(mkey(d));if(i<0)return;var v=Math.abs(Number(r[am])||0),t=String(r[ty]);
    if(/inc|přij|prij|^in$|revenue|výnos/i.test(t)){inc[i]+=v;ok=true}else if(/exp|výd|vyd|out|cost|náklad/i.test(t)){exp[i]+=v;ok=true}});
   if(ok)return {inc:inc,exp:exp,src:'záznamy financí'}}}
 APP.d.invoices.rows.forEach(function(x){if(!x.paid_at)return;var d=new Date(x.paid_at),i=ms.map(function(m){return mkey(m)}).indexOf(mkey(d));if(i>=0)inc[i]+=Number(x.total||0)});
 return {inc:inc,exp:exp,src:'zaplacené faktury (výdaje zatím nejsou k dispozici)'}}
function trend(cur,prev){if(!prev)return '';var p=Math.round((cur-prev)/prev*100);return '<em class="'+(p>=0?'up':'dn2')+'">'+(p>=0?'↗ +':'↘ ')+p+' %</em>'}
function spark(a,cls){var m=Math.max.apply(null,a.concat([1]));return '<span class="spk">'+a.map(function(v,i){return '<i class="'+cls+'" style="height:'+Math.max(8,Math.round(v/m*100))+'%;animation-delay:'+(i*60)+'ms"></i>'}).join('')+'</span>'}
function byMonth(rows,f,ms){var o=ms.map(function(){return 0}),keys=ms.map(function(m){return mkey(m)});rows.forEach(function(r){var d=f(r);if(!d)return;d=new Date(d);if(isNaN(d))return;var i=keys.indexOf(mkey(d));if(i>=0)o[i]+=(r.__v==null?1:r.__v)});return o}
function recs(){
 var d=APP.d,s=summary(),R=[],t0=dayStart(0);
 var over=d.invoices.rows.filter(function(x){return !x.paid_at&&x.due_on&&new Date(x.due_on)<t0}),osum=over.reduce(function(a,x){return a+Number(x.total||0)},0);
 if(over.length)R.push({c:'bad',ic:'warn',t:over.length+' '+plural(over.length,'faktura','faktury','faktur')+' po splatnosti',x:'Celkem '+fM(osum)+'. Mohu připravit texty upomínek a úkoly k urgenci.',go:'faktury',act:'reminders',lab:'Připravit upomínky'});
 var oj=d.jobs.rows.filter(function(x){return x.due_at&&!DONE.test(x.status||'')&&new Date(x.due_at)<t0});
 if(oj.length)R.push({c:'blue',ic:'zakazky',t:oj.length+' '+plural(oj.length,'zakázka','zakázky','zakázek')+' po termínu',x:'Doporučuji kontaktovat zákazníky a domluvit nový termín. Mohu vytvořit úkoly.',go:'zakazky',act:'jobtasks',lab:'Vytvořit úkoly'});
 if(s.vydaje_kc>s.prijmy_kc&&s.vydaje_kc>0)R.push({c:'warn',ic:'warn',t:'Výdaje převyšují příjmy',x:'Rozdíl '+fM(s.vydaje_kc-s.prijmy_kc)+' podle údajů v databázi. Zkontrolujte výdaje a nezaplacené pohledávky ('+fM(s.pohledavky_kc)+'). Přesnou předpověď cash flow umožní až modul Finance.',go:'faktury',act:null});
 else if(s.pohledavky_kc>0&&!over.length)R.push({c:'warn',ic:'faktury',t:'Nezaplacené pohledávky '+fM(s.pohledavky_kc),x:'Žádná není po splatnosti. Hlídejte data splatnosti.',go:'faktury',act:null});
 var withJob={};d.jobs.rows.forEach(function(j){if(j.customer_id)withJob[j.customer_id]=1});
 var idle=d.customers.rows.filter(function(x){return !withJob[x.id]});
 if(idle.length)R.push({c:'ok',ic:'tr',t:'Příležitost k růstu',x:idle.length+' '+plural(idle.length,'zákazník nemá','zákazníci nemají','zákazníků nemá')+' žádnou zakázku. Zvažte nabídnout jim službu.',go:'zakaznici',act:'offer',lab:'Připravit nabídku'});
 if(s.ukoly_po_terminu)R.push({c:'warn',ic:'ukoly',t:s.ukoly_po_terminu+' '+plural(s.ukoly_po_terminu,'úkol','úkoly','úkolů')+' po termínu',x:'Projděte úkoly a dokončete nebo přesuňte termíny.',go:'ukoly',act:null});
 if(!d.customers.rows.length)R.push({c:'blue',ic:'zakaznici',t:'Začněte prvním zákazníkem',x:'Po přidání zákazníků a zakázek bude AI CEO doporučovat konkrétnější kroky.',go:'zakaznici',act:null});
 if(!R.length)R.push({c:'ok',ic:'ukoly',t:'Vše je v pořádku',x:'Žádné faktury ani zakázky po termínu.',go:null,act:null});
 return R}
function summary(){
 var d=APP.d,now=new Date(),t0=dayStart(0),t8=dayStart(7),ms=new Date(now.getFullYear(),now.getMonth(),1);
 var unpaid=d.invoices.rows.filter(function(x){return !x.paid_at}),over=unpaid.filter(function(x){return x.due_on&&new Date(x.due_on)<t0});
 var open=d.tasks.rows.filter(function(x){return !x.completed});
 return {firma:APP.co,obor:APP.ind,zeme:APP.meta.country||'',zakaznici:d.customers.rows.length,zakazky_celkem:d.jobs.rows.length,zakazky_aktivni:d.jobs.rows.filter(function(x){return !DONE.test(x.status||'')}).length,
  zakazky_po_terminu:d.jobs.rows.filter(function(x){return x.due_at&&!DONE.test(x.status||'')&&new Date(x.due_at)<t0}).length,
  ukoly_otevrene:open.length,ukoly_po_terminu:open.filter(function(x){return x.due_at&&new Date(x.due_at)<t0}).length,
  rezervace_dnes:d.reservations.rows.filter(function(x){var s=new Date(x.starts_at);return !x.canceled&&s>=t0&&s<dayStart(1)}).length,
  rezervace_7_dni:d.reservations.rows.filter(function(x){var s=new Date(x.starts_at);return !x.canceled&&s>=t0&&s<t8}).length,
  faktury_nezaplacene:unpaid.length,pohledavky_kc:unpaid.reduce(function(s,x){return s+Number(x.total||0)},0),faktury_po_splatnosti:over.length,
  fakturovano_tento_mesic_kc:d.invoices.rows.filter(function(x){return x.issued_on&&new Date(x.issued_on)>=ms}).reduce(function(s,x){return s+Number(x.total||0)},0),
  prijmy_kc:d.ds.income,vydaje_kc:d.ds.expenses}}
function ceoPanel(){if(!hasCeo())return '<div class="ceop"><h3>Váš AI CEO</h3><p class="mut">AI CEO není součástí tarifu '+esc(PLANN[effPlan()]||'')+'. Je ve Vexaronet PRO a vyšších.</p></div>';
 var Q=[['Připravit přehled financí','Připrav stručný přehled financí mé firmy podle čísel.'],['Zkontrolovat zakázky','Zkontroluj stav zakázek a termínů a řekni, co hoří.'],['Navrhnout nabídku','Připrav krátkou obchodní nabídku pro stávající zákazníky mé firmy.'],['Najít nové zákazníky','Navrhni 3 způsoby, jak získat nové zákazníky pro můj obor.'],['Navrhnout marketing','Doporuč jednoduchou marketingovou kampaň pro můj obor.']];
 return '<div class="ceop"><div class="orb" aria-hidden="true"><svg viewBox="0 0 64 64" width="64" height="64"><defs><linearGradient id="og" x1="0" x2="1" y1="0" y2="1"><stop offset="0" stop-color="#7fa0ff"/><stop offset="1" stop-color="#b07cff"/></linearGradient></defs><circle cx="32" cy="32" r="30" fill="url(#og)" opacity=".25"/><path d="M16 20l16 26 16-26" fill="none" stroke="url(#og)" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"/></svg></div><h3>Váš AI CEO</h3><p class="mut">Analyzuje data vaší firmy, hlídá důležité věci a radí. Důležité kroky provede až po vašem potvrzení.</p><div class="chatl" id="ceoLog">'+ceoMsgs()+'</div><div class="qp">'+Q.map(function(q,i){return '<button type="button" data-q="'+i+'">'+esc(q[0])+'</button>'}).join('')+'</div><form class="aif" id="ceoForm"><input id="ceoIn" placeholder="Napište mi, co potřebujete…" maxlength="500" autocomplete="off" aria-label="Zpráva pro AI CEO"><button class="sendb" type="submit" aria-label="Odeslat">'+ico('send')+'</button></form></div>'}
var CEOQ=[['Připravit přehled financí','Připrav stručný přehled financí mé firmy podle čísel.'],['Zkontrolovat zakázky','Zkontroluj stav zakázek a termínů a řekni, co hoří.'],['Navrhnout nabídku','Připrav krátkou obchodní nabídku pro stávající zákazníky mé firmy.'],['Najít nové zákazníky','Navrhni 3 způsoby, jak získat nové zákazníky pro můj obor.'],['Navrhnout marketing','Doporuč jednoduchou marketingovou kampaň pro můj obor.']];
function ceoMsgs(){return (APP.chat.length?APP.chat:[{role:'assistant',content:'Dobrý den. Co pro vás mohu dnes udělat? Zeptejte se na finance, zakázky nebo zákazníky.'}]).map(function(m){return '<div class="msg '+(m.role==='user'?'me':'bot')+'">'+esc(m.content)+'</div>'}).join('')}
async function ceoAsk(q){
 if(!hasCeo()){toast('AI CEO je součástí tarifu Vexaronet PRO a vyšších.','err');return}
 if(APP.busy)return;APP.busy=true;APP.chat.push({role:'user',content:q});
 ['ceoLog'].forEach(function(id){var lg=A(id);if(lg){lg.innerHTML=ceoMsgs()+'<div class="msg bot" id="aiWait">Píšu odpověď…</div>';lg.scrollTop=lg.scrollHeight}});
 var rep=await askAI(APP.chat.slice(-10),function(t){var w=A('aiWait');if(w)w.textContent=t});
 if(rep)APP.chat.push({role:'assistant',content:rep});else APP.chat.pop();
 APP.busy=false;var lg=A('ceoLog');if(lg){lg.innerHTML=ceoMsgs();if(!rep)lg.insertAdjacentHTML('beforeend','<div class="msg bot err">AI CEO teď není dostupný. Zkuste to později.</div>');lg.scrollTop=lg.scrollHeight}}
function greet(){var h=new Date().getHours(),n=(APP.meta.full_name||'').trim().split(/\s+/)[0]||'';return (h<10?'Dobré ráno':(h<18?'Dobrý den':'Dobrý večer'))+(n?', '+esc(n):'')+'!'}
function tile2(c,ic,l,v,sub,go,extra){return '<'+(go?'button type="button" data-tab="'+go+'"':'div')+' class="kpi"><span class="ki '+c+'">'+ico(ic,22)+'</span><div class="kt"><small>'+l+'</small><b>'+v+'</b></div><div class="ks">'+(sub||'')+'</div>'+(extra||'')+'</'+(go?'button':'div')+'>'}
function events(){
 var d=APP.d,now=new Date(),E=[];
 d.reservations.rows.forEach(function(r){if(!r.canceled&&new Date(r.ends_at||r.starts_at)>=now)E.push([new Date(r.starts_at),r.title||'Rezervace','kalendar','calendar'])});
 d.tasks.rows.forEach(function(r){if(!r.completed&&r.due_at&&new Date(r.due_at)>=dayStart(0))E.push([new Date(r.due_at),'Úkol: '+r.title,'ukoly','ukoly'])});
 d.jobs.rows.forEach(function(r){if(r.due_at&&!DONE.test(r.status||'')&&new Date(r.due_at)>=dayStart(0))E.push([new Date(r.due_at),'Termín zakázky: '+r.title,'zakazky','zakazky'])});
 return E.sort(function(a,b){return a[0]-b[0]}).slice(0,4)}
function dayLbl(d){var a=dayStart(0),k=Math.round((new Date(d.getFullYear(),d.getMonth(),d.getDate())-a)/864e5);return k===0?'Dnes':(k===1?'Zítra':d.toLocaleDateString('cs-CZ',{day:'numeric',month:'numeric'}))}
var VIEWS={
 prehled:function(){
  var d=APP.d,s=summary(),ms=monthsBack(6),h=trialBanner()+(APP.betaHidden?'':'<div class="betab"><span><b>Rozpracovaná beta verze.</b> Hotové části fungují se skutečnými daty, nehotové jsou označené „brzy“.</span><button type="button" class="lnk" data-app="hidebeta">Skrýt</button></div>');
  var errs=['customers','jobs','reservations','tasks','invoices'].filter(function(k){return d[k].err}).map(function(k){return k+': '+d[k].err});
  if(errs.length||d.ds.err)h+='<div class="draft">Část dat se nepodařilo načíst. '+esc(errs.concat(d.ds.err?['přehled: '+d.ds.err]:[]).join(' · '))+'</div>';
  var inv=d.invoices.rows.map(function(x){return {issued_on:x.issued_on,__v:Number(x.total||0),paid_at:x.paid_at}}),all=byMonth(inv,function(x){return x.issued_on},ms),
      unp=byMonth(inv.filter(function(x){return !x.paid_at}),function(x){return x.issued_on},ms),
      cu=byMonth(d.customers.rows,function(x){return x.created_at},ms),n=ms.length,
      active=s.zakazky_aktivni,tot=s.zakazky_celkem,pct=tot?Math.round(active/tot*100):0,newC=cu[n-1];
  var qa=[['jobs','Nová zakázka','zakazky'],['customers','Nový zákazník','zakaznici'],['reservations','Rezervace','kalendar'],['tasks','Nový úkol','ukoly']];
  h+='<div class="dgrid"><div class="dl"><div class="greet"><div><h2>'+greet()+'</h2><p class="mut">Zde je přehled vaší firmy. AI CEO hlídá důležité věci a navrhuje kroky.</p></div><div class="gd">'+new Date().toLocaleDateString('cs-CZ',{weekday:'long'}).replace(/^./,function(c){return c.toUpperCase()})+'<br>'+new Date().toLocaleDateString('cs-CZ',{day:'numeric',month:'long',year:'numeric'})+'</div><div class="qw"><button type="button" class="pri" data-app="quick">+ Rychlá akce ▾</button><div class="pop qpop" id="qPop">'+qa.map(function(q){return '<button type="button" data-new="'+q[0]+'">'+q[1]+'</button>'}).join('')+'</div></div></div>'
  +'<div class="kpis">'+tile2('g','tr','Tržby tento měsíc',fM(all[n-1]),trend(all[n-1],all[n-2])||'<small class="mut">vystavené faktury</small>','faktury',spark(all,'sg'))
  +tile2('r','faktury','Nezaplacené faktury',fM(s.pohledavky_kc),'<small class="mut">'+s.faktury_nezaplacene+' '+plural(s.faktury_nezaplacene,'faktura','faktury','faktur')+(s.faktury_po_splatnosti?', '+s.faktury_po_splatnosti+' po splatnosti':'')+'</small>','faktury',spark(unp,'sr'))
  +tile2('b','zakazky','Aktivní zakázky',active,'<small class="mut">z '+tot+' celkem</small><span class="prog"><i style="width:'+pct+'%"></i></span>','zakazky')
  +tile2('p','zakaznici','Noví zákazníci',newC,(trend(newC,cu[n-2])||'<small class="mut">tento měsíc</small>')+'<small class="mut"> · celkem '+s.zakaznici+'</small>','zakaznici',spark(cu,'sp'))+'</div>'
  +'<section class="card2 recs"><div class="rh"><span class="ki p">'+ico('ceo',22)+'</span><h3>AI CEO – dnešní doporučení</h3><button type="button" class="btn btn-ghost btn-sm" data-tab="ceo">Zobrazit všechny</button></div>'+recsHtml(4)+'<p class="mut fine">Doporučení vznikají z vašich skutečných dat podle pevných pravidel. Akce „Provést“ se vždy nejdřív zeptá na potvrzení.</p></section></div>'
  +'<aside class="dr card2">'+ceoPanel()+'</aside>'
  +'<div class="db4"><section class="card2"><h3>Příjmy a výdaje</h3><div id="chCash"></div></section><section class="card2"><h3>Tržby podle zákazníků</h3><div id="chCust"></div></section><section class="card2"><h3>Nejbližší události</h3>'+evHtml()+'</section><section class="card2"><h3>Rychlé akce</h3><div class="qg">'+qa.map(function(q){return '<button type="button" data-new="'+q[0]+'"><span class="ki b">'+ico(q[2],20)+'</span>'+q[1]+'</button>'}).join('')+'<button type="button" class="qs" data-soon="Vystavování faktur přidáme v etapě 4 (po odborné kontrole).">'+'<span class="ki g">'+ico('faktury',20)+'</span>Nová faktura<em>brzy</em></button><button type="button" class="qs" data-soon="Nahrávání dokladů zatím není připojené.">'+'<span class="ki p">'+ico('sklad',20)+'</span>Nahrát doklady<em>brzy</em></button></div></section></div></div>'+onboard();
  return h},
 ceo:function(){
  return '<div class="two"><section class="card2"><h3>Doporučení AI CEO</h3>'+recsHtml(10)+'<p class="mut fine">Pevná pravidla nad vašimi skutečnými daty, ne odhady AI. Akce vždy potvrzujete.</p></section><section class="card2 dr0">'+ceoPanel()+'</section></div><section class="card2"><h3>Co AI CEO umí a v jakém stavu</h3><ul class="rows">'+[['Analýza zakázek, zákazníků a faktur','funguje (rady od AI a pevná pravidla)'],['Upozornění na nezaplacené faktury a termíny','funguje'],['Příprava textů upomínek a nabídek','funguje (texty ke zkopírování)'],['Vytváření úkolů z doporučení','funguje po potvrzení'],['Odesílání e-mailů a zpráv','zatím není připojeno'],['Předpověď nedostatku peněz','omezeně, přesná předpověď až s modulem Finance'],['Automatizace opakovaných úkolů','připravujeme (etapa 5)'],['Marketingové kampaně','pouze rady, spouštění připravujeme']].map(function(x){return '<li><b>'+x[0]+'</b><span>'+x[1]+'</span></li>'}).join('')+'</ul></section>'},
 finance:function(){
  var x=APP.d.fe,rs=x.rows.slice().sort(function(a,b){return new Date(b.entry_date||b.created_at)-new Date(a.entry_date||a.created_at)}),inc=0,exp=0;
  rs.forEach(function(r){var v=Math.abs(Number(r.amount)||0);if(isInc(r.kind))inc+=v;else exp+=v});
  var h='<div class="kpis" style="margin:10px 0 14px">'+tile2('g','tr','Příjmy (záznamy)',fM(inc),'')+tile2('r','finance','Výdaje (záznamy)',fM(exp),'')+tile2(inc>=exp?'b':'o','faktury','Rozdíl',fM(inc-exp),'')+'</div>'+head('financial_entries','+ Nový záznam')+errBox(x);
  if(!rs.length)return h+'<p class="mut">Zatím žádné záznamy. Přidejte příjem nebo výdaj.</p>';
  return h+'<ul class="rows big">'+rs.map(function(r){return '<li data-edit="financial_entries:'+esc(r.id)+'"><div><b>'+esc(r.title||'Záznam')+'</b><small>'+fD(r.entry_date)+'</small></div><span class="'+(isInc(r.kind)?'inc':'')+'">'+(isInc(r.kind)?'+':'−')+fM(Math.abs(Number(r.amount)||0))+' · '+esc(KL(r.kind))+'</span></li>'}).join('')+'</ul><p class="mut fine">Jednoduchá evidence příjmů a výdajů. Nejde o účetnictví ani daňové přiznání.</p>'},
 ucetni:function(){
  var st=accStats(),ch=accChecks(),nowM=new Date().toISOString().slice(0,7),lim=ACCLIM[effPlan()]||0;
  var h='<div class="card2 note"><b>AI Účetní pomáhá s evidencí a doklady.</b> Nenahrazuje účetního ani daňového poradce. Údaje vytěžené z dokladů vždy zkontrolujte, do evidence se uloží až po vašem potvrzení. Účetnictví, DPH a daňové podklady jsou zatím jen plánované.</div>';
  h+='<div class="kpis" style="margin:12px 0">'+tile2('g','tr','Příjmy tento měsíc',fM(st.i0),'minulý měsíc '+fM(st.i1))+tile2('r','finance','Výdaje tento měsíc',fM(st.e0),'minulý měsíc '+fM(st.e1))+tile2(st.i0>=st.e0?'b':'o','faktury','Rozdíl tento měsíc',fM(st.i0-st.e0),'')+tile2('o','faktury','Nezaplacené faktury',fM(st.unp),st.unpN+' '+plural(st.unpN,'faktura','faktury','faktur')+(st.ovN?', po splatnosti '+st.ovN:''))+'</div>';
  h+='<div class="two"><section class="card2"><h3>Zpracovat doklad (AI)</h3><p class="mut">Nahrajte fotku nebo PDF faktury či účtenky. AI z něj vytáhne údaje a navrhne záznam, vy ho zkontrolujete a uložíte. Původní soubor se neukládá.</p><p class="mut fine" id="accUse">Počítám zpracované doklady…</p><div class="f full"><label for="accFile">Doklad (JPG, PNG, WebP, HEIC nebo PDF, do 6 MB)</label><input id="accFile" type="file" accept="image/*,application/pdf,.heic,.heif"></div><div class="dact"><button class="pri" type="button" data-acc="process">Zpracovat doklad</button></div><div class="st" id="accSt" role="status"></div><div id="accRes"></div></section>';
  h+='<section class="card2"><h3>Kontrola záznamů</h3><p class="mut fine">Jednoduchá kontrola vaší evidence podle pevných pravidel. Nejde o účetní audit.</p>'+(ch.length?'<ul class="rows">'+ch.map(function(x){return '<li><b>'+x[0]+'</b><span>'+x[1]+'</span></li>'}).join('')+'</ul>':'<p class="mut">Nic podezřelého jsme nenašli.</p>')+'</section></div>';
  h+='<div class="two"><section class="card2"><h3>Export pro účetního</h3><p class="mut">Stáhněte příjmy a výdaje nebo faktury jako soubor CSV (otevře Excel i účetní programy). Měsíc nechte prázdný pro vše.</p><div class="f full"><label for="accMon">Měsíc</label><input id="accMon" type="month" value="'+nowM+'"></div><div class="dact"><button class="btn btn-ghost btn-sm" type="button" data-acc="csv-ent">Příjmy a výdaje (CSV)</button><button class="btn btn-ghost btn-sm" type="button" data-acc="csv-inv">Faktury (CSV)</button></div></section>';
  h+='<section class="card2"><h3>Zeptejte se AI Účetní</h3><p class="mut fine">Odpovídá z čísel ve vaší evidenci. Nedává závazné rady k DPH, daním ani účtování, tam se obraťte na účetního.</p><div class="chatl" id="accLog" style="height:230px">'+accMsgs()+'</div><form class="aif" id="accForm"><input id="accIn" placeholder="Např. Kolik jsem tento měsíc utratil?" maxlength="500" autocomplete="off" aria-label="Zpráva pro AI Účetní"><button class="sendb" type="submit" aria-label="Odeslat">'+ico('send')+'</button></form></section></div>';
  h+='<section class="card2"><h3>Bankovní výpis a párování plateb</h3><p class="mut">Nahrajte CSV výpis z internetového bankovnictví (funguje s většinou českých bank i s exporty z platebních terminálů). AI Účetní spáruje platby s vašimi fakturami podle variabilního symbolu a částky. Faktury označí jako zaplacené až po vašem potvrzení. Soubor se nikam neukládá, zpracuje se jen ve vašem prohlížeči.</p><div class="f full"><label for="bkFile">Výpis (CSV)</label><input id="bkFile" type="file" accept=".csv,.txt,text/csv"></div><div class="dact"><button class="pri" type="button" data-acc="bk-file">Načíst výpis</button>'+(DEMO?'<button class="btn btn-ghost btn-sm" type="button" data-acc="bk-demo">Načíst ukázkový výpis</button>':'')+'</div><div class="st" id="bkSt" role="status"></div><div id="bkRes">'+bkView()+'</div></section>';
  h+='<section class="card2"><h3>Co je hotové a co se připravuje</h3><ul class="rows">'+[['Vytěžení údajů z faktur a účtenek (foto, PDF)','funguje, vždy po vaší kontrole'],['Evidence příjmů a výdajů','funguje'],['Kontrola záznamů (duplicity, budoucí data, po splatnosti)','funguje'],['Export CSV pro účetního','funguje'],['Dotazy na AI Účetní nad vaší evidencí','funguje'],['Podvojné účetnictví, deník a hlavní kniha','připravujeme, čeká na kontrolu odborníkem'],['DPH a daňové podklady','připravujeme, čeká na kontrolu odborníkem'],['Import bankovního výpisu (CSV) a párování plateb s fakturami','funguje, vždy po vašem potvrzení'],['Přímé napojení bankovního účtu (PSD2) a platebního terminálu','připravujeme, vyžaduje oficiální bankovní přístup'],['Účetní závěrky, mzdy a odvody','připravujeme']].map(function(x){return '<li'+(/^funguje/.test(x[1])?'':' class="off"')+'><b>'+x[0]+'</b><span>'+x[1]+'</span></li>'}).join('')+'</ul><p class="mut fine">Váš tarif: '+esc(PLANN[effPlan()]||'')+' · limit '+lim+' dokladů měsíčně.</p></section>';
  return h},
 zakaznici:function(){return listView('customers','Hledat zákazníka…','+ Nový zákazník',function(x){return '<div><b>'+esc(custName(x))+'</b><small>'+[x.email,x.phone].filter(Boolean).map(esc).join(' · ')+'</small></div>'},'Zatím žádní zákazníci.')},
 zakazky:function(){var cm=cmap();return listView('jobs','Hledat zakázku…','+ Nová zakázka',function(x){return '<div><b>'+esc(x.title)+'</b><small>'+esc(cm[x.customer_id]||'bez zákazníka')+(x.description?' · '+esc(x.description):'')+'</small></div><span>'+fM(x.price)+' · do '+fD(x.due_at)+(x.status?' · <em class="stt">'+esc(x.status)+'</em>':'')+'</span>'},'Zatím žádné zakázky.',function(a,b){return new Date(b.created_at)-new Date(a.created_at)})},
 kalendar:function(){
  if(!APP.calM){var n0=new Date();APP.calM=new Date(n0.getFullYear(),n0.getMonth(),1)}
  var M=APP.calM,mode=APP.calMode||'m',mg=APP.role==='owner'||APP.role==='admin',mn=M.toLocaleDateString('cs-CZ',{month:'long',year:'numeric'});mn=mn.charAt(0).toUpperCase()+mn.slice(1);
  var h='<div class="calbar"><div class="calnav"><button type="button" class="ib" data-calnav="-1" aria-label="Předchozí měsíc">‹</button><h3>'+esc(mn)+'</h3><button type="button" class="ib" data-calnav="1" aria-label="Další měsíc">›</button><button type="button" class="btn btn-ghost btn-sm" data-calnav="0">Dnes</button></div><div class="calact"><div class="calseg"><button type="button" data-calmode="m" aria-pressed="'+(mode==='m')+'">Měsíc</button><button type="button" data-calmode="l" aria-pressed="'+(mode==='l')+'">Seznam</button></div><button type="button" class="btn btn-main btn-sm" data-new="reservations">+ Rezervace</button>'+(mg?'<button type="button" class="btn btn-ghost btn-sm" data-new="shifts">+ Směna</button>':'')+'</div></div>'+errBox(APP.d.reservations);
  if(mode==='l')return h+calList();
  var first=new Date(M.getFullYear(),M.getMonth(),1),off=(first.getDay()+6)%7,st=new Date(first);st.setDate(1-off);
  var it=calItems(),tk=locD(new Date()),sel=APP.calSel||tk;
  var g='<div class="calg"><div class="calw">'+['Po','Út','St','Čt','Pá','So','Ne'].map(function(x){return '<span>'+x+'</span>'}).join('')+'</div><div class="calc">';
  for(var i=0;i<42;i++){var d=new Date(st);d.setDate(st.getDate()+i);if(i>=35&&d.getMonth()!==M.getMonth())break;var k=locD(d),li=it[k]||[];
   g+='<button type="button" class="cd'+(d.getMonth()!==M.getMonth()?' oth':'')+(k===tk?' td':'')+(k===sel?' sel':'')+'" data-calday="'+k+'"><span class="cdn">'+d.getDate()+'</span>'+li.slice(0,3).map(function(x){return '<span class="cchip c'+x.k+'">'+esc(x.lab)+'</span>'}).join('')+(li.length>3?'<span class="more">+'+(li.length-3)+' další</span>':'')+'</button>'}
  g+='</div></div><div class="calleg"><span><i class="cdot cr"></i>Rezervace</span><span><i class="cdot cj"></i>Termín zakázky</span><span><i class="cdot cs"></i>Směna</span><span><i class="cdot ct"></i>Úkol</span></div>';
  var di=it[sel]||[],sd=new Date(sel+'T12:00:00'),dt=sd.toLocaleDateString('cs-CZ',{weekday:'long',day:'numeric',month:'long'});
  g+='<section class="card2"><h3>'+esc(dt.charAt(0).toUpperCase()+dt.slice(1))+'</h3>'+(di.length?'<ul class="rows big">'+di.map(function(x){var ed=(x.ent!=='shifts'||mg);return '<li'+(ed?' data-edit="'+x.ent+':'+esc(x.id)+'"':'')+'><div><b>'+esc(x.t)+'</b><small>'+CALK[x.k]+'</small></div><span><i class="cdot c'+x.k+'"></i> '+esc(x.tm)+'</span></li>'}).join('')+'</ul>':'<p class="mut">V tento den nic není naplánováno.</p>')+'</section>';
  return h+g},
 online:function(){return onlineView()},
 weby:function(){return webView()},
 marketing:function(){return mkView()},
 ukoly:function(){
  var x=APP.d.tasks,ts=x.rows.slice().sort(function(a,b){return (a.completed-b.completed)||(new Date(a.due_at||'2999')-new Date(b.due_at||'2999'))});
  var h=head('tasks','+ Nový úkol')+errBox(x);if(!ts.length)return h+'<p class="mut">Zatím žádné úkoly.</p>';
  return h+'<ul class="rows big">'+ts.map(function(t){var late=!t.completed&&t.due_at&&new Date(t.due_at)<dayStart(0);return '<li'+(t.completed?' class="off"':'')+'><label class="chk"><input type="checkbox" data-task="'+esc(t.id)+'"'+(t.completed?' checked':'')+'><span>'+esc(t.title)+'</span></label><span'+(late?' class="late"':'')+'>'+fD(t.due_at)+'</span><button type="button" class="lnk" data-edit="tasks:'+esc(t.id)+'">Upravit</button></li>'}).join('')+'</ul>'},
 faktury:function(){
  var x=APP.d.invoices,fs=x.rows.slice().sort(function(a,b){return new Date(b.issued_on||b.created_at)-new Date(a.issued_on||a.created_at)});
  var h='<div class="card2 note"><b>Pozor:</b> faktury se vystavují přes pravidla ve vaší databázi (číslování, DPH). Před ostrým používáním je musí zkontrolovat účetní. Odesílání faktur e-mailem a PDF zatím nejsou připojené.</div><div class="bar2"><button type="button" class="btn btn-ghost btn-sm" data-invprof="1">Fakturační údaje</button><button type="button" class="pri sm" data-newinv="1">+ Nová faktura</button></div>'+errBox(x);
  if(!fs.length)return h+'<p class="mut">Zatím žádné faktury. Nejdřív vyplňte Fakturační údaje, pak vystavte první fakturu.</p>';
  return h+'<ul class="rows big">'+fs.map(function(f){var cu=f.customer_snapshot,nm=cu&&typeof cu==='object'?(cu.name||cu.company_name||''):'',late=!f.paid_at&&f.due_on&&new Date(f.due_on)<dayStart(0);return '<li><div><b>'+esc(f.number||'bez čísla')+'</b><small>'+esc(nm)+' · vystaveno '+fD(f.issued_on)+' · splatnost '+fD(f.due_on)+(f.lifecycle?' · '+esc(f.lifecycle):'')+'</small></div><span'+(late?' class="late"':'')+'>'+fM(f.total,f.currency)+' · '+(f.paid_at?'zaplaceno '+fD(f.paid_at):(late?'po splatnosti':'nezaplaceno'))+'</span><button type="button" class="lnk" data-invview="'+esc(f.id)+'">Zobrazit fakturu</button>'+(f.paid_at?'':'<button type="button" class="lnk" data-pay="'+esc(f.id)+'">Označit jako zaplacenou</button>')+'</li>'}).join('')+'</ul>'},
 zamestnanci:function(){
  var lim=TEAMLIM[effPlan()]||1,mg=APP.role==='owner'||APP.role==='admin';
  return '<div class="card2"><div class="bar2"><div><h3>Zaměstnanci a tým</h3><p class="mut">Tarif '+esc(PLANN[effPlan()]||effPlan())+': nejvýše '+lim+' '+plural(lim,'uživatel','uživatelé','uživatelů')+(effPlan()==='accountant'?' (vy a externí účetní)':'')+'. Do počtu se počítají i nevyřízené pozvánky.</p></div>'+(mg?'<button class="pri sm" type="button" data-invnew="1">+ Pozvat člena</button>':'')+'</div><div id="teamBox"><p class="mut">Načítám tým…</p></div></div><div class="draft">Po vytvoření pozvánky se e-mail odešle automaticky. Pozvaný se zaregistruje stejným e-mailem a po potvrzení e-mailu se automaticky přidá do vaší firmy. Zaměstnanec vidí zákazníky, zakázky, úkoly a kalendář; faktury, finance a AI CEO ne.</div>'},
 profil:function(){
  var s=APP.sub,m=APP.meta,fs=m.features||[];
  return '<div class="two"><section class="card2"><h3>Firma a účet</h3><ul class="rows"><li><b>E-mail</b><span>'+esc(APP.user.email)+'</span></li><li><b>Jméno</b><span>'+esc(m.full_name||'–')+'</span></li><li><b>Firma</b><span>'+esc(APP.co)+'</span></li><li><b>Obor</b><span>'+esc(APP.ind||'–')+'</span></li><li><b>Stát</b><span>'+esc(m.country||'–')+'</span></li><li><b>Role</b><span>'+esc(APP.role||'–')+'</span></li></ul></section><section class="card2"><h3>Předplatné</h3>'+(s?'<ul class="rows"><li><b>Tarif</b><span>'+esc(PLANN[String(s.plan).toLowerCase()]||s.plan)+'</span></li><li><b>Stav</b><span>'+esc(STATN[s.status]||s.status)+'</span></li>'+(s.trial_end?'<li><b>Zkušební období do</b><span>'+fD(s.trial_end)+'</span></li>':'')+(effPlan()!==String(s.plan).toLowerCase()?'<li><b>Aktuálně platí</b><span>'+esc(PLANN[effPlan()])+'</span></li>':'')+'</ul><p class="mut">'+esc(PLANLIM[effPlan()]||'')+'</p><p class="mut fine">Ceny jsou měsíční bez DPH. Platební brána zatím není připojená, nic vám neúčtujeme a nic se automaticky nestrhává. Přechod na START je okamžitý, vyšší tarif nastavíme po vaší žádosti ručně.</p><div class="dact"><a class="btn btn-ghost btn-sm" href="/cenik">Zobrazit ceník</a><button class="pri sm" type="button" data-app="plan">Změnit tarif</button></div>':'<p class="mut">Předplatné nenalezeno.</p>')+'</section></div>'
  +'<section class="card2"><h3>Použité funkce</h3><form id="featForm"><div class="fg"><div class="f"><label for="pC">Stát</label><select id="pC">'+COUNTRIES.map(function(x){return '<option'+(x===m.country?' selected':'')+'>'+x+'</option>'}).join('')+'</select></div></div><div class="chks">'+FEATS.map(function(f){return '<label class="chk"><input type="checkbox" name="ft" value="'+f[0]+'"'+(fs.indexOf(f[0])>=0?' checked':'')+'><span>'+f[1]+'</span></label>'}).join('')+'</div><button class="btn btn-main btn-sm" type="submit">Uložit</button></form></section><div class="dact"><button class="btn btn-ghost" type="button" data-app="logout">Odhlásit se</button></div>'}
};
function trialBanner(){var x=APP.sub;if(!x||x.status!=='trial'||!x.trial_end)return '';var d=Math.ceil((new Date(x.trial_end)-new Date())/864e5);
 if(d<=0)return '<div class="betab"><span><b>Zkušební období skončilo.</b> Účet teď běží v tarifu START, vaše data zůstávají zachována. Pro plné funkce vyberte tarif.</span><button class="btn btn-ghost btn-sm" type="button" data-app="plan">Změnit tarif</button></div>';
 if(d<=7)return '<div class="betab"><span><b>Zkušební období končí za '+d+' '+(d===1?'den':(d<5?'dny':'dní'))+'.</b> Pak můžete vybrat placený tarif, nebo přejít na START. Nic se automaticky neúčtuje.</span><a class="btn btn-ghost btn-sm" href="/cenik">Ceník</a></div>';return ''}
function recsHtml(n){if(!hasCeo())return '<p class="mut">AI CEO (doporučení a chat nad vašimi daty) je součástí tarifu Vexaronet PRO a vyšších.</p><div class="dact"><a class="btn btn-ghost btn-sm" href="/cenik">Zobrazit ceník</a></div>';return '<div class="rl">'+recs().slice(0,n).map(function(r,i){return '<div class="rec"><span class="ki '+(r.c==='bad'?'r':r.c==='warn'?'o':r.c==='ok'?'g':'b')+'">'+ico(r.ic,22)+'</span><div class="rt"><b>'+esc(r.t)+'</b><small>'+esc(r.x)+'</small></div><div class="ra">'+(r.go?'<button type="button" class="btn btn-ghost btn-sm" data-tab="'+r.go+'">Zobrazit</button>':'')+(r.act?'<button type="button" class="pri sm" data-act="'+r.act+'">'+ico('send',16)+' '+esc(r.lab)+'</button>':'')+'</div></div>'}).join('')+'</div>'}
function evHtml(){var E=events();if(!E.length)return '<p class="mut">Žádné nadcházející události.</p>';return '<ul class="ev">'+E.map(function(e){var tm=e[0].getHours()||e[0].getMinutes()?e[0].toLocaleTimeString('cs-CZ',{hour:'2-digit',minute:'2-digit'}):'';return '<li><button type="button" data-tab="'+e[2]+'"><span class="evd"><b>'+dayLbl(e[0])+'</b><small>'+tm+'</small></span><span class="evt">'+esc(e[1])+'</span></button></li>'}).join('')+'</ul>'}
var AFTER={weby:function(){webPrev()},kalendar:function(){try{getSb().rpc('company_team',{cid:APP.cid}).then(function(r){if(r&&r.data)APP.team=r.data})}catch(e){}},ucetni:function(){accUsage()},zamestnanci:function(){loadTeam()},prehled:function(){
  var d=APP.d,ms=monthsBack(6),lb=ms.map(function(m){return m.toLocaleDateString('cs-CZ',{month:'short'})}),f=finSeries(ms);
  A('chCash').innerHTML=(d.invoices.rows.length||d.ds.income)?barChart(lb,f.inc,f.exp,'Příjmy','Výdaje','b2','b3')+'<p class="mut fine">Zdroj: '+esc(f.src)+'.</p>':'<p class="mut">Zatím žádná data.</p>';
  var cn={},tot=0;d.invoices.rows.forEach(function(x){var cu=x.customer_snapshot,nm=cu&&typeof cu==='object'?(cu.name||cu.company_name):'';nm=nm||'Neznámý';var v=Number(x.total||0);cn[nm]=(cn[nm]||0)+v;tot+=v});
  var it=Object.keys(cn).map(function(k){return [k,cn[k]]}).sort(function(a,b){return b[1]-a[1]});if(it.length>4){var rest=it.slice(3).reduce(function(s,x){return s+x[1]},0);it=it.slice(0,3).concat([['Ostatní',rest]])}
  A('chCust').innerHTML=tot?donut(it.map(function(x){return [x[0]+' ('+Math.round(x[1]/tot*100)+' %)',Math.round(x[1])]}),fM(tot)):'<p class="mut">Zatím žádné faktury.</p>'}};

/* ---- Zaměstnanci: tým a pozvánky ---- */
function teamErr(m){m=String(m||'');var M={'Nemate opravneni zvat cleny tymu.':'Nemáte oprávnění zvát členy týmu.','Neplatna role.':'Neplatná role.','Spravce muze pridat jen majitel.':'Správce může přidat jen majitel.','Zadejte platny e-mail.':'Zadejte platný e-mail.','Tento clovek uz ve firme je.':'Tento člověk už ve firmě je.','Tento e-mail uz je pozvany.':'Tento e-mail už je pozvaný.','Nemate opravneni.':'Nemáte oprávnění.','Majitele firmy nelze odebrat.':'Majitele firmy nelze odebrat.','Sami sebe odebrat nelze.':'Sami sebe odebrat nelze.','Spravce muze odebrat jen majitel.':'Správce může odebrat jen majitel.'};if(M[m])return M[m];var x=/nejvyse (\d+) uzivatelu/.exec(m);if(x)return 'Váš tarif umožňuje nejvýše '+x[1]+' uživatelů (včetně nevyřízených pozvánek). Pro více členů přejděte na vyšší tarif.';return m}
async function loadTeam(){
 var box=A('teamBox');if(!box)return;var c=getSb(),mg=APP.role==='owner'||APP.role==='admin';
 var T=await c.rpc('company_team',{cid:APP.cid});
 if(T.error){box.innerHTML='<div class="draft">Tým se nepodařilo načíst: '+esc(T.error.message)+'. Pokud jste ještě nespustili SQL pro pozvánky, je potřeba ho dokončit v databázi.</div>';return}
 var I=mg?await c.from('company_invites').select('*').eq('company_id',APP.cid).is('accepted_at',null).order('created_at'):{data:[]};
 APP.team=T.data||[];APP.invs=I.data||[];
 var h='<ul class="rows big">'+APP.team.map(function(x){var can=mg&&x.role!=='owner'&&!x.is_me&&!(x.role==='admin'&&APP.role!=='owner');return '<li><div><b>'+esc(x.email)+(x.is_me?' (vy)':'')+'</b><small>'+esc(ROLEN[x.role]||x.role)+'</small></div>'+(can?'<button class="btn btn-ghost btn-sm" type="button" data-rmm="'+esc(x.user_id)+'">Odebrat</button>':'')+'</li>'}).join('')+'</ul>';
 if(mg){h+='<h4>Nevyřízené pozvánky</h4>'+(APP.invs.length?'<ul class="rows big">'+APP.invs.map(function(x){return '<li><div><b>'+esc(x.email)+'</b><small>'+esc(ROLEN[x.role]||x.role)+' · pozváno '+fD(x.created_at)+'</small></div><span><button class="btn btn-ghost btn-sm" type="button" data-invshow="'+esc(x.id)+'">Text pozvánky</button> <button class="btn btn-ghost btn-sm" type="button" data-invcancel="'+esc(x.id)+'">Zrušit</button></span></li>'}).join('')+'</ul>':'<p class="mut">Žádné nevyřízené pozvánky.</p>')}
 box.innerHTML=h}
function inviteModal(){
 var own=APP.role==='owner';
 modal('<h3>Pozvat člena týmu</h3><form id="inviteForm"><div class="fg"><div class="f full"><label for="ivE">E-mail pozvaného <i>*</i></label><input id="ivE" type="email" autocomplete="off" required></div><div class="f full"><label for="ivR">Role</label><select id="ivR"><option value="employee">Zaměstnanec (zákazníci, zakázky, úkoly, kalendář)</option>'+(own?'<option value="admin">Správce (vše včetně financí a týmu)</option>':'')+'</select></div></div><div class="st" id="entSt" role="status"></div><div class="dact"><button class="pri" type="submit">Vytvořit pozvánku</button><button class="btn btn-ghost" type="button" data-app="mclose">Zrušit</button></div></form>')}
function inviteText(email){
 var nm=(APP.meta.full_name||'').trim();
 return 'Dobrý den,\npozývám Vás do firmy '+APP.co+' ve Vexaronetu.\n\n1. Otevřete https://vexaronet.com a klikněte na Přihlášení, pak na Registrace.\n2. Zaškrtněte, že jste pozvaný/á do firmy zaměstnavatele.\n3. Registrujte se přesně tímto e-mailem: '+email+'\n4. Potvrďte e-mail (přijde Vám odkaz) a přihlaste se.\n\nPo přihlášení uvidíte firmu '+APP.co+'.\n\nS pozdravem\n'+(nm||APP.co)}
function inviteDone(email,failed){
 var tx=inviteText(email),sub='Pozvánka do firmy '+APP.co+' ve Vexaronetu';
 modal('<h3>Pozvánka je připravená</h3><p class="mut">'+(failed?'Pozvánka je uložená, ale e-mail se nepodařilo odeslat automaticky. Pošlete tento text sami:':'Text pozvánky, který můžete poslat znovu:')+'</p><textarea id="remTx" rows="10" readonly>'+esc(tx)+'</textarea><div class="dact"><a class="pri" href="mailto:'+encodeURIComponent(email)+'?subject='+encodeURIComponent(sub)+'&body='+encodeURIComponent(tx)+'">Otevřít v e-mailu</a><button class="btn btn-ghost" type="button" data-do="copy">Kopírovat text</button><button class="btn btn-ghost" type="button" data-app="mclose">Zavřít</button></div>')}

/* ---- AI Účetní ---- */
var ACCLIM={accountant:100,pro:150,business:500,enterprise:5000};
function accSt(t,c){var e=A('accSt');if(e){e.className='st '+(c||'');e.textContent=t}}
function accUse(u,l){var e=A('accUse');if(e)e.textContent='Zpracováno tento měsíc: '+u+' z '+l+' dokladů.'}
async function accUsage(){var e=A('accUse');if(!e)return;var lim=ACCLIM[effPlan()]||0,m0=new Date(Date.UTC(new Date().getUTCFullYear(),new Date().getUTCMonth(),1)).toISOString();
 try{var r=await getSb().from('ai_usage').select('id',{count:'exact',head:true}).eq('company_id',APP.cid).eq('kind','doc').gte('created_at',m0);
  if(r.error){e.textContent='Počítadlo dokladů ještě není nastavené v databázi (chybí tabulka ai_usage). Zpracování dokladů nebude fungovat, dokud ji správce nevytvoří.';e.className='mut fine err';return}
  accUse(r.count||0,lim)}catch(x){e.textContent=''}}
function monthKey(s){return String(s||'').slice(0,7)}
function accStats(){var d=APP.d,n=new Date(),k0=n.getFullYear()+'-'+('0'+(n.getMonth()+1)).slice(-2),p=new Date(n.getFullYear(),n.getMonth()-1,1),k1=p.getFullYear()+'-'+('0'+(p.getMonth()+1)).slice(-2),o={i0:0,e0:0,i1:0,e1:0};
 d.fe.rows.forEach(function(r){var v=Math.abs(Number(r.amount)||0),k=monthKey(r.entry_date||r.created_at),inc=isInc(r.kind);if(k===k0){if(inc)o.i0+=v;else o.e0+=v}else if(k===k1){if(inc)o.i1+=v;else o.e1+=v}});
 var un=d.invoices.rows.filter(function(x){return !x.paid_at}),t0=dayStart(0);o.unp=un.reduce(function(s,x){return s+Number(x.total||0)},0);o.unpN=un.length;o.ovN=un.filter(function(x){return x.due_on&&new Date(x.due_on)<t0}).length;return o}
function accChecks(){var d=APP.d,out=[],g={},t1=dayStart(1);
 d.fe.rows.forEach(function(r){var k=[r.kind,Math.abs(Number(r.amount)||0),String(r.entry_date||'').slice(0,10)].join('|');(g[k]=g[k]||[]).push(r)});
 Object.keys(g).forEach(function(k){if(g[k].length>1)out.push(['Možná duplicita: '+esc(g[k][0].title||'záznam'),g[k].length+'× stejná částka a datum'])});
 d.fe.rows.forEach(function(r){var v=Number(r.amount);if(!v)out.push(['Nulová nebo chybějící částka: '+esc(r.title||'záznam'),fD(r.entry_date)]);if(r.entry_date&&new Date(r.entry_date)>=new Date(t1.getTime()+864e5))out.push(['Datum v budoucnu: '+esc(r.title||'záznam'),fD(r.entry_date)])});
 var ov=overInv();if(ov.length)out.push(['Faktury po splatnosti',ov.length+' ('+fM(ov.reduce(function(s,x){return s+Number(x.total||0)},0))+')']);
 return out.slice(0,12)}
function accMsgs(){return (APP.accChat&&APP.accChat.length?APP.accChat:[{role:'assistant',content:'Dobrý den. Zeptejte se na příjmy, výdaje nebo faktury ve své evidenci.'}]).map(function(m){return '<div class="msg '+(m.role==='user'?'me':'bot')+'">'+esc(m.content)+'</div>'}).join('')}
async function accCall(payload){var ses=(await getSb().auth.getSession()).data.session;if(!ses)throw new Error('auth');var r=await dfetch('/api/accountant',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+ses.access_token},body:JSON.stringify(Object.assign({cid:APP.cid},payload))});var j=await r.json().catch(function(){return null});return {r:r,j:j}}
function accErr(r,j){var c=j&&j.error;if(r.status===403)return 'AI Účetní je součástí tarifu AI Účetní a vyšších.';if(c==='limit')return 'Tento měsíc jste využili všech '+j.limit+' zpracovaných dokladů. Limit se obnoví začátkem dalšího měsíce.';if(r.status===429)return 'Příliš mnoho požadavků. Zkuste to za chvíli.';if(c==='usage_table')return 'Počítadlo dokladů ještě není nastavené v databázi. Napište nám na info@vexaronet.com.';if(c==='bad_file')return 'Soubor se nepodařilo přijmout. Použijte fotku (JPG, PNG, WebP, HEIC) nebo PDF do 6 MB.';if(c==='unreadable')return 'Doklad se nepodařilo přečíst. Zkuste ostřejší fotku nebo PDF.';if(c==='not_configured')return 'AI Účetní zatím není na serveru nastavená.';return 'AI Účetní teď není dostupná. Zkuste to později.'}

/* ===== Bankovní výpis (CSV) a párování plateb ===== */
var BK={rows:[]};
function bkNorm(x){return String(x||'').normalize('NFD').replace(/[̀-ͯ]/g,'').toLowerCase().trim()}
function bkSplit(line,d){var o=[],c='',q=false;for(var i=0;i<line.length;i++){var ch=line.charAt(i);if(ch==='"'){if(q&&line.charAt(i+1)==='"'){c+='"';i++}else q=!q}else if(ch===d&&!q){o.push(c);c=''}else c+=ch}o.push(c);return o}
function bkNum(v){var t=String(v==null?'':v).replace(/[\s ]/g,'').replace(/[^0-9,.\-+]/g,'');if(!t)return NaN;if(t.indexOf(',')>=0&&t.indexOf('.')>=0)t=t.replace(/\./g,'').replace(',','.');else t=t.replace(',','.');return parseFloat(t)}
function bkDate(v){var t=String(v||''),m=t.match(/(\d{1,2})\.\s?(\d{1,2})\.\s?(\d{4})/);if(m)return m[3]+'-'+('0'+m[2]).slice(-2)+'-'+('0'+m[1]).slice(-2);m=t.match(/(\d{4})-(\d{2})-(\d{2})/);return m?m[0]:''}
function bkParse(text){
 var ls=text.split(/\r?\n/).filter(function(l){return l.trim()});if(!ls.length)return {err:'Soubor je prázdný.'};
 var dl=';',bn=-1;[';',',','\t'].forEach(function(d){var n=ls.slice(0,15).reduce(function(a,l){return a+bkSplit(l,d).length-1},0);if(n>bn){bn=n;dl=d}});
 var hi=-1,col={};
 for(var i=0;i<Math.min(ls.length,40)&&hi<0;i++){var h=bkSplit(ls[i],dl).map(bkNorm),c={};
  h.forEach(function(x,j){
   if(c.d==null&&/^(datum|date|booking date|datum (zauctovani|provedeni|pohybu|transakce))/.test(x))c.d=j;
   else if(c.a==null&&/^(objem|castka|amount|hodnota|castka v|transaction amount)/.test(x))c.a=j;
   else if(c.v==null&&/(variabil|^vs$|variable)/.test(x))c.v=j;
   else if(c.n==null&&/(nazev protistrany|nazev uctu protistrany|protistrana|jmeno protistrany|counterparty|nazev uctu|^platce|^prijemce|^nazev$)/.test(x))c.n=j;
   else if(c.m==null&&/(zprava|poznamk|message|popis|uzivatelska identifikace|note)/.test(x))c.m=j;
   else if(c.c==null&&/^(mena|currency)/.test(x))c.c=j});
  if(c.d!=null&&c.a!=null){hi=i;col=c}}
 if(hi<0)return {err:'Nepodařilo se najít sloupce s datem a částkou. Použijte export pohybů na účtu ve formátu CSV (v internetovém bankovnictví hledejte „Export“ nebo „Stáhnout výpis“).'};
 var rows=[];
 for(var k=hi+1;k<ls.length&&rows.length<3000;k++){var p=bkSplit(ls[k],dl),dt=bkDate(p[col.d]),am=bkNum(p[col.a]);if(!dt||isNaN(am)||am===0)continue;
  rows.push({date:dt,amt:am,vs:col.v!=null?String(p[col.v]||'').replace(/\D/g,''):'',name:col.n!=null?String(p[col.n]||'').trim():'',msg:col.m!=null?String(p[col.m]||'').trim():'',cur:col.c!=null?String(p[col.c]||'').trim().toUpperCase():'CZK'})}
 if(!rows.length)return {err:'Ve výpisu jsem nenašel žádné platby.'};
 return {rows:rows}}
function bkMatch(rows){
 var inv=APP.d.invoices.rows.filter(function(x){return !x.paid_at}),used={};
 function z(v){return String(v||'').replace(/\D/g,'').replace(/^0+/,'')}
 var fe=APP.d.fe.rows;
 rows.forEach(function(r){
  r.act=null;r.on=false;r.note='';
  var kind=r.amt>0?'income':'expense',a=Math.abs(r.amt);
  if(fe.some(function(x){return Math.abs(Math.abs(Number(x.amount)||0)-a)<0.005&&String(x.entry_date||'').slice(0,10)===r.date&&(isInc(x.kind)?'income':'expense')===kind&&String(x.title||'')===(r.name||r.msg||'Bankovní pohyb')})){r.act='dup';r.note='Už je v evidenci.';return}
  if(r.amt>0){
   var cand=inv.filter(function(x){return !used[x.id]&&(x.currency||'CZK')===(r.cur||'CZK')}),hit=null,lvl='';
   if(r.vs){hit=cand.filter(function(x){return z(x.number)===z(r.vs)&&Math.abs(Number(x.total||0)-r.amt)<0.005})[0];if(hit)lvl='sure';
    else{hit=cand.filter(function(x){return z(x.number)===z(r.vs)})[0];if(hit)lvl='vs'}}
   if(!hit){var eq=cand.filter(function(x){return Math.abs(Number(x.total||0)-r.amt)<0.005});if(eq.length===1){hit=eq[0];lvl='maybe'}}
   if(hit){used[hit.id]=1;r.act='pay';r.inv=hit;r.on=(lvl==='sure');r.note=lvl==='sure'?'Sedí variabilní symbol i částka.':lvl==='vs'?'Sedí variabilní symbol, ale částka se liší ('+fM(hit.total,hit.currency)+').':'Sedí částka, variabilní symbol chybí. Zkontrolujte.';return}
   r.act='inc';r.note='Žádná faktura nesedí. Můžete zapsat jako příjem.';return}
  r.act='exp';r.note='Můžete zapsat jako výdaj.'});
 return rows}
function bkView(){
 var rs=BK.rows;if(!rs.length)return '';
 var pay=rs.filter(function(r){return r.act==='pay'&&r.on}).length;
 return '<p class="mut">Načteno '+rs.length+' plateb. Předvybrané jsou jen jistě sedící platby faktur. Ostatní si zaškrtněte sami, nic se neuloží, dokud nepotvrdíte.</p><ul class="rows big bkl">'+rs.map(function(r,i){
  var lab=r.act==='pay'?'Označit fakturu '+esc(r.inv.number||'')+' jako zaplacenou':r.act==='inc'?'Zapsat jako příjem':r.act==='exp'?'Zapsat jako výdaj':'';
  return '<li'+(r.act==='dup'?' class="off"':'')+'><label class="bkr"><input type="checkbox" data-bkrow="'+i+'"'+(r.on?' checked':'')+(r.act==='dup'?' disabled':'')+'><span><b>'+esc(r.name||r.msg||'Bankovní pohyb')+'</b><small>'+fD(r.date)+(r.vs?' · VS '+esc(r.vs):'')+' · '+esc(lab||'Přeskočeno')+' · '+esc(r.note)+'</small></span></label><span class="'+(r.amt>0?'inc':'')+'">'+(r.amt>0?'+':'−')+fM(Math.abs(r.amt),r.cur&&r.cur!=='CZK'?r.cur:'')+'</span></li>'}).join('')+'</ul><div class="dact"><button class="pri" type="button" data-acc="bk-apply">Potvrdit vybrané</button><button class="btn btn-ghost btn-sm" type="button" data-acc="bk-clear">Zrušit</button></div>'}
function bkSt(t,c){var e=A('bkSt');if(e){e.className='st '+(c||'');e.textContent=t}}
async function bkLoad(text){
 var o=bkParse(text);if(o.err){bkSt(o.err,'err');return}
 BK.rows=bkMatch(o.rows);A('bkRes').innerHTML=bkView();bkSt('Výpis načten. Zkontrolujte návrhy níže.','ok')}
async function bkFile(){
 var fi=A('bkFile'),f=fi&&fi.files&&fi.files[0];if(!f){bkSt('Vyberte soubor s výpisem (CSV).','err');return}
 if(f.size>2e6){bkSt('Soubor je příliš velký (nejvýše 2 MB).','err');return}
 try{var buf=await f.arrayBuffer();await bkLoad(bkDec(buf))}catch(e){bkSt('Soubor se nepodařilo přečíst.','err')}}
function bkDec(buf){var t=new TextDecoder('utf-8').decode(buf);if(t.indexOf('�')>=0){try{t=new TextDecoder('windows-1250').decode(buf)}catch(e){}}return t.replace(/^﻿/,'')}
function bkDemo(){
 var un=APP.d.invoices.rows.filter(function(x){return !x.paid_at}).slice(0,2),L=['Datum;Objem;Měna;Protiúčet;Název protistrany;Variabilní symbol;Zpráva pro příjemce'];
 un.forEach(function(x,i){var cu=x.customer_snapshot&&typeof x.customer_snapshot==='object'?(x.customer_snapshot.name||''):'';var d=new Date();d.setDate(d.getDate()-1-i);L.push(d.getDate()+'.'+(d.getMonth()+1)+'.'+d.getFullYear()+';'+String(Number(x.total||0)).replace('.',',')+';CZK;123456789/0800;'+(cu||'Zákazník')+';'+String(x.number||'').replace(/\D/g,'')+';Platba faktury')});
 var t=new Date();L.push(t.getDate()+'.'+(t.getMonth()+1)+'.'+t.getFullYear()+';-1250,00;CZK;987654321/0100;Kancelářské potřeby;;Nákup materiálu');
 L.push(t.getDate()+'.'+(t.getMonth()+1)+'.'+t.getFullYear()+';890,00;CZK;111222333/0300;Neznámý plátce;;Platba kartou terminál');
 bkLoad(L.join('\n'))}
async function bkApply(){
 var sel=BK.rows.filter(function(r){return r.on&&r.act&&r.act!=='dup'});if(!sel.length){bkSt('Nic není vybráno.','err');return}
 if(APP.busy)return;APP.busy=true;var okp=0,oke=0,bad=0;
 try{
  for(var i=0;i<sel.length;i++){var r=sel[i];if(r.act==='pay'){var pr=await rpcInv('paid',{id:r.inv.id,payment_date:r.date});if(pr.error)bad++;else okp++}}
  var ents=sel.filter(function(r){return r.act==='inc'||r.act==='exp'}).map(function(r){return {company_id:APP.cid,title:(r.name||r.msg||'Bankovní pohyb').slice(0,120),amount:Math.abs(r.amt),kind:r.act==='inc'?'income':'expense',entry_date:r.date}});
  if(ents.length){var er=await getSb().from('financial_entries').insert(ents);if(er.error)bad+=ents.length;else oke=ents.length}
 }finally{APP.busy=false}
 BK.rows=[];await refresh();appTab('ucetni');
 toast(bad?'Uloženo '+(okp+oke)+', nepodařilo se '+bad+'.':'Hotovo: '+okp+' zaplacených faktur, '+oke+' nových záznamů.',bad?'err':'ok')}

/* ===== Jednoduchý web: editor, AI návrh, veřejná stránka ===== */
var WEBN=6;
function webDef(){var pr=(APP.d.booking_profiles.rows[0])||{};return {color:'#6d5cff',font:'sans',hero:{title:APP.co||'Vaše firma',subtitle:'',cta:'Kontaktujte nás'},about:{title:'O nás',text:''},services:[],contact:{phone:pr.phone||'',email:'',address:pr.address||'',hours:''},booking:false,footer:''}}
function webUrl(slug){return (location.protocol==='file:'||DEMO?'https://vexaronet.com':location.origin)+'/?w='+slug}
function webSafeTel(v){return String(v||'').replace(/[^0-9+]/g,'').slice(0,20)}
function webOk(v){return /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/.test(String(v||''))}
function siteHTML(d,o){o=o||{};d=d||{};
 var col=/^#[0-9a-f]{6}$/i.test(d.color||'')?d.color:'#6d5cff',ff=d.font==='serif'?"Georgia,'Times New Roman',serif":"-apple-system,'Segoe UI',Roboto,Arial,sans-serif";
 var H=d.hero||{},Ab=d.about||{},C=d.contact||{},sv=(d.services||[]).filter(function(x){return x&&x.name}),nm=o.name||'';
 function nl(t){return esc(t).replace(/\n/g,'<br>')}
 var bk=d.booking&&o.bookUrl?o.bookUrl:'';
 var cta=bk?'<a class="btn" href="'+esc(bk)+'" target="_top">'+esc(H.cta||'Rezervovat termín')+'</a>':'<a class="btn" href="#kontakt">'+esc(H.cta||'Kontaktujte nás')+'</a>';
 var h='<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+esc(H.title||nm)+'</title><meta name="description" content="'+esc(H.subtitle||'')+'"><style>'
 +':root{--c:'+col+'}*{box-sizing:border-box}body{margin:0;font-family:'+ff+';color:#1b1e2e;line-height:1.6;background:#fff}'+(o.prev?'a{pointer-events:none}':'')
 +'.w{max-width:960px;margin:0 auto;padding:0 20px}header{padding:16px 0;border-bottom:1px solid #eceef5}header .w{display:flex;justify-content:space-between;align-items:center;gap:12px}header b{font-size:18px}header a{color:var(--c);text-decoration:none;font-weight:600;font-size:15px}'
 +'.hero{background:linear-gradient(135deg,var(--c),#1b1e2e);color:#fff;padding:72px 0}.hero h1{font-size:clamp(28px,5vw,46px);line-height:1.15;margin:0 0 14px}.hero p{font-size:clamp(16px,2.2vw,20px);margin:0 0 26px;max-width:620px;opacity:.92}'
 +'.btn{display:inline-block;background:#fff;color:#1b1e2e;padding:13px 26px;border-radius:999px;font-weight:700;text-decoration:none}'
 +'section{padding:48px 0}section h2{font-size:28px;margin:0 0 14px}.g{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:16px}.card{border:1px solid #e6e8f2;border-radius:14px;padding:18px}.card h3{margin:0 0 6px;font-size:18px;color:var(--c)}.card p{margin:0;color:#4a4f66;font-size:15px}.card small{display:block;margin-top:8px;font-weight:700}'
 +'.alt{background:#f6f7fb}.ct p{margin:4px 0}.ct a{color:var(--c)}footer{padding:22px 0;color:#7b8199;font-size:13px;border-top:1px solid #eceef5;text-align:center}'
 +'</style></head><body'+(o.prev?' class="prev"':'')+'><header><div class="w"><b>'+esc(nm||H.title||'')+'</b>'+(bk?'<a href="'+esc(bk)+'" target="_top">Rezervace</a>':'<a href="#kontakt">Kontakt</a>')+'</div></header>'
 +'<div class="hero"><div class="w"><h1>'+esc(H.title||nm)+'</h1>'+(H.subtitle?'<p>'+esc(H.subtitle)+'</p>':'')+cta+'</div></div>';
 if(Ab.text)h+='<section><div class="w"><h2>'+esc(Ab.title||'O nás')+'</h2><p>'+nl(Ab.text)+'</p></div></section>';
 if(sv.length)h+='<section class="alt"><div class="w"><h2>Služby</h2><div class="g">'+sv.map(function(x){return '<div class="card"><h3>'+esc(x.name)+'</h3>'+(x.desc?'<p>'+esc(x.desc)+'</p>':'')+(x.price?'<small>'+esc(x.price)+'</small>':'')+'</div>'}).join('')+'</div></div></section>';
 var cl=[];if(C.phone&&webSafeTel(C.phone))cl.push('<p>Telefon: <a href="tel:'+webSafeTel(C.phone)+'">'+esc(C.phone)+'</a></p>');if(webOk(C.email))cl.push('<p>E-mail: <a href="mailto:'+esc(C.email)+'">'+esc(C.email)+'</a></p>');if(C.address)cl.push('<p>Adresa: '+esc(C.address)+'</p>');if(C.hours)cl.push('<p>Otevřeno: '+nl(C.hours)+'</p>');
 if(cl.length||bk)h+='<section id="kontakt"><div class="w ct"><h2>Kontakt</h2>'+cl.join('')+(bk?'<p style="margin-top:14px"><a class="btn" style="background:var(--c);color:#fff" href="'+esc(bk)+'" target="_top">Rezervovat termín online</a></p>':'')+'</div></section>';
 h+='<footer><div class="w">'+(d.footer?esc(d.footer)+' · ':'')+'Web vytvořený ve Vexaronetu</div></footer></body></html>';
 return h}
function webView(){
 var S=APP.d.sites;if(S.err)return '<div class="draft">Editor webu vyžaduje dokončit nastavení databáze (SQL schema_web). Detail: '+esc(S.err)+'</div>';
 var row=S.rows[0]||null,d=Object.assign(webDef(),row&&row.data||{}),slug=row?row.slug:slugify(APP.co),mg=APP.role==='owner'||APP.role==='admin';
 d.hero=Object.assign(webDef().hero,d.hero);d.about=Object.assign(webDef().about,d.about);d.contact=Object.assign(webDef().contact,d.contact);d.services=d.services||[];
 var bp=APP.d.booking_profiles.rows[0],bkOn=!!(bp&&bp.enabled);
 function f(id,l,v,m,t){return '<div class="f full"><label for="'+id+'">'+l+'</label>'+(t==='ta'?'<textarea id="'+id+'" rows="3" maxlength="'+m+'">'+esc(v||'')+'</textarea>':'<input id="'+id+'" maxlength="'+m+'" value="'+esc(v||'')+'">')+'</div>'}
 var h='<div class="card2 note"><b>Jednoduchý firemní web na jedné stránce.</b> Napíšete texty (nebo si je nechte navrhnout AI), zvolíte barvu a zapnete publikování. Web se zobrazí na vašem odkazu '+esc(location.host||'vexaronet.com')+'/?w=… Vlastní doména a e-shop zatím nejsou k dispozici. AI jen navrhuje text, nic nepublikuje, o zveřejnění rozhodujete vy.</div>';
 if(row)h+='<div class="card2 bklink"><div><small class="mut">Odkaz na váš web'+(row.enabled?'':' (zatím je vypnutý)')+'</small><b>'+esc(webUrl(row.slug))+'</b>'+(DEMO?'<small class="mut">V ukázce odkaz na internetu nefunguje, tlačítko níže otevře náhled.</small>':'')+'</div><div class="dact">'+(DEMO?'':'<button type="button" class="btn btn-ghost btn-sm" data-web="copy">Kopírovat odkaz</button>')+'</div></div>';
 h+='<div class="webw"><form id="webForm" class="card2"><h3>Obsah webu</h3>'
 +'<div class="webai"><h4>Návrh textů od AI</h4><p class="mut fine">Popište, čím se zabýváte, pro koho a co nabízíte. AI navrhne nadpis, text o firmě a služby. Návrh se jen vyplní do formuláře, zkontrolujte ho a uložte.'+(hasCeo()?'':' Tato funkce je v tarifu PRO a vyšších.')+'</p><div class="f full"><label for="w_ai">Popis firmy</label><textarea id="w_ai" rows="3" maxlength="900" placeholder="Např. Rodinný autoservis v Plzni, děláme servis, pneuservis a STK přípravu pro místní řidiče a malé firmy."></textarea></div><div class="dact"><button type="button" class="btn btn-ghost btn-sm" data-web="ai"'+(hasCeo()?'':' disabled')+'>Navrhnout texty s AI</button></div><div class="st" id="webAiSt" role="status"></div></div>'
 +'<h4 style="margin:14px 0 6px">Hlavní část</h4>'+f('w_ht','Hlavní nadpis',d.hero.title,80)+f('w_hs','Podnadpis',d.hero.subtitle,160)+f('w_hc','Text tlačítka',d.hero.cta,30)
 +'<h4 style="margin:14px 0 6px">O firmě</h4>'+f('w_at','Nadpis sekce',d.about.title,60)+f('w_ax','Text',d.about.text,700,'ta')
 +'<h4 style="margin:14px 0 6px">Služby (až '+WEBN+')</h4>'+Array.apply(null,Array(WEBN)).map(function(_,i){var x=d.services[i]||{};return '<div class="fg webs"><div class="f"><label for="w_sn'+i+'">Služba '+(i+1)+'</label><input id="w_sn'+i+'" maxlength="60" value="'+esc(x.name||'')+'"></div><div class="f"><label for="w_sp'+i+'">Cena (nepovinné)</label><input id="w_sp'+i+'" maxlength="40" value="'+esc(x.price||'')+'" placeholder="např. od 500 Kč"></div><div class="f full"><label for="w_sd'+i+'">Popis</label><input id="w_sd'+i+'" maxlength="200" value="'+esc(x.desc||'')+'"></div></div>'}).join('')
 +'<h4 style="margin:14px 0 6px">Kontakt</h4><div class="fg"><div class="f"><label for="w_cp">Telefon</label><input id="w_cp" maxlength="40" value="'+esc(d.contact.phone)+'"></div><div class="f"><label for="w_ce">E-mail</label><input id="w_ce" maxlength="120" value="'+esc(d.contact.email)+'"></div></div>'+f('w_ca','Adresa',d.contact.address,200)+f('w_ch','Otevírací doba',d.contact.hours,200)
 +'<h4 style="margin:14px 0 6px">Vzhled a publikování</h4><div class="fg"><div class="f"><label for="w_col">Hlavní barva</label><input id="w_col" type="color" value="'+esc(/^#[0-9a-f]{6}$/i.test(d.color)?d.color:'#6d5cff')+'"></div><div class="f"><label for="w_font">Písmo</label><select id="w_font"><option value="sans"'+(d.font==='serif'?'':' selected')+'>Moderní (bezpatkové)</option><option value="serif"'+(d.font==='serif'?' selected':'')+'>Klasické (patkové)</option></select></div></div>'
 +'<div class="f full"><label class="chk"><input type="checkbox" id="w_bk"'+(d.booking?' checked':'')+(bkOn?'':' disabled')+'><span>Zobrazit tlačítko online rezervace'+(bkOn?'':' (nejdřív zapněte stránku v záložce Online rezervace)')+'</span></label></div>'
 +f('w_ft','Text v patičce (nepovinné)',d.footer,120)
 +'<div class="f full"><label for="w_slug">Adresa webu</label><div class="slugr"><span>'+esc(location.host||'vexaronet.com')+'/?w=</span><input id="w_slug" value="'+esc(slug)+'" maxlength="41" autocomplete="off"></div></div>'
 +'<div class="f full"><label class="chk"><input type="checkbox" id="w_on"'+(row&&row.enabled?' checked':'')+'><span>Web je zapnutý (veřejně viditelný)</span></label></div>'
 +'<div class="st" id="entSt" role="status"></div><div class="dact"><button class="btn btn-main" type="submit"'+(mg?'':' disabled')+'>Uložit web</button><button type="button" class="btn btn-ghost" data-web="open">Zobrazit celou stránku</button></div>'+(mg?'':'<p class="mut fine">Web mohou upravovat jen majitel a správce.</p>')+'</form>'
 +'<aside class="card2 webp"><h3>Náhled</h3><iframe id="webFr" title="Náhled webu" sandbox="" class="webfr"></iframe></aside></div>';
 return h}
function webRead(){
 var g=function(id){var e=A(id);return e?e.value.trim():''},sv=[];
 for(var i=0;i<WEBN;i++){var n=g('w_sn'+i);if(n)sv.push({name:n,desc:g('w_sd'+i),price:g('w_sp'+i)})}
 var bk=A('w_bk');
 return {color:g('w_col')||'#6d5cff',font:g('w_font')||'sans',hero:{title:g('w_ht'),subtitle:g('w_hs'),cta:g('w_hc')},about:{title:g('w_at'),text:g('w_ax')},services:sv,contact:{phone:g('w_cp'),email:g('w_ce'),address:g('w_ca'),hours:g('w_ch')},booking:!!(bk&&bk.checked&&!bk.disabled),footer:g('w_ft')}}
function webBook(){var bp=APP.d.booking_profiles.rows[0];return bp&&bp.enabled?bookUrl(bp.slug):''}
function webPrev(){var fr=A('webFr');if(!fr)return;fr.srcdoc=siteHTML(webRead(),{prev:true,name:APP.co,bookUrl:webBook()||'#'})}
function webSt(t,c){var e=A('webAiSt');if(e){e.className='st '+(c||'');e.textContent=t}}
function webFill(x){
 function sv(id,v){var e=A(id);if(e&&v!=null)e.value=v}
 if(x.hero){sv('w_ht',x.hero.title);sv('w_hs',x.hero.subtitle);sv('w_hc',x.hero.cta)}
 if(x.about){sv('w_at',x.about.title);sv('w_ax',x.about.text)}
 if(x.services){for(var i=0;i<WEBN;i++){var o=x.services[i];sv('w_sn'+i,o?o.name:'');sv('w_sd'+i,o?o.desc:'')}}
 webPrev()}
async function webAI(){
 var ds=(A('w_ai').value||'').trim();if(ds.length<15){webSt('Napište aspoň pár vět o firmě.','err');return}
 if(!hasCeo()){webSt('AI návrh textů je v tarifu PRO a vyšších.','err');return}
 if(APP.busy)return;APP.busy=true;webSt('AI píše návrh, bývá to pár sekund…','ok');
 try{var ses=(await getSb().auth.getSession()).data.session;
  var r=await dfetch('/api/web-ai',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+(ses?ses.access_token:'')},body:JSON.stringify({name:APP.co,description:ds})});
  var j=await r.json().catch(function(){return null});
  if(!r.ok||!j||!j.site){var c=j&&j.error;webSt(r.status===403?'AI návrh textů je v tarifu PRO a vyšších.':r.status===429?'Příliš mnoho požadavků. Zkuste to za chvíli.':c==='not_configured'?'AI zatím není na serveru zapnutá. Napište nám na info@vexaronet.com.':'Návrh se nepodařilo vytvořit. Zkuste to znovu.','err');return}
  webFill(j.site);webSt((j.demo?'Ukázkový návrh (v ostrém účtu ho píše AI podle vašeho popisu). ':'')+'Návrh je ve formuláři, ještě není uložený. Zkontrolujte texty a upravte je podle sebe.','ok')
 }catch(x){webSt('Návrh se nepodařilo vytvořit. Zkuste to znovu.','err')}finally{APP.busy=false}}
async function saveWeb(f){
 var sl=A('w_slug').value.trim().toLowerCase();if(!/^[a-z0-9][a-z0-9-]{2,40}$/.test(sl)){entMsg('Adresa: 3 až 41 znaků, malá písmena bez diakritiky, čísla a pomlčky.');return}
 var d=webRead(),en=A('w_on').checked;
 if(en&&!d.hero.title){entMsg('Pro zapnutí webu vyplňte hlavní nadpis.');return}
 var b=f.querySelector('button[type=submit]');b.disabled=true;
 var r=await getSb().from('sites').upsert({company_id:APP.cid,slug:sl,enabled:en,data:d,updated_at:new Date().toISOString()},{onConflict:'company_id'});b.disabled=false;
 if(r.error){entMsg(/duplicate|unique|23505/i.test(r.error.message+(r.error.code||''))?'Tuto adresu už používá jiný web, zvolte jinou.':'Nepodařilo se uložit: '+r.error.message);return}
 await refresh();appTab('weby');toast(en?'Uloženo. Web je zapnutý.':'Uloženo. Web je zatím vypnutý.','ok')}
async function webOpen(slug,prev){
 var old=A('vxsite');if(old)old.remove();
 var el=document.createElement('div');el.id='vxsite';el.className='vxsite';document.body.appendChild(el);document.documentElement.style.overflow='hidden';
 function close(){el.remove();document.documentElement.style.overflow=A('vxapp')?'hidden':'';if(!prev){try{history.replaceState(null,'',location.pathname)}catch(e){}}}
 var fr=document.createElement('iframe');fr.className='vxsf';fr.title='Web';fr.setAttribute('sandbox','allow-popups allow-top-navigation-by-user-activation');el.appendChild(fr);
 if(prev){var x=document.createElement('button');x.type='button';x.className='vxsx';x.textContent='Zavřít náhled';x.addEventListener('click',close);el.appendChild(x);fr.srcdoc=siteHTML(webRead(),{name:APP.co,bookUrl:webBook()});return}
 var r=null;try{r=await getSb().rpc('public_site',{p_slug:slug})}catch(e){}
 if(!r||r.error||!r.data){fr.srcdoc='<!doctype html><meta charset="utf-8"><body style="font-family:Arial;padding:40px"><h1>Stránka nenalezena</h1><p>Web neexistuje nebo je vypnutý. Zkontrolujte odkaz.</p>';return}
 var dd=r.data;try{document.title=(dd.data&&dd.data.hero&&dd.data.hero.title)||dd.name||document.title}catch(e){}
 fr.srcdoc=siteHTML(dd.data,{name:dd.name,bookUrl:dd.booking?bookUrl(dd.booking):''})}

/* ===== Marketing: AI návrhy textů a plán příspěvků ===== */
var MKK=[['social','Příspěvek na sociální sítě','Sociální sítě'],['email','E-mail zákazníkům (newsletter)','E-mail'],['ad','Text online reklamy','Reklama'],['plan','Plán obsahu na týden','Plán obsahu'],['review','Odpověď na recenzi','Recenze']],MKCH=['Instagram','Facebook','E-mail','Web nebo blog','Reklama','Jiné'],MKST={draft:'Koncept',planned:'Naplánováno',done:'Zveřejněno'};
function mkView(){
 var P=APP.d.marketing_posts;if(P.err)return '<div class="draft">Marketing vyžaduje dokončit nastavení databáze (SQL schema_marketing). Detail: '+esc(P.err)+'</div>';
 var rs=P.rows.slice().sort(function(a,b){return String(b.planned_on||b.created_at).localeCompare(String(a.planned_on||a.created_at))});
 var h='<div class="card2 note"><b>AI pomocník pro marketing.</b> Napíšete, o čem chcete psát, a AI navrhne text příspěvku, e-mailu, reklamy nebo týdenní plán. Nic se nikam neodesílá ani nepublikuje, text si zkontrolujete, upravíte a zkopírujete. Hromadné marketingové e-maily smíte posílat jen zákazníkům, kteří s tím souhlasili, a Vexaronet je zatím sám neodesílá.</div>';
 h+='<section class="card2"><h3>Navrhnout text</h3>'+(hasCeo()?'':'<p class="mut fine">Návrhy od AI jsou v tarifu PRO a vyšších. Plán příspěvků níže můžete vést i bez nich.</p>')
 +'<div class="fg"><div class="f"><label for="mk_kind">Co potřebujete</label><select id="mk_kind">'+MKK.map(function(k){return '<option value="'+k[0]+'">'+k[1]+'</option>'}).join('')+'</select></div><div class="f"><label for="mk_tone">Tón</label><select id="mk_tone"><option value="friendly">Přátelský</option><option value="pro">Profesionální</option><option value="light">Odlehčený</option></select></div>'
 +'<div class="f full"><label for="mk_topic">O čem to má být</label><textarea id="mk_topic" rows="3" maxlength="700" placeholder="Např. Od listopadu nabízíme přezutí zimních pneumatik, objednat se dá online. Napište i cenu nebo slevu, pokud ji chcete uvést."></textarea></div></div>'
 +'<div class="dact"><button type="button" class="pri" data-mk="gen"'+(hasCeo()?'':' disabled')+'>Navrhnout s AI</button></div><div class="st" id="mkSt" role="status"></div>'
 +'<div id="mkRes"></div></section>';
 h+='<section class="card2"><div class="bar2"><h3>Plán příspěvků</h3><button type="button" class="btn btn-main btn-sm" data-new="marketing_posts">+ Nový příspěvek</button></div>'+errBox(P)
 +(rs.length?'<ul class="rows big">'+rs.map(function(r){return '<li data-edit="marketing_posts:'+esc(r.id)+'"><div><b>'+esc(r.title)+'</b><small>'+esc(r.channel||'bez kanálu')+' · '+esc(MKST[r.status]||r.status)+'</small></div><span>'+(r.planned_on?fD(r.planned_on):'bez data')+'</span></li>'}).join('')+'</ul>':'<p class="mut">Zatím žádné příspěvky. Nechte si jeden navrhnout výše, nebo přidejte vlastní.</p>')+'</section>';
 return h}
function mkSt(t,c){var e=A('mkSt');if(e){e.className='st '+(c||'');e.textContent=t}}
async function mkGen(){
 var tp=(A('mk_topic').value||'').trim();if(tp.length<5){mkSt('Napište aspoň pár slov, o čem má text být.','err');return}
 if(!hasCeo()){mkSt('Návrhy od AI jsou v tarifu PRO a vyšších.','err');return}
 if(APP.busy)return;APP.busy=true;mkSt('AI píše návrh, bývá to pár sekund…','ok');A('mkRes').innerHTML='';
 try{var ses=(await getSb().auth.getSession()).data.session;
  var r=await dfetch('/api/marketing',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+(ses?ses.access_token:'')},body:JSON.stringify({kind:A('mk_kind').value,tone:A('mk_tone').value,topic:tp,name:APP.co})});
  var j=await r.json().catch(function(){return null});
  if(!r.ok||!j||!j.text){var c=j&&j.error;mkSt(r.status===403?'Návrhy od AI jsou v tarifu PRO a vyšších.':r.status===429?'Příliš mnoho požadavků. Zkuste to za chvíli.':c==='not_configured'?'AI zatím není na serveru zapnutá. Napište nám na info@vexaronet.com.':'Návrh se nepodařilo vytvořit. Zkuste to znovu.','err');return}
  mkSt((j.demo?'Ukázkový návrh (v ostrém účtu ho píše AI podle vašeho zadání). ':'')+'Zkontrolujte text a doplňte údaje ve značkách [doplnit].','ok');
  A('mkRes').innerHTML='<div class="f full"><label for="mk_out">Návrh textu (můžete upravit)</label><textarea id="mk_out" rows="9" maxlength="4000">'+esc(j.text)+'</textarea></div><div class="dact"><button type="button" class="btn btn-ghost btn-sm" data-mk="copy">Kopírovat</button><button type="button" class="btn btn-main btn-sm" data-mk="save">Uložit do plánu</button></div>'
 }catch(x){mkSt('Návrh se nepodařilo vytvořit. Zkuste to znovu.','err')}finally{APP.busy=false}}
async function mkSave(){
 var tx=(A('mk_out').value||'').trim();if(!tx)return;var kd=MKK.filter(function(k){return k[0]===A('mk_kind').value})[0]||MKK[0],tp=(A('mk_topic').value||'').trim();
 var ch={social:'Instagram',email:'E-mail',ad:'Reklama',plan:'Jiné',review:'Jiné'}[kd[0]];
 var r=await getSb().from('marketing_posts').insert({company_id:APP.cid,title:(kd[2]+': '+tp).slice(0,100),channel:ch,status:'draft',body:tx});
 if(r.error){mkSt('Nepodařilo se uložit: '+r.error.message,'err');return}
 await refresh();appTab('marketing');toast('Uloženo do plánu jako koncept.','ok')}
async function accProcess(){
 var fi=A('accFile'),f=fi&&fi.files&&fi.files[0];
 if(!f){accSt('Vyberte soubor s dokladem (foto nebo PDF).','err');return}
 var mt=(f.type||(/\.hei[cf]$/i.test(f.name)?'image/heic':'')).toLowerCase();
 if(!/^(image\/(jpeg|png|webp|heic|heif)|application\/pdf)$/.test(mt)){accSt('Podporované jsou fotky (JPG, PNG, WebP, HEIC) a PDF.','err');return}
 if(f.size>6e6){accSt('Soubor je příliš velký (nejvýše 6 MB).','err');return}
 if(APP.busy)return;APP.busy=true;accSt('Zpracovávám doklad, bývá to pár sekund…','ok');A('accRes').innerHTML='';
 try{var data=await new Promise(function(res,rej){var fr=new FileReader();fr.onload=function(){res(String(fr.result).split(',')[1]||'')};fr.onerror=rej;fr.readAsDataURL(f)});
  var o=await accCall({mime:mt,data:data});
  if(!o.r.ok){accSt(accErr(o.r,o.j),'err');return}
  APP.accDoc=o.j.doc;accUse(o.j.used,o.j.limit);accSt('Hotovo. Zkontrolujte údaje níže, nic ještě není uložené.','ok');A('accRes').innerHTML=accForm(o.j.doc)
 }catch(x){accSt('Zpracování se nepodařilo. Zkuste to znovu.','err')}finally{APP.busy=false}}
function accForm(d){
 var cz=!d.currency||d.currency==='CZK',w=(d.warnings||[]).slice();
 if(!cz)w.push('Doklad je v měně '+d.currency+'. Zadejte částku v Kč podle svého kurzu.');
 if(d.total_amount==null)w.push('Částka nebyla na dokladu nalezena.');
 if(d.confidence==='low')w.push('AI si u tohoto dokladu není jistá. Zkontrolujte všechny údaje.');
 var inc=d.document_type==='issued_invoice',title=[d.supplier_name,d.document_number,d.description].filter(Boolean).join(' · ')||'Doklad',
  rows=[['Dodavatel',d.supplier_name],['IČO',d.supplier_ico],['DIČ',d.supplier_dic],['Číslo dokladu',d.document_number],['Datum vystavení',d.issue_date?fD(d.issue_date):null],['Splatnost',d.due_date?fD(d.due_date):null],['Celkem na dokladu',d.total_amount==null?null:d.total_amount+' '+(d.currency||'')],['DPH',d.vat_amount==null?null:d.vat_amount+' '+(d.currency||'')+(d.vat_rate!=null?' ('+d.vat_rate+' %)':'')],['Navržená kategorie',d.category]].filter(function(x){return x[1]});
 return '<form id="accRF" class="accrf"><h4>Navržený záznam</h4>'+(w.length?'<div class="draft">'+w.map(esc).join('<br>')+'</div>':'')+'<div class="fg"><div class="f"><label for="af_kind">Druh</label><select id="af_kind"><option value="expense"'+(inc?'':' selected')+'>Výdaj</option><option value="income"'+(inc?' selected':'')+'>Příjem</option></select></div><div class="f"><label for="af_amt">Částka v Kč <i>*</i></label><input id="af_amt" type="number" step="any" min="0" required value="'+(cz&&d.total_amount!=null?esc(Math.abs(d.total_amount)):'')+'"></div><div class="f"><label for="af_date">Datum <i>*</i></label><input id="af_date" type="date" required value="'+esc(d.issue_date||locD(new Date()))+'"></div><div class="f full"><label for="af_title">Popis <i>*</i></label><input id="af_title" required maxlength="200" value="'+esc(title)+'"></div></div><details><summary>Údaje načtené z dokladu</summary><ul class="rows">'+rows.map(function(x){return '<li><b>'+x[0]+'</b><span>'+esc(x[1])+'</span></li>'}).join('')+'<li><b>Jistota AI</b><span>'+({low:'nízká',medium:'střední',high:'vysoká'}[d.confidence]||'')+'</span></li></ul></details><div class="dact"><button class="pri" type="submit">Uložit do evidence</button><button class="btn btn-ghost" type="button" data-acc="discard">Zahodit</button></div></form>'}
async function accAsk(q){
 if(APP.busy)return;APP.busy=true;APP.accChat=APP.accChat||[];APP.accChat.push({role:'user',content:q});
 var lg=A('accLog');if(lg){lg.innerHTML=accMsgs()+'<div class="msg bot" id="accWait">Píšu odpověď…</div>';lg.scrollTop=lg.scrollHeight}
 var rep=null,err='';
 try{var sm=summary(),ac=accStats();sm.prijmy_tento_mesic_kc=ac.i0;sm.vydaje_tento_mesic_kc=ac.e0;sm.prijmy_minuly_mesic_kc=ac.i1;sm.vydaje_minuly_mesic_kc=ac.e1;sm.zaznamu_v_evidenci=APP.d.fe.rows.length;
  var o=await accCall({mode:'ask',messages:APP.accChat.slice(-10),summary:sm});if(o.r.ok&&o.j&&o.j.reply)rep=o.j.reply;else err=accErr(o.r,o.j)}catch(x){err='AI Účetní teď není dostupná. Zkuste to později.'}
 if(rep)APP.accChat.push({role:'assistant',content:rep});else APP.accChat.pop();
 APP.busy=false;lg=A('accLog');if(lg){lg.innerHTML=accMsgs()+(rep?'':'<div class="msg bot err">'+esc(err)+'</div>');lg.scrollTop=lg.scrollHeight}}
function accExport(kind){var m=A('accMon')?A('accMon').value:'',d=APP.d,rows,name;
 if(kind==='ent'){rows=[['Datum','Druh','Popis','Částka v Kč']];d.fe.rows.slice().sort(function(a,b){return new Date(a.entry_date||a.created_at)-new Date(b.entry_date||b.created_at)}).forEach(function(r){var k=String(r.entry_date||r.created_at||'').slice(0,10);if(m&&k.slice(0,7)!==m)return;rows.push([k,isInc(r.kind)?'Příjem':'Výdaj',r.title||'',String(Math.abs(Number(r.amount)||0)).replace('.',',')])});name='vexaronet-prijmy-vydaje'+(m?'-'+m:'')+'.csv'}
 else{rows=[['Číslo','Zákazník','Vystaveno','Splatnost','Celkem','Měna','Zaplaceno dne']];d.invoices.rows.slice().sort(function(a,b){return new Date(a.issued_on||a.created_at)-new Date(b.issued_on||b.created_at)}).forEach(function(x){var k=String(x.issued_on||x.created_at||'').slice(0,10);if(m&&k.slice(0,7)!==m)return;rows.push([x.number||'',invName(x),k,String(x.due_on||'').slice(0,10),String(Number(x.total||0)).replace('.',','),x.currency||'CZK',String(x.paid_at||'').slice(0,10)])});name='vexaronet-faktury'+(m?'-'+m:'')+'.csv'}
 if(rows.length<2){toast('V tomto období nejsou žádná data k exportu.','err');return}
 var csv='﻿'+rows.map(function(r){return r.map(function(c){var t=String(c==null?'':c);return /[;"\n\r]/.test(t)?'"'+t.replace(/"/g,'""')+'"':t}).join(';')}).join('\r\n'),b=new Blob([csv],{type:'text/csv;charset=utf-8'}),u=URL.createObjectURL(b),a=document.createElement('a');a.href=u;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(function(){URL.revokeObjectURL(u)},1500);toast('Export stažen: '+name,'ok')}
/* ---- akce AI CEO (vždy po potvrzení) ---- */
function modal(h){var m=A('appModal');if(!m){m=document.createElement('div');m.id='appModal';m.className='amodal on';m.setAttribute('role','dialog');m.setAttribute('aria-modal','true');A('vxapp').appendChild(m)}m.className='amodal on';m.innerHTML='<div class="mbox">'+h+'</div>'}

/* ---- náhled faktury ---- */
function invHTML(f){
 var sp=f.supplier_snapshot&&typeof f.supplier_snapshot==='object'?f.supplier_snapshot:{},cu=f.customer_snapshot&&typeof f.customer_snapshot==='object'?f.customer_snapshot:{},cur=f.currency||'CZK',
  its=(Array.isArray(f.items)&&f.items)||(Array.isArray(f.lines)&&f.lines)||[],vat={},tot=0,rows='';
 function m(n){return Number(n||0).toLocaleString('cs-CZ',{minimumFractionDigits:2,maximumFractionDigits:2})+' '+(cur==='CZK'?'Kč':esc(cur))}
 if(its.length){its.forEach(function(i){var q=Number(i.quantity)||0,g=Number(i.unit_gross)||0,r=Number(i.vat_rate)||0,l=q*g;tot+=l;var k=String(r);vat[k]=vat[k]||{g:0};vat[k].g+=l;
   rows+='<tr><td>'+esc(i.description||'')+'</td><td class="r">'+esc(q)+' '+esc(i.unit||'')+'</td><td class="r">'+m(g)+'</td><td class="r">'+r+' %</td><td class="r">'+m(l)+'</td></tr>'})}
 else{tot=Number(f.total)||0;rows='<tr><td colspan="4">Celková částka faktury (položky nejsou v tomto zobrazení k dispozici)</td><td class="r">'+m(tot)+'</td></tr>'}
 var rec='';Object.keys(vat).sort(function(a,b){return b-a}).forEach(function(k){var g=vat[k].g,r=Number(k),n=r?g/(1+r/100):g;rec+='<tr><td>'+r+' %</td><td class="r">'+m(n)+'</td><td class="r">'+m(g-n)+'</td><td class="r">'+m(g)+'</td></tr>'});
 function blk(t,o){return '<div><h4>'+t+'</h4><b>'+esc(o.legal_name||o.name||o.company_name||'–')+'</b><br>'+(o.address_text||o.billing_address?esc(o.address_text||o.billing_address)+'<br>':'')+(o.ico?'IČO: '+esc(o.ico)+'<br>':'')+(o.dic?'DIČ: '+esc(o.dic)+'<br>':'')+(o.email?esc(o.email):'')+'</div>'}
 return '<div class="invdoc"><div class="ih"><div><h2>Faktura – daňový doklad</h2><div class="inum">č. '+esc(f.number||'bez čísla')+'</div></div><div class="ist '+(f.paid_at?'ok':'')+'">'+(f.paid_at?'ZAPLACENO':'K ÚHRADĚ')+'</div></div>'
 +'<div class="i2">'+blk('Dodavatel',sp)+blk('Odběratel',cu)+'</div>'
 +'<div class="i3"><div><small>Datum vystavení</small><b>'+fD(f.issued_on)+'</b></div><div><small>Datum zdan. plnění</small><b>'+fD(f.taxable_supply_on||f.issued_on)+'</b></div><div><small>Splatnost</small><b>'+fD(f.due_on)+'</b></div><div><small>Číslo účtu</small><b>'+esc(sp.bank_account||sp.iban||'–')+'</b></div></div>'
 +'<table class="it"><thead><tr><th>Popis</th><th class="r">Množství</th><th class="r">Cena/jedn. s DPH</th><th class="r">DPH</th><th class="r">Celkem s DPH</th></tr></thead><tbody>'+rows+'</tbody></table>'
 +(rec?'<table class="it sm"><thead><tr><th>Sazba DPH</th><th class="r">Základ</th><th class="r">DPH</th><th class="r">Celkem</th></tr></thead><tbody>'+rec+'</tbody></table>':'')
 +'<div class="itot">Celkem k úhradě <b>'+m(Number(f.total)||tot)+'</b></div>'+(f.paid_at?'<p class="ifine">Uhrazeno dne '+fD(f.paid_at)+'.</p>':'')+'<p class="ifine">Vystaveno ve Vexaronetu. Náhled faktury; odesílání e-mailem a QR platba se připravují.</p></div>'}
var INVCSS='.invdoc{background:#fff;color:#14172b;border-radius:10px;padding:26px;font:14px/1.5 system-ui,Arial,sans-serif;text-align:left}.invdoc h2{margin:0;font-size:22px;color:#14172b}.invdoc h4{margin:0 0 4px;font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#6b7090}.invdoc .ih{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;border-bottom:2px solid #5b6eff;padding-bottom:12px;margin-bottom:16px}.invdoc .inum{color:#5b6eff;font-weight:700;margin-top:2px}.invdoc .ist{border:2px solid #d9822b;color:#d9822b;font-weight:800;padding:4px 10px;border-radius:8px;white-space:nowrap}.invdoc .ist.ok{border-color:#1a9d63;color:#1a9d63}.invdoc .i2{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:16px}.invdoc .i3{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;background:#f2f4fb;padding:10px 12px;border-radius:8px;margin-bottom:16px}.invdoc .i3 small{display:block;color:#6b7090;font-size:11px}.invdoc table{width:100%;border-collapse:collapse;margin-bottom:12px}.invdoc th{text-align:left;font-size:11px;color:#6b7090;border-bottom:1px solid #d5d9ea;padding:6px 4px}.invdoc td{padding:7px 4px;border-bottom:1px solid #eceef7}.invdoc .r{text-align:right}.invdoc .sm td,.invdoc .sm th{font-size:12px}.invdoc .itot{text-align:right;font-size:16px;margin-top:8px}.invdoc .itot b{font-size:22px;color:#5b6eff;margin-left:8px}.invdoc .ifine{color:#6b7090;font-size:12px;margin:8px 0 0}@media(max-width:620px){.invdoc{padding:16px}.invdoc .i2{grid-template-columns:1fr}.invdoc .i3{grid-template-columns:1fr 1fr}.invdoc .it{font-size:12px}}';
function invView(id){var f=APP.d.invoices.rows.filter(function(x){return x.id===id})[0];if(!f)return;APP.invOpen=f;
 modal('<style>'+INVCSS+'</style>'+invHTML(f)+'<div class="dact"><button class="btn btn-main btn-sm" type="button" data-invprint="1">Vytisknout / uložit jako PDF</button><button class="btn btn-ghost btn-sm" type="button" data-app="mclose">Zavřít</button></div>')}
function invPrint(){var f=APP.invOpen;if(!f)return;var fr=document.createElement('iframe');fr.style.cssText='position:fixed;right:0;bottom:0;width:0;height:0;border:0';document.body.appendChild(fr);var d=fr.contentWindow.document;d.open();d.write('<!doctype html><html lang="cs"><head><meta charset="utf-8"><title>Faktura '+esc(f.number||'')+'</title><style>body{margin:0;padding:20px}'+INVCSS+'.invdoc{padding:0}</style></head><body>'+invHTML(f)+'</body></html>');d.close();setTimeout(function(){try{fr.contentWindow.focus();fr.contentWindow.print()}catch(e){}setTimeout(function(){fr.remove()},2000)},300)}

/* ---- kalendář ---- */
var CALK={r:'Rezervace',j:'Termín zakázky',s:'Směna',t:'Úkol'},CALO={r:0,s:1,j:2,t:3};
function hmm(v){return new Date(v).toLocaleTimeString('cs-CZ',{hour:'2-digit',minute:'2-digit'})}
function calItems(){var m={},d=APP.d;
 function add(k,dt,o){if(!dt)return;var dd=new Date(dt);if(isNaN(dd))return;var key=locD(dd);o.k=k;o.at=dd.getTime();(m[key]=m[key]||[]).push(o)}
 d.reservations.rows.forEach(function(r){if(!r.canceled)add('r',r.starts_at,{id:r.id,ent:'reservations',t:r.title||'Rezervace',tm:hmm(r.starts_at)+' – '+hmm(r.ends_at),lab:hmm(r.starts_at)+' '+(r.title||'Rezervace')})});
 d.jobs.rows.forEach(function(j){if(!DONE.test(j.status||''))add('j',j.due_at,{id:j.id,ent:'jobs',t:j.title||'Zakázka',tm:'termín dokončení',lab:j.title||'Zakázka'})});
 d.tasks.rows.forEach(function(t){if(!t.completed)add('t',t.due_at,{id:t.id,ent:'tasks',t:t.title||'Úkol',tm:'termín úkolu',lab:t.title||'Úkol'})});
 (d.shifts&&d.shifts.rows||[]).forEach(function(x){var nm=String(x.person||'').split('@')[0];add('s',x.starts_at,{id:x.id,ent:'shifts',t:nm+(x.note?' – '+x.note:''),tm:hmm(x.starts_at)+' – '+hmm(x.ends_at),lab:nm.split(' ')[0]+' '+hmm(x.starts_at)+'–'+hmm(x.ends_at).replace(/^0/,'')})});
 Object.keys(m).forEach(function(k){m[k].sort(function(a,b){return (CALO[a.k]-CALO[b.k])||(a.at-b.at)})});return m}
function calList(){
 var cm=cmap(),x=APP.d.reservations,rs=x.rows.slice().sort(function(a,b){return new Date(a.starts_at)-new Date(b.starts_at)});
 if(!rs.length)return '<p class="mut">Zatím žádné rezervace.</p>';
 var h='',cur='',now=dayStart(0);h+='<div class="cal">';
 rs.forEach(function(r){var k=locD(r.starts_at);if(k!==cur){if(cur)h+='</ul>';cur=k;var d=new Date(r.starts_at);h+='<h4 class="dh'+(d<now?' past':'')+(k===locD(new Date())?' today':'')+'">'+d.toLocaleDateString('cs-CZ',{weekday:'long',day:'numeric',month:'long',year:'numeric'})+'</h4><ul class="rows big">'}
  h+='<li data-edit="reservations:'+esc(r.id)+'"'+(r.canceled?' class="off"':'')+'><div><b>'+esc(r.title||'Rezervace')+'</b><small>'+esc(cm[r.customer_id]||'bez zákazníka')+'</small></div><span>'+hmm(r.starts_at)+' – '+hmm(r.ends_at)+(r.canceled?' · zrušeno':'')+'</span></li>'});
 return h+'</ul></div>'}
function teamNames(){var a=[];(APP.team||[]).forEach(function(x){if(x.email)a.push(x.email)});if(APP.meta&&APP.meta.full_name&&a.indexOf(APP.meta.full_name)<0)a.unshift(APP.meta.full_name);return a}
function calRe(){var m=A('appMain'),y=m?m.scrollTop:0;appTab(APP.tab);if(m)m.scrollTop=y}
/* ---- online rezervace (veřejná stránka) ---- */
var BKDN=['Pondělí','Úterý','Středa','Čtvrtek','Pátek','Sobota','Neděle'];
function slugify(t){return String(t||'').normalize('NFD').replace(/[̀-ͯ]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'').slice(0,40)}
function bookUrl(sl){return (location.protocol==='file:'||DEMO?'https://vexaronet.com':location.origin)+'/?r='+sl}
function onlineView(){
 var P=APP.d.booking_profiles,pr=P.rows[0]||{},sv=APP.d.booking_services,hrs=pr.hours||{},has=!!pr.slug,slug=pr.slug||slugify(APP.co);
 if(P.err)return '<div class="draft">Online rezervace vyžadují dokončit nastavení databáze (SQL schema_rezervace). Detail: '+esc(P.err)+'</div>';
 var h='<div class="card2 note"><b>Veřejná rezervační stránka.</b> Nastavíte otevírací dobu a služby, zkopírujete odkaz a pošlete ho zákazníkům (web, Instagram, vizitka, e-mail). Zákazník si sám vybere službu a volný termín, rezervace se vám objeví v kalendáři. Zákazník po rezervaci dostane potvrzení e-mailem se souborem do kalendáře.</div>';
 if(has)h+='<div class="card2 bklink"><div><small class="mut">Váš odkaz pro zákazníky'+(pr.enabled?'':' (stránka je zatím vypnutá)')+'</small><b>'+esc(bookUrl(pr.slug))+'</b>'+(DEMO?'<small class="mut">V ukázce odkaz na internetu nefunguje, tlačítko níže otevře náhled.</small>':'')+'</div><div class="dact">'+(DEMO?'':'<button type="button" class="btn btn-ghost btn-sm" data-bkcopy="1">Kopírovat odkaz</button>')+'<button type="button" class="btn btn-main btn-sm" data-bkopen="1">'+(DEMO?'Zobrazit jako zákazník':'Otevřít stránku')+'</button></div></div>';
 h+='<form id="bookForm" class="card2"><h3>Nastavení stránky</h3><div class="fg"><div class="f full"><label class="chk"><input type="checkbox" id="bk_on"'+(pr.enabled?' checked':'')+'><span>Stránka je zapnutá (zákazníci se mohou objednávat)</span></label></div>'
 +'<div class="f full"><label for="bk_slug">Adresa stránky</label><div class="slugr"><span>vexaronet.com/?r=</span><input id="bk_slug" value="'+esc(slug)+'" maxlength="41" autocomplete="off"></div></div>'
 +'<div class="f full"><label for="bk_title">Nadpis</label><input id="bk_title" maxlength="120" value="'+esc(pr.title||(APP.co+' – online rezervace'))+'"></div>'
 +'<div class="f full"><label for="bk_desc">Krátký popis</label><textarea id="bk_desc" rows="2" maxlength="400">'+esc(pr.description||'')+'</textarea></div>'
 +'<div class="f"><label for="bk_addr">Adresa provozovny</label><input id="bk_addr" maxlength="200" value="'+esc(pr.address||'')+'"></div><div class="f"><label for="bk_tel">Telefon</label><input id="bk_tel" maxlength="40" value="'+esc(pr.phone||'')+'"></div></div>'
 +'<h4 style="margin:16px 0 8px">Otevírací doba</h4><div class="hrs">'+BKDN.map(function(n,i){var d=i+1,o=has?hrs[d]:(d<=5?{o:'08:00',c:'17:00'}:null);return '<div class="hr"><label class="chk"><input type="checkbox" id="hk_'+d+'_on"'+(o?' checked':'')+'><span>'+n+'</span></label><input type="time" id="hk_'+d+'_o" value="'+esc(o?o.o:'08:00')+'" aria-label="Od"><span>–</span><input type="time" id="hk_'+d+'_c" value="'+esc(o?o.c:'17:00')+'" aria-label="Do"></div>'}).join('')+'</div>'
 +'<div class="fg" style="margin-top:12px"><div class="f"><label for="bk_step">Krok nabízených časů</label><select id="bk_step">'+[15,30,45,60].map(function(m){return '<option value="'+m+'"'+((pr.slot_minutes||30)===m?' selected':'')+'>'+m+' minut</option>'}).join('')+'</select></div><div class="f"><label for="bk_cap">Kolik zákazníků najednou (kapacita)</label><input id="bk_cap" type="number" min="1" max="50" value="'+esc(pr.capacity||1)+'"></div></div>'
 +'<div class="st" id="entSt" role="status"></div><div class="dact"><button class="btn btn-main" type="submit">Uložit nastavení</button></div></form>'
 +'<section class="card2"><div class="bar2"><h3>Služby</h3><button type="button" class="btn btn-main btn-sm" data-new="booking_services">+ Přidat službu</button></div>'+errBox(sv)
 +(sv.rows.length?'<ul class="rows big">'+sv.rows.map(function(x){return '<li data-edit="booking_services:'+esc(x.id)+'"'+(x.active===false?' class="off"':'')+'><div><b>'+esc(x.name)+'</b><small>'+esc(x.duration_min)+' min'+(x.active===false?' · nenabízí se':'')+'</small></div><span>'+(x.price!=null?fM(x.price):'cena neuvedena')+'</span></li>'}).join('')+'</ul>':'<p class="mut">Zatím žádné služby. Přidejte první (například „Prohlídka vozu, 30 minut“).</p>')+'</section>';
 return h}
async function saveBook(f){
 var sl=A('bk_slug').value.trim().toLowerCase();if(!/^[a-z0-9][a-z0-9-]{2,40}$/.test(sl)){entMsg('Adresa: 3 až 41 znaků, malá písmena bez diakritiky, čísla a pomlčky.');return}
 var hh={};for(var d=1;d<=7;d++){if(A('hk_'+d+'_on').checked){var o=A('hk_'+d+'_o').value,c=A('hk_'+d+'_c').value;if(!o||!c||o>=c){entMsg('Zkontrolujte otevírací dobu ('+BKDN[d-1]+').');return}hh[d]={o:o,c:c}}}
 var en=A('bk_on').checked;
 if(en&&!APP.d.booking_services.rows.some(function(x){return x.active!==false})){entMsg('Pro zapnutí stránky přidejte alespoň jednu službu.');return}
 if(en&&!Object.keys(hh).length){entMsg('Nastavte alespoň jeden otevřený den.');return}
 var row={company_id:APP.cid,slug:sl,enabled:en,title:A('bk_title').value.trim()||null,description:A('bk_desc').value.trim()||null,address:A('bk_addr').value.trim()||null,phone:A('bk_tel').value.trim()||null,hours:hh,slot_minutes:Number(A('bk_step').value)||30,capacity:Math.max(1,parseInt(A('bk_cap').value)||1),updated_at:new Date().toISOString()};
 var b=f.querySelector('button[type=submit]');b.disabled=true;var r=await getSb().from('booking_profiles').upsert(row,{onConflict:'company_id'});b.disabled=false;
 if(r.error){entMsg(/duplicate|unique|23505/i.test(r.error.message+(r.error.code||''))?'Tuto adresu už používá jiná firma, zvolte jinou.':'Nepodařilo se uložit: '+r.error.message);return}
 await refresh();appTab('online');toast(en?'Uloženo. Stránka je zapnutá.':'Uloženo. Stránka je zatím vypnutá.','ok')}
function bookOpen(slug,prev){
 var old=A('vxbook');if(old)old.remove();
 var el=document.createElement('div');el.id='vxbook';el.className='vxbook';document.body.appendChild(el);document.documentElement.style.overflow='hidden';
 var B={info:null,svc:null,day:null,slot:null,slots:null,f:{n:'',e:'',p:'',c:false},msg:'',done:null,busy:false,nf:false};
 function ymd(d){return d.getFullYear()+'-'+('0'+(d.getMonth()+1)).slice(-2)+'-'+('0'+d.getDate()).slice(-2)}
 function tm(v){return new Date(v).toLocaleTimeString('cs-CZ',{hour:'2-digit',minute:'2-digit',timeZone:'Europe/Prague'})}
 function close(){el.remove();document.documentElement.style.overflow=A('vxapp')?'hidden':'';if(prev&&A('vxapp'))refresh().then(function(){appTab(APP.tab)});if(!prev){try{history.replaceState(null,'',location.pathname)}catch(e){}}}
 function draw(){
  var I=B.info,h='<div class="bkw"><button type="button" class="bkx" data-bk="close" aria-label="Zavřít">×</button>';
  if(prev)h+='<div class="bkprev">Náhled: takto uvidí stránku vaši zákazníci. Rezervace v ukázce zůstane jen v ukázkových datech.</div>';
  if(B.nf){el.innerHTML=h+'<h1>Stránka nenalezena</h1><p class="bkd">Rezervační stránka neexistuje nebo je vypnutá. Zkontrolujte odkaz.</p></div>';return}
  if(!I){el.innerHTML=h+'<p class="bkd">Načítám…</p></div>';return}
  h+='<h1>'+esc(I.title||I.name)+'</h1>'+(I.description?'<p class="bkd">'+esc(I.description)+'</p>':'')+'<p class="bkm">'+esc(I.name)+(I.address?' · '+esc(I.address):'')+(I.phone?' · '+esc(I.phone):'')+'</p>';
  if(B.done){var dn=B.done,dd=new Date(dn.start);h+='<div class="bkok"><div class="bkck">✓</div><h2>Rezervace je uložená</h2><p><b>'+esc(dn.service)+'</b><br>'+esc(dd.toLocaleDateString('cs-CZ',{weekday:'long',day:'numeric',month:'long',year:'numeric',timeZone:'Europe/Prague'}))+' v '+esc(tm(dn.start))+'<br>'+esc(dn.business)+'</p><p class="bkm">'+(dn.mail==='sent'?'Potvrzení jsme poslali na váš e-mail, včetně souboru do kalendáře. Pokud nemůžete přijít, dejte provozovně vědět.':DEMO?'V ukázce se e-mail neodesílá. V ostrém provozu zákazník dostane potvrzení e-mailem.':'Potvrzení e-mailem se nepodařilo odeslat, termín si prosím poznamenejte. Pokud nemůžete přijít, dejte provozovně vědět.')+'</p></div>'}
  else{
   h+='<h2>1. Vyberte službu</h2><div class="bks">'+(I.services||[]).map(function(x){return '<button type="button" class="bkc'+(B.svc===x.id?' on':'')+'" data-bks="'+esc(x.id)+'"><b>'+esc(x.name)+'</b><small>'+esc(x.duration_min)+' min'+(x.price!=null?' · '+Number(x.price).toLocaleString('cs-CZ')+' Kč':'')+'</small></button>'}).join('')+'</div>';
   if(B.svc){h+='<h2>2. Vyberte den</h2><div class="bkd2">';var n=0;for(var i=0;i<28&&n<21;i++){var d=new Date();d.setDate(d.getDate()+i);var dw=d.getDay()||7;if(I.hours&&I.hours[dw]){n++;h+='<button type="button" class="bkc sm'+(B.day===ymd(d)?' on':'')+'" data-bkd="'+ymd(d)+'"><b>'+esc(d.toLocaleDateString('cs-CZ',{weekday:'short'}))+'</b><small>'+d.getDate()+'. '+(d.getMonth()+1)+'.</small></button>'}}h+='</div>'}
   if(B.day){h+='<h2>3. Vyberte čas</h2>';if(B.slots===null)h+='<p class="bkd">Načítám volné časy…</p>';else if(!B.slots.length)h+='<p class="bkd">Tento den už není nic volného. Zkuste jiný den.</p>';else h+='<div class="bkt">'+B.slots.map(function(t){return '<button type="button" class="bkc sm'+(B.slot===t?' on':'')+'" data-bkt="'+esc(t)+'">'+esc(tm(t))+'</button>'}).join('')+'</div>'}
   if(B.slot){h+='<h2>4. Vaše údaje</h2><form id="bkForm"><div class="bkfg"><label>Jméno a příjmení<input id="bk_n" maxlength="120" required autocomplete="name" value="'+esc(B.f.n)+'"></label><label>E-mail<input id="bk_e" type="email" maxlength="200" required autocomplete="email" value="'+esc(B.f.e)+'"></label><label>Telefon (nepovinné)<input id="bk_p" type="tel" maxlength="40" autocomplete="tel" value="'+esc(B.f.p)+'"></label></div><label class="bkcons"><input type="checkbox" id="bk_c"'+(B.f.c?' checked':'')+' required><span>Souhlasím, že provozovna zpracuje mé jméno, e-mail a telefon za účelem vyřízení této rezervace.</span></label>'+(B.msg?'<div class="bkerr" role="alert">'+esc(B.msg)+'</div>':'')+'<button class="bkgo" type="submit"'+(B.busy?' disabled':'')+'>'+(B.busy?'Ukládám…':'Rezervovat')+'</button></form>'}
   else if(B.msg)h+='<div class="bkerr" role="alert">'+esc(B.msg)+'</div>'}
  h+='<p class="bkf">Rezervační stránka běží na <b>Vexaronet</b>.</p></div>';
  var st=el.scrollTop;el.innerHTML=h;el.scrollTop=st}
 async function loadSlots(){B.slots=null;draw();try{var r=await getSb().rpc('public_slots',{p_slug:slug,p_service:B.svc,p_day:B.day});B.slots=r.error?[]:(r.data||[])}catch(e){B.slots=[]}draw()}
 el.addEventListener('input',function(e){var t=e.target;if(t.id==='bk_n')B.f.n=t.value;else if(t.id==='bk_e')B.f.e=t.value;else if(t.id==='bk_p')B.f.p=t.value;else if(t.id==='bk_c')B.f.c=t.checked});
 el.addEventListener('click',function(e){var t=e.target.closest('[data-bk],[data-bks],[data-bkd],[data-bkt]');if(!t)return;
  if(t.dataset.bk==='close'){close();return}
  if(t.dataset.bks){B.svc=t.dataset.bks;B.day=null;B.slot=null;B.slots=null;B.msg='';draw();return}
  if(t.dataset.bkd){B.day=t.dataset.bkd;B.slot=null;B.msg='';loadSlots();return}
  if(t.dataset.bkt){B.slot=t.dataset.bkt;B.msg='';draw();setTimeout(function(){var n=A('bk_n');if(n)n.focus()},50)}});
 el.addEventListener('submit',async function(e){if(e.target.id!=='bkForm')return;e.preventDefault();if(B.busy)return;B.busy=true;B.msg='';draw();
  var r=null;
  if(!DEMO){try{var fr=await fetch('/api/book',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({slug:slug,service:B.svc,start:B.slot,name:B.f.n,email:B.f.e,phone:B.f.p||null})});if(fr.status!==404&&fr.status!==405){var fj=await fr.json().catch(function(){return null});r=fr.ok&&fj&&fj.ok?{data:fj}:{error:{message:String(fj&&fj.error||'x')}}}}catch(x){r=null}}
  if(!r){try{r=await getSb().rpc('public_book',{p_slug:slug,p_service:B.svc,p_start:B.slot,p_name:B.f.n,p_email:B.f.e,p_phone:B.f.p||null})}catch(x){r={error:{message:'x'}}}}
  B.busy=false;
  if(r.error||!r.data){var m=String(r.error&&r.error.message||'');B.msg=/slot_taken/.test(m)?'Tento čas mezitím někdo obsadil. Vyberte prosím jiný.':/bad_email/.test(m)?'Zadejte platný e-mail.':/bad_name/.test(m)?'Zadejte jméno a příjmení.':/too_many/.test(m)?'Příliš mnoho rezervací za krátkou dobu. Zkuste to později.':'Rezervaci se nepodařilo uložit. Zkuste to znovu.';if(/slot_taken/.test(m)){B.slot=null;loadSlots();return}draw();return}
  B.done=r.data;draw()});
 draw();
 (async function(){try{var c=getSb();if(!c){B.nf=true;draw();return}var r=await c.rpc('public_booking_info',{p_slug:slug});if(r.error||!r.data){B.nf=true}else B.info=r.data}catch(e){B.nf=true}draw()})()}
function invName(f){var cu=f.customer_snapshot;return cu&&typeof cu==='object'?(cu.name||cu.company_name||''):''}
function overInv(){var t0=dayStart(0);return APP.d.invoices.rows.filter(function(x){return !x.paid_at&&x.due_on&&new Date(x.due_on)<t0})}
function overJobs(){var t0=dayStart(0);return APP.d.jobs.rows.filter(function(x){return x.due_at&&!DONE.test(x.status||'')&&new Date(x.due_at)<t0})}
function reminderText(f){return 'Dobrý den'+(invName(f)?', '+invName(f):'')+',\ndovolujeme si Vás upozornit, že faktura č. '+(f.number||'')+' ve výši '+fM(f.total,f.currency)+' byla splatná dne '+fD(f.due_on)+'. Prosíme o její úhradu. Pokud jste již platbu provedli, považujte tento e-mail za bezpředmětný.\nDěkujeme a zdravíme,\n'+APP.co}
function doAct(a){
 if(a==='reminders'){var L=overInv();if(!L.length){toast('Žádné faktury po splatnosti.');return}
  modal('<h3>Upomínky k '+L.length+' '+plural(L.length,'faktuře','fakturám','fakturám')+'</h3><p class="mut">Odesílání e-mailů zatím není připojené. Texty si zkopírujte a pošlete sami. Můžete také vytvořit úkoly k urgenci.</p><textarea id="remTx" rows="10" readonly>'+esc(L.map(reminderText).join('\n\n---\n\n'))+'</textarea><div class="dact"><button class="pri" type="button" data-do="copy">Zkopírovat texty</button><button class="btn btn-ghost" type="button" data-do="remtasks">Vytvořit úkoly k urgenci</button><button class="btn btn-ghost" type="button" data-app="mclose">Zavřít</button></div>');return}
 if(a==='jobtasks'){var J=overJobs();modal('<h3>Vytvořit úkoly?</h3><p>Vytvořím '+J.length+' '+plural(J.length,'úkol','úkoly','úkolů')+' s termínem dnes:</p><ul class="ticks">'+J.map(function(j){return '<li>Kontaktovat zákazníka: '+esc(j.title)+'</li>'}).join('')+'</ul><div class="dact"><button class="pri" type="button" data-do="jobtasks">Ano, vytvořit</button><button class="btn btn-ghost" type="button" data-app="mclose">Zrušit</button></div>');return}
 if(a==='offer'){appTab('ceo');setTimeout(function(){ceoAsk('Připrav krátkou obchodní nabídku pro stávající zákazníky, kteří zatím nemají žádnou zakázku.')},50)}}
async function mkTasks(titles){
 var have={};APP.d.tasks.rows.forEach(function(t){if(!t.completed)have[t.title]=1});var rows=titles.filter(function(t){return !have[t]}).map(function(t){return {company_id:APP.cid,title:t,due_at:new Date(dayStart(0).getTime()+12*36e5).toISOString()}});
 if(!rows.length){closeModal();toast('Tyto úkoly už existují.');return}
 var r=await getSb().from('tasks').insert(rows);if(r.error){toast('Nepodařilo se vytvořit úkoly: '+r.error.message,'err');return}
 closeModal();await refresh();appTab(APP.tab);toast('Vytvořeno úkolů: '+rows.length,'ok')}
function cmap(){var m={};APP.d.customers.rows.forEach(function(x){m[x.id]=custName(x)});return m}
function head(ent,btn,ph){return '<div class="bar2">'+(ph?'<input class="srch" type="search" placeholder="'+ph+'" aria-label="Hledat">':'<span></span>')+'<button type="button" class="btn btn-main btn-sm" data-new="'+ent+'">'+btn+'</button></div>'}
function listView(ent,ph,btn,row,emptyT,sort){
 var x=APP.d[ent],rs=x.rows.slice();if(sort)rs.sort(sort);var h=head(ent,btn,ph)+errBox(x);
 if(!rs.length)return h+'<p class="mut">'+emptyT+'</p>';
 return h+'<ul class="rows big" id="lst">'+rs.map(function(r){return '<li data-edit="'+ent+':'+esc(r.id)+'">'+row(r)+'</li>'}).join('')+'</ul>'}

/* ---- formuláře (přidání, úprava, mazání) ---- */
function custFields(){return [{k:'name',l:'Jméno / firma',t:'text',req:1},{k:'email',l:'E-mail',t:'email'},{k:'phone',l:'Telefon',t:'tel'},{k:'billing_address',l:'Fakturační adresa'},{k:'ico',l:'IČO'},{k:'dic',l:'DIČ'},{k:'notes',l:'Poznámka',t:'textarea'},{k:'archived',l:'Archivovat (skrýt ze seznamu)',t:'bool'}]}
function entDef(ent){
 var cu=APP.d.customers.rows;
 var D={
  customers:{n:'zákazníka',f:custFields},
  jobs:{n:'zakázku',f:function(){var st=[];APP.d.jobs.rows.forEach(function(j){if(j.status&&st.indexOf(j.status)<0)st.push(j.status)});return [{k:'title',l:'Název',req:1},{k:'customer_id',l:'Zákazník',t:'cust'},{k:'price',l:'Cena (Kč)',t:'number'},{k:'due_at',l:'Termín',t:'date'},{k:'status',l:'Stav',t:'text',list:st},{k:'description',l:'Popis',t:'textarea'},{k:'notes',l:'Poznámky',t:'textarea'}]}},
  reservations:{n:'rezervaci',f:function(){return [{k:'title',l:'Název',req:1},{k:'customer_id',l:'Zákazník',t:'cust'},{k:'starts_at',l:'Začátek',t:'datetime-local',req:1},{k:'ends_at',l:'Konec',t:'datetime-local',req:1},{k:'reminder_minutes',l:'Připomenout minut předem',t:'number'},{k:'canceled',l:'Zrušeno',t:'bool'}]}},
  financial_entries:{n:'finanční záznam',f:function(){var ks=['income','expense'];APP.d.fe.rows.forEach(function(r){if(r.kind&&ks.indexOf(r.kind)<0)ks.push(r.kind)});return [{k:'title',l:'Popis',req:1},{k:'kind',l:'Druh',t:'sel',opts:ks.map(function(k){return [k,KL(k)]}),req:1},{k:'amount',l:'Částka (Kč)',t:'number',req:1},{k:'entry_date',l:'Datum',t:'dateonly',req:1}]}},
  shifts:{n:'směnu',f:function(){return [{k:'person',l:'Zaměstnanec (jméno nebo e-mail)',req:1,list:teamNames()},{k:'starts_at',l:'Začátek směny',t:'datetime-local',req:1},{k:'ends_at',l:'Konec směny',t:'datetime-local',req:1},{k:'note',l:'Poznámka'}]}},
  booking_services:{n:'službu',f:function(){return [{k:'name',l:'Název služby',req:1},{k:'duration_min',l:'Délka (minuty)',t:'number',req:1},{k:'price',l:'Cena (Kč, nepovinné)',t:'number'},{k:'active',l:'Nabízet zákazníkům',t:'bool',def:1}]}},
  marketing_posts:{n:'příspěvek',f:function(){return [{k:'title',l:'Název',req:1},{k:'channel',l:'Kanál',t:'sel',opts:MKCH.map(function(c){return [c,c]})},{k:'status',l:'Stav',t:'sel',opts:Object.keys(MKST).map(function(k){return [k,MKST[k]]}),req:1},{k:'planned_on',l:'Naplánováno na',t:'dateonly'},{k:'body',l:'Text',t:'textarea'}]}},
  tasks:{n:'úkol',f:function(){return [{k:'title',l:'Úkol',req:1},{k:'due_at',l:'Termín',t:'date'},{k:'description',l:'Popis',t:'textarea'},{k:'completed',l:'Hotovo',t:'bool'}]}}
 };return D[ent]}

function rpcInv(action,doc){return getSb().rpc('invoice_action',{cid:APP.cid,action:action,doc:doc})}
function itemRow(){return '<div class="irow"><input class="id" placeholder="Popis položky" aria-label="Popis"><input class="iq" type="number" step="any" value="1" aria-label="Množství"><input class="iu" value="ks" aria-label="Jednotka"><input class="ip" type="number" step="any" placeholder="Cena s DPH" aria-label="Cena za jednotku s DPH"><select class="iv" aria-label="Sazba DPH"><option>21</option><option>12</option><option>0</option></select><button type="button" class="lnk" data-delrow="1" aria-label="Odebrat">×</button></div>'}
function invTotals(){var t=0;[].forEach.call(document.querySelectorAll('#iRows .irow'),function(r){t+=(parseFloat(r.querySelector('.iq').value)||0)*(parseFloat(r.querySelector('.ip').value)||0)});var e=A('iTot');if(e)e.textContent='Celkem s DPH: '+fM(Math.round(t*100)/100)}
function invForm(){var lm=limitMsg('invoices');if(lm){toast(lm,'err');return}
 var cs=APP.d.customers.rows,td=locD(new Date()),du=locD(new Date(Date.now()+14*864e5));
 if(!cs.length){toast('Nejdřív přidejte zákazníka.');return}
 modal('<h3>Nová faktura</h3><form id="invForm"><div class="fg"><div class="f full"><label for="iC">Zákazník <i>*</i></label><select id="iC">'+cs.map(function(x){return '<option value="'+esc(x.id)+'">'+esc(custName(x))+'</option>'}).join('')+'</select></div><div class="f"><label for="iI">Datum vystavení</label><input id="iI" type="date" value="'+td+'"></div><div class="f"><label for="iT">Datum zdanitelného plnění</label><input id="iT" type="date" value="'+td+'"></div><div class="f"><label for="iD">Splatnost</label><input id="iD" type="date" value="'+du+'"></div><div class="f"><label for="iCur">Měna</label><select id="iCur"><option>CZK</option><option>EUR</option></select></div><div class="f full"><label for="iJ">Zakázka (nepovinné)</label><select id="iJ"><option value="">– bez zakázky –</option>'+APP.d.jobs.rows.map(function(j){return '<option value="'+esc(j.id)+'">'+esc(j.title)+'</option>'}).join('')+'</select></div></div><h4>Položky</h4><div id="iRows">'+itemRow()+'</div><button type="button" class="btn btn-ghost btn-sm" data-addrow="1">+ Položka</button><p class="mut" id="iTot"></p><p class="mut fine">Sazby DPH a jejich použití musí ověřit účetní.</p><div class="st" id="entSt" role="status"></div><div class="dact"><button class="pri" type="submit">Vystavit fakturu</button><button class="btn btn-ghost" type="button" data-app="mclose">Zrušit</button></div></form>')}
function profForm(){
 var last=APP.d.invoices.rows.filter(function(x){return x.supplier_snapshot&&typeof x.supplier_snapshot==='object'}).sort(function(a,b){return new Date(b.created_at)-new Date(a.created_at)})[0],sp=last?last.supplier_snapshot:{};
 function f(k,l,req,t){return '<div class="f"><label for="p_'+k+'">'+l+(req?' <i>*</i>':'')+'</label><input id="p_'+k+'" type="'+(t||'text')+'" value="'+esc(sp[k]==null?'':sp[k])+'"></div>'}
 modal('<h3>Fakturační údaje (dodavatel)</h3><p class="mut">Údaje, které se objeví na fakturách. Uloží se přes pravidla ve vaší databázi.</p><form id="profForm"><div class="fg">'+f('legal_name','Obchodní jméno',1)+f('ico','IČO')+f('dic','DIČ')+f('address_text','Adresa')+f('bank_account','Číslo účtu')+f('iban','IBAN')+f('email','E-mail','','email')+f('country_code','Země (kód)')+f('default_due_days','Splatnost (dní)','','number')+f('default_currency','Výchozí měna')+f('registration_text','Zápis v rejstříku')+'<div class="f full"><label class="chk"><input type="checkbox" id="p_vat_payer"'+(sp.vat_payer?' checked':'')+'><span>Jsem plátce DPH</span></label></div></div><div class="st" id="entSt" role="status"></div><div class="dact"><button class="pri" type="submit">Uložit</button><button class="btn btn-ghost" type="button" data-app="mclose">Zrušit</button></div></form>')}
var PLANPR={start:'zdarma',accountant:'399 Kč / měsíc',pro:'699 Kč / měsíc',business:'1 199 Kč / měsíc',enterprise:'individuální cena'};
function planModal(){
 var cur=effPlan(),opts=PLAN_ALLOWED.filter(function(x){return x!==cur}).map(function(x){return '<label class="chk"><input type="radio" name="pl" value="'+x+'"><span><b>'+esc(PLANN[x])+'</b> – '+PLANPR[x]+' (bez DPH)</span></label>'}).join('');
 modal('<h3>Změna tarifu</h3><p class="mut">Aktuální tarif: <b>'+esc(PLANN[cur])+'</b>. Placené tarify mají 30 dní zdarma, jednou na firmu.</p><form id="planForm"><div class="chks" style="grid-template-columns:1fr">'+opts+'</div><div class="f full"><label for="plN">Poznámka (nepovinné)</label><input id="plN" maxlength="300"></div><div class="draft">Přechod na START proběhne ihned a data zůstanou zachována. U ostatních tarifů odešleme žádost a tarif nastavíme ručně, protože platební brána zatím není připojená. Nic se neúčtuje.</div><div class="st" id="entSt" role="status"></div><div class="dact"><button class="pri" type="submit">Pokračovat</button><button class="btn btn-ghost" type="button" data-app="mclose">Zrušit</button></div></form>')}
async function sendPlanRequest(want,note){var r=await getSb().from('plan_requests').insert({company_id:APP.cid,current_plan:effPlan(),requested_plan:want,note:note||null});if(r.error)throw r.error}
function isInc(k){return /inc|přij|prij|^in$|revenue|výnos/i.test(String(k))}
function KL(k){return k==='income'?'Příjem':(k==='expense'?'Výdaj':(isInc(k)?'Příjem ('+k+')':'Výdaj ('+k+')'))}
function openForm(ent,id){var lm=!id&&limitMsg(ent);if(lm){toast(lm,'err');return}
 var def=entDef(ent),row=id?(APP.d[ent].rows.filter(function(r){return String(r.id)===id})[0]||{}):{},F=def.f();
 var h='<h3>'+(id?'Upravit':'Nový')+' – '+def.n+'</h3><form id="entForm" data-ent="'+ent+'" data-id="'+esc(id||'')+'"><div class="fg">';
 F.forEach(function(f){var v=row[f.k],lab='<label for="e_'+f.k+'">'+f.l+(f.req?' <i>*</i>':'')+'</label>',c='';
  if(f.t==='cust')c='<select id="e_'+f.k+'">'+'<option value="">– bez zákazníka –</option>'+APP.d.customers.rows.map(function(x){return '<option value="'+esc(x.id)+'"'+(x.id===v?' selected':'')+'>'+esc(custName(x))+'</option>'}).join('')+'</select>';
  else if(f.t==='sel')c='<select id="e_'+f.k+'">'+f.opts.map(function(o){return '<option value="'+esc(o[0])+'"'+(o[0]===v?' selected':'')+'>'+esc(o[1])+'</option>'}).join('')+'</select>';
  else if(f.t==='textarea')c='<textarea id="e_'+f.k+'" rows="3">'+esc(v||'')+'</textarea>';
  else if(f.t==='bool'){h+='<div class="f full"><label class="chk"><input type="checkbox" id="e_'+f.k+'"'+((v==null&&f.def)||v?' checked':'')+'><span>'+f.l+'</span></label></div>';return}
  else{var val=v==null?'':v;if(f.t==='date')val=v?locD(v):'';if(f.t==='dateonly')val=v||'';if(f.t==='datetime-local')val=v?loc(v):'';c='<input id="e_'+f.k+'" type="'+(f.t==='dateonly'?'date':(f.t||'text'))+'" value="'+esc(val)+'"'+(f.t==='number'?' step="any"':'')+(f.list?' list="dl_'+f.k+'"':'')+'>'+(f.list?'<datalist id="dl_'+f.k+'">'+f.list.map(function(s){return '<option value="'+esc(s)+'">'}).join('')+'</datalist>':'')}
  h+='<div class="f'+(f.t==='textarea'?' full':'')+'">'+lab+c+'</div>'});
 h+='</div><div class="st" id="entSt" role="status"></div><div class="dact"><button class="btn btn-main" type="submit">Uložit</button>'+(id?'<button class="btn btn-ghost" type="button" data-del="1">Smazat</button>':'')+'<button class="btn btn-ghost" type="button" data-app="mclose">Zrušit</button></div></form>';
 var m=A('appModal');if(!m){m=document.createElement('div');m.id='appModal';m.className='amodal';m.setAttribute('role','dialog');m.setAttribute('aria-modal','true');A('vxapp').appendChild(m)}
 m.innerHTML='<div class="mbox">'+h+'</div>';m.classList.add('on');var fi=m.querySelector('input,select,textarea');if(fi)fi.focus()}
function closeModal(){var m=A('appModal');if(m)m.remove()}
function entMsg(t){var e=A('entSt');if(e){e.className='st err';e.textContent=t}}
async function saveEnt(form){
 var ent=form.dataset.ent,id=form.dataset.id,F=entDef(ent).f(),row={};
 for(var i=0;i<F.length;i++){var f=F[i],el=A('e_'+f.k);if(!el)continue;var v=f.t==='bool'?el.checked:el.value.trim();
  if(f.req&&!v){entMsg('Vyplňte pole: '+f.l+'.');return}
  if(f.t==='bool')row[f.k]=v;
  else if(f.t==='number')row[f.k]=v===''?null:Number(v);
  else if(f.t==='dateonly')row[f.k]=v||null;
  else if(f.t==='date')row[f.k]=v?new Date(v+'T12:00:00').toISOString():null;
  else if(f.t==='datetime-local')row[f.k]=v?new Date(v).toISOString():null;
  else if(f.t==='cust')row[f.k]=v||null;
  else row[f.k]=v===''?(id?null:undefined):v;
  if(row[f.k]===undefined)delete row[f.k]}
 if((ent==='reservations'||ent==='shifts')&&new Date(row.ends_at)<=new Date(row.starts_at)){entMsg('Konec musí být po začátku.');return}
 if(ent==='booking_services'&&!(row.duration_min>=5&&row.duration_min<=600)){entMsg('Délka služby musí být 5 až 600 minut.');return}
 var b=form.querySelector('button[type=submit]');b.disabled=true;var q=getSb().from(ent),r;
 if(id)r=await q.update(row).eq('id',id).eq('company_id',APP.cid);else{row.company_id=APP.cid;r=await q.insert(row)}
 b.disabled=false;if(r.error){entMsg('Nepodařilo se uložit: '+r.error.message);return}
 closeModal();await refresh();appTab(APP.tab);toast('Uloženo.','ok')}
async function delEnt(form){
 if(!confirm('Opravdu smazat tento záznam? Akci nelze vrátit.'))return;
 var r=await getSb().from(form.dataset.ent).delete().eq('id',form.dataset.id).eq('company_id',APP.cid);
 if(r.error){entMsg('Nepodařilo se smazat: '+r.error.message);return}
 closeModal();await refresh();appTab(APP.tab);toast('Smazáno.','ok')}
function themeToggle(){var r=document.documentElement,n=r.getAttribute('data-theme')==='light'?'dark':'light';r.setAttribute('data-theme',n);try{localStorage.setItem('vx-theme',n)}catch(e){}}
async function askAI(msgs,out){
 var ses=(await getSb().auth.getSession()).data.session;if(!ses){out('Přihlášení vypršelo. Přihlaste se znovu.');return null}
 try{var r=await dfetch('/api/advisor',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+ses.access_token},body:JSON.stringify({messages:msgs,summary:summary()})});
  if(r.status===403){out('AI CEO je součástí tarifu Vexaronet PRO a vyšších.');return null}
  if(r.status===429){out('Příliš mnoho dotazů. Zkuste to za chvíli.');return null}
  if(!r.ok)throw new Error(r.status);var d=await r.json();if(!d.reply)throw new Error('e');return d.reply}catch(e){out('AI poradce teď není dostupný. Zkuste to později.');return null}}
document.addEventListener('click',async function(e){
 if(e.target.closest('[data-demo]')){e.preventDefault();var mn2=A('mnav');if(mn2&&mn2.classList.contains('on'))menu(false);startDemo();return}
 if(e.target.closest('[data-demo-signup]')){closeApp();showAuth('signup');return}
 if(e.target.closest('#openApp')){openApp();return}
 var a=e.target.closest('#vxapp [data-app]');
 if(a){var k=a.dataset.app;
  if(k==='close')closeApp();
  else if(k==='side')A('vxapp').classList.toggle('side');
  else if(k==='bell')A('appBell').classList.toggle('on');
  else if(k==='quick'){var q=A('qPop');if(q)q.classList.toggle('on')}
  else if(k==='theme')themeToggle();
  else if(k==='mclose')closeModal();
  else if(k==='plan')planModal();
  else if(k==='hidebeta'){APP.betaHidden=true;appTab(APP.tab)}
  else if(k==='logout'){if(DEMO){closeApp();return}var c=getSb();if(c)await c.auth.signOut();closeApp()}
  return}
 var dd=e.target.closest('#vxapp [data-do]');
 if(dd){var w=dd.dataset.do;if(w==='copy'){var tx=A('remTx');try{await navigator.clipboard.writeText(tx.value);toast('Zkopírováno.','ok')}catch(x){tx.select();toast('Označeno, zkopírujte pomocí Ctrl+C.')}}
  else if(w==='remtasks')mkTasks(overInv().map(function(f){return 'Urgovat fakturu '+(f.number||'')+(invName(f)?' ('+invName(f)+')':'')}));
  else if(w==='jobtasks')mkTasks(overJobs().map(function(j){return 'Kontaktovat zákazníka: '+j.title}));return}
 var ac=e.target.closest('#vxapp [data-act]');if(ac){doAct(ac.dataset.act);return}
 var qq=e.target.closest('#vxapp [data-q]');if(qq){ceoAsk(CEOQ[+qq.dataset.q][1]);return}
 if(e.target.closest('#vxapp [data-newinv]')){invForm();return}
 if(e.target.closest('#vxapp [data-invprof]')){profForm();return}
 if(e.target.closest('#vxapp [data-addrow]')){A('iRows').insertAdjacentHTML('beforeend',itemRow());return}
 var dr=e.target.closest('#vxapp [data-delrow]');if(dr){if(document.querySelectorAll('#iRows .irow').length>1){dr.closest('.irow').remove();invTotals()}return}
 var cn=e.target.closest('#vxapp [data-calnav]');if(cn){var v=+cn.dataset.calnav,M0=APP.calM||new Date();APP.calM=v===0?new Date(new Date().getFullYear(),new Date().getMonth(),1):new Date(M0.getFullYear(),M0.getMonth()+v,1);if(v===0)APP.calSel=locD(new Date());calRe();return}
 var cdy=e.target.closest('#vxapp [data-calday]');if(cdy){APP.calSel=cdy.dataset.calday;calRe();return}
 var cmd=e.target.closest('#vxapp [data-calmode]');if(cmd){APP.calMode=cmd.dataset.calmode;calRe();return}
 if(e.target.closest('#vxapp [data-bkcopy]')){var bp=APP.d.booking_profiles.rows[0];if(bp&&navigator.clipboard)navigator.clipboard.writeText(bookUrl(bp.slug)).then(function(){toast('Odkaz zkopírován.','ok')},function(){toast('Zkopírujte odkaz ručně.','err')});return}
 if(e.target.closest('#vxapp [data-bkopen]')){var bp2=APP.d.booking_profiles.rows[0];if(!bp2)return;if(DEMO)bookOpen(bp2.slug,true);else window.open(bookUrl(bp2.slug),'_blank','noopener');return}
 var iv=e.target.closest('#vxapp [data-invview]');if(iv){invView(iv.dataset.invview);return}
 if(e.target.closest('#vxapp [data-invprint]')){invPrint();return}
 var pay=e.target.closest('#vxapp [data-pay]');if(pay){if(!confirm('Označit fakturu jako zaplacenou dnes? Změna se promítne do účetních údajů.'))return;var pr=await rpcInv('paid',{id:pay.dataset.pay,payment_date:locD(new Date())});if(pr.error){toast('Nepodařilo se uložit: '+pr.error.message,'err');return}await refresh();appTab('faktury');toast('Faktura označena jako zaplacená.','ok');return}
 var mx=e.target.closest('#vxapp [data-mk]');if(mx){var mk=mx.dataset.mk;if(mk==='gen')mkGen();else if(mk==='save')mkSave();else if(mk==='copy'){var mo=A('mk_out');try{navigator.clipboard.writeText(mo.value);toast('Text zkopírován.','ok')}catch(x){mo.select();toast('Označeno, zkopírujte ručně (Ctrl+C).','ok')}}return}
 var wx=e.target.closest('#vxapp [data-web]');if(wx){var wk=wx.dataset.web;if(wk==='ai')webAI();else if(wk==='open')webOpen('',true);else if(wk==='copy'){var wr=APP.d.sites.rows[0];if(wr){try{navigator.clipboard.writeText(webUrl(wr.slug));toast('Odkaz zkopírován.','ok')}catch(x){toast(webUrl(wr.slug),'ok')}}}return}
 var ax=e.target.closest('#vxapp [data-acc]');if(ax){var ak=ax.dataset.acc;if(ak==='process')accProcess();else if(ak==='discard'){A('accRes').innerHTML='';accSt('','')}else if(ak==='csv-ent')accExport('ent');else if(ak==='csv-inv')accExport('inv');else if(ak==='bk-file')bkFile();else if(ak==='bk-demo')bkDemo();else if(ak==='bk-apply')bkApply();else if(ak==='bk-clear'){BK.rows=[];A('bkRes').innerHTML='';bkSt('','')}return}
 if(e.target.closest('#vxapp [data-invnew]')){inviteModal();return}
 var is=e.target.closest('#vxapp [data-invshow]');if(is){var iv=(APP.invs||[]).filter(function(x){return x.id===is.dataset.invshow})[0];if(iv)inviteDone(iv.email);return}
 var ic=e.target.closest('#vxapp [data-invcancel]');if(ic){if(!confirm('Zrušit tuto pozvánku?'))return;var cr=await getSb().rpc('cancel_invite',{invite_id:ic.dataset.invcancel});if(cr.error){toast('Nepodařilo se zrušit: '+teamErr(cr.error.message),'err');return}toast('Pozvánka zrušena.','ok');loadTeam();return}
 var rm=e.target.closest('#vxapp [data-rmm]');if(rm){if(!confirm('Odebrat tohoto člena z firmy? Ztratí přístup k datům firmy.'))return;var rr2=await getSb().rpc('remove_member',{cid:APP.cid,member_id:rm.dataset.rmm});if(rr2.error){toast('Nepodařilo se odebrat: '+teamErr(rr2.error.message),'err');return}toast('Člen odebrán.','ok');loadTeam();return}
 var so=e.target.closest('#vxapp [data-soon]');if(so){toast(so.dataset.soon);return}
 var pq=A('qPop');if(pq&&pq.classList.contains('on')&&!e.target.closest('.qw'))pq.classList.remove('on');
 if(A('appBell')&&A('appBell').classList.contains('on')&&!e.target.closest('.bellw'))A('appBell').classList.remove('on');
 var t=e.target.closest('#vxapp [data-tab]');if(t){appTab(t.dataset.tab);return}
 var nw=e.target.closest('#vxapp [data-new]');if(nw){if(pq)pq.classList.remove('on');openForm(nw.dataset.new);return}
 var ed=e.target.closest('#vxapp [data-edit]');if(ed&&!e.target.closest('input')){var p=ed.dataset.edit.split(':');openForm(p[0],p.slice(1).join(':'));return}
 if(e.target.closest('#vxapp [data-del]')){delEnt(A('entForm'));return}
 if(e.target.classList&&e.target.classList.contains('amodal'))closeModal()});
document.addEventListener('change',async function(e){
 var t=e.target;if(t.dataset&&t.dataset.bkrow!=null&&BK.rows[+t.dataset.bkrow]){BK.rows[+t.dataset.bkrow].on=t.checked;return}if(t.dataset&&t.dataset.task){var r=await getSb().from('tasks').update({completed:t.checked}).eq('id',t.dataset.task).eq('company_id',APP.cid);if(r.error){toast('Nepodařilo se uložit: '+r.error.message,'err');t.checked=!t.checked}else{await refresh();appTab('ukoly')}}});
document.addEventListener('input',function(e){if(e.target.closest&&e.target.closest('#webForm'))webPrev();if(e.target.closest&&e.target.closest('#iRows'))invTotals();if(e.target.classList&&e.target.classList.contains('srch')){var v=e.target.value.toLowerCase();[].forEach.call(document.querySelectorAll('#lst li'),function(li){li.style.display=li.textContent.toLowerCase().indexOf(v)<0?'none':''})}});
document.addEventListener('submit',async function(e){
 var f=e.target;
 if(f.id==='entForm'){e.preventDefault();saveEnt(f);return}
 if(f.id==='bookForm'){e.preventDefault();saveBook(f);return}
 if(f.id==='onbForm'||f.id==='featForm'){e.preventDefault();var ft=[].map.call(f.querySelectorAll('input[name=ft]:checked'),function(x){return x.value}),co=(A('oC')||A('pC')).value;
  var r=await getSb().auth.updateUser({data:{country:co,features:ft,onboarded:true}});if(r.error){toast('Nepodařilo se uložit: '+r.error.message,'err');return}
  APP.meta=r.data.user.user_metadata||{};toast('Nastavení uloženo.','ok');appTab(APP.tab);return}
 if(f.id==='invForm'){e.preventDefault();var its=[].map.call(f.querySelectorAll('#iRows .irow'),function(r){return {description:r.querySelector('.id').value.trim(),quantity:parseFloat(r.querySelector('.iq').value)||0,unit:r.querySelector('.iu').value.trim()||'ks',unit_gross:parseFloat(r.querySelector('.ip').value),vat_rate:parseFloat(r.querySelector('.iv').value)}}).filter(function(i){return i.description&&i.quantity>0&&!isNaN(i.unit_gross)});
  if(!its.length){entMsg('Přidejte alespoň jednu položku s popisem, množstvím a cenou.');return}
  var cu=APP.d.customers.rows.filter(function(x){return x.id===A('iC').value})[0]||{};
  if(!confirm('Vystavit fakturu? Přidělí se číslo faktury a vystavenou fakturu už nelze vzít zpět.'))return;
  var doc={customer:{id:cu.id,name:cu.name,email:cu.email||null,ico:cu.ico||null,dic:cu.dic||null,billing_address:cu.billing_address||null},items:its,issued_on:A('iI').value,taxable_supply_on:A('iT').value,due_on:A('iD').value,currency:A('iCur').value,language:'cs'};if(A('iJ').value)doc.job_id=A('iJ').value;
  var b=f.querySelector('button[type=submit]');b.disabled=true;var r=await rpcInv('issue',doc);b.disabled=false;
  if(r.error){entMsg('Fakturu se nepodařilo vystavit: '+r.error.message);return}
  closeModal();await refresh();appTab('faktury');toast('Faktura vystavena'+(r.data&&r.data.number?' (č. '+r.data.number+')':'')+'.','ok');return}
 if(f.id==='profForm'){e.preventDefault();if(!A('p_legal_name').value.trim()){entMsg('Vyplňte obchodní jméno.');return}
  var d={};['legal_name','ico','dic','address_text','bank_account','iban','email','country_code','default_currency','registration_text'].forEach(function(k){var v=A('p_'+k).value.trim();if(v)d[k]=v});
  var dd=A('p_default_due_days').value;if(dd)d.default_due_days=Number(dd);d.vat_payer=A('p_vat_payer').checked;
  var r2=await rpcInv('profile',d);if(r2.error){entMsg('Nepodařilo se uložit: '+r2.error.message);return}closeModal();toast('Fakturační údaje uloženy.','ok');return}
 if(f.id==='webForm'){e.preventDefault();await saveWeb(f);return}
 if(f.id==='accForm'){e.preventDefault();var ai=A('accIn'),aq=ai.value.trim();if(!aq)return;ai.value='';accAsk(aq);return}
 if(f.id==='accRF'){e.preventDefault();var am=parseFloat(A('af_amt').value),ad=A('af_date').value,ak2=A('af_kind').value,at=A('af_title').value.trim();
  if(!(am>=0)||!ad||!at){accSt('Vyplňte částku, datum a popis.','err');return}
  var dp=APP.d.fe.rows.some(function(x){return Math.abs(Math.abs(Number(x.amount)||0)-am)<0.005&&String(x.entry_date||'').slice(0,10)===ad&&x.kind===ak2});
  if(dp&&!confirm('V evidenci už je záznam se stejnou částkou, datem a druhem. Přesto uložit?'))return;
  var sb=f.querySelector('button[type=submit]');sb.disabled=true;var ir2=await getSb().from('financial_entries').insert({company_id:APP.cid,title:at,amount:am,kind:ak2,entry_date:ad});sb.disabled=false;
  if(ir2.error){accSt('Nepodařilo se uložit: '+ir2.error.message,'err');return}
  await refresh();appTab('ucetni');toast('Doklad uložen do evidence.','ok');return}
 if(f.id==='inviteForm'){e.preventDefault();var em=A('ivE').value.trim().toLowerCase();if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(em)){entMsg('Zadejte platný e-mail.');return}var TY={'gamil.com':'gmail.com','gmial.com':'gmail.com','gmai.com':'gmail.com','gmail.cz':'gmail.com','gmaill.com':'gmail.com','gnail.com':'gmail.com','seznan.cz':'seznam.cz','sezman.cz':'seznam.cz','seznam.com':'seznam.cz','email.com':'email.cz','outlok.com':'outlook.com','hotmial.com':'hotmail.com'},dm=em.split('@')[1];if(TY[dm]&&A('ivE').dataset.ok!==em){entMsg('Nemyslíte '+em.split('@')[0]+'@'+TY[dm]+'? Adresa vypadá jako překlep. Opravte ji, nebo odešlete znovu, pokud je správně.');A('ivE').dataset.ok=em;return}
  var ib=f.querySelector('button[type=submit]');ib.disabled=true;var ses=(await getSb().auth.getSession()).data.session,ir=null,ij=null;try{ir=await dfetch('/api/invite',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+(ses?ses.access_token:'')},body:JSON.stringify({cid:APP.cid,email:em,role:A('ivR').value})});ij=await ir.json().catch(function(){return null})}catch(x){}ib.disabled=false;
  if(!ir||!ir.ok){entMsg(ij&&ij.message?teamErr(ij.message):(ir&&ir.status===429?'Příliš mnoho pozvánek za krátkou dobu, zkuste to později.':'Pozvánku se nepodařilo vytvořit. Zkuste to znovu.'));return}
  await loadTeam();if(DEMO){closeModal();toast('Ukázka: pozvánka je jen vyzkoušená, e-mail se neodesílá.','ok')}else if(ij&&ij.mail==='sent'){closeModal();toast('Pozvánka odeslána na '+em+'.','ok')}else inviteDone(em,true);return}
 if(f.id==='planForm'){e.preventDefault();var sel=f.querySelector('input[name=pl]:checked');if(!sel){entMsg('Vyberte tarif.');return}var want=sel.value,note=A('plN').value.trim(),bt=f.querySelector('button[type=submit]');bt.disabled=true;
  try{
   if(want==='start'){if(!confirm('Přejít na tarif START? AI CEO a rozšířené funkce se vypnou, data zůstanou zachována.')){bt.disabled=false;return}
    var u=await getSb().from('subscriptions').update({plan:'start'}).eq('company_id',APP.cid).select();
    if(!u.error&&u.data&&u.data.length){var rs=await getSb().from('subscriptions').select('*').eq('company_id',APP.cid).limit(1);APP.sub=rs.data&&rs.data[0]||APP.sub;closeModal();subCard();appTab('profil');toast('Přešli jste na tarif START.','ok');return}}
   await sendPlanRequest(want,note);closeModal();toast('Žádost o změnu tarifu odeslána. Ozveme se vám e-mailem.','ok')
  }catch(x){entMsg('Žádost se nepodařilo odeslat ('+((x&&(x.code||x.message))||'chyba')+'). Napište nám na info@vexaronet.com.')}bt.disabled=false;return}
 if(f.id==='ceoForm'){e.preventDefault();var inp=A('ceoIn'),q=inp.value.trim();if(!q)return;inp.value='';ceoAsk(q);return}
 if(f.id==='gsForm'){e.preventDefault();var gi=A('gsIn'),g=gi.value.trim();if(!g)return;gi.value='';if(!A('ceoLog'))appTab('ceo');ceoAsk(g)}});
document.addEventListener('keydown',function(e){
 if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'&&A('gsIn')){e.preventDefault();A('gsIn').focus();return}
 if(e.key==='Escape'){if(A('appModal'))closeModal();else if(A('vxapp')&&!dlg.open)closeApp()}});


/* chat */
var fab=$('#chatFab'),chat=$('#chat'),body=$('#chatBody'),sugg=$('#chatSugg'),cf=$('#chatForm'),cin=$('#chatIn');
var hist=[];try{hist=JSON.parse(sessionStorage.getItem('vx-chat-v3')||'[]')}catch(e){}
function save(){try{sessionStorage.setItem('vx-chat-v3',JSON.stringify(hist.slice(-20)))}catch(e){}}
function add(t,c){var d=document.createElement('div');d.className='msg '+c;d.textContent=t;body.appendChild(d);body.scrollTop=body.scrollHeight;return d}
function openChat(o){chat.classList.toggle('on',o);fab.setAttribute('aria-expanded',o);if(o){if(!body.children.length){add('Dobrý den, jsem AI asistent Vexaronetu. Poradím, co platforma bude umět a v jaké je fázi. Na co se chcete zeptat?','bot');hist.forEach(function(m){add(m.content,m.role==='user'?'me':'bot')})}
 if(!sugg.children.length&&!hist.length)['Co Vexaronet umí?','Kolik to stojí?','Je už k dispozici?'].forEach(function(q){var b=document.createElement('button');b.type='button';b.textContent=q;b.onclick=function(){cin.value=q;cf.requestSubmit()};sugg.appendChild(b)});setTimeout(function(){cin.focus()},50)}}
fab.addEventListener('click',function(){openChat(!chat.classList.contains('on'))});$('#chatX').addEventListener('click',function(){openChat(false)});$('#openChat').addEventListener('click',function(){openChat(true)});
cin.addEventListener('keydown',function(e){if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();cf.requestSubmit()}});
cf.addEventListener('submit',function(e){e.preventDefault();var t=cin.value.trim();if(!t)return;cin.value='';sugg.innerHTML='';add(t,'me');hist.push({role:'user',content:t});save();var w=add('Píšu odpověď…','bot');
 fetch('/api/chat',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({messages:hist.slice(-12)})}).then(function(r){if(!r.ok)throw new Error(r.status);return r.json()}).then(function(d){if(!d.reply)throw new Error('e');w.textContent=d.reply;hist.push({role:'assistant',content:d.reply});save();body.scrollTop=body.scrollHeight}).catch(function(){w.className='msg bot err';w.textContent='AI asistent zatím není dostupný nebo se nepodařilo spojit. Napište nám prosím na info@vexaronet.com.';hist.pop();save()})});
})();
</script>
</body>
</html>'''

out = (tpl.replace('@@CSS@@', css + extra_css).replace('@@KEYS@@', keys).replace('@@MODS@@', mods_html)
       .replace('@@BIZOPTS@@', biz_opts).replace('@@BIZ@@', biz_chips).replace('@@PLANS@@', plans_html).replace('@@STAGES@@', stages_html)
       .replace('@@MODDATA@@', json.dumps({m['id']: dict(name=m['name'], short=m['short'], items=m['items'], stage=m['stage']) for m in MODS}, ensure_ascii=False).replace('</', '<\\/'))
       .replace('@@BIZDATA@@', json.dumps(BIZ, ensure_ascii=False)))
assert '@@' not in out
open(D + 'index.html', 'w', encoding='utf-8').write(out)
print('OK', len(out))
