/* ===== Fakturační modul: přehled, editor s živým náhledem, doklad s QR platbou ===== */
/* Přepisuje starší funkce invHTML, invView, invPrint a invForm (původní kód zůstává výše beze změny). */
var IVSTAT={draft:'Koncept',issued:'Vystaveno'};
function ivProf(){var p=APP.d.profile&&APP.d.profile.rows&&APP.d.profile.rows[0];if(p)return p;var last=APP.d.invoices.rows.filter(function(x){return x.supplier_snapshot&&typeof x.supplier_snapshot==='object'&&x.supplier_snapshot.legal_name}).sort(function(a,b){return new Date(b.created_at)-new Date(a.created_at)})[0];return last?last.supplier_snapshot:null}
function ivItems(f){return Array.isArray(f.items)?f.items:[]}
function ivM(n,cur){return Number(n||0).toLocaleString('cs-CZ',{minimumFractionDigits:2,maximumFractionDigits:2})+' '+((cur||'CZK')==='CZK'?'Kč':esc(cur))}
function ivStatus(f){if(f.lifecycle==='draft'||(!f.number&&!f.paid_at))return {k:'draft',t:'Koncept'};if(f.paid_at)return {k:'paid',t:'Zaplaceno'};var t0=dayStart(0);if(f.due_on&&new Date(f.due_on)<t0){var d=Math.floor((t0-new Date(f.due_on))/864e5);return {k:'late',t:'Po splatnosti'+(d>0?' '+d+' '+plural(d,'den','dny','dní'):'')}}return {k:'open',t:'K úhradě'}}
/* Doklad: stejné vykreslení pro náhled v editoru, detail i tisk. o: {color,preview} */
function invDoc(f,o){o=o||{};
 var sp=f.supplier_snapshot&&typeof f.supplier_snapshot==='object'?f.supplier_snapshot:{},cu=f.customer_snapshot&&typeof f.customer_snapshot==='object'?f.customer_snapshot:{},cur=f.currency||'CZK',vp=f.vat_payer!=null?!!f.vat_payer:!!sp.vat_payer,
  its=ivItems(f),C=VXINV.calc(its,vp),T=C.total,st=o.badge||ivStatus(f),color=o.color||'#4f46e5';
 var hasDisc=its.some(function(i){return Number(i.discount_pct)>0});
 var rows=C.lines.map(function(l,ix){var i=its[ix];return '<tr><td>'+esc(i.description||'')+'</td><td class="r">'+esc(Number(i.quantity)||0)+' '+esc(i.unit||'')+'</td><td class="r">'+ivM(i.unit_gross,cur)+'</td>'+(hasDisc?'<td class="r">'+(Number(i.discount_pct)?esc(i.discount_pct)+' %':'')+'</td>':'')+(vp?'<td class="r">'+(l.rate==null?'':esc(l.rate)+' %')+'</td>':'')+'<td class="r">'+ivM(l.gross,cur)+'</td></tr>'}).join('')||'<tr><td colspan="6" class="mutd">Zatím žádné položky.</td></tr>';
 var rec='';if(vp){Object.keys(T.byRate).sort(function(a,b){return b-a}).forEach(function(k){var b=T.byRate[k];rec+='<tr><td>'+(b.rate==null?'–':esc(b.rate)+' %')+'</td><td class="r">'+ivM(b.net,cur)+'</td><td class="r">'+ivM(b.tax,cur)+'</td><td class="r">'+ivM(b.gross,cur)+'</td></tr>'})}
 function blk(t,x,sup){return '<div class="pb"><h4>'+t+'</h4><b>'+esc(x.legal_name||x.name||x.company_name||'–')+'</b><br>'+(x.address_text||x.billing_address?esc(x.address_text||x.billing_address).replace(/\n/g,'<br>')+'<br>':'')+(x.ico?'IČO: '+esc(x.ico)+'<br>':'')+(x.dic?'DIČ: '+esc(x.dic)+'<br>':'')+(x.email?esc(x.email):'')+(sup&&x.registration_text?'<br><span class="fn">'+esc(x.registration_text)+'</span>':'')+'</div>'}
 var spd=(o.noqr||(o.preview&&!f.number))?null:VXINV.spayd(Object.assign({},f,{total:f.total!=null?f.total:T.gross})),qr='';
 if(spd){try{qr='<div class="qrb">'+VXQR.svg(spd,{label:'QR platba'})+'<small>QR platba</small></div>'}catch(e){qr=''}}
 else if(o.preview&&!f.number&&!o.noqr)qr='<div class="qrb ph"><small>QR platba se zobrazí po vystavení faktury (potřebuje číslo faktury a platný IBAN).</small></div>';
 var acct=sp.bank_account||'',iban=sp.iban||'';
 var title=o.title||(vp?'Faktura – daňový doklad':'Faktura');
 return '<div class="ivd" style="--ivc:'+esc(color)+'"><div class="ivh"><div><h2>'+title+'</h2><div class="ivn">'+(f.number?'č. '+esc(f.number):(o.noqr?'(číslo se přidělí po uložení)':'bez čísla (koncept)'))+'</div></div><div class="ivs ivs-'+st.k+'">'+esc(st.t)+'</div></div>'
  +'<div class="iv2">'+blk('Dodavatel',sp,true)+blk('Odběratel',cu,false)+'</div>'
  +'<div class="iv3"><div><small>Datum vystavení</small><b>'+fD(f.issued_on)+'</b></div>'+(vp||f.taxable_supply_on?'<div><small>Datum zdan. plnění</small><b>'+fD(f.taxable_supply_on||f.issued_on)+'</b></div>':'')+'<div><small>'+(o.dueLabel||'Splatnost')+'</small><b>'+fD(f.due_on)+'</b></div>'+(o.noqr?'':'<div><small>Způsob úhrady</small><b>Převodem</b></div>')+'</div>'
  +(o.noqr?'':'<div class="ivp"><div><small>Číslo účtu</small><b>'+esc(acct||'–')+'</b></div><div><small>IBAN</small><b>'+esc(iban||'–')+'</b></div><div><small>Variabilní symbol</small><b>'+esc(f.variable_symbol||f.number||'–')+'</b></div></div>')
  +'<table class="ivt"><thead><tr><th>Popis</th><th class="r">Množství</th><th class="r">'+(vp?'Cena/jedn. s DPH':'Cena/jedn.')+'</th>'+(hasDisc?'<th class="r">Sleva</th>':'')+(vp?'<th class="r">DPH</th>':'')+'<th class="r">Celkem</th></tr></thead><tbody>'+rows+'</tbody></table>'
  +(rec?'<table class="ivt sm"><thead><tr><th>Sazba DPH</th><th class="r">Základ</th><th class="r">DPH</th><th class="r">Celkem</th></tr></thead><tbody>'+rec+'</tbody></table>':'')
  +'<div class="ivb">'+qr+'<div class="ivtot"><span>Celkem k úhradě</span><b>'+ivM(f.total!=null?f.total:T.gross,cur)+'</b>'+(f.paid_at?'<small>Uhrazeno dne '+fD(f.paid_at)+'</small>':'')+'</div></div>'
  +(vp?'':'<p class="fn">Dodavatel není plátcem DPH.</p>')+(o.noqr?'':'<p class="fn">Vystaveno ve Vexaronetu.</p>')+'</div>'}
