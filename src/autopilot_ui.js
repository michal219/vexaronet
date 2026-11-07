/* ===== AI Autopilot: AI Marketing (část 1) ===== */
IC.autopilot='M12 3l2.2 4.6 5 .7-3.6 3.5.9 5-4.5-2.4-4.5 2.4.9-5L4.8 8.3l5-.7zM5 20h14';
var AP={mod:'marketing',sub:'prehled',d:null,loading:false,err:'',timer:null,st:null,busy:false};
var APMODS=[['marketing','AI Marketing'],['obchodnik','AI Obchodník'],['ceo','AI CEO'],['ucetni','AI Účetnictví'],['weby','AI Weby a e-shopy'],['automatizace','AI Automatizace']];
var APMODI={obchodnik:['pripady','Obchodní případy, nabídky a historie klienta už fungují v CRM. AI Obchodník, který bude sám připravovat nabídky a navazovat na marketing, se připravuje.'],
 ceo:['ceo','AI CEO funguje: doporučení, zdraví firmy a chat nad vašimi daty. Propojení s Autopilotem (společné úlohy a schvalování) se připravuje.'],
 ucetni:['ucetni','AI Účetní funguje: odpovědi z vaší evidence a vytěžení dokladů ke kontrole. Propojení s Autopilotem se připravuje.'],
 weby:['weby','Jednoduchý web s AI návrhem textů a e-shop fungují. Propojení s Autopilotem (např. úpravy textů podle kampaní) se připravuje.'],
 automatizace:['automatizace','Automatizace hlídají faktury, termíny a sklad a navrhují úkoly. Běh na serveru pro tato pravidla a propojení s Autopilotem se připravuje.']};
var APSUB=[['prehled','Přehled'],['schvalovani','Ke schválení'],['kalendar','Kalendář obsahu'],['kampane','Kampaně'],['videa','Videa'],['analytika','Analytika'],['historie','Historie'],['nastaveni','Nastavení']];
var APK={chat:'Chat',strategy:'Strategie',content_plan:'Návrhy obsahu',campaign:'Kampaň',video:'Video',diagnose:'Diagnóza',analysis:'Analýza firmy',morning:'Ranní kontrola',evening:'Večerní report'};
var APTS={queued:'Čeká ve frontě',running:'Pracuje se',done:'Hotovo',failed:'Chyba',canceled:'Zrušeno'};
var APCS={draft:'Koncept',pending_approval:'Čeká na schválení',approved:'Schváleno',rejected:'Zamítnuto',published:'Publikováno',running:'Běží',paused:'Pozastaveno',finished:'Ukončeno',rendering:'Vzniká',ready:'Hotovo',failed:'Chyba'};
var APCH={instagram:'Instagram',facebook:'Facebook',tiktok:'TikTok',youtube:'YouTube',email:'E-mail',web:'Web'};
var APMET=[['views','Zhlédnutí'],['reach','Dosah'],['clicks','Prokliky'],['conversions','Konverze'],['leads','Poptávky'],['customers','Zákazníci'],['spend','Útrata (Kč)'],['revenue','Tržby (Kč)']];
var APACT={task_requested:'Zadána úloha',task_done:'Úloha hotová',task_error:'Chyba úlohy',task_canceled:'Úloha zrušena',paused:'AI pozastavena',resumed:'AI obnovena',decision_approved:'Schváleno',decision_rejected:'Zamítnuto',marked_published:'Označeno jako publikované'};
(function(){var s=document.createElement('style');s.textContent=
 '.apmods{display:flex;gap:6px;flex-wrap:wrap;margin:0 0 14px}.apmods button,.apsub button{border:1px solid var(--line);background:var(--glass);color:inherit;border-radius:99px;padding:8px 14px;cursor:pointer;font:inherit;font-size:.9rem}'
+'.apmods button[aria-pressed=true]{background:linear-gradient(135deg,#7a5cff,#6b4bf2);color:#fff;border-color:transparent}.apsub{display:flex;gap:6px;overflow-x:auto;margin:0 0 14px;padding-bottom:4px}.apsub button{white-space:nowrap;font-size:.85rem;padding:7px 12px}.apsub button[aria-pressed=true]{border-color:#7a5cff;box-shadow:inset 0 0 0 1px #7a5cff}'
+'.apst{display:flex;gap:14px;align-items:center;flex-wrap:wrap}.apdot{width:12px;height:12px;border-radius:50%;background:#4be3a5;box-shadow:0 0 0 4px rgba(75,227,165,.18)}.apdot.p{background:#ffb648;box-shadow:0 0 0 4px rgba(255,182,72,.18)}.apdot.x{background:#ff6b7d;box-shadow:0 0 0 4px rgba(255,107,125,.18)}.apdot.w{animation:apb 1.2s infinite}@keyframes apb{50%{opacity:.35}}'
+'.apst b{font-size:1.05rem;display:block}.apst small{display:block}.apst .grow{flex:1;min-width:200px}.apbtn{border:1px solid var(--line);background:transparent;color:inherit;border-radius:12px;padding:9px 14px;cursor:pointer;font:inherit}.apbtn.stop{border-color:#ff6b7d;color:#ff8a98}.apbtn:disabled,.vxapp .pri:disabled{opacity:.5;cursor:not-allowed}'
+'.apchat{max-height:340px;overflow:auto;display:grid;gap:8px;margin:0 0 10px}.apm{padding:10px 12px;border-radius:14px;max-width:85%;white-space:pre-wrap;font-size:.93rem;line-height:1.45}.apm.u{justify-self:end;background:linear-gradient(135deg,#7a5cff,#6b4bf2);color:#fff;border-bottom-right-radius:4px}.apm.a{background:rgba(110,140,255,.09);border:1px solid var(--line);border-bottom-left-radius:4px}'
+'.apchips{display:flex;gap:6px;flex-wrap:wrap;margin:6px 0 0}.apchips button{border:1px dashed var(--line);background:none;color:inherit;border-radius:99px;padding:5px 10px;font-size:.8rem;cursor:pointer}'
+'.apform{display:flex;gap:8px}.apform input,.apform textarea{flex:1;min-width:0;padding:10px 12px;border-radius:12px;border:1px solid var(--line);background:var(--glass);color:inherit}'
+'.apq{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:10px}.apq form{border:1px solid var(--line);border-radius:14px;padding:12px;display:grid;gap:8px;align-content:start}.apq h4{margin:0}.apq input,.apq select,.apq textarea,.apf input,.apf select,.apf textarea{width:100%;box-sizing:border-box;padding:9px 11px;border-radius:10px;border:1px solid var(--line);background:var(--glass);color:inherit}'
+'.aptag{display:inline-block;font-size:.72rem;padding:2px 8px;border-radius:99px;border:1px solid var(--line);margin-left:6px;vertical-align:middle}.aptag.sep{border-color:#ff8a98;color:#ff8a98}.aptag.ok{border-color:#4be3a5;color:#4be3a5}.aptag.wait{border-color:#ffb648;color:#ffb648}'
+'.apcard{border:1px solid var(--line);border-radius:14px;padding:12px 14px;margin:0 0 10px;background:rgba(110,140,255,.04)}.apcard p{margin:6px 0;white-space:pre-wrap}.apcard .dact{margin-top:8px}.apday{margin:14px 0 6px;font-weight:700}'
+'.apsc{width:100%;border-collapse:collapse;font-size:.85rem}.apsc td,.apsc th{border-bottom:1px solid var(--line);padding:6px;text-align:left;vertical-align:top}.apf{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}.apf label{display:block;font-size:.85rem;color:var(--mut);margin:0 0 4px}.apf .full{grid-column:1/-1}'
+'.apbar{height:8px;border-radius:99px;background:rgba(110,140,255,.15);overflow:hidden}.apbar i{display:block;height:100%;background:linear-gradient(90deg,#7a5cff,#4be3a5)}@media(max-width:640px){.apm{max-width:95%}.apform{flex-direction:column}}';
document.head.appendChild(s)})();

