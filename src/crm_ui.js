/* ===== CRM: obchodní případy, nabídky, historie klienta ===== */
IC.pripady='M3 5h5v14H3zM10 5h5v9h-5zM17 5h4v6h-4z';IC.nabidky='M6 3h9l4 4v14H6zM9 12h7M9 16h5';
var CRMST=[['new','Nový',10],['contact','Kontakt',25],['offer','Nabídka',50],['negotiation','Jednání',75],['won','Vyhráno',100],['lost','Prohráno',0]];
var CRMQ={draft:'Koncept',sent:'Odeslaná',accepted:'Přijatá',rejected:'Odmítnutá'};
function crmErr(x){return x&&x.err?'<div class="draft">Data se nepodařilo načíst: '+esc(x.err)+' Tato část vyžaduje aktualizaci databáze, která zatím nebyla provedena.</div>':''}
function crmCust(id){return APP.d.customers.rows.filter(function(c){return c.id===id})[0]||null}
function crmSum(a,k){return a.reduce(function(s,d){return s+Number(d[k||'value']||0)},0)}
VIEWS.pripady=function(){
 var x=APP.d.deals,rs=x.rows,open=rs.filter(function(d){return d.stage!=='won'&&d.stage!=='lost'}),m0=new Date(new Date().getFullYear(),new Date().getMonth(),1),
  fc=open.reduce(function(s,d){return s+Number(d.value||0)*(Number(d.probability)||0)/100},0),
  won=rs.filter(function(d){return d.stage==='won'&&new Date(d.updated_at||d.created_at)>=m0});
 var h='<div class="bar2"><span class="mut">Rozjednané obchody a odhad tržeb. Pravděpodobnost úspěchu určujete sami.</span><button type="button" class="pri sm" data-new="deals">+ Nový obchodní případ</button></div>'+crmErr(x)
  +'<div class="ivkpi"><div><small>Otevřené případy</small><b>'+open.length+'</b><em>v hodnotě '+fM(crmSum(open))+'</em></div><div><small>Vážený odhad tržeb</small><b>'+fM(Math.round(fc))+'</b><em>hodnota × pravděpodobnost</em></div><div><small>Vyhráno tento měsíc</small><b>'+fM(crmSum(won))+'</b><em>'+won.length+' '+plural(won.length,'případ','případy','případů')+'</em></div></div>';
 if(!rs.length&&!x.err)h+='<p class="mut">Zatím žádné obchodní případy. Přidejte první a posouvejte ho mezi fázemi.</p>';
 return h+'<div class="kbn">'+CRMST.map(function(s,i){var c=rs.filter(function(d){return d.stage===s[0]});
  return '<section class="kbc" aria-label="'+esc(s[1])+'"><h4>'+esc(s[1])+' <em>'+c.length+'</em></h4><small class="mut">'+fM(crmSum(c))+'</small>'+c.map(function(d){var cu=crmCust(d.customer_id);
   return '<div class="kbd"><b data-edit="deals:'+esc(d.id)+'" tabindex="0" role="button">'+esc(d.title)+'</b><small>'+esc(cu?custName(cu):'bez zákazníka')+'</small><span>'+fM(d.value)+' · '+esc(d.probability)+' %'+(d.expected_close?' · '+fD(d.expected_close):'')+'</span><div class="kbm">'+(i>0?'<button type="button" class="lnk" data-crm="mv:'+esc(d.id)+':-1" aria-label="Posunout o fázi zpět">‹</button>':'')+(i<CRMST.length-1?'<button type="button" class="lnk" data-crm="mv:'+esc(d.id)+':1" aria-label="Posunout o fázi dál">›</button>':'')+(s[0]==='offer'||s[0]==='negotiation'?'<button type="button" class="lnk" data-crm="qd:'+esc(d.id)+'">Nabídka</button>':'')+'</div></div>'}).join('')+'</section>'}).join('')+'</div>'};