var IVCSS='.ivd{background:#fff;color:#161a33;border-radius:10px;padding:24px;font:13.5px/1.5 system-ui,Arial,sans-serif;text-align:left;box-sizing:border-box}.ivd *{box-sizing:border-box}.ivd h2{margin:0;font-size:21px;color:#161a33}.ivd h4{margin:0 0 3px;font-size:10.5px;letter-spacing:.08em;text-transform:uppercase;color:#6b7090;font-weight:700}.ivd small{display:block;color:#6b7090;font-size:11px}.ivd .fn{font-size:11.5px;color:#6b7090;margin:8px 0 0}'
 +'.ivd .ivh{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;border-bottom:3px solid var(--ivc);padding-bottom:12px;margin-bottom:14px}.ivd .ivn{color:var(--ivc);font-weight:800;margin-top:2px;font-size:15px}.ivd .ivs{border:2px solid #d9822b;color:#b8650f;font-weight:800;padding:4px 10px;border-radius:8px;white-space:nowrap;font-size:12px;text-transform:uppercase}.ivd .ivs-paid{border-color:#1a9d63;color:#117a4b}.ivd .ivs-late{border-color:#d03b3b;color:#b02a2a}.ivd .ivs-draft{border-color:#8a8fb0;color:#5a5f80}'
 +'.ivd .iv2{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-bottom:14px}.ivd .iv3,.ivd .ivp{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:10px;background:#f3f4fb;padding:10px 12px;border-radius:8px;margin-bottom:10px}.ivd .iv3 b,.ivd .ivp b{display:block;word-break:break-word}'
 +'.ivd table{width:100%;border-collapse:collapse;margin:10px 0}.ivd th{text-align:left;font-size:10.5px;color:#6b7090;border-bottom:1px solid #d5d9ea;padding:6px 4px;text-transform:uppercase;letter-spacing:.04em}.ivd td{padding:7px 4px;border-bottom:1px solid #eceef7;vertical-align:top}.ivd .r{text-align:right;white-space:nowrap}.ivd .sm td,.ivd .sm th{font-size:12px}.ivd .mutd{color:#6b7090;text-align:center;padding:16px}'
 +'.ivd .ivb{display:flex;justify-content:space-between;align-items:flex-end;gap:16px;margin-top:12px;flex-wrap:wrap}.ivd .qrb{width:128px}.ivd .qrb svg{width:128px;height:128px;display:block;border:1px solid #d5d9ea;border-radius:6px}.ivd .qrb small{text-align:center;margin-top:3px}.ivd .qrb.ph{width:190px;padding:10px;border:1px dashed #c3c8e0;border-radius:8px}.ivd .ivtot{margin-left:auto;text-align:right}.ivd .ivtot span{display:block;color:#6b7090;font-size:12px}.ivd .ivtot b{font-size:24px;color:var(--ivc)}'
 +'@media(max-width:560px){.ivd{padding:14px}.ivd .iv2{grid-template-columns:1fr}.ivd .ivt{display:block;overflow-x:auto}}';