function apMg(){return APP.role==='owner'||APP.role==='admin'}
function apSt(t,c){var e=A('apSt');if(e){e.className='st '+(c||'');e.textContent=t}}
function apErr(e){var m=String(e&&e.message||e||'');return /Forbidden/.test(m)?'K této akci nemáte oprávnění (jen vlastník nebo správce).':m.slice(0,300)}
function apChLabel(c){return APCH[c]||c}
function apDemoData(){var n=Date.now(),iso=function(d,h){var x=new Date(n+d*864e5);x.setHours(h||10,0,0,0);return x.toISOString()};
 return {profile:{company_id:'demo',business_name:APP.co||'Autoservis Novotný',industry:'Autoservis',offer:'Servis, pneuservis, diagnostika',location:'Brno a okolí',audience:'Řidiči a firmy s vozovým parkem v Brně',competitors:'',website:'',budget_monthly:3000,goals:'Více poptávek na servis',tone:'přátelský',channels:['instagram','facebook'],completed:true},
  settings:{autopilot_on:true,paused:false,morning_hour:7,evening_hour:19,monthly_ai_limit:150},
  tasks:[{id:'dt1',kind:'content_plan',title:'Návrhy obsahu na týden',status:'done',source:'chat',created_at:iso(0,8),result:{summary:'Připraveno 3 návrhů příspěvků ke schválení.'}},{id:'dt2',kind:'strategy',title:'Strategie na 30 dní',status:'done',source:'user',created_at:iso(-1,9)},{id:'dt3',kind:'morning',title:'Ranní kontrola marketingu',status:'done',source:'schedule',created_at:iso(0,7)}],
  content:[{id:'dc1',channel:'instagram',format:'reel',title:'Přezutí bez čekání',caption:'Zima klepe na dveře. Objednejte přezutí online a vyhněte se frontám.',hashtags:['#pneuservis','#brno'],cta:'Rezervace v profilu',planned_at:iso(1,18),status:'pending_approval'},{id:'dc2',channel:'facebook',format:'post',title:'Tip na zimu',caption:'3 věci, které zkontrolovat před zimou: pneumatiky, baterie, kapalina do ostřikovačů.',hashtags:['#autoservis'],cta:'Objednejte kontrolu',planned_at:iso(3,10),status:'approved'}],
  approvals:[{id:'da1',entity:'content',entity_id:'dc1',level:'rule',summary:'Příspěvek instagram: Přezutí bez čekání',status:'pending',created_at:iso(0,8)},{id:'da2',entity:'campaign',entity_id:'dk1',level:'separate',summary:'Spuštění placené kampaně „Zimní servis“ (meta), rozpočet 3000 Kč',status:'pending',created_at:iso(0,8)}],
  campaigns:[{id:'dk1',platform:'meta',name:'Zimní servis',objective:'Získat poptávky na zimní servis',budget_total:3000,budget_daily:214.28,audience:{age_min:25,age_max:60,locations:['Brno + 20 km'],interests:['automobily']},ads:[{headline:'Zimní servis bez čekání',primary_text:'Objednejte se online.',cta:'Rezervovat'}],kpis:{items:[{metric:'poptávky',target:'odhad 10–20'}]},status:'pending_approval',created_at:iso(0,8)}],
  media:[{id:'dm1',title:'Přezutí za 30 sekund',status:'pending_approval',render_note:'Automatický render videa zatím není připojený, proto vzniká kompletní podklad k ruční výrobě.',package:{hook:'Čekáte v zimě hodinu na přezutí?',duration_s:30,scenes:[{from_s:0,to_s:3,visual:'Fronta aut před servisem',voiceover:'Čekáte v zimě hodinu na přezutí?',caption:'Hodina ve frontě?'},{from_s:3,to_s:12,visual:'Telefon s rezervací',voiceover:'U nás si termín vyberete online.',caption:'Termín online'}],music_brief:'svižný podkres s licencí',cta:'Rezervace v profilu',voiceover_full:'Čekáte v zimě hodinu na přezutí? U nás si termín vyberete online.',subtitles_srt:''},created_at:iso(0,8)}],
  strategies:[{id:'ds1',period:'month',title:'Zimní sezóna: více poptávek na servis',summary:'Zaměřit se na přezutí a zimní prohlídky, obsah 3× týdně, malá kampaň na Facebooku.',data:{channels:[{channel:'facebook',budget_czk:2000,why:'místní cílení'},{channel:'instagram',budget_czk:1000,why:'krátká videa'}],goals:[{goal:'Více rezervací',metric:'rezervace online',target:'odhad +15'}]},created_at:iso(-1,9)}],
  reports:[{id:'dr1',kind:'morning',title:'Ranní kontrola',body:'Marketingové metriky zatím nejsou zadané ani propojené, výsledky kampaní proto nelze vyhodnotit.\n→ Zadejte v Analytice dosah a prokliky z minulého týdne.',created_at:iso(0,7)}],
  metrics:[],chat:[{id:'dh1',role:'user',body:'Připrav obsah na celý příští týden.',created_at:iso(0,8)},{id:'dh2',role:'assistant',body:'Zadal jsem přípravu návrhů příspěvků na Instagram a Facebook na příští týden. Najdete je v Kalendáři obsahu ke schválení.',created_at:iso(0,8)}],
  activity:[{id:'dy1',actor:'ai',action:'ai_content_plan',detail:'Návrhy obsahu na týden',model:'gemini-3.5-flash-lite',input_tokens:4100,output_tokens:1900,cost_usd:0.006,created_at:iso(0,8)},{id:'dy2',actor:'user',action:'task_requested',detail:'Návrhy obsahu na týden',created_at:iso(0,8)}],integrations:[]}}

async function apLoad(silent){
 if(DEMO){if(!AP.d)AP.d=apDemoData();AP.st={ai_configured:true,render_configured:false,publishing:{},budget:{used:12,limit:150}};apDraw();return}
 if(AP.loading)return;AP.loading=true;if(!silent&&!AP.d)apDraw();
 try{var c=getSb(),q=function(t,o,lim){return c.from(t).select('*').eq('company_id',APP.cid).order(o||'created_at',{ascending:false}).limit(lim||100)};
  var R=await Promise.all([c.from('mkt_profiles').select('*').eq('company_id',APP.cid).limit(1),c.from('mkt_settings').select('*').eq('company_id',APP.cid).limit(1),q('mkt_tasks','created_at',40),q('mkt_content','planned_at',120),q('mkt_approvals','created_at',100),q('mkt_campaigns'),q('mkt_media'),q('mkt_strategies','created_at',5),q('mkt_reports','created_at',10),q('mkt_metrics','metric_date',500),q('mkt_chat','created_at',30),q('mkt_activity','created_at',60),c.from('mkt_integrations').select('*').eq('company_id',APP.cid)]);
  var bad=R.filter(function(r){return r.error})[0];if(bad){AP.err=bad.error.message;AP.d=null}
  else{AP.err='';AP.d={profile:(R[0].data||[])[0]||null,settings:(R[1].data||[])[0]||null,tasks:R[2].data,content:R[3].data,approvals:R[4].data,campaigns:R[5].data,media:R[6].data,strategies:R[7].data,reports:R[8].data,metrics:R[9].data,chat:(R[10].data||[]).slice().reverse(),activity:R[11].data,integrations:R[12].data}}
 }catch(e){AP.err=apErr(e)}
 AP.loading=false;var pol=AP.poll;AP.poll=false;if(APP.tab==='autopilot')apDraw(pol);apSchedule()}

