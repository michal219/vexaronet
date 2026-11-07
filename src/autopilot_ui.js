/* ===== AI Autopilot: horní přepínač režimů a přehled stavu a bezpečnosti =====
   Tato část NESPOUŠTÍ žádné volání AI. Přepínač jen otevírá existující moduly a přehled zobrazuje a nastavuje
   měsíční limit (RPC autopilot_status / autopilot_set_budget). Vynucování limitu probíhá v databázi. */
IC.autopilot='M12 2l2.2 5.4L20 9l-4.4 3.6L17 19l-5-3-5 3 1.4-6.4L4 9l5.8-1.6z';
var APS={mode:null};
function apStyle(){if(document.getElementById('apCss'))return;var s=document.createElement('style');s.id='apCss';
 s.textContent='.apbar{display:flex;gap:8px;overflow-x:auto;padding:6px 20px 8px;white-space:nowrap;scrollbar-width:thin;-webkit-overflow-scrolling:touch}.apbar .apb{flex:0 0 auto;display:inline-flex;align-items:center;gap:8px;padding:8px 14px;border-radius:999px;border:1px solid rgba(139,108,255,.35);background:rgba(139,108,255,.08);color:inherit;font:inherit;font-size:.92rem;cursor:pointer}.apbar .apb:hover{background:rgba(139,108,255,.18)}.apbar .apb.on{background:rgba(139,108,255,.34);border-color:rgba(139,108,255,.9);font-weight:600}.apbar .apb:focus-visible{outline:2px solid #8b6cff;outline-offset:2px}.apbar .apt{font-style:normal;font-size:.72rem;padding:2px 7px;border-radius:999px;background:rgba(128,128,160,.22)}.apbar .apt.soon{background:rgba(255,190,80,.22)}.apbar .apt.lock{background:rgba(220,60,80,.2)}.apsub{display:flex;flex-wrap:wrap;gap:8px 14px;align-items:center;padding:0 20px 8px;font-size:.88rem}.apsub .mut{flex:1 1 280px}.apsub button{font:inherit;font-size:.85rem}.ap .apgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px}.ap .apcard{padding:14px;border-radius:14px;border:1px solid rgba(128,128,160,.3)}.ap .apcard h4{margin:0 0 6px}.ap .apmeter{height:10px;border-radius:999px;background:rgba(128,128,160,.25);overflow:hidden;margin:8px 0}.ap .apmeter i{display:block;height:100%;background:#8b6cff}.ap .apchk{list-style:none;padding:0;margin:8px 0}.ap .apchk li{padding:4px 0}.ap .apchk b{display:inline-block;width:1.4em}.ap .sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)}.ap .apok{color:#5fd18a}.ap .apno{color:#ff9aa8}@media(max-width:640px){.apbar,.apsub{padding-left:12px;padding-right:12px}}';
 document.head.appendChild(s)}
function apNeedsOk(m){var p=effPlan();if(m.needs==='start')return true;if(m.needs==='accountant')return ['accountant','pro','business','enterprise'].indexOf(p)>=0;return ['pro','business','enterprise'].indexOf(p)>=0}
function apBar(){
 var main=A('appMain'),root=A('vxapp');if(!main||!root)return;
 var bar=A('apBar'),sub=A('apSub');
 if(APP.role==='employee'){if(bar)bar.remove();if(sub)sub.remove();return}
 apStyle();
 if(!bar){bar=document.createElement('nav');bar.id='apBar';bar.className='apbar';bar.setAttribute('aria-label','Režimy AI Autopilota');main.parentNode.insertBefore(bar,main)}
 if(!sub){sub=document.createElement('div');sub.id='apSub';sub.className='apsub';main.parentNode.insertBefore(sub,main)}
 var cur=VXAP.modeOfTab(APP.tab,APS.mode);if(cur&&cur!=='home')APS.mode=cur;
 bar.innerHTML='<button type="button" class="apb'+(cur==='home'?' on':'')+'" data-tab="autopilot" data-ap="home"'+(cur==='home'?' aria-current="page"':'')+'>'+ico('autopilot',16)+'<span>Autopilot</span></button>'
  +VXAP.MODES.map(function(m){var locked=!apNeedsOk(m)||!allowed(m.tab),tag=locked?'<i class="apt lock">'+(m.needs==='accountant'?'AI Účetní+':'PRO+')+'</i>':'<i class="apt '+m.state+'">'+VXAP.STATE[m.state]+'</i>';
   return '<button type="button" class="apb'+(cur===m.id?' on':'')+'" data-tab="'+m.tab+'" data-ap="'+m.id+'"'+(cur===m.id?' aria-current="page"':'')+'><span>'+esc(m.name)+'</span>'+tag+'</button>'}).join('');
 var m=VXAP.MODES.filter(function(x){return x.id===cur})[0];
 if(!m){sub.innerHTML=cur==='home'?'<span class="mut">Přehled Autopilota: stav, limit a bezpečnost. Autopilot zatím nespouští žádné placené volání.</span>':'';sub.style.display=cur==='home'?'':'none';return}
 sub.style.display='';
 sub.innerHTML='<span class="mut"><b>'+esc(m.name)+'</b> ('+esc(VXAP.STATE[m.state])+'): '+esc(m.text)+'</span>'
  +m.tabs.map(function(t){return '<button type="button" class="btn btn-ghost btn-sm" data-tab="'+t+'">'+esc(tabLab(t))+'</button>'}).join('')}