function invView(id){var f=APP.d.invoices.rows.filter(function(x){return x.id===id})[0];if(!f)return;APP.invOpen=f;var st=ivStatus(f);
 modal('<style>'+IVCSS+'</style><div class="ivwrap">'+invDoc(f)+'</div><div class="dact"><button class="btn btn-main btn-sm" type="button" data-invprint="1">Tisk / uložit jako PDF</button>'+(st.k==='draft'?'<button class="btn btn-ghost btn-sm" type="button" data-ie="edit:'+esc(f.id)+'">Upravit koncept</button>':'<button class="btn btn-ghost btn-sm" type="button" data-ie="dup:'+esc(f.id)+'">Vytvořit podobnou</button>')+(st.k==='open'||st.k==='late'?'<button class="btn btn-ghost btn-sm" type="button" data-pay="'+esc(f.id)+'">Označit jako zaplacenou</button>':'')+'<button class="btn btn-ghost btn-sm" type="button" data-app="mclose">Zavřít</button></div>');
 var mb=document.querySelector('#appModal .mbox');if(mb)mb.classList.add('wide')}
function invPrint(){var f=APP.invOpen;if(!f)return;var fr=document.createElement('iframe');fr.style.cssText='position:fixed;right:0;bottom:0;width:0;height:0;border:0';document.body.appendChild(fr);var d=fr.contentWindow.document;d.open();
 d.write('<!doctype html><html lang="cs"><head><meta charset="utf-8"><title>Faktura '+esc(f.number||'')+'</title><style>@page{size:A4;margin:12mm}html,body{margin:0;background:#fff}'+IVCSS+'.ivd{padding:0;border-radius:0}.ivd svg{-webkit-print-color-adjust:exact;print-color-adjust:exact}*{-webkit-print-color-adjust:exact;print-color-adjust:exact}</style></head><body>'+invDoc(f)+'</body></html>');d.close();
 setTimeout(function(){try{fr.contentWindow.focus();fr.contentWindow.print()}catch(e){}setTimeout(function(){fr.remove()},2500)},300)}
/* ---- přehled ---- */
function ivStats(){var rows=APP.d.invoices.rows,t0=dayStart(0),m0=new Date(t0.getFullYear(),t0.getMonth(),1),o={open:{},late:{},paid:{},nOpen:0,nLate:0,nDraft:0,nPaidM:0};
 function add(b,cur,v){b[cur]=Math.round(((b[cur]||0)+Number(v||0))*100)/100}
 rows.forEach(function(f){var s=ivStatus(f),c=f.currency||'CZK';if(s.k==='draft'){o.nDraft++;return}if(s.k==='paid'){if(new Date(f.paid_at)>=m0){add(o.paid,c,f.total);o.nPaidM++}return}add(o.open,c,f.total);o.nOpen++;if(s.k==='late'){add(o.late,c,f.total);o.nLate++}});return o}