async function apFn(action){
 if(DEMO)return {demo:true};
 var s=(await getSb().auth.getSession()).data.session;if(!s)throw new Error('Přihlaste se znovu.');
 var r=await fetch(SB_URL+'/functions/v1/mkt-autopilot',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+s.access_token,apikey:SB_KEY},body:JSON.stringify({action:action,company_id:APP.cid})});
 var j={};try{j=await r.json()}catch(e){}if(!r.ok)throw new Error(j.error||('Server odpověděl chybou '+r.status));return j}
async function apStatus(){if(DEMO||AP.st)return;try{AP.st=await apFn('status')}catch(e){AP.st={error:apErr(e)}}if(APP.tab==='autopilot')apDraw()}
function apActive(){var t=AP.d&&AP.d.tasks||[];return t.filter(function(x){return x.status==='queued'||x.status==='running'}).length}
function apSchedule(){clearTimeout(AP.timer);if(DEMO||APP.tab!=='autopilot'||!apActive())return;AP.timer=setTimeout(function(){if(APP.tab==='autopilot'){AP.poll=true;apLoad(true)}},4000)}
async function apKick(){if(DEMO)return;try{await apFn('run')}catch(e){toast(apErr(e),'err')}apLoad(true)}

VIEWS.autopilot=function(){
 var h='<div class="apmods" role="group" aria-label="Moduly AI Autopilota">'+APMODS.map(function(m){return '<button type="button" data-ap="mod:'+m[0]+'" aria-pressed="'+(AP.mod===m[0])+'">'+m[1]+'</button>'}).join('')+'</div><div id="apBody"></div>';
 return h};
AFTER.autopilot=function(){apDraw();if(AP.mod==='marketing'){apLoad();apStatus()}};

function apDraw(pol){var b=A('apBody');if(!b)return;var ci=A('apChatIn'),keep=ci?ci.value:'',foc=ci&&document.activeElement===ci;if(pol&&document.activeElement&&b.contains(document.activeElement)&&document.activeElement.tagName!=='BUTTON'&&!foc&&APP.tab==='autopilot'&&AP.d&&b.querySelector('form'))return apSchedule();apDraw0();var cj=A('apChatIn');if(cj&&keep){cj.value=keep}if(cj&&foc)cj.focus();var lg=A('apChatLog');if(lg)lg.scrollTop=lg.scrollHeight}
function apDraw0(){var b=A('apBody');
 [].forEach.call(document.querySelectorAll('#vxapp [data-ap^="mod:"]'),function(x){x.setAttribute('aria-pressed',x.dataset.ap==='mod:'+AP.mod)});
 if(AP.mod!=='marketing'){var i=APMODI[AP.mod],nm=(APMODS.filter(function(m){return m[0]===AP.mod})[0]||[])[1];
  b.innerHTML='<section class="card2"><h3>'+esc(nm)+' <span class="aptag wait">propojení připravujeme</span></h3><p>'+esc(i[1])+'</p><div class="dact"><button type="button" class="pri" data-tab="'+i[0]+'">Otevřít modul</button></div></section>';return}
 if(!hasCeo()){b.innerHTML='<section class="card2 soonc"><h3>AI Marketing je součástí tarifů PRO a BUSINESS</h3><p class="mut">Po přechodu na vyšší tarif se AI marketingový zaměstnanec odemkne.</p></section>';return}
 if(AP.err){b.innerHTML='<div class="draft">AI Marketing vyžaduje dokončit nastavení databáze (SQL schema_mkt_autopilot). Detail: '+esc(AP.err)+'</div>';return}
 if(!AP.d){b.innerHTML='<p class="mut">Načítám AI Marketing…</p>';return}
 if(!AP.d.profile||!AP.d.profile.completed){b.innerHTML=apOnb();return}
 b.innerHTML=apStatusCard()+'<nav class="apsub" aria-label="Části AI Marketingu">'+APSUB.map(function(s){var n=s[0]==='schvalovani'?apPend().length:0;return '<button type="button" data-ap="sub:'+s[0]+'" aria-pressed="'+(AP.sub===s[0])+'">'+s[1]+(n?' ('+n+')':'')+'</button>'}).join('')+'</nav><div id="apSt" class="st" role="status"></div>'+(APV[AP.sub]||APV.prehled)()}

function apPend(){return (AP.d.approvals||[]).filter(function(a){return a.status==='pending'})}
function apMonthCost(){var m0=new Date();m0.setDate(1);m0.setHours(0,0,0,0);var a=(AP.d.activity||[]).filter(function(x){return x.actor==='ai'&&new Date(x.created_at)>=m0});return a.reduce(function(s,x){return s+Number(x.cost_usd||0)},0)}
function apStatusCard(){var S=AP.d.settings||{},paused=!!S.paused,act=apActive(),st=AP.st||{},noai=st.ai_configured===false,b=st.budget||null;
 var dot=paused?'p':(noai?'x':(act?'w':'')),txt=paused?'Pozastaveno':(noai?'AI služba není na serveru nastavená':(act?'Pracuje na '+act+' '+plural(act,'úloze','úlohách','úlohách'):'Připraveno, čeká na úkoly'));
 var used=b?b.used:null,lim=b?b.limit:null,pct=lim?Math.min(100,Math.round(used/lim*100)):0;
 return '<section class="card2"><div class="apst"><span class="apdot '+dot+'" aria-hidden="true"></span><div class="grow"><b>AI marketingový zaměstnanec: '+esc(txt)+'</b><small class="mut">'+(S.autopilot_on?'Autopilot zapnutý: ranní kontrola v '+esc(S.morning_hour)+':00, večerní report v '+esc(S.evening_hour)+':00.':'Autopilot je vypnutý, AI pracuje jen na vaše zadání. Zapnete ho v Nastavení.')+'</small></div>'
  +(apMg()?'<button type="button" class="apbtn'+(paused?'':' stop')+'" data-ap="pause:'+(paused?'0':'1')+'">'+(paused?'▶ Obnovit AI':'■ Okamžitě pozastavit AI')+'</button>':'')+'</div>'
  +(b?'<div style="margin-top:12px"><small class="mut">AI úlohy tento měsíc: '+esc(used)+' z '+esc(lim)+' · náklady AI odhadem '+apUsd(apMonthCost())+'</small><div class="apbar" aria-hidden="true"><i style="width:'+pct+'%"></i></div></div>':(st.error?'<p class="mut fine">Stav serveru se nepodařilo načíst: '+esc(st.error)+'</p>':''))+'</section>'}
function apUsd(v){return Number(v||0).toLocaleString('cs-CZ',{maximumFractionDigits:3})+' USD'}