/* ---- přehled Autopilota ---- */
function apCard(m){var ok=apNeedsOk(m)&&allowed(m.tab);
 return '<div class="apcard"><h4>'+esc(m.name)+' <small class="mut">· '+esc(VXAP.STATE[m.state])+'</small></h4><p class="mut">'+esc(m.text)+'</p>'
  +(ok?'<button type="button" class="btn btn-ghost btn-sm" data-tab="'+m.tab+'">Otevřít</button>':'<small class="mut">Součástí vyššího tarifu.</small>')+'</div>'}
function apErr(res,what){
 var e=res.error,c=String(e.code||''),msg=String(e.message||'');
 if(c==='42501'||/forbidden|read_only/.test(msg))return 'K nastavení nemáte oprávnění, nebo je účet jen pro čtení.';
 if(/function|schema cache|does not exist|PGRST20/i.test(msg+c))return what+' vyžaduje aktualizaci databáze, která zatím nebyla provedena.';
 return what+' se nepodařilo načíst ('+msg+').'}
async function apLoad(){
 var root=A('apRoot');if(!root)return;
 if(DEMO){root.innerHTML='<div class="draft">V ukázce se stav limitu nezobrazuje.</div>'+apModesHtml();return}
 var c=getSb(),cid=APP.cid,st=await c.rpc('autopilot_status',{cid:cid}),pr=await c.rpc('profile_get',{cid:cid});
 if(!A('apRoot'))return;
 var h='';
 if(st.error){root.innerHTML='<div class="draft">'+esc(apErr(st,'Stav limitu'))+'</div>'+apModesHtml();return}
 var s=st.data,profileOk=pr.error?null:(pr.data.is_root?!!pr.data.active:!!pr.data.shared_from_root),
  lim=s.monthly_limit_nusd,spent=Number(s.spent_nusd||0),pct=lim?Math.min(100,Math.round(spent/Number(lim)*100)):0,rd=VXAP.readiness(s,profileOk),all=rd.every(function(r){return r.ok});
 h+='<section class="card2"><h3>Placené AI běhy</h3><p>'+(all?'<b class="apok">Podmínky jsou splněné.</b> I tak Autopilot zatím žádné placené volání nespouští; funkce se zapínají postupně.':'<b class="apno">Placené AI běhy jsou vypnuté.</b> Autopilot zatím nespouští žádné placené volání.')+'</p><ul class="apchk">'
  +rd.map(function(r){return '<li><b class="'+(r.ok?'apok':'apno')+'" aria-hidden="true">'+(r.ok?'✓':'✗')+'</b>'+esc(r.text)+'<span class="sr">'+(r.ok?' splněno':' nesplněno')+'</span></li>'}).join('')+'</ul></section>';
 h+='<section class="card2"><h3>Měsíční limit nákladů na AI</h3>'
  +'<p>'+(lim==null?'Limit zatím <b>není nastaven</b>, placené běhy se proto odmítnou.':'Limit: <b>'+esc(VXAP.fmtUsd(lim))+'</b> měsíčně pro celou firmu včetně poboček.')+'</p>'
  +(lim!=null?'<div class="apmeter" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="'+pct+'" aria-label="Využití měsíčního limitu"><i style="width:'+pct+'%"></i></div><p class="mut">Tento měsíc: '+esc(VXAP.fmtUsd(spent))+' ('+pct+' %), zbývá '+esc(VXAP.fmtUsd(s.remaining_nusd))+'. Rezervace za běžící operace se počítají v plné výši.</p>':'')
  +(s.is_root?'<form id="apBudgetForm" class="fg"><div class="f"><label for="apLimit">Limit na měsíc (USD, nejvýše 50)</label><input id="apLimit" inputmode="decimal" autocomplete="off" value="'+(lim==null?'':esc(String(Number(lim)/1e9).replace('.',',')))+'" placeholder="0,25"><small class="fe" id="apLimitErr" style="display:block;color:#ff9aa8"></small></div>'
   +'<div class="f"><button class="btn btn-main btn-sm" type="submit">Uložit limit</button> <button class="btn btn-ghost btn-sm" type="button" data-ap-act="preset">Doporučených 0,25 USD</button> '+(lim!=null?'<button class="btn btn-ghost btn-sm" type="button" data-ap-act="clear">Zrušit limit</button>':'')+'</div></form><p class="mut fine">Uložení limitu nespustí žádné volání AI. Hlídá ho databáze: před každým během se rezervuje nejvyšší možná cena a při překročení se běh odmítne.</p>':'<p class="mut">Limit nastavuje a vidí hlavní firma.</p>')
  +'<div id="apBudgetMsg" class="st" role="status" aria-live="polite"></div></section>';
 h+='<section class="card2"><h3>Ceník modelu</h3>'+((s.models||[]).length?'<ul class="rows">'+s.models.map(function(m){return '<li><b>'+esc(m.model)+'</b><span>vstup '+esc(VXAP.perMillionUsd(m.input_nusd_per_token).toFixed(2).replace('.',','))+' USD, výstup '+esc(VXAP.perMillionUsd(m.output_nusd_per_token).toFixed(2).replace('.',','))+' USD za 1 M tokenů · ověřeno '+esc(String(m.verified_on))+'</span></li>'}).join('')+'</ul><p class="mut fine">Zdroj: oficiální ceník Google (Standard). Model bez ověřené ceny se odmítne.</p>':'<p class="mut">Žádný model nemá ověřenou cenu, placené běhy nejsou možné.</p>')+'</section>';
 root.innerHTML=h+apModesHtml()}