function ivSum(b){var k=Object.keys(b);return k.length?k.map(function(c){return ivM(b[c],c)}).join(' + '):ivM(0,'CZK')}
function fakturyView(){
 var x=APP.d.invoices,F=APP.invF||'all',Q=(APP.invQ||'').toLowerCase().trim(),S=ivStats();
 var h='<div class="card2 note"><b>Pozor:</b> faktury se vystavují přes pravidla ve vaší databázi (číslování, DPH). Před ostrým používáním je musí zkontrolovat účetní. Odesílání faktur e-mailem zatím není připojené.</div>'
  +'<div class="bar2"><button type="button" class="btn btn-ghost btn-sm" data-invprof="1">Fakturační údaje</button><button type="button" class="pri sm" data-newinv="1">+ Nová faktura</button></div>'+errBox(x)
  +'<div class="ivkpi"><div><small>K úhradě</small><b>'+ivSum(S.open)+'</b><em>'+S.nOpen+' '+plural(S.nOpen,'faktura','faktury','faktur')+'</em></div><div class="'+(S.nLate?'bad':'')+'"><small>Po splatnosti</small><b>'+ivSum(S.late)+'</b><em>'+S.nLate+' '+plural(S.nLate,'faktura','faktury','faktur')+'</em></div><div><small>Zaplaceno tento měsíc</small><b>'+ivSum(S.paid)+'</b><em>'+S.nPaidM+' '+plural(S.nPaidM,'faktura','faktury','faktur')+'</em></div><div><small>Koncepty</small><b>'+S.nDraft+'</b><em>nevystavené</em></div></div>';
 var fl=[['all','Vše'],['open','K úhradě'],['late','Po splatnosti'],['paid','Zaplacené'],['draft','Koncepty']];
 h+='<div class="ivfl" role="group" aria-label="Filtr faktur">'+fl.map(function(c){return '<button type="button" class="chipb" data-ie="f:'+c[0]+'" aria-pressed="'+(F===c[0])+'">'+c[1]+'</button>'}).join('')+'<label class="ivq"><span class="sr">Hledat faktury</span><input id="ivQ" type="search" placeholder="Hledat podle čísla nebo zákazníka" value="'+esc(APP.invQ||'')+'"></label></div>';
 var fs=x.rows.slice().sort(function(a,b){return new Date(b.issued_on||b.created_at)-new Date(a.issued_on||a.created_at)}).filter(function(f){var s=ivStatus(f).k;if(F==='open'&&s!=='open'&&s!=='late')return false;if(F!=='all'&&F!=='open'&&s!==F)return false;if(Q&&(String(f.number||'')+' '+invName(f)).toLowerCase().indexOf(Q)<0)return false;return true});
 if(!x.rows.length)return h+'<p class="mut">Zatím žádné faktury. Nejdřív vyplňte Fakturační údaje, pak vystavte první fakturu.</p>';
 if(!fs.length)return h+'<p class="mut" id="ivEmpty">Žádná faktura neodpovídá filtru.</p>';
 return h+'<ul class="rows big ivl">'+fs.map(function(f){var s=ivStatus(f);return '<li><div><b>'+esc(f.number||'Koncept')+'</b><small>'+esc(invName(f))+' · vystaveno '+fD(f.issued_on)+' · splatnost '+fD(f.due_on)+'</small></div><span class="ivst ivst-'+s.k+'">'+esc(s.t)+'</span><span class="ivam">'+fM(f.total,f.currency)+'</span><span class="ivac"><button type="button" class="lnk" data-invview="'+esc(f.id)+'">Zobrazit</button>'+(s.k==='draft'?'<button type="button" class="lnk" data-ie="edit:'+esc(f.id)+'">Upravit</button>':'<button type="button" class="lnk" data-ie="dup:'+esc(f.id)+'">Podobná</button>')+((s.k==='open'||s.k==='late')?'<button type="button" class="lnk" data-pay="'+esc(f.id)+'">Zaplaceno</button>':'')+'</span></li>'}).join('')+'</ul>'}