/* ---- nabídky ---- */
function crmQDoc(q,o){o=o||{};var cu=q.customer_snapshot||crmCust(q.customer_id)||{},sp=ivProf()||{},vp=!!sp.vat_payer,
 f={lifecycle:'draft',number:q.number||'',issued_on:q.created_at||new Date().toISOString(),due_on:q.valid_until,currency:q.currency||'CZK',vat_payer:vp,supplier_snapshot:sp,customer_snapshot:{name:cu.name||custName(cu),address_text:cu.billing_address||cu.address_text||'',ico:cu.ico||'',dic:cu.dic||'',email:cu.email||''},items:q.items||[],total:q.total};
 return invDoc(f,{title:'Cenová nabídka',noqr:true,dueLabel:'Platnost nabídky do',badge:{k:q.status==='accepted'?'paid':(q.status==='rejected'?'late':'draft'),t:CRMQ[q.status]||'Koncept'},color:o.color})}
VIEWS.nabidky=function(){
 var x=APP.d.quotes,rs=x.rows.slice().sort(function(a,b){return new Date(b.created_at)-new Date(a.created_at)});
 var h='<div class="card2 note"><b>Pozor:</b> nabídka není daňový doklad. Odesílání nabídek e-mailem zatím není připojené, nabídku si můžete vytisknout nebo uložit jako PDF.</div><div class="bar2"><span></span><button type="button" class="pri sm" data-crm="qn">+ Nová nabídka</button></div>'+crmErr(x);
 if(!rs.length)return h+(x.err?'':'<p class="mut">Zatím žádné nabídky. Vytvořte první a po přijetí z ní jedním kliknutím připravíte fakturu.</p>');
 return h+'<ul class="rows big ivl">'+rs.map(function(q){var cu=crmCust(q.customer_id);return '<li><div><b>'+esc(q.number||'Nabídka')+(q.title?' · '+esc(q.title):'')+'</b><small>'+esc(cu?custName(cu):'bez zákazníka')+' · vytvořeno '+fD(q.created_at)+(q.valid_until?' · platí do '+fD(q.valid_until):'')+'</small></div><span class="ivst ivst-'+(q.status==='accepted'?'paid':(q.status==='rejected'?'late':'open'))+'">'+esc(CRMQ[q.status]||q.status)+'</span><span class="ivam">'+fM(q.total,q.currency)+'</span><span class="ivac"><button type="button" class="lnk" data-crm="qv:'+esc(q.id)+'">Zobrazit</button><button type="button" class="lnk" data-crm="qe:'+esc(q.id)+'">Upravit</button>'+(q.status==='draft'?'<button type="button" class="lnk" data-crm="qs:'+esc(q.id)+':sent">Označit jako odeslanou</button>':'')+(q.status==='sent'||q.status==='draft'?'<button type="button" class="lnk" data-crm="qs:'+esc(q.id)+':accepted">Přijata</button><button type="button" class="lnk" data-crm="qs:'+esc(q.id)+':rejected">Odmítnuta</button>':'')+'<button type="button" class="lnk" data-crm="qi:'+esc(q.id)+'">Vytvořit fakturu</button></span></li>'}).join('')+'</ul>'};
var QE=null;
function qeRows(){return [].map.call(document.querySelectorAll('#qeRows .ier'),function(r){var q=parseFloat(r.querySelector('.iq').value),u=parseFloat(r.querySelector('.ip').value),v=r.querySelector('.iv');return {description:r.querySelector('.id').value.trim(),quantity:isNaN(q)?0:q,unit:r.querySelector('.iu').value.trim()||'ks',unit_gross:isNaN(u)?NaN:u,vat_rate:QE.vp&&v?parseFloat(v.value):null}})}
function qeSync(){if(!QE||!A('qeForm'))return;var its=qeRows(),C=VXINV.calc(its.map(function(i){return {quantity:i.quantity,unit_gross:isNaN(i.unit_gross)?0:i.unit_gross,vat_rate:i.vat_rate}}),QE.vp);
 [].forEach.call(document.querySelectorAll('#qeRows .ier'),function(r,i){var o=r.querySelector('.il');if(o&&C.lines[i])o.textContent=ivM(C.lines[i].gross,A('qeCur').value)});
 A('qePrev').innerHTML=crmQDoc({number:QE.number,status:QE.status||'draft',customer_id:A('qeC').value,valid_until:A('qeV').value,currency:A('qeCur').value,items:its.map(function(i){return {description:i.description,quantity:i.quantity,unit:i.unit,unit_gross:isNaN(i.unit_gross)?0:i.unit_gross,vat_rate:i.vat_rate}}),total:C.total.gross,created_at:new Date().toISOString()})}