/* ---- úvodní nastavení ---- */
function apOnb(){var p=AP.d.profile||{},w=(APP.d.sites&&APP.d.sites.rows[0])||null,wd=w&&w.data||{},sv=(wd.services||[]).map(function(x){return x.name}).filter(Boolean).join(', ');
 var pre={business_name:p.business_name||APP.co||'',industry:p.industry||APP.ind||'',offer:p.offer||sv||'',website:p.website||(w&&w.slug&&typeof webUrl==='function'?webUrl(w.slug):'')||'',location:p.location||'',audience:p.audience||'',competitors:p.competitors||'',budget_monthly:p.budget_monthly==null?'':p.budget_monthly,goals:p.goals||'',tone:p.tone||'přátelský a lidský',channels:p.channels||['instagram','facebook']};
 var nC=(APP.d.customers&&APP.d.customers.rows.length)||0;
 function f(k,l,t,m,ph,full){return '<div class="'+(full?'full':'')+'"><label for="apo_'+k+'">'+l+'</label>'+(t==='ta'?'<textarea id="apo_'+k+'" rows="3" maxlength="'+m+'" placeholder="'+esc(ph||'')+'">'+esc(pre[k])+'</textarea>':'<input id="apo_'+k+'" '+(t==='num'?'type="number" min="0" step="100"':'')+' maxlength="'+m+'" placeholder="'+esc(ph||'')+'" value="'+esc(pre[k])+'">')+'</div>'}
 return '<section class="card2"><h3>Seznamte AI se svou firmou</h3><p class="mut">Než AI marketing začne pracovat, potřebuje znát vaši firmu. Údaje se uloží jen k vaší firmě a AI z nich vychází při každé úloze. Co nevíte, nechte prázdné; AI si nic nedomýšlí.</p>'
 +'<p class="fine mut">Předvyplnili jsme, co už Vexaronet o firmě ví: název'+(APP.ind?', obor':'')+(sv?', služby z vašeho webu':'')+'. V CRM máte '+nC+' '+plural(nC,'zákazníka','zákazníky','zákazníků')+'; AI pracuje jen se souhrnnými čísly (počty, ne jména ani kontakty).</p>'
 +(apMg()?'':'<div class="draft">Úvodní nastavení může dokončit vlastník nebo správce firmy.</div>')
 +'<form id="apOnb" class="apf">'+f('business_name','Název firmy','',120)+f('industry','Obor podnikání','',120,'např. autoservis')+f('offer','Produkty a služby','ta',2000,'Co nabízíte, hlavní služby, případně ceny',1)
 +f('location','Lokalita působení','',200,'např. Brno a okolí')+f('website','Webové stránky','',300,'https://')+f('audience','Cílová skupina','ta',1000,'Kdo jsou vaši zákazníci',1)+f('competitors','Hlavní konkurenti','ta',1000,'Názvy nebo weby konkurentů (veřejné informace)',1)
 +f('budget_monthly','Měsíční marketingový rozpočet (Kč)','num',12,'0 = jen neplacený obsah')+f('tone','Preferovaný styl komunikace','',200)+f('goals','Hlavní obchodní cíle','ta',1000,'např. 20 nových poptávek měsíčně',1)
 +'<div class="full"><label>Používané sociální sítě a kanály</label><div class="apchips" style="margin:0">'+Object.keys(APCH).map(function(k){return '<label style="display:inline-flex;gap:6px;align-items:center;margin:0 10px 0 0;color:inherit"><input type="checkbox" name="apo_ch" value="'+k+'"'+(pre.channels.indexOf(k)>=0?' checked':'')+' style="width:auto">'+APCH[k]+'</label>'}).join('')+'</div></div>'
 +'<div class="full dact"><button type="submit" class="pri"'+(apMg()?'':' disabled')+'>Uložit a připravit první strategii</button></div></form></section>'}