/* ---- editor ---- */
var IE=null;
function ivRates(sp){return sp.country_code==='SK'?[23,19,5]:[21,12]}
function ivRow(it,sp,vp){var rt=ivRates(sp),vr=it&&it.vat_rate!=null?Number(it.vat_rate):rt[0];
 return '<div class="ier"><input class="id" placeholder="Popis položky" aria-label="Popis" value="'+esc(it&&it.description||'')+'"><input class="iq" type="number" step="any" min="0" aria-label="Množství" value="'+esc(it&&it.quantity!=null?it.quantity:1)+'"><input class="iu" aria-label="Jednotka" value="'+esc(it&&it.unit||'ks')+'"><input class="ip" type="number" step="any" min="0" aria-label="'+(vp?'Cena za jednotku s DPH':'Cena za jednotku')+'" placeholder="'+(vp?'Cena s DPH':'Cena')+'" value="'+esc(it&&it.unit_gross!=null?it.unit_gross:'')+'">'
  +(vp?'<select class="iv" aria-label="Sazba DPH">'+rt.map(function(r){return '<option'+(r===vr?' selected':'')+'>'+r+'</option>'}).join('')+'</select>':'<span class="ivx"></span>')+'<output class="il" aria-label="Celkem za řádek"></output><button type="button" class="lnk" data-ie="del" aria-label="Odebrat položku">×</button></div>'}