function quoteEditor(q,pre){q=q||{};pre=pre||{};var sp=ivProf()||{},vp=!!sp.vat_payer,cs=APP.d.customers.rows;
 if(!cs.length){toast('Nejdřív přidejte zákazníka (menu CRM a zákazníci).','err');return}
 QE={id:q.id||null,sp:sp,vp:vp,number:q.number||'',status:q.status,deal:q.deal_id||pre.deal_id||null};
 var its=(q.items&&q.items.length?q.items:[{}]),cu0=q.customer_id||pre.customer_id||cs[0].id,vu=q.valid_until||locD(new Date(Date.now()+30*864e5));
 modal('<style>'+IVCSS+'</style><h3>'+(q.id?'Upravit nabídku '+esc(q.number||''):'Nová nabídka')+'</h3><form id="qeForm" novalidate><div class="ied"><div class="iedf"><fieldset class="ies"><legend>Údaje nabídky</legend><div class="fg"><div class="f full"><label for="qeC">Zákazník <i>*</i></label><select id="qeC">'+cs.map(function(c){return '<option value="'+esc(c.id)+'"'+(c.id===cu0?' selected':'')+'>'+esc(custName(c))+'</option>'}).join('')+'</select></div><div class="f full"><label for="qeT">Název nabídky</label><input id="qeT" maxlength="200" value="'+esc(q.title||pre.title||'')+'"></div><div class="f"><label for="qeV">Platnost do</label><input id="qeV" type="date" value="'+esc(vu)+'"></div><div class="f"><label for="qeCur">Měna</label><select id="qeCur"><option'+((q.currency||'CZK')==='CZK'?' selected':'')+'>CZK</option><option'+(q.currency==='EUR'?' selected':'')+'>EUR</option></select></div></div></fieldset>'
  +'<fieldset class="ies"><legend>Položky</legend><div id="qeRows" class="ierows">'+its.map(function(i){return ivRow(i,sp,vp)}).join('')+'</div><div class="dact"><button type="button" class="btn btn-ghost btn-sm" data-crm="qa">+ Položka</button></div><p class="mut fine">'+(vp?'Ceny zadávejte včetně DPH.':'Dodavatel není plátcem DPH, ceny bez DPH.')+'</p></fieldset>'
  +'<div class="f full"><label for="qeN">Poznámka k nabídce</label><textarea id="qeN" rows="2" maxlength="4000">'+esc(q.note||'')+'</textarea></div><div class="st" id="entSt" role="status"></div><div class="dact"><button class="pri" type="submit">Uložit nabídku</button><button class="btn btn-ghost" type="button" data-app="mclose">Zrušit</button></div></div><div class="iedp"><div class="mut fine" style="margin-bottom:6px">Živý náhled</div><div id="qePrev"></div></div></div></form>');
 var mb=document.querySelector('#appModal .mbox');if(mb)mb.classList.add('wide');qeSync()}
async function quoteSave(){var its=qeRows(),cid=A('qeC').value;
 if(!its.length||its.some(function(i){return !i.description||!(i.quantity>0)||isNaN(i.unit_gross)||i.unit_gross<0})){entMsg('U každé položky vyplňte popis, množství a cenu.');return}
 var C=VXINV.calc(its,QE.vp),row={customer_id:cid,title:A('qeT').value.trim()||null,valid_until:A('qeV').value||null,currency:A('qeCur').value,items:its,total:C.total.gross,note:A('qeN').value.trim()||null};
 var b=document.querySelector('#qeForm button[type=submit]');b.disabled=true;
 try{var r;if(QE.id)r=await getSb().from('quotes').update(row).eq('id',QE.id);else{row.company_id=APP.cid;if(QE.deal)row.deal_id=QE.deal;r=await getSb().from('quotes').insert(row)}
  if(r.error)throw r.error;closeModal();await refresh();appTab('nabidky');toast('Nabídka uložena.','ok');QE=null}
 catch(ex){b.disabled=false;entMsg('Nabídku se nepodařilo uložit: '+String(ex&&ex.message||ex))}}