/* ---- jednotlivé části ---- */
var APV={
 prehled:function(){var D=AP.d,t=(D.tasks||[]).slice(0,10),pend=apPend().length,up=(D.content||[]).filter(function(c){return c.planned_at&&new Date(c.planned_at)>new Date()&&c.status!=='rejected'}).length,lastS=(D.strategies||[])[0],lastR=(D.reports||[])[0];
  var h='<div class="ivkpi"><div><small>Ke schválení</small><b>'+pend+'</b><em>návrhy čekají na vás</em></div><div><small>Naplánovaný obsah</small><b>'+up+'</b><em>příspěvků dopředu</em></div><div><small>Rozpracované kampaně</small><b>'+(D.campaigns||[]).filter(function(c){return c.status!=='rejected'&&c.status!=='finished'}).length+'</b><em>návrhy a schválené</em></div><div><small>Aktuální úlohy</small><b>'+apActive()+'</b><em>ve frontě nebo v práci</em></div></div>';
  h+='<div class="two"><section class="card2"><h3>Zadejte úkol AI</h3><div class="apchat" id="apChatLog">'+((D.chat||[]).length?(D.chat||[]).slice(-12).map(function(m){return '<div class="apm '+(m.role==='user'?'u':'a')+'">'+esc(m.body)+'</div>'}).join(''):'<p class="mut">Napište, co potřebujete. AI úkol rozdělí na konkrétní úlohy a uvidíte jejich průběh.</p>')+'</div>'
   +'<form id="apChatF" class="apform"><input id="apChatIn" maxlength="1500" placeholder="Např. Připrav obsah na celý příští týden" aria-label="Zpráva pro AI"'+(apMg()?'':' disabled')+'><button type="submit" class="pri"'+(apMg()?'':' disabled')+'>Odeslat</button></form>'
   +'<div class="apchips">'+['Vytvoř marketingovou strategii na příštích 30 dní.','Připrav pět reklamních videí na naši službu.','Zjisti, proč nám klesá počet poptávek.','Navrhni kampaň s rozpočtem 3 000 Kč.','Připrav obsah na celý příští týden.'].map(function(x){return '<button type="button" data-ap="ex" data-tx="'+esc(x)+'">'+esc(x)+'</button>'}).join('')+'</div></section>'
   +'<section class="card2"><div class="bar2"><h3>Aktuální úlohy</h3>'+(apMg()&&apActive()?'<button type="button" class="apbtn" data-ap="kick">Zpracovat hned</button>':'')+'</div>'+(t.length?'<ul class="rows">'+t.map(apTaskLi).join('')+'</ul>':'<p class="mut">Zatím žádné úlohy.</p>')+'</section></div>';
  h+=apQuick();
  h+='<div class="two"><section class="card2"><h3>Aktuální strategie</h3>'+(lastS?apStrategy(lastS):'<p class="mut">Strategie zatím není. Zadejte ji výše.</p>')+'</section><section class="card2"><h3>Poslední report</h3>'+(lastR?'<div class="apcard"><b>'+esc(lastR.title)+'</b> <small class="mut">'+fD(lastR.created_at,1)+'</small><p>'+esc(lastR.body||'')+'</p></div>':'<p class="mut">Reporty vznikají při ranní a večerní rutině autopilota nebo na vaše zadání.</p>')+'</section></div>';
  return h},
 schvalovani:function(){var P=apPend();
  var h='<section class="card2 note"><b>Schvalování.</b> Návrhy obsahu a videí patří mezi akce podle předem schválených pravidel. Spuštění placené kampaně a navýšení rozpočtu vyžaduje <b>samostatné schválení</b> vlastníkem nebo správcem. Nic se nepublikuje ani neplatí automaticky.</section>';
  if(!P.length)return h+'<p class="mut">Nic nečeká na schválení.</p>';
  return h+P.map(function(a){return '<div class="apcard"><b>'+esc(a.summary)+'</b><span class="aptag '+(a.level==='separate'?'sep':'')+'">'+(a.level==='separate'?'samostatné schválení':'podle pravidel')+'</span><small class="mut" style="display:block">'+fD(a.created_at,1)+'</small>'+apEntity(a)
   +(apMg()?'<div class="dact"><button type="button" class="pri sm" data-ap="dec:'+esc(a.id)+':approved">Schválit</button><button type="button" class="apbtn" data-ap="dec:'+esc(a.id)+':rejected">Zamítnout</button></div>':'')+'</div>'}).join('')},
 kalendar:function(){var C=(AP.d.content||[]).filter(function(c){return c.status!=='rejected'}).sort(function(a,b){return String(a.planned_at).localeCompare(String(b.planned_at))}),g={},o=[];
  C.forEach(function(c){var k=c.planned_at?new Date(c.planned_at).toLocaleDateString('cs-CZ',{weekday:'long',day:'numeric',month:'numeric'}):'Bez termínu';if(!g[k]){g[k]=[];o.push(k)}g[k].push(c)});
  var h='<section class="card2 note">Publikace na sociální sítě zatím není propojená (viz Nastavení). Schválený příspěvek zkopírujte, zveřejněte sami a označte jako publikovaný. Výsledky pak zadejte v Analytice.</section>';
  if(!C.length)return h+'<p class="mut">Zatím žádný naplánovaný obsah. Zadejte „Připrav obsah na příští týden“.</p>';
  return h+o.map(function(k){return '<div class="apday">'+esc(k.charAt(0).toUpperCase()+k.slice(1))+'</div>'+g[k].map(apContent).join('')}).join('')},
 kampane:function(){var C=AP.d.campaigns||[];
  var h='<section class="card2 note">Reklamní účet Meta Ads ani jiné platformy zatím nejsou propojené. Schválená kampaň proto nezačne utrácet sama: nastavíte ji ve správci reklam podle návrhu a výsledky zadáte v Analytice.</section>';
  return h+(C.length?C.map(apCampaign).join(''):'<p class="mut">Zatím žádné kampaně. Zadejte například „Navrhni kampaň s rozpočtem 3 000 Kč“.</p>')},
 videa:function(){var M=AP.d.media||[],st=AP.st||{};
  var h='<section class="card2 note"><b>Stav výroby videí:</b> AI připraví scénář, hook, storyboard, voiceover, titulky (SRT) a zadání hudby. '+(st.render_configured?'':'Automatické generování záběrů, AI hlasu a střih zatím <b>nejsou připojené</b> (vyžadují placené API služeb pro video a hlas). Do té doby video vyrobíte z podkladu ručně.')+'</section>';
  return h+(M.length?M.map(apMedia).join(''):'<p class="mut">Zatím žádná videa. Zadejte například „Připrav pět reklamních videí na naši službu“.</p>')},
 analytika:function(){return apAnalytics()},
 historie:function(){var A_=AP.d.activity||[];
  return '<section class="card2"><h3>Historie vykonané práce</h3>'+(A_.length?'<ul class="rows">'+A_.map(function(x){var ai=x.actor==='ai';return '<li><div><b>'+esc(ai?'AI: '+(APK[String(x.action).replace(/^ai_/,'')]||x.action):(APACT[x.action]||x.action))+'</b><small>'+esc(x.detail||'')+(ai&&x.model?' · '+esc(x.model)+' · '+esc((x.input_tokens||0)+(x.output_tokens||0))+' tokenů · '+apUsd(x.cost_usd):'')+'</small></div><span>'+fD(x.created_at,1)+'</span></li>'}).join('')+'</ul>':'<p class="mut">Zatím žádná činnost.</p>')+'</section>'},
 nastaveni:function(){var S=AP.d.settings||{},st=AP.st||{},I={};(AP.d.integrations||[]).forEach(function(i){I[i.provider]=i});
  var INT=[['meta','Facebook a Instagram (Meta)','Publikace příspěvků a spouštění reklam vyžaduje aplikaci Meta schválenou pro oprávnění ke správě stránek a reklam (App Review) a propojení vašeho firemního účtu.'],['tiktok','TikTok','Publikace vyžaduje schválený přístup k TikTok Content Posting API.'],['youtube','YouTube','Nahrávání videí vyžaduje projekt Google Cloud s YouTube Data API a ověřenou aplikaci OAuth.'],['google_ads','Google Ads','Vyžaduje developer token Google Ads API a propojení reklamního účtu.']];
  var h='<section class="card2"><h3>Nastavení automatizace</h3><form id="apSetF" class="apf"><div class="full"><label style="display:flex;gap:8px;align-items:center;color:inherit"><input type="checkbox" id="aps_on" style="width:auto"'+(S.autopilot_on?' checked':'')+'> Autopilot: každý den ranní kontrola a večerní report bez vaší přítomnosti</label></div>'
   +'<div><label for="aps_m">Ranní kontrola (hodina)</label><input id="aps_m" type="number" min="0" max="23" value="'+esc(S.morning_hour==null?7:S.morning_hour)+'"></div><div><label for="aps_e">Večerní report (hodina)</label><input id="aps_e" type="number" min="0" max="23" value="'+esc(S.evening_hour==null?19:S.evening_hour)+'"></div>'
   +'<div><label for="aps_l">Měsíční limit AI úloh</label><input id="aps_l" type="number" min="0" max="3000" value="'+esc(S.monthly_ai_limit==null?150:S.monthly_ai_limit)+'"><small class="mut">Skutečný limit je nejvýš strop vašeho tarifu.</small></div>'
   +'<div class="full dact"><button type="submit" class="pri"'+(apMg()?'':' disabled')+'>Uložit nastavení</button><button type="button" class="apbtn" data-ap="onb">Upravit profil firmy</button></div></form></section>';
  h+='<section class="card2"><h3>Režim schvalování</h3><table class="apsc"><tr><th>Automaticky povolené</th><td>analýzy, návrhy strategií, textové koncepty, interní reporty, příprava úloh</td></tr><tr><th>Podle pravidel</th><td>návrhy příspěvků a scénářů videí (schválíte, publikujete; automatické publikování po propojení sítí)</td></tr><tr><th>Samostatné schválení</th><td>spuštění placené reklamy, navýšení rozpočtu, zprávy zákazníkům, zásadní změny veřejných kampaní</td></tr></table><p class="fine mut">Marketingové zprávy zákazníkům AI zatím neposílá vůbec. Až to bude možné, každá rozesílka bude vyžadovat samostatné schválení a souhlas příjemců.</p></section>';
  h+='<section class="card2"><h3>Propojení a služby</h3><table class="apsc"><tr><th>Služba</th><th>Stav</th><th>Co je potřeba</th></tr>'
   +'<tr><td>AI model (texty, strategie, scénáře)</td><td>'+(st.ai_configured?'<span class="aptag ok">funguje</span>':(st.ai_configured===false?'<span class="aptag sep">chybí klíč</span>':'–'))+'</td><td>Klíč GEMINI_API_KEY v Supabase (Edge Functions → Secrets).</td></tr>'
   +'<tr><td>Generování záběrů, AI hlas, střih videa</td><td><span class="aptag wait">nepřipojeno</span></td><td>Placené API služby pro video a hlas s licencí pro komerční použití.</td></tr>'
   +INT.map(function(x){var i=I[x[0]];return '<tr><td>'+esc(x[1])+'</td><td><span class="aptag '+(i&&i.status==='connected'?'ok':'wait')+'">'+(i&&i.status==='connected'?'propojeno':'nepřipojeno')+'</span></td><td>'+esc(x[2])+'</td></tr>'}).join('')+'</table></section>';
  return h}
};
function apTaskLi(t){var bad=t.status==='failed';return '<li><div><b>'+esc(APK[t.kind]||t.kind)+': '+esc(t.title)+'</b><small>'+esc(APTS[t.status]||t.status)+(t.source==='schedule'?' · autopilot':'')+' · '+fD(t.created_at,1)+(bad&&t.error?' · '+esc(t.error):'')+(t.status==='done'&&t.result&&t.result.summary?' · '+esc(t.result.summary):'')+'</small></div>'+(t.status==='queued'&&apMg()?'<button type="button" class="lnk" data-ap="cancel:'+esc(t.id)+'">Zrušit</button>':'<span class="aptag '+(t.status==='done'?'ok':bad?'sep':'wait')+'">'+esc(APTS[t.status]||t.status)+'</span>')+'</li>'}
function apQuick(){if(!apMg())return '';var p=AP.d.profile||{};
 return '<section class="card2"><h3>Rychlé zadání</h3><div class="apq">'
 +'<form data-apq="strategy"><h4>Strategie</h4><select name="days"><option value="30">na 30 dní</option><option value="7">na 7 dní</option></select><button class="pri sm">Vytvořit</button></form>'
 +'<form data-apq="content_plan"><h4>Obsah</h4><select name="days"><option value="7">na příští týden</option><option value="14">na 14 dní</option></select><input name="topic" maxlength="300" placeholder="Téma (nepovinné)"><button class="pri sm">Připravit</button></form>'
 +'<form data-apq="campaign"><h4>Kampaň Meta</h4><input name="budget_czk" type="number" min="100" step="100" placeholder="Rozpočet v Kč" value="'+esc(p.budget_monthly||'')+'"><input name="goal" maxlength="300" placeholder="Cíl, např. poptávky na servis"><button class="pri sm">Navrhnout</button></form>'
 +'<form data-apq="video"><h4>Videa 9:16</h4><input name="topic" maxlength="300" placeholder="O čem videa budou"><select name="count"><option>1</option><option>3</option><option>5</option></select><button class="pri sm">Připravit</button></form>'
 +'<form data-apq="diagnose"><h4>Diagnóza</h4><input name="question" maxlength="400" placeholder="Např. Proč klesá počet poptávek?"><button class="pri sm">Zjistit</button></form>'
 +'</div></section>'}