function ivBuyerFromCust(c,sp){return {name:custName(c),address_text:c.billing_address||'',ico:c.ico||'',dic:c.dic||'',email:c.email||'',country_code:(sp&&sp.country_code)||'CZ'}}
function invEditor(o){o=o||{};var sp=ivProf();
 if(!sp||!sp.legal_name){toast('Nejdřív vyplňte Fakturační údaje (dodavatel), bez nich nejde fakturu vystavit.','err');profForm();return}
 var lm=!(o.draft)&&limitMsg('invoices');if(lm){toast(lm,'err');return}
 var src=o.draft||o.copy||null,vp=!!sp.vat_payer,td=locD(new Date()),dd=Number(sp.default_due_days)||14,du=locD(new Date(Date.now()+dd*864e5)),cs=APP.d.customers.rows,
  buyer=src&&src.customer_snapshot&&typeof src.customer_snapshot==='object'?src.customer_snapshot:(cs[0]?ivBuyerFromCust(cs[0],sp):{country_code:sp.country_code||'CZ'}),
  its=src?ivItems(src).map(function(i){return Object.assign({},i)}):[{}],base=sp.default_currency||'CZK',cur=src&&src.currency||base;
 IE={id:o.draft?o.draft.id:null,job:o.draft?o.draft.job_id:null,sp:sp,vp:vp,base:base};
 var h='<style>'+IVCSS+'</style><h3>'+(o.draft?'Upravit koncept faktury':(o.copy?'Nová faktura podle '+esc(src.number||'konceptu'):'Nová faktura'))+'</h3><form id="invEd" novalidate><div class="ied"><div class="iedf">'
  +'<fieldset class="ies"><legend>Odběratel</legend><div class="fg"><div class="f full"><label for="ieC">Zákazník z evidence</label><select id="ieC"><option value="">– zadat ručně –</option>'+cs.map(function(c){return '<option value="'+esc(c.id)+'">'+esc(custName(c))+'</option>'}).join('')+'</select></div>'
  +'<div class="f full"><label for="ieN">Název / jméno <i>*</i></label><input id="ieN" maxlength="200" value="'+esc(buyer.name||'')+'"></div><div class="f full"><label for="ieA">Adresa <i>*</i></label><textarea id="ieA" rows="2" maxlength="500">'+esc(buyer.address_text||buyer.billing_address||'')+'</textarea></div>'
  +'<div class="f"><label for="ieI">IČO</label><input id="ieI" inputmode="numeric" maxlength="30" value="'+esc(buyer.ico||'')+'"></div><div class="f"><label for="ieD">DIČ</label><input id="ieD" maxlength="30" value="'+esc(buyer.dic||'')+'"></div>'
  +'<div class="f"><label for="ieM">E-mail</label><input id="ieM" type="email" maxlength="200" value="'+esc(buyer.email||'')+'"></div><div class="f"><label for="ieK">Stát</label><select id="ieK"><option value="CZ"'+(buyer.country_code==='SK'?'':' selected')+'>Česko</option><option value="SK"'+(buyer.country_code==='SK'?' selected':'')+'>Slovensko</option></select></div>'
  +'<div class="f full" id="ieDomW" hidden><label class="chk"><input type="checkbox" id="ieDom"><span>Potvrzuji tuzemské místo plnění (jiný stát odběratele)</span></label></div></div></fieldset>'
  +'<fieldset class="ies"><legend>Údaje faktury</legend><div class="fg"><div class="f"><label for="ieIs">Datum vystavení</label><input id="ieIs" type="date" value="'+td+'"></div>'+(vp||sp.country_code==='SK'?'<div class="f"><label for="ieT">Datum zdanitelného plnění</label><input id="ieT" type="date" value="'+td+'"></div>':'')
  +'<div class="f"><label for="ieDu">Splatnost</label><input id="ieDu" type="date" value="'+(src&&src.due_on&&o.draft?String(src.due_on).slice(0,10):du)+'"></div><div class="f"><label for="ieCur">Měna</label><select id="ieCur"><option'+(cur==='CZK'?' selected':'')+'>CZK</option><option'+(cur==='EUR'?' selected':'')+'>EUR</option></select></div>'
  +'<div class="f full" id="ieFxW" hidden><div class="fg"><div class="f"><label for="ieFx">Kurz (kolik '+esc(base)+' za 1 vybranou měnu) <i>*</i></label><input id="ieFx" type="number" step="any" min="0"></div><div class="f"><label for="ieFxS">Zdroj kurzu <i>*</i></label><input id="ieFxS" maxlength="300" placeholder="např. kurz ČNB"></div><div class="f"><label for="ieFxD">Datum kurzu <i>*</i></label><input id="ieFxD" type="date" value="'+td+'"></div></div></div></div></fieldset>'
  +'<fieldset class="ies"><legend>Položky</legend><div id="ieRows" class="ierows">'+its.map(function(i){return ivRow(i,sp,vp)}).join('')+'</div><div class="dact"><button type="button" class="btn btn-ghost btn-sm" data-ie="add">+ Položka</button>'
  +(APP.d.products.rows.some(function(p){return p.active!==false&&Number(p.price)>0})?'<label class="ivprod"><span class="sr">Přidat produkt ze skladu</span><select id="iePr"><option value="">+ Přidat produkt ze skladu…</option>'+APP.d.products.rows.filter(function(p){return p.active!==false&&Number(p.price)>0}).map(function(p){return '<option value="'+esc(p.id)+'">'+esc(p.name)+' – '+ivM(p.price,'CZK')+'</option>'}).join('')+'</select></label>':'')+'</div>'
  +'<p class="mut fine">'+(vp?'Ceny zadávejte včetně DPH.':'Dodavatel není plátcem DPH, faktura bez DPH.')+' Sazby DPH a jejich použití musí ověřit účetní.</p></fieldset>'
  +'<div class="st" id="entSt" role="status"></div><div class="dact"><button class="btn btn-ghost" type="submit" data-save="draft">Uložit koncept</button><button class="pri" type="submit" data-save="issue">Vystavit fakturu</button><button class="btn btn-ghost" type="button" data-app="mclose">Zrušit</button></div></div>'
  +'<div class="iedp"><div class="mut fine" style="margin-bottom:6px">Živý náhled (číslo se přidělí při vystavení)</div><div id="iePrev"></div></div></div></form>';
 modal(h);var mb=document.querySelector('#appModal .mbox');if(mb)mb.classList.add('wide');
 if(!src||!its.length)A('ieRows').innerHTML=ivRow({},sp,vp);
 if(src&&src.customer_snapshot&&cs.length){var m=cs.filter(function(c){return custName(c)===buyer.name})[0];if(m)A('ieC').value=m.id}
 ivSync()}