function crmQView(id){var q=APP.d.quotes.rows.filter(function(x){return x.id===id})[0];if(!q)return;APP.crmQ=q;
 modal('<style>'+IVCSS+'</style><div class="ivwrap">'+crmQDoc(q)+'</div><div class="dact"><button class="btn btn-main btn-sm" type="button" data-crm="qp">Tisk / uložit jako PDF</button><button class="btn btn-ghost btn-sm" type="button" data-app="mclose">Zavřít</button></div>');var mb=document.querySelector('#appModal .mbox');if(mb)mb.classList.add('wide')}
function crmQPrint(){var q=APP.crmQ;if(!q)return;var fr=document.createElement('iframe');fr.style.cssText='position:fixed;right:0;bottom:0;width:0;height:0;border:0';document.body.appendChild(fr);var d=fr.contentWindow.document;d.open();
 d.write('<!doctype html><html lang="cs"><head><meta charset="utf-8"><title>Nabídka '+esc(q.number||'')+'</title><style>@page{size:A4;margin:12mm}html,body{margin:0;background:#fff}'+IVCSS+'.ivd{padding:0;border-radius:0}*{-webkit-print-color-adjust:exact;print-color-adjust:exact}</style></head><body>'+crmQDoc(q)+'</body></html>');d.close();
 setTimeout(function(){try{fr.contentWindow.focus();fr.contentWindow.print()}catch(e){}setTimeout(function(){fr.remove()},2500)},300)}
/* ---- historie klienta ---- */
var CRMK={note:'Poznámka',call:'Telefonát',meeting:'Schůzka',email:'E-mail'};
function crmTimeline(cid){var c=crmCust(cid);if(!c)return;APP.crmC=cid;var ev=[],d=APP.d;
 d.jobs.rows.filter(function(j){return j.customer_id===cid}).forEach(function(j){ev.push({t:j.created_at,k:'Zakázka',s:j.title+(j.price!=null?' · '+fM(j.price):'')})});
 d.invoices.rows.forEach(function(f){var cs=f.customer_snapshot&&typeof f.customer_snapshot==='object'?f.customer_snapshot:{};if(cs.id===cid||(cs.name&&cs.name===custName(c)))ev.push({t:f.issued_on||f.created_at,k:'Faktura',s:(f.number||'koncept')+' · '+fM(f.total,f.currency)+' · '+ivStatus(f).t})});
 d.quotes.rows.filter(function(q){return q.customer_id===cid}).forEach(function(q){ev.push({t:q.created_at,k:'Nabídka',s:(q.number||'')+' · '+fM(q.total,q.currency)+' · '+(CRMQ[q.status]||'')})});
 d.deals.rows.filter(function(x){return x.customer_id===cid}).forEach(function(x){ev.push({t:x.created_at,k:'Obchodní případ',s:x.title+' · '+fM(x.value)})});
 d.reservations.rows.filter(function(r){return r.customer_id===cid}).forEach(function(r){ev.push({t:r.starts_at,k:'Rezervace',s:r.title})});
 d.client_notes.rows.filter(function(n){return n.customer_id===cid}).forEach(function(n){ev.push({t:n.created_at,k:CRMK[n.kind]||'Poznámka',s:n.body})});
 ev.sort(function(a,b){return new Date(b.t)-new Date(a.t)});
 modal('<h3>Historie klienta: '+esc(custName(c))+'</h3><form id="cnForm"><div class="fg"><div class="f"><label for="cnK">Druh záznamu</label><select id="cnK">'+Object.keys(CRMK).map(function(k){return '<option value="'+k+'">'+CRMK[k]+'</option>'}).join('')+'</select></div><div class="f full"><label for="cnB">Zápis <i>*</i></label><textarea id="cnB" rows="2" maxlength="4000"></textarea></div></div><div class="st" id="entSt" role="status"></div><div class="dact"><button class="pri sm" type="submit">Přidat záznam</button><button class="btn btn-ghost btn-sm" type="button" data-app="mclose">Zavřít</button></div></form>'+crmErr(d.client_notes)
  +(ev.length?'<ul class="rows tl">'+ev.map(function(e){return '<li><div><b>'+esc(e.k)+'</b><small>'+fD(e.t)+'</small></div><span>'+esc(e.s)+'</span></li>'}).join('')+'</ul>':'<p class="mut">U tohoto klienta zatím nic není.</p>'))}