function apStrategy(s){var d=s.data||{};return '<div class="apcard"><b>'+esc(s.title||'Strategie')+'</b> <small class="mut">'+(s.starts_on?fD(s.starts_on)+' – '+fD(s.ends_on):fD(s.created_at))+'</small><p>'+esc(s.summary||'')+'</p>'
 +((d.goals||[]).length?'<table class="apsc"><tr><th>Cíl</th><th>Metrika</th><th>Cíl. hodnota</th></tr>'+d.goals.map(function(g){return '<tr><td>'+esc(g.goal)+'</td><td>'+esc(g.metric)+'</td><td>'+esc(g.target)+'</td></tr>'}).join('')+'</table>':'')
 +((d.channels||[]).length?'<table class="apsc" style="margin-top:8px"><tr><th>Kanál</th><th>Proč</th><th>Rozpočet</th></tr>'+d.channels.map(function(c){return '<tr><td>'+esc(c.channel)+'</td><td>'+esc(c.why)+'</td><td>'+fM(c.budget_czk)+'</td></tr>'}).join('')+'</table>':'')
 +(d.budget_note?'<p class="fine mut">'+esc(d.budget_note)+'</p>':'')+((d.weekly_plan||[]).length?'<details><summary>Plán po týdnech</summary>'+d.weekly_plan.map(function(w){return '<p><b>'+esc(w.week)+'. týden: '+esc(w.focus)+'</b>\n'+esc((w.actions||[]).map(function(a){return '• '+a}).join('\n'))+'</p>'}).join('')+'</details>':'')
 +((d.data_gaps||[]).length?'<p class="fine mut">Chybějící data: '+esc(d.data_gaps.join('; '))+'</p>':'')+'</div>'}
function apContent(c){var ed=apMg()&&c.status!=='published';
 return '<div class="apcard"><b>'+esc(apChLabel(c.channel))+' · '+esc(c.format)+(c.title?' · '+esc(c.title):'')+'</b><span class="aptag '+(c.status==='approved'||c.status==='published'?'ok':'wait')+'">'+esc(APCS[c.status]||c.status)+'</span><small class="mut" style="display:block">'+(c.planned_at?fD(c.planned_at,1):'bez termínu')+(c.series?' · série '+esc(c.series):'')+'</small>'
 +'<p>'+esc(c.caption||'')+'</p>'+((c.hashtags||[]).length?'<small class="mut">'+esc(c.hashtags.join(' '))+'</small>':'')+(c.cta?'<p><b>Výzva:</b> '+esc(c.cta)+'</p>':'')+(c.published_url?'<p><a href="'+esc(c.published_url)+'" target="_blank" rel="noopener">Zveřejněný příspěvek</a></p>':'')
 +'<div class="dact"><button type="button" class="apbtn" data-ap="copy:'+esc(c.id)+'">Kopírovat text</button>'+(ed?'<button type="button" class="apbtn" data-ap="edit:'+esc(c.id)+'">Upravit</button>':'')+(apMg()&&c.status==='approved'?'<button type="button" class="pri sm" data-ap="pub:'+esc(c.id)+'">Označit jako publikované</button>':'')+'</div></div>'}
function apCampaign(c){var a=c.audience||{},k=c.kpis||{};
 return '<div class="apcard"><b>'+esc(c.name)+'</b><span class="aptag '+(c.status==='approved'?'ok':c.status==='rejected'?'sep':'wait')+'">'+esc(APCS[c.status]||c.status)+'</span><small class="mut" style="display:block">'+esc(String(c.platform).toUpperCase())+' · rozpočet '+fM(c.budget_total)+(c.budget_daily?' (≈ '+fM(c.budget_daily)+'/den)':'')+'</small><p>'+esc(c.objective||'')+'</p>'
 +'<details><summary>Cílení, reklamy a KPI</summary><p><b>Cílení:</b> věk '+esc(a.age_min||'?')+'–'+esc(a.age_max||'?')+'; lokality: '+esc((a.locations||[]).join(', ')||'–')+'; zájmy: '+esc((a.interests||[]).join(', ')||'–')+(a.notes?'\n'+esc(a.notes):'')+'</p>'
 +(c.ads||[]).map(function(x,i){return '<p><b>Varianta '+(i+1)+': '+esc(x.headline)+'</b>\n'+esc(x.primary_text)+(x.description?'\n'+esc(x.description):'')+(x.cta?'\nTlačítko: '+esc(x.cta):'')+(x.creative_idea?'\nVizuál: '+esc(x.creative_idea):'')+'</p>'}).join('')
 +((k.items||[]).length?'<p><b>KPI:</b> '+esc(k.items.map(function(i){return i.metric+': '+i.target}).join('; '))+'</p>':'')+(k.measurement?'<p><b>Měření:</b> '+esc(k.measurement)+'</p>':'')+'</details>'
 +(c.status==='approved'?'<p class="fine mut">Schváleno. Reklamní účet zatím není propojený, kampaň nastavíte ve správci reklam podle návrhu.</p>':'')+'</div>'}