function ivRead(){var sp=IE.sp,vp=IE.vp,items=[].map.call(document.querySelectorAll('#ieRows .ier'),function(r){var q=parseFloat(r.querySelector('.iq').value),u=parseFloat(r.querySelector('.ip').value),v=r.querySelector('.iv');return {description:r.querySelector('.id').value.trim(),quantity:isNaN(q)?0:q,unit:r.querySelector('.iu').value.trim()||'ks',unit_gross:isNaN(u)?NaN:u,vat_rate:vp&&v?parseFloat(v.value):null}}),
  buyer={name:A('ieN').value.trim(),address_text:A('ieA').value.trim(),ico:A('ieI').value.trim(),dic:A('ieD').value.trim(),email:A('ieM').value.trim(),country_code:A('ieK').value};
 return {items:items,buyer:buyer,issued_on:A('ieIs').value,due_on:A('ieDu').value,taxable_supply_on:A('ieT')?A('ieT').value:'',currency:A('ieCur').value}}
function ivSync(){if(!IE||!A('invEd'))return;var d=ivRead(),sp=IE.sp,C=VXINV.calc(d.items.map(function(i){return {quantity:i.quantity,unit_gross:isNaN(i.unit_gross)?0:i.unit_gross,vat_rate:i.vat_rate}}),IE.vp);
 [].forEach.call(document.querySelectorAll('#ieRows .ier'),function(r,i){var o=r.querySelector('.il');if(o&&C.lines[i])o.textContent=ivM(C.lines[i].gross,d.currency)});
 A('ieFxW').hidden=d.currency===IE.base;A('ieDomW').hidden=d.buyer.country_code===(sp.country_code||'CZ');
 var f={lifecycle:'draft',number:'',issued_on:d.issued_on,taxable_supply_on:d.taxable_supply_on||d.issued_on,due_on:d.due_on,currency:d.currency,vat_payer:IE.vp,supplier_snapshot:sp,customer_snapshot:d.buyer,items:d.items.map(function(i){return {description:i.description,quantity:i.quantity,unit:i.unit,unit_gross:isNaN(i.unit_gross)?0:i.unit_gross,vat_rate:i.vat_rate}}),total:C.total.gross};
 A('iePrev').innerHTML=invDoc(f,{preview:true})}
async function ivSave(kind){
 var d=ivRead(),sp=IE.sp,vp=IE.vp,issue=kind==='issue';
 if(!d.buyer.name){entMsg('Vyplňte jméno nebo název odběratele.');return}
 if(d.buyer.address_text.length<5){entMsg('Vyplňte úplnou adresu odběratele (alespoň 5 znaků).');return}
 if(!d.items.length||d.items.some(function(i){return !i.description||!(i.quantity>0)||isNaN(i.unit_gross)||i.unit_gross<0})){entMsg('U každé položky vyplňte popis, množství a cenu.');return}
 if(!d.issued_on||!d.due_on||d.due_on<d.issued_on){entMsg('Zkontrolujte data vystavení a splatnosti.');return}
 var today=locD(new Date());if(issue&&d.issued_on!==today){d.issued_on=today;A('ieIs').value=today}
 if(!issue&&false){}
 var doc={customer:d.buyer,items:d.items.map(function(i){return {description:i.description,quantity:i.quantity,unit:i.unit,unit_gross:i.unit_gross,vat_rate:i.vat_rate}}),issued_on:d.issued_on,taxable_supply_on:d.taxable_supply_on||d.issued_on,due_on:d.due_on,currency:d.currency,language:'cs'};
 if(d.currency!==IE.base){var fx=parseFloat(A('ieFx').value);if(!(fx>0)){entMsg('Doplňte kurz pro přepočet měny.');return}doc.fx_to_base=fx;doc.tax_fx=fx;doc.fx_source=A('ieFxS').value.trim();doc.fx_date=A('ieFxD').value;if(!doc.fx_source||!doc.fx_date){entMsg('Doplňte zdroj a datum kurzu.');return}}
 if(d.buyer.country_code!==(sp.country_code||'CZ'))doc.domestic_place_confirmed=A('ieDom').checked;
 if(issue&&!confirm('Vystavit fakturu? Přidělí se číslo faktury a vystavenou fakturu už nelze upravit ani vzít zpět.'))return;
 var bs=[].slice.call(document.querySelectorAll('#invEd button[type=submit]'));bs.forEach(function(b){b.disabled=true});entMsg('');var er=A('entSt');if(er){er.className='st';er.textContent=issue?'Vystavuji…':'Ukládám…'}
 try{
  var id=IE.id,cu=APP.d.customers.rows.filter(function(x){return x.id===A('ieC').value})[0]||{};
  if(!id){var tt=VXINV.calc(d.items,vp).total.gross,jr=await getSb().from('jobs').insert({company_id:APP.cid,customer_id:cu.id||null,title:'Faktura: '+d.items[0].description.slice(0,80),price:tt,status:'done',stage:'Hotovo'}).select('id');
   if(jr.error)throw jr.error;var jid=jr.data&&jr.data[0]&&jr.data[0].id;if(!jid)throw new Error('Nepodařilo se připravit fakturu.');
   var sr=await rpcInv('start',{job_id:jid});if(sr.error)throw sr.error;id=sr.data&&sr.data.id;if(!id)throw new Error('Nepodařilo se založit fakturu.');IE.id=id;doc.job_id=jid}
  if(IE.job)doc.job_id=IE.job;doc.id=id;var r=await rpcInv(issue?'issue':'save',doc);if(r.error)throw r.error;
  closeModal();await refresh();appTab('faktury');toast(issue?'Faktura vystavena'+(r.data&&r.data.number?' (č. '+r.data.number+')':'')+'.':'Koncept uložen.','ok');IE=null
 }catch(ex){bs.forEach(function(b){b.disabled=false});var msg=String(ex&&ex.message||ex);
  if(/fakturační údaje|profil/i.test(msg)){toast('Nejdřív vyplňte fakturační údaje dodavatele.','err');profForm();return}
  entMsg((issue?'Fakturu se nepodařilo vystavit: ':'Koncept se nepodařilo uložit: ')+msg)}}