function apModesHtml(){return '<h3 style="margin:18px 0 8px">Režimy</h3><div class="apgrid">'+VXAP.MODES.map(apCard).join('')+'</div><section class="card2" style="margin-top:14px"><h3>Jak je to zabezpečené</h3><ul class="ticks"><li>AI jen navrhuje. Nic nepublikuje, neodesílá ani neplatí bez vašeho potvrzení.</li><li>Potvrzovat smí jen vlastník nebo správce, vždy pod svou přihlášenou identitou.</li><li>Náklady hlídá databáze (rezervace před během, vypořádání po něm), ne prohlížeč.</li><li>Data firem jsou oddělená; AI dostane jen údaje potřebné pro danou úlohu.</li></ul></section>'}
async function apSaveLimit(nusd){
 var msg=A('apBudgetMsg');if(msg){msg.className='st';msg.textContent='Ukládám…'}
 var r=await getSb().rpc('autopilot_set_budget',{cid:APP.cid,p_limit_nusd:nusd==null?null:Number(nusd)});
 if(r.error){var m=VXPCORE.mapRpcError(r.error),t=m.kind==='validation'?'Limit musí být od 0 do 50 USD.':(String(r.error.message||'')==='only_root'?'Limit nastavuje hlavní firma.':m.message);if(msg){msg.className='st err';msg.textContent=t}return}
 toast(nusd==null?'Limit zrušen.':'Limit uložen.','ok');await apLoad()}
VIEWS.autopilot=function(){apStyle();if(APP.role==='employee')return '<div class="card2 soonc"><h2>Autopilot</h2><p>Autopilot spravuje vlastník nebo správce.</p></div>';
 return '<div class="ap" id="apRoot"><p class="mut">Načítám stav Autopilota…</p></div>'};
AFTER.autopilot=function(){if(APP.role!=='employee')apLoad()};
if(!window.__apBound){window.__apBound=true;
 document.addEventListener('submit',function(e){if(e.target.id!=='apBudgetForm')return;e.preventDefault();
  var v=A('apLimit').value,n=VXAP.usdToNusd(v),er=A('apLimitErr');
  if(n==null){er.textContent='Zadejte částku od 0 do 50 USD, např. 0,25.';return}
  er.textContent='';apSaveLimit(n)});
 document.addEventListener('click',function(e){var b=e.target.closest&&e.target.closest('[data-ap-act]');if(!b)return;var a=b.getAttribute('data-ap-act');
  if(a==='preset'){A('apLimit').value='0,25';A('apLimitErr').textContent=''}
  if(a==='clear'){apSaveLimit(null)}})}