function apMedia(m){var p=m.package||{};
 return '<div class="apcard"><b>'+esc(m.title)+'</b><span class="aptag '+(m.status==='approved'?'ok':m.status==='rejected'?'sep':'wait')+'">'+esc(APCS[m.status]||m.status)+'</span><small class="mut" style="display:block">9:16 · '+esc(p.duration_s||'?')+' s · '+esc(m.render_note||'')+'</small>'
 +'<p><b>Hook:</b> '+esc(p.hook||'')+'</p><details><summary>Storyboard, voiceover a titulky</summary><table class="apsc"><tr><th>Čas</th><th>Obraz</th><th>Voiceover</th><th>Titulek</th></tr>'+(p.scenes||[]).map(function(s){return '<tr><td>'+esc(s.from_s)+'–'+esc(s.to_s)+' s</td><td>'+esc(s.visual)+'</td><td>'+esc(s.voiceover)+'</td><td>'+esc(s.caption)+'</td></tr>'}).join('')+'</table>'
 +'<p><b>Hudba:</b> '+esc(p.music_brief||'')+'</p><p><b>Výzva:</b> '+esc(p.cta||'')+'</p>'+((p.generation_prompts||[]).length?'<p><b>Prompty pro generátor záběrů:</b>\n'+esc(p.generation_prompts.join('\n'))+'</p>':'')+'</details>'
 +'<div class="dact"><button type="button" class="apbtn" data-ap="vo:'+esc(m.id)+'">Kopírovat voiceover</button>'+(p.subtitles_srt?'<button type="button" class="apbtn" data-ap="srt:'+esc(m.id)+'">Stáhnout titulky .srt</button>':'')+'</div></div>'}
function apEntity(a){var D=AP.d,f=function(arr){return (arr||[]).filter(function(x){return x.id===a.entity_id})[0]};
 if(a.entity==='content'){var c=f(D.content);return c?'<p>'+esc(c.caption||'')+'</p>'+(c.planned_at?'<small class="mut">Plán: '+fD(c.planned_at,1)+'</small>':''):''}
 if(a.entity==='campaign'){var k=f(D.campaigns);return k?apCampaign(k):''}
 if(a.entity==='media'){var m=f(D.media);return m?apMedia(m):''}return ''}

/* ---- analytika: jen skutečná data ---- */
function apAnalytics(){var M=AP.d.metrics||[],d30=new Date(Date.now()-30*864e5),cur=M.filter(function(m){return new Date(m.metric_date)>=d30}),sum={};cur.forEach(function(m){sum[m.metric]=(sum[m.metric]||0)+Number(m.value||0)});
 var cust=(APP.d.customers&&APP.d.customers.rows||[]).filter(function(c){return new Date(c.created_at)>=d30}).length,deals=(APP.d.deals&&APP.d.deals.rows||[]).filter(function(x){return x.stage==='won'&&new Date(x.updated_at||x.created_at)>=d30}),dv=deals.reduce(function(s,x){return s+Number(x.value||0)},0);
 var nd='<em>Nejsou data</em>',v=function(k,cz){return sum[k]!=null?'<b>'+(cz?fM(sum[k]):Number(sum[k]).toLocaleString('cs-CZ'))+'</b>':'<b>–</b>'+nd};
 var newC=sum.customers!=null?sum.customers:null,cpa=sum.spend!=null&&newC?Math.round(sum.spend/newC):null,rev=sum.revenue!=null?sum.revenue:null,roi=sum.spend&&rev!=null?Math.round((rev-sum.spend)/sum.spend*100):null;
 var h='<section class="card2 note">Analytika ukazuje jen skutečná data: výsledky, které zadáte z reklamních účtů a sociálních sítí, a čísla z CRM Vexaronetu. Dokud nejsou sítě propojené, nic se neodhaduje ani nedopočítává.</section>';
 h+='<div class="ivkpi">'+APMET.map(function(m){return '<div><small>'+esc(m[1])+' (30 dní)</small>'+v(m[0],m[0]==='spend'||m[0]==='revenue')+'</div>'}).join('')
  +'<div><small>Náklady na zákazníka</small>'+(cpa!=null?'<b>'+fM(cpa)+'</b><em>útrata ÷ zákazníci z marketingu</em>':'<b>–</b><em>chybí útrata nebo zákazníci</em>')+'</div><div><small>Návratnost (ROI)</small>'+(roi!=null?'<b>'+roi+' %</b><em>(tržby − útrata) ÷ útrata</em>':'<b>–</b><em>chybí útrata nebo tržby</em>')+'</div></div>';
 h+='<section class="card2"><h3>Z CRM Vexaronetu (30 dní)</h3><div class="ivkpi"><div><small>Noví zákazníci v CRM</small><b>'+cust+'</b><em>všechny zdroje, ne jen marketing</em></div><div><small>Vyhrané obchodní případy</small><b>'+deals.length+'</b><em>'+fM(dv)+'</em></div></div></section>';
 h+='<section class="card2"><h3>Zadat výsledky</h3><p class="mut fine">Čísla opište z přehledů platforem (např. Meta Business Suite, TikTok Studio, YouTube Studio).</p>'+(apMg()?'<form id="apMetF" class="apf"><div><label for="apm_d">Datum</label><input id="apm_d" type="date" value="'+new Date().toISOString().slice(0,10)+'" required></div><div><label for="apm_c">Kanál</label><select id="apm_c">'+Object.keys(APCH).concat(['meta_ads','google_ads','jine']).map(function(k){return '<option value="'+k+'">'+esc(APCH[k]||k.replace('_',' '))+'</option>'}).join('')+'</select></div><div><label for="apm_m">Ukazatel</label><select id="apm_m">'+APMET.map(function(m){return '<option value="'+m[0]+'">'+m[1]+'</option>'}).join('')+'</select></div><div><label for="apm_v">Hodnota</label><input id="apm_v" type="number" min="0" step="any" required></div><div class="full dact"><button class="pri sm">Uložit výsledek</button></div></form>':'')
  +(M.length?'<ul class="rows" style="margin-top:12px">'+M.slice(0,30).map(function(m){return '<li><div><b>'+esc((APMET.filter(function(x){return x[0]===m.metric})[0]||[])[1]||m.metric)+': '+Number(m.value).toLocaleString('cs-CZ')+'</b><small>'+esc(apChLabel(m.channel))+' · '+fD(m.metric_date)+' · '+esc(m.source==='manual'?'zadáno ručně':m.source)+'</small></div>'+(apMg()&&m.source==='manual'?'<button type="button" class="lnk" data-ap="mdel:'+esc(m.id)+'">Smazat</button>':'')+'</li>'}).join('')+'</ul>':'')+'</section>';
 return h}

/* ---- akce ---- */
async function apRequest(kind,title,payload){if(DEMO){toast('V ukázce se úlohy nespouštějí. V ostrém účtu by AI začala pracovat.','ok');return}
 var r=await getSb().rpc('mkt_request',{p_company:APP.cid,p_kind:kind,p_title:title,p_payload:payload||{}});if(r.error)throw new Error(r.error.message);
 toast('Úloha zadána, AI na ní začíná pracovat.','ok');await apLoad(true);apKick()}