document.addEventListener('click',function(e){
 var t=e.target.closest('#vxapp [data-ie]');if(!t)return;var k=t.dataset.ie,p=k.split(':');
 if(p[0]==='f'){APP.invF=p[1];appTab('faktury');return}
 if(p[0]==='edit'){var f=APP.d.invoices.rows.filter(function(x){return x.id===p[1]})[0];if(f)invEditor({draft:f});return}
 if(p[0]==='dup'){var g=APP.d.invoices.rows.filter(function(x){return x.id===p[1]})[0];if(g)invEditor({copy:g});return}
 if(k==='add'){A('ieRows').insertAdjacentHTML('beforeend',ivRow({},IE.sp,IE.vp));ivSync();var l=A('ieRows').lastElementChild;l&&l.querySelector('.id').focus();return}
 if(k==='del'){var rw=t.closest('.ier');if(document.querySelectorAll('#ieRows .ier').length>1){rw.remove();ivSync()}else toast('Faktura musí mít alespoň jednu položku.','err');return}});
document.addEventListener('click',function(e){var b=e.target.closest('#invEd button[type=submit]');if(b)IE&&(IE.kind=b.dataset.save)},true);
document.addEventListener('submit',function(e){if(e.target.id!=='invEd')return;e.preventDefault();e.stopImmediatePropagation();ivSave((e.submitter&&e.submitter.dataset.save)||(IE&&IE.kind)||'draft')},true);
document.addEventListener('input',function(e){if(e.target.id==='ivQ'){APP.invQ=e.target.value;var pos=e.target.selectionStart;appTab('faktury');var q=A('ivQ');if(q){q.focus();try{q.setSelectionRange(pos,pos)}catch(x){}}return}if(e.target.closest&&e.target.closest('#invEd'))ivSync()});
document.addEventListener('change',function(e){var t=e.target;if(!t.closest||!t.closest('#invEd'))return;
 if(t.id==='ieC'){var c=APP.d.customers.rows.filter(function(x){return x.id===t.value})[0];if(c){var b=ivBuyerFromCust(c,IE.sp);A('ieN').value=b.name;A('ieA').value=b.address_text;A('ieI').value=b.ico;A('ieD').value=b.dic;A('ieM').value=b.email}}
 if(t.id==='iePr'){var p=APP.d.products.rows.filter(function(x){return x.id===t.value})[0];if(p){var rt=ivRates(IE.sp),vr=rt.indexOf(Number(p.vat_rate))>=0?Number(p.vat_rate):rt[0],rows=A('ieRows'),last=rows.lastElementChild,empty=last&&!last.querySelector('.id').value.trim()&&!last.querySelector('.ip').value;if(empty)last.remove();rows.insertAdjacentHTML('beforeend',ivRow({description:p.name,quantity:1,unit:p.unit||'ks',unit_gross:Number(p.price),vat_rate:vr},IE.sp,IE.vp));t.value=''}}
 ivSync()});