function crmAfterForm(ent,id){if(ent!=='customers'||!id)return;var da=document.querySelector('#entForm .dact');if(da)da.insertAdjacentHTML('afterbegin','<button class="btn btn-ghost" type="button" data-crm="th:'+esc(id)+'">Historie klienta</button>')}
async function crmMove(id,dir){var d=APP.d.deals.rows.filter(function(x){return x.id===id})[0];if(!d)return;var i=CRMST.findIndex(function(s){return s[0]===d.stage})+dir;if(i<0||i>=CRMST.length)return;
 var r=await getSb().from('deals').update({stage:CRMST[i][0],probability:CRMST[i][2],updated_at:new Date().toISOString()}).eq('id',id);if(r.error){toast('Případ se nepodařilo posunout: '+r.error.message,'err');return}await refresh();appTab('pripady')}
document.addEventListener('click',async function(e){var t=e.target.closest('#vxapp [data-crm]');if(!t)return;var p=t.dataset.crm.split(':'),k=p[0],q;
 function Q(i){return APP.d.quotes.rows.filter(function(x){return x.id===i})[0]}
 if(k==='mv')return crmMove(p[1],Number(p[2]));
 if(k==='qn')return quoteEditor();
 if(k==='qe'){q=Q(p[1]);if(q)quoteEditor(q);return}
 if(k==='qv')return crmQView(p[1]);
 if(k==='qp')return crmQPrint();
 if(k==='qa'){A('qeRows').insertAdjacentHTML('beforeend',ivRow({},QE.sp,QE.vp));qeSync();return}
 if(k==='qd'){var d=APP.d.deals.rows.filter(function(x){return x.id===p[1]})[0];if(d)quoteEditor(null,{customer_id:d.customer_id,deal_id:d.id,title:d.title});return}
 if(k==='qs'){var r=await getSb().from('quotes').update({status:p[2]}).eq('id',p[1]);if(r.error){toast('Stav se nepodařilo změnit: '+r.error.message,'err');return}await refresh();appTab('nabidky');return}
 if(k==='qi'){q=Q(p[1]);if(!q)return;var cu=crmCust(q.customer_id)||{};invEditor({copy:{number:q.number,currency:q.currency,items:q.items||[],customer_snapshot:{name:custName(cu),address_text:cu.billing_address||'',ico:cu.ico||'',dic:cu.dic||'',email:cu.email||'',country_code:(ivProf()||{}).country_code||'CZ'}}});return}
 if(k==='th')return crmTimeline(p[1])});
document.addEventListener('submit',async function(e){var f=e.target;if(f.id==='qeForm'){e.preventDefault();e.stopImmediatePropagation();quoteSave();return}
 if(f.id==='cnForm'){e.preventDefault();e.stopImmediatePropagation();var b=A('cnB').value.trim();if(!b){entMsg('Napište text záznamu.');return}
  var r=await getSb().from('client_notes').insert({company_id:APP.cid,customer_id:APP.crmC,kind:A('cnK').value,body:b});if(r.error){entMsg('Záznam se nepodařilo uložit: '+r.error.message);return}
  await refresh();crmTimeline(APP.crmC)}},true);
document.addEventListener('input',function(e){if(e.target.closest&&e.target.closest('#qeForm'))qeSync()});
document.addEventListener('change',function(e){if(e.target.closest&&e.target.closest('#qeForm'))qeSync()});
document.addEventListener('click',function(e){var t=e.target.closest('#qeForm [data-ie="del"]');if(!t)return;e.stopPropagation();var rw=t.closest('.ier');if(document.querySelectorAll('#qeRows .ier').length>1){rw.remove();qeSync()}else toast('Nabídka musí mít alespoň jednu položku.','err')},true);