document.addEventListener('click',async function(e){var x=e.target.closest('#vxapp [data-ap]');if(!x)return;var a=x.dataset.ap,p=a.split(':');
 try{
 if(p[0]==='mod'){AP.mod=p[1];apDraw();if(AP.mod==='marketing'){apLoad();apStatus()}return}
 if(p[0]==='sub'){AP.sub=p[1];apDraw();return}
 if(a==='onb'){AP.d.profile=Object.assign({},AP.d.profile,{completed:false});apDraw();return}
 if(a==='ex'){var i=A('apChatIn');if(i){i.value=x.dataset.tx;i.focus()}return}
 if(a==='kick'){apSt('Zpracovávám úlohy…','ok');await apKick();apSt('');return}
 if(p[0]==='copy'||p[0]==='vo'){var c=p[0]==='copy'?(AP.d.content||[]).filter(function(z){return z.id===p[1]})[0]:null,m=p[0]==='vo'?(AP.d.media||[]).filter(function(z){return z.id===p[1]})[0]:null;
  var tx=c?[c.caption,(c.hashtags||[]).join(' '),c.cta].filter(Boolean).join('\n\n'):(m&&m.package&&m.package.voiceover_full)||'';try{await navigator.clipboard.writeText(tx);toast('Zkopírováno.','ok')}catch(er){toast('Kopírování se nepodařilo, označte text ručně.','err')}return}
 if(p[0]==='srt'){var md=(AP.d.media||[]).filter(function(z){return z.id===p[1]})[0];if(!md)return;var bl=new Blob([md.package.subtitles_srt||''],{type:'application/x-subrip'}),u=URL.createObjectURL(bl),l=document.createElement('a');l.href=u;l.download=(md.title||'titulky').replace(/[^\p{L}\p{N}-]+/gu,'-').slice(0,60)+'.srt';document.body.appendChild(l);l.click();l.remove();setTimeout(function(){URL.revokeObjectURL(u)},1000);return}
 if(DEMO){toast('V ukázce se nic neukládá.','ok');return}
 if(AP.busy)return;AP.busy=true;
 if(p[0]==='pause'){var r=await getSb().rpc('mkt_set_paused',{p_company:APP.cid,p_paused:p[1]==='1'});if(r.error)throw new Error(r.error.message);toast(p[1]==='1'?'AI je pozastavená. Rozpracovaná úloha doběhne, další se nespustí.':'AI znovu pracuje.','ok');await apLoad(true);if(p[1]==='0')apKick()}
 else if(p[0]==='dec'){var r2=await getSb().rpc('mkt_decide',{p_approval:p[1],p_decision:p[2]});if(r2.error)throw new Error(r2.error.message);toast(p[2]==='approved'?'Schváleno.':'Zamítnuto.','ok');await apLoad(true)}
 else if(p[0]==='cancel'){var r3=await getSb().rpc('mkt_cancel',{p_task:p[1]});if(r3.error)throw new Error(r3.error.message);await apLoad(true)}
 else if(p[0]==='pub'){var url=prompt('Odkaz na zveřejněný příspěvek (nepovinné, začíná https://):','');if(url===null){AP.busy=false;return}var r4=await getSb().rpc('mkt_mark_published',{p_content:p[1],p_url:url.trim()||null});if(r4.error)throw new Error(r4.error.message);toast('Označeno jako publikované.','ok');await apLoad(true)}
 else if(p[0]==='edit'){var ce=(AP.d.content||[]).filter(function(z){return z.id===p[1]})[0];if(ce){var nt=prompt('Upravte text příspěvku:',ce.caption||'');if(nt!==null&&nt.trim()){var r5=await getSb().from('mkt_content').update({caption:nt.trim().slice(0,5000)}).eq('id',ce.id);if(r5.error)throw new Error(r5.error.message);toast('Text upraven.','ok');await apLoad(true)}}}
 else if(p[0]==='mdel'){var r6=await getSb().from('mkt_metrics').delete().eq('id',p[1]);if(r6.error)throw new Error(r6.error.message);await apLoad(true)}
 }catch(er){toast(apErr(er),'err')}AP.busy=false});
document.addEventListener('submit',async function(e){var f=e.target;if(!f.closest||!f.closest('#vxapp'))return;
 var id=f.id,qk=f.dataset&&f.dataset.apq;if(id!=='apOnb'&&id!=='apChatF'&&id!=='apSetF'&&id!=='apMetF'&&!qk)return;e.preventDefault();
 if(DEMO){toast('V ukázce se nic neukládá ani nespouští. V ostrém účtu by AI začala pracovat.','ok');return}
 if(AP.busy)return;AP.busy=true;var c=getSb(),v=function(k){var el=A(k);return el?el.value.trim():''};
 try{
 if(id==='apOnb'){var ch=[].map.call(f.querySelectorAll('input[name=apo_ch]:checked'),function(x){return x.value}),bud=v('apo_budget_monthly');
  var row={company_id:APP.cid,business_name:v('apo_business_name'),industry:v('apo_industry'),offer:v('apo_offer'),location:v('apo_location'),website:v('apo_website'),audience:v('apo_audience'),competitors:v('apo_competitors'),budget_monthly:bud===''?null:Math.max(0,Number(bud)||0),goals:v('apo_goals'),tone:v('apo_tone'),channels:ch,completed:true,updated_at:new Date().toISOString()};
  if(!row.business_name||!row.offer){toast('Vyplňte aspoň název firmy a produkty nebo služby.','err');AP.busy=false;return}
  var r=await c.from('mkt_profiles').upsert(row,{onConflict:'company_id'});if(r.error)throw new Error(r.error.message);
  if(!AP.d.settings){var r0=await c.from('mkt_settings').upsert({company_id:APP.cid},{onConflict:'company_id'});if(r0.error)throw new Error(r0.error.message)}
  toast('Profil uložen.','ok');AP.busy=false;
  if(!(AP.d.strategies||[]).length)await apRequest('strategy','Strategie na 30 dní',{days:30});else await apLoad(true)}
 else if(id==='apChatF'){var t=v('apChatIn');if(t.length<2){AP.busy=false;return}var r1=await c.rpc('mkt_chat_send',{p_company:APP.cid,p_text:t});if(r1.error)throw new Error(r1.error.message);A('apChatIn').value='';await apLoad(true);apKick()}
 else if(id==='apSetF'){var r2=await c.from('mkt_settings').upsert({company_id:APP.cid,autopilot_on:A('aps_on').checked,morning_hour:Math.min(23,Math.max(0,parseInt(v('aps_m'),10)||7)),evening_hour:Math.min(23,Math.max(0,parseInt(v('aps_e'),10)||19)),monthly_ai_limit:Math.min(3000,Math.max(0,parseInt(v('aps_l'),10)||0)),updated_at:new Date().toISOString()},{onConflict:'company_id'});if(r2.error)throw new Error(r2.error.message);toast('Nastavení uloženo.','ok');await apLoad(true)}
 else if(id==='apMetF'){var val=Number(v('apm_v'));if(!(val>=0)){toast('Zadejte číslo.','err');AP.busy=false;return}var r3=await c.from('mkt_metrics').insert({company_id:APP.cid,metric_date:v('apm_d'),channel:v('apm_c'),metric:v('apm_m'),value:val});if(r3.error)throw new Error(r3.error.message);toast('Výsledek uložen.','ok');await apLoad(true)}
 else if(qk){var fd=new FormData(f),pl={},o={};fd.forEach(function(val,k){if(String(val).trim()!=='')o[k]=String(val).trim()});
  if(o.days)pl.days=parseInt(o.days,10);if(o.count)pl.count=parseInt(o.count,10);if(o.budget_czk)pl.budget_czk=Number(o.budget_czk);['topic','goal','question'].forEach(function(k){if(o[k])pl[k]=o[k].slice(0,400)});
  if(qk==='campaign'&&!(pl.budget_czk>0)){toast('Zadejte rozpočet kampaně.','err');AP.busy=false;return}
  if(qk==='diagnose'&&!pl.question){toast('Napište, co chcete zjistit.','err');AP.busy=false;return}
  var tt={strategy:'Strategie na '+(pl.days||30)+' dní',content_plan:'Obsah na '+(pl.days||7)+' dní'+(pl.topic?': '+pl.topic:''),campaign:'Kampaň Meta za '+pl.budget_czk+' Kč',video:(pl.count||1)+'× video 9:16'+(pl.topic?': '+pl.topic:''),diagnose:pl.question||'Diagnóza'}[qk];
  AP.busy=false;await apRequest(qk,String(tt).slice(0,200),pl);return}
 }catch(er){toast(apErr(er),'err')}AP.busy=false});
