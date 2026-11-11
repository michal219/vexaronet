/* ===== AI tým: jedno prostředí pro šest AI pracovníků (Marketing, Obchodník, CEO, Účetní, Weby a e-shopy, Automatizace) =====
   Data: ai_team_state / acc_state / bank_reconciliation (DB podle firmy a role). AI běží jen přes /api/ai-worker; limity, tarif a vypínač vynucuje server.
   AI nic neprovádí sama: návrhy změn (akce) provede až schválení člověkem (ai_action_decide s otiskem obsahu). Viz docs/AI_TYM.md. */
var AIT={tab:'prehled',st:null,acc:null,bank:null,err:null,cid:null,busy:{},chat:{},chatLoaded:{},vat:null,csv:null};
var AIT_MODS=[['marketing','AI Marketing'],['obchodnik','AI Obchodník'],['ceo','AI CEO'],['ucetnictvi','AI Účetní'],['weby_eshopy','AI Weby a e-shopy'],['automatizace','AI Automatizace']];
var AIT_ST={queued:'čeká',running:'běží',awaiting_approval:'čeká na schválení',done:'hotovo',failed:'nepovedlo se',cancelled:'zrušeno'};
var AIT_CAD={daily:'denně',weekly:'týdně',monthly:'měsíčně'};
var AIT_ACT={task:'Úkol',marketing_post:'Koncept příspěvku',customer_note:'Poznámka k zákazníkovi',finance_entry:'Finanční záznam',quote_draft:'Koncept nabídky',site_text:'Text webu',product_description:'Popis produktu',goal:'Měřitelný cíl',schedule:'Pravidelný plán'};
var AIT_MET={poptavky:'poptávek',zakaznici:'nových zákazníků',rezervace:'rezervací',objednavky:'objednávek',trzby:'Kč tržeb'};
var AIT_REG={neurceno:'Neurčeno',danova_evidence:'Daňová evidence',ucetnictvi:'Účetnictví (podvojné)',pausalni_dan:'Paušální daň'};
function aitCss(){if(document.getElementById('aitCss'))return;var s=document.createElement('style');s.id='aitCss';s.textContent=
 '.ait .ait-tabs{display:flex;gap:8px;overflow-x:auto;padding:4px 0 10px;margin-bottom:6px}.ait .ait-tabs button{flex:0 0 auto;min-height:42px;padding:8px 14px;border-radius:12px;border:1px solid var(--line);background:transparent;color:inherit;cursor:pointer;font:inherit}'
 +'.ait .ait-tabs button[aria-current=page]{background:linear-gradient(120deg,#5b6cff,#8b5cf6);color:#fff;border-color:transparent;font-weight:700}'
 +'.ait .ait-g{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(0,1fr);gap:14px;align-items:start}@media(max-width:900px){.ait .ait-g{grid-template-columns:minmax(0,1fr)}}'
 +'.ait .card2{margin-bottom:14px}.ait h3{margin:0 0 8px;font-size:1.05rem}.ait .ait-row{display:flex;gap:8px;flex-wrap:wrap;align-items:end}.ait .ait-row .f{flex:1;min-width:160px}'
 +'.ait ul.ait-l{list-style:none;margin:0;padding:0}.ait ul.ait-l>li{padding:10px 0;border-bottom:1px solid var(--line)}.ait ul.ait-l>li:last-child{border-bottom:0}'
 +'.ait .ait-tag{display:inline-block;padding:2px 8px;border-radius:999px;font-size:.75rem;border:1px solid var(--line);margin-right:6px}.ait .ait-tag.w{border-color:#e0a030;color:#e0a030}.ait .ait-tag.g{border-color:#3fbf7f;color:#3fbf7f}.ait .ait-tag.r{border-color:#ff6e82;color:#ff6e82}'
 +'.ait .ait-act{border:1px solid var(--line);border-radius:12px;padding:10px 12px;margin:8px 0;background:rgba(139,108,255,.06)}.ait .ait-act pre{white-space:pre-wrap;font:inherit;margin:6px 0;max-height:220px;overflow:auto}'
 +'.ait .ait-btn{min-height:40px;padding:8px 14px;border-radius:10px;border:1px solid var(--line);background:transparent;color:inherit;cursor:pointer;font:inherit}.ait .ait-btn.p{background:#4b3bd0;border-color:#4b3bd0;color:#fff;font-weight:700}.ait .ait-btn.ok{background:#1f7a4d;border-color:#1f7a4d;color:#fff}.ait .ait-btn[disabled]{opacity:.5;cursor:not-allowed}'
 +'.ait .ait-chat{max-height:300px;overflow:auto;display:flex;flex-direction:column;gap:8px;margin-bottom:8px}.ait .ait-chat div{padding:8px 12px;border-radius:12px;max-width:90%;white-space:pre-wrap}.ait .ait-chat .u{align-self:flex-end;background:rgba(91,108,255,.25)}.ait .ait-chat .a{align-self:flex-start;border:1px solid var(--line)}'
 +'.ait .ait-bar{height:10px;border-radius:999px;background:rgba(130,150,255,.2);overflow:hidden}.ait .ait-bar i{display:block;height:100%;background:linear-gradient(90deg,#3bb6ff,#c06cff)}'
 +'.ait details{margin-top:6px}.ait summary{cursor:pointer}.ait table{width:100%;border-collapse:collapse}.ait td,.ait th{padding:6px 8px;border-bottom:1px solid var(--line);text-align:left;font-size:.9rem}.ait .mut{opacity:.75}.ait textarea,.ait input,.ait select{max-width:100%}';
 document.head.appendChild(s)}
function aitKey(){return 'a'+Date.now().toString(36)+Math.random().toString(36).slice(2,12)}
function aitErr(e){var m=String(e&&e.message||e||'');
 if(/stale/.test(m))return 'Obsah se mezitím změnil. Načetli jsme aktuální stav, zkontrolujte ho a akci zopakujte.';
 if(/no_longer_valid/.test(m))return 'Návrh už nejde provést (záznam, kterého se týká, se mezitím změnil nebo zmizel).';
 if(/duplicate/.test(m))return 'Doklad vypadá jako duplicita dříve nahraného. Schválit ho jde jen s výslovným potvrzením.';
 if(/issued_invoice_not_found/.test(m))return 'K dokladu jsme nenašli vystavenou fakturu se stejným číslem a částkou.';
 if(/incomplete/.test(m))return 'Doplňte částku a datum vystavení.';if(/budget_over_plan_cap/.test(m))return 'Limit je vyšší, než dovoluje váš tarif.';
 if(/not_schedulable/.test(m))return 'Tuto úlohu nelze spouštět pravidelně.';if(/too_many/.test(m))return 'Dosáhli jste limitu počtu. Zkuste to později.';
 if(/permission|forbidden|42501|read_only/.test(m))return 'K této akci nemáte oprávnění, nebo je účet jen pro čtení.';
 if(/function|schema cache|does not exist/i.test(m))return 'Tato část ještě není v databázi nasazená.';return 'Akce se nepovedla: '+m}
async function aitRpc(fn,args,okMsg){try{var r=await getSb().rpc(fn,Object.assign({cid:APP.cid},args||{}));if(r.error){toast(aitErr(r.error),'err');return null}if(okMsg)toast(okMsg,'ok');return r.data==null?{}:r.data}catch(e){toast(aitErr(e),'err');return null}}
async function aitLoad(){
 if(DEMO||APP.role==='employee'||!APP.cid)return;var cid=APP.cid,sb=getSb();
 try{var r=await sb.rpc('ai_team_state',{cid:cid});if(APP.cid!==cid)return;
  if(r.error){AIT.st=null;AIT.err=aitErr(r.error)}else{AIT.st=r.data;AIT.err=null}
  if(AIT.tab==='ucetnictvi'&&!r.error){var a=await sb.rpc('acc_state',{cid:cid});AIT.acc=a.error?null:a.data;
   try{var b=await sb.rpc('bank_reconciliation',{cid:cid,op:'list',doc:{status:'all'}});AIT.bank=b.error?{err:b.error.message}:b.data}catch(e){AIT.bank={err:String(e)}}}
  AIT.cid=cid}catch(e){AIT.err='Stav AI týmu se nepodařilo načíst. Zkontrolujte připojení.'}
 aitPaint()}
/* Překreslení zachová rozepsané hodnoty formulářů (zadání úkolu, zpráva, období…), aby je neúspěšný požadavek nesmazal. */
function aitPaint(){var b=A('aitBody');if(!b||!A('ait'))return;var ae=document.activeElement,foc=ae&&ae.id&&b.contains(ae)?ae.id:null,keep={};
 [].forEach.call(b.querySelectorAll('input[id],textarea[id],select[id]'),function(el){if(el.type==='file')return;keep[el.id]=el.type==='checkbox'?{c:el.checked}:{v:el.value}});
 b.innerHTML=aitBody();
 Object.keys(keep).forEach(function(id){var el=A(id);if(!el||!b.contains(el))return;if('c' in keep[id])el.checked=keep[id].c;else if(el.tagName!=='SELECT'||[].some.call(el.options,function(o){return o.value===keep[id].v}))el.value=keep[id].v});
 if(foc&&A(foc))A(foc).focus();var c=A('aitChat');if(c)c.scrollTop=c.scrollHeight}
function aitKinds(m){return ((AIT.st&&AIT.st.kinds)||[]).filter(function(k){return k.module===m})}
function aitModName(m){return (AIT_MODS.filter(function(x){return x[0]===m})[0]||[m,m])[1]}
function aitUsd(n){return n==null?'–':VXAP.fmtUsd(n)}
/* ---------- akce ke schválení ---------- */
function aitActBody(a){var p=a.payload||{},t=a.type;
 if(t==='task')return '<b>'+esc(p.title)+'</b>'+(p.due_in_days!=null?' <small class="mut">termín za '+esc(p.due_in_days)+' dní</small>':'')+(p.description?'<pre>'+esc(p.description)+'</pre>':'');
 if(t==='marketing_post')return '<b>'+esc(p.title)+'</b> <small class="mut">'+esc(p.channel)+' · za '+esc(p.planned_in_days)+' dní</small><pre>'+esc(p.body)+'</pre>';
 if(t==='customer_note')return '<pre>'+esc(p.body)+'</pre>';
 if(t==='finance_entry')return '<b>'+esc(p.title)+'</b> · '+esc(p.kind==='income'?'příjem':'výdaj')+' '+esc(fM(p.amount))+' · '+esc(fD(p.entry_date));
 if(t==='quote_draft')return '<b>'+esc(p.title)+'</b><table><tr><th>Položka</th><th>Množství</th><th>Cena</th></tr>'+(p.items||[]).map(function(i){return '<tr><td>'+esc(i.name)+'</td><td>'+esc(i.qty)+'</td><td>'+esc(fM(i.price))+'</td></tr>'}).join('')+'</table><b>Celkem '+esc(fM(p.total))+'</b>'+(p.note?'<pre>'+esc(p.note)+'</pre>':'');
 if(t==='site_text')return '<small class="mut">'+esc({'hero.title':'Titulek webu','hero.subtitle':'Podtitulek webu','about.title':'Nadpis sekce O nás','about.text':'Text sekce O nás'}[p.field]||p.field)+'</small><pre>'+esc(p.value)+'</pre>';
 if(t==='product_description')return '<pre>'+esc(p.description)+'</pre>';
 if(t==='goal')return '<b>'+esc(p.title)+'</b> · cíl '+esc(Number(p.target).toLocaleString('cs-CZ'))+' '+esc(AIT_MET[p.metric]||p.metric)+' za '+esc(p.days)+' dní';
 if(t==='schedule'){var k=((AIT.st&&AIT.st.kinds)||[]).filter(function(x){return x.module===p.module&&x.kind===p.kind})[0];return '<b>'+esc(aitModName(p.module))+': '+esc(k?k.title:p.kind)+'</b> · '+esc(AIT_CAD[p.cadence]||p.cadence)+(p.brief?'<pre>'+esc(p.brief)+'</pre>':'')}
 return '<pre>'+esc(JSON.stringify(p))+'</pre>'}
function aitActHtml(a){var open=a.status==='proposed';
 return '<div class="ait-act"><span class="ait-tag'+(open?' w':a.status==='applied'?' g':' r')+'">'+esc(AIT_ACT[a.type]||a.type)+(open?'':a.status==='applied'?' · provedeno':' · zamítnuto')+'</span><small class="mut">'+esc(aitModName(a.module))+'</small><div>'+aitActBody(a)+'</div>'
  +(open?'<div class="ait-row" style="margin-top:6px"><button type="button" class="ait-btn ok" data-ait="act-ok" data-id="'+esc(a.id)+'">Schválit a provést</button><button type="button" class="ait-btn" data-ait="act-no" data-id="'+esc(a.id)+'">Zamítnout</button></div>':'')+'</div>'}
function aitActions(m,onlyOpen){var L=((AIT.st&&AIT.st.actions)||[]).filter(function(a){return (!m||a.module===m)&&(!onlyOpen||a.status==='proposed')});
 return L.length?L.map(aitActHtml).join(''):'<p class="mut">Žádné návrhy ke schválení.</p>'}
/* ---------- úlohy ---------- */
function aitJobHtml(j){var o=j.output||{},c=j.status==='failed'?' r':j.status==='awaiting_approval'?' w':j.status==='done'?' g':'';
 var kids=((AIT.st&&AIT.st.jobs)||[]).filter(function(x){return x.parent_id===j.id});
 return '<li><span class="ait-tag'+c+'">'+esc(AIT_ST[j.status]||j.status)+'</span><b>'+esc(j.title)+'</b> <small class="mut">'+esc(aitModName(j.module))+' · '+esc(fD(j.created_at))+(j.source==='schedule'?' · z plánu':j.source==='ceo'?' · zadal AI CEO':'')+(j.cost_nusd!=null?' · '+esc(aitUsd(j.cost_nusd)):'')+'</small>'
  +(j.brief?'<div class="mut">Zadání: '+esc(j.brief)+'</div>':'')
  +(j.status==='queued'?'<div class="ait-row" style="margin-top:6px"><button type="button" class="ait-btn p" data-ait="job-run" data-id="'+esc(j.id)+'"'+(AIT.busy['job:'+j.id]?' disabled':'')+'>'+(AIT.busy['job:'+j.id]?'AI pracuje…':'Spustit')+'</button><button type="button" class="ait-btn" data-ait="job-cancel" data-id="'+esc(j.id)+'">Zrušit</button></div>':'')
  +(j.status==='failed'&&j.error?'<div class="mut">Důvod: '+esc({paid_runs_disabled:'placené AI běhy nejsou zapnuté',budget_not_set:'není nastaven limit nákladů',budget_exceeded:'limit nákladů je vyčerpaný',run_limit_exceeded:'limit na jednu operaci',user_limit_exceeded:'limit uživatele',upstream:'služba AI nebyla dostupná',invalid_ai_output:'výstup AI neprošel kontrolou',requester_not_allowed:'zadavatel už nemá oprávnění',max_attempts:'vyčerpány pokusy'}[j.error]||j.error)+'</div>':'')
  +(o.summary?'<details'+(j.status==='awaiting_approval'?' open':'')+'><summary>Výsledek</summary><p>'+esc(o.summary)+'</p>'+(o.sections||[]).map(function(s){return '<b>'+esc(s.title)+'</b><ul>'+(s.items||[]).map(function(i){return '<li>'+esc(i)+'</li>'}).join('')+'</ul>'}).join('')
    +(o.dropped_actions?'<small class="mut">'+esc(o.dropped_actions)+' návrhů AI neprošlo kontrolou a nebylo uloženo.</small>':'')+'</details>':'')
  +(kids.length?'<details open><summary>Dílčí úlohy pro AI pracovníky ('+kids.length+')</summary><ul class="ait-l">'+kids.map(aitJobHtml).join('')+'</ul></details>':'')+'</li>'}
function aitJobs(m){var all=(AIT.st&&AIT.st.jobs)||[],L=all.filter(function(j){return (!m||j.module===m)&&!(j.parent_id&&all.some(function(x){return x.id===j.parent_id&&(!m||x.module===m)}))});
 return L.length?'<ul class="ait-l">'+L.map(aitJobHtml).join('')+'</ul>':'<p class="mut">Zatím žádná činnost.</p>'}
/* ---------- přehled všech AI pracovníků ---------- */
function aitOverview(){var s=AIT.st,L=s.limits||{},open=(s.actions||[]).filter(function(a){return a.status==='proposed'}).length,pct=L.monthly_nusd>0?Math.min(100,Math.round(Number(L.spent_nusd)/Number(L.monthly_nusd)*100)):0;
 var h='<div class="card2"><h3>Náklady na AI tento měsíc</h3>'
  +(L.paid_runs_enabled?'':'<div class="draft">Placené AI běhy zatím nejsou zapnuté provozovatelem. Úlohy lze připravit, ale AI se nespustí a nic se neúčtuje.</div>')
  +(L.monthly_nusd==null?'<p>Limit firmy není nastaven. Nastavíte ho v <button type="button" class="lnkb" data-tab="autopilot">AI Marketing → Finance &amp; ROI</button>.</p>'
   :'<p>Spotřeba <b>'+esc(aitUsd(L.spent_nusd))+'</b> z limitu <b>'+esc(aitUsd(L.monthly_nusd))+'</b> ('+pct+' %)</p><div class="ait-bar" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="'+pct+'" aria-label="Využití měsíčního limitu"><i style="width:'+pct+'%"></i></div>'
    +'<p class="mut" style="margin-top:8px">Limit na jednu operaci: '+esc(aitUsd(L.per_run_nusd))+' · limit na uživatele: '+esc(L.per_user_nusd==null?'nenastaven':aitUsd(L.per_user_nusd))+' · strop tarifu: '+esc(aitUsd(L.plan_cap_nusd))+'</p>'
    +'<p class="mut">'+AIT_MODS.map(function(m){return esc(m[1])+': '+esc(aitUsd((L.by_module||{})[m[0]]||0))}).join(' · ')+'</p>'
    +'<details><summary>Změnit limit na uživatele a na operaci</summary><form id="aitLim" class="ait-row" novalidate><div class="f"><label for="ait_lu">Na uživatele (USD/měsíc, prázdné = bez limitu)</label><input id="ait_lu" inputmode="decimal" value="'+(L.per_user_nusd==null?'':esc(String(Number(L.per_user_nusd)/1e9).replace('.',',')))+'"></div><div class="f"><label for="ait_lr">Na jednu operaci (USD, prázdné = výchozí)</label><input id="ait_lr" inputmode="decimal"></div><button type="submit" class="ait-btn">Uložit limity</button></form></details>')+'</div>';
 h+='<div class="ait-g"><div><div class="card2"><h3>Ke schválení ('+open+')</h3>'+aitActions(null,true)+'</div><div class="card2"><h3>Činnost AI pracovníků</h3>'+aitJobs(null)+'</div></div><div>'+aitGoals()+aitSched(null)+'</div></div>';return h}
function aitGoals(){var G=(AIT.st&&AIT.st.goals)||[];return '<div class="card2"><h3>Měřitelné cíle</h3>'+(G.length?'<ul class="ait-l">'+G.map(function(g){var p=Math.min(100,Math.round(Number(g.value)/Number(g.target)*100));
  return '<li><b>'+esc(g.title)+'</b><div>'+esc(Number(g.value).toLocaleString('cs-CZ'))+' z '+esc(Number(g.target).toLocaleString('cs-CZ'))+' '+esc(AIT_MET[g.metric]||'')+' <small class="mut">do '+esc(fD(g.due_on))+'</small></div><div class="ait-bar" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="'+p+'" aria-label="Plnění cíle"><i style="width:'+p+'%"></i></div></li>'}).join('')+'</ul><small class="mut">Plnění se počítá ze skutečných záznamů od schválení cíle.</small>':'<p class="mut">Zatím žádný cíl. Navrhne ho AI CEO (Plán růstu) a vy ho schválíte.</p>')+'</div>'}
function aitSched(m){var S=((AIT.st&&AIT.st.schedules)||[]).filter(function(s){return !m||s.module===m}),K=m?aitKinds(m).filter(function(k){return k.schedulable}):[];
 var h='<div class="card2"><h3>Pravidelné plány (běží i bez prohlížeče)</h3>'+(S.length?'<ul class="ait-l">'+S.map(function(s){return '<li><span class="ait-tag'+(s.enabled?' g':'')+'">'+(s.enabled?'zapnuto':'vypnuto')+'</span><b>'+esc(s.title)+'</b> <small class="mut">'+esc(aitModName(s.module))+' · '+esc(AIT_CAD[s.cadence])+(s.enabled?' · další běh '+esc(fD(s.next_run_at)):'')+(s.last_status?' · poslední: '+esc(s.last_status==='ok'?'v pořádku':'nepovedl se'):'')+'</small>'
   +'<div><button type="button" class="ait-btn" data-ait="sch-toggle" data-m="'+esc(s.module)+'" data-k="'+esc(s.kind)+'" data-c="'+esc(s.cadence)+'" data-on="'+(s.enabled?'0':'1')+'">'+(s.enabled?'Vypnout':'Zapnout')+'</button></div></li>'}).join('')+'</ul>':'<p class="mut">Žádný plán.</p>')
  +(K.length?'<form id="aitSch" class="ait-row" novalidate data-m="'+esc(m)+'"><div class="f"><label for="ait_sk">Úloha</label><select id="ait_sk">'+K.map(function(k){return '<option value="'+esc(k.kind)+'">'+esc(k.title)+'</option>'}).join('')+'</select></div><div class="f"><label for="ait_sc">Jak často</label><select id="ait_sc"><option value="weekly">týdně</option><option value="daily">denně</option><option value="monthly">měsíčně</option></select></div><button type="submit" class="ait-btn">Přidat plán</button></form><small class="mut">Plán schvalujete vy a běží na váš účet v limitech firmy. Výsledky jsou návrhy, změny dat dál schvalujete.</small>':'')
  +(S.some(function(s){return s.enabled})?'<div style="margin-top:10px"><button type="button" class="ait-btn" data-ait="sch-stop">Zastavit všechny plány a čekající úlohy</button></div>':'')+'</div>';return h}
/* ---------- sekce jednoho AI pracovníka ---------- */
function aitModule(m){var K=aitKinds(m),C=AIT.chat[m]||[];
 var h='<div class="ait-g"><div><div class="card2"><h3>Zadat úkol: '+esc(aitModName(m))+'</h3><form id="aitRun" novalidate data-m="'+esc(m)+'"><div class="f"><label for="ait_kind">Co má udělat</label><select id="ait_kind">'+K.map(function(k){return '<option value="'+esc(k.kind)+'">'+esc(k.title)+'</option>'}).join('')+'</select></div>'
  +'<div class="f"><label for="ait_brief">Upřesnění vlastními slovy (nepovinné'+(m==='ceo'?'; u komplexního zadání popište cíl':'')+')</label><textarea id="ait_brief" rows="3" maxlength="2000" placeholder="'+esc(m==='ceo'?'Např. Chci zvýšit tržby o 20 %. Připrav marketingovou strategii, obchodní plán a finanční rozpočet.':m==='obchodnik'?'Např. Nabídka pro Dopravu Novák: servis 10 vozů, 1 500 Kč za vůz.':'Na co se má zaměřit')+'"></textarea></div>'
  +'<div class="ait-row"><button type="submit" class="ait-btn p"'+(AIT.busy.run?' disabled':'')+'>'+(AIT.busy.run?'AI pracuje…':'Spustit úkol')+'</button><small class="mut">AI vychází z dat vaší firmy. Výsledek je návrh; změny dat provedete až schválením.</small></div></form></div>'
  +(m==='ucetnictvi'?aitAcc():'')
  +'<div class="card2"><h3>Ke schválení</h3>'+aitActions(m,false)+'</div><div class="card2"><h3>Historie činností</h3>'+aitJobs(m)+'</div></div>'
  +'<div><div class="card2"><h3>Chat: '+esc(aitModName(m))+'</h3><div class="ait-chat" id="aitChat" aria-live="polite">'+(C.length?C.map(function(x){return '<div class="'+(x.role==='user'?'u':'a')+'">'+esc(x.content)+'</div>'}).join(''):'<div class="a">Zeptejte se na cokoli k datům vaší firmy. Odpovídám jen z toho, co je ve Vexaronetu.</div>')+(AIT.busy.chat?'<div class="a">Píšu odpověď…</div>':'')+'</div>'
  +'<form id="aitChatF" class="ait-row" novalidate data-m="'+esc(m)+'"><div class="f"><label for="ait_msg" class="sr">Zpráva</label><input id="ait_msg" maxlength="1500" placeholder="Napište dotaz" autocomplete="off"></div><button type="submit" class="ait-btn p"'+(AIT.busy.chat?' disabled':'')+'>Odeslat</button></form></div>'+aitSched(m)+(m==='ceo'?aitGoals():'')+aitExt(m)+'</div></div>';return h}
/* stav externích integrací: nic se nesimuluje */
function aitExt(m){var E={marketing:[['Facebook a Instagram (publikování, statistiky)','Meta Graph API: aplikace, App Review, ověření firmy'],['Google Business Profile','schválení přístupu k API'],['TikTok, YouTube, LinkedIn','vlastní schvalovací procesy']],
  obchodnik:[['Odesílání e-mailů zákazníkům','ověřená doména odesílatele a souhlasy; nevyžádaná sdělení se neposílají']],ucetnictvi:[['Automatické načítání banky (Open Banking)','licencovaný poskytovatel a souhlas majitele účtu; dnes ruční nahrání výpisu CSV'],['Ověření plátce DPH a účtů (ARES, registr DPH)','zatím nepropojeno']],
  weby_eshopy:[['Měření návštěvnosti','jen se souhlasem návštěvníků; dnes vypnuto']],ceo:[],automatizace:[]}[m]||[];
 return E.length?'<div class="card2"><h3>Externí propojení</h3><ul class="ait-l">'+E.map(function(x){return '<li><span class="ait-tag">Nepřipojeno</span><b>'+esc(x[0])+'</b><div class="mut">Vyžaduje: '+esc(x[1])+'</div></li>'}).join('')+'</ul></div>':''}
/* ---------- AI Účetní: doklady, režim, DPH, export, banka ---------- */
function aitAcc(){var a=AIT.acc;if(!a)return '<div class="card2"><h3>Doklady a účetní přehledy</h3><p class="mut">Načítám…</p></div>';
 var D=a.documents||[],S=a.settings||{},td=apdIso(apdD0(0)),m0=td.slice(0,8)+'01';
 var h='<div class="card2 note"><b>AI Účetní připravuje podklady, nerozhoduje.</b> Návrhy kontrolujete a schvalujete vy nebo váš účetní. Přehledy jsou orientační a nenahrazují účetnictví ani daňové přiznání.</div>';
 h+='<div class="card2"><h3>Režim evidence</h3><form id="aitReg" class="ait-row" novalidate><div class="f"><label for="ait_reg">Vedeme</label><select id="ait_reg">'+Object.keys(AIT_REG).map(function(k){return '<option value="'+k+'"'+(S.regime===k?' selected':'')+'>'+esc(AIT_REG[k])+'</option>'}).join('')+'</select></div><label class="chk" style="min-width:150px"><input type="checkbox" id="ait_vat"'+(S.vat_payer?' checked':'')+'> Jsme plátci DPH</label><button type="submit" class="ait-btn">Uložit</button></form><small class="mut">Podle režimu AI navrhuje buď zařazení do příjmů a výdajů (daňová evidence), nebo předkontace (účetnictví). Vždy jde o návrh k ověření.</small></div>';
 h+='<div class="card2"><h3>Doklady ('+D.length+')</h3><p class="mut">Doklad nahrajete v sekci <button type="button" class="lnkb" data-tab="ucetni">AI Účetní → Nahrát doklad</button>. AI z něj vytěží údaje a uloží ho sem ke kontrole. Soubor se neukládá, jen jeho otisk pro rozpoznání duplicit.</p>'
  +(D.length?'<ul class="ait-l">'+D.map(function(r){var d=r.doc||{},open=r.status==='extracted',ch=open&&JSON.stringify(r.doc)!==JSON.stringify(r.ai_doc);
   return '<li><span class="ait-tag'+(open?' w':r.status==='approved'?' g':' r')+'">'+(open?'ke kontrole':r.status==='approved'?'schváleno':'zamítnuto')+'</span>'+(r.duplicate_of&&open?'<span class="ait-tag r">možná duplicita</span>':'')+(ch?'<span class="ait-tag">upraveno člověkem</span>':'')
    +'<b>'+esc(d.supplier_name||'Doklad')+'</b> '+esc(d.document_number||'')+' · '+esc(d.total_amount==null?'částka chybí':fM(d.total_amount))+(d.vat_amount!=null?' <small class="mut">(DPH '+esc(fM(d.vat_amount))+(d.vat_rate!=null?', '+esc(d.vat_rate)+' %':'')+')</small>':'')+' <small class="mut">'+esc(d.issue_date?fD(d.issue_date):'bez data')+(d.category?' · '+esc(d.category):'')+'</small>'
    +(open?'<div class="ait-row" style="margin-top:6px"><button type="button" class="ait-btn ok" data-ait="doc-ok" data-id="'+esc(r.id)+'">'+(d.document_type==='issued_invoice'?'Svázat s vystavenou fakturou':'Schválit jako výdaj')+'</button><button type="button" class="ait-btn" data-ait="doc-edit" data-id="'+esc(r.id)+'">Opravit údaje</button><button type="button" class="ait-btn" data-ait="doc-no" data-id="'+esc(r.id)+'">Zamítnout</button></div>':'')+'</li>'}).join('')+'</ul>':'<p class="mut">Zatím žádné doklady.</p>')+'</div>';
 h+='<div class="card2"><h3>Přehled DPH a export</h3><form id="aitVat" class="ait-row" novalidate><div class="f"><label for="ait_vf">Od</label><input id="ait_vf" type="date" value="'+m0+'"></div><div class="f"><label for="ait_vt">Do</label><input id="ait_vt" type="date" value="'+td+'"></div><button type="submit" class="ait-btn">Zobrazit DPH</button><button type="button" class="ait-btn" data-ait="acc-export">Export CSV</button></form>'+aitVatHtml()+'</div>';
 h+=aitBank();return h}
function aitVatHtml(){var v=AIT.vat;if(!v)return '';var sum=function(L){return (L||[]).reduce(function(s,x){return s+Number(x.vat||0)},0)},row=function(x){return '<tr><td>'+esc(x.rate)+' %</td><td>'+esc(fM(x.base))+'</td><td>'+esc(fM(x.vat))+'</td></tr>'};
 return '<div style="margin-top:10px"><b>'+esc(fD(v.from))+' – '+esc(fD(v.to))+'</b><table><tr><th colspan="3">Výstup (vystavené faktury)</th></tr><tr><th>Sazba</th><th>Základ</th><th>DPH</th></tr>'+((v.output||[]).map(row).join('')||'<tr><td colspan="3" class="mut">žádné faktury plátce DPH</td></tr>')
  +'<tr><th colspan="3">Vstup (schválené přijaté doklady)</th></tr>'+((v.input||[]).map(row).join('')||'<tr><td colspan="3" class="mut">žádné doklady</td></tr>')+'</table>'
  +'<p>Výstup '+esc(fM(sum(v.output)))+' − vstup '+esc(fM(sum(v.input)))+' = <b>'+esc(fM(sum(v.output)-sum(v.input)))+'</b> (orientačně)</p>'+(v.documents_without_vat?'<p class="mut">'+esc(v.documents_without_vat)+' dokladů nemá uvedenou částku DPH.</p>':'')+'<div class="draft">'+esc(v.note)+'</div></div>'}
function aitBank(){var b=AIT.bank;
 var h='<div class="card2"><h3>Banka: kontrola plateb</h3><div class="draft">Bankovní účet není propojený. Vexaronet nenačítá transakce z banky sám; pracuje jen s výpisem, který nahrajete. Automatické načítání (Open Banking) vyžaduje licencovaného poskytovatele.</div>';
 if(!b||b.err)return h+'<p class="mut">'+(b&&b.err?'Bankovní podklady nejsou k dispozici: '+esc(aitErr({message:b.err})):'Načítám…')+'</p></div>';
 var c=b.counts||{},R=b.rows||[];
 h+='<form id="aitCsv" novalidate><div class="ait-row"><div class="f"><label for="ait_ba">Označení účtu</label><input id="ait_ba" maxlength="100" placeholder="např. Fio CZK"></div><div class="f"><label for="ait_bf">Výpis CSV z banky</label><input id="ait_bf" type="file" accept=".csv,text/csv"></div></div>'
  +(AIT.csv?'<p>Načteno <b>'+AIT.csv.rows.length+'</b> pohybů'+(AIT.csv.skipped?', přeskočeno '+AIT.csv.skipped:'')+'.'+(AIT.csv.errors.length?'<br><span class="mut">'+AIT.csv.errors.map(esc).join('<br>')+'</span>':'')+'</p><label class="chk"><input type="checkbox" id="ait_bc"> Potvrzuji, že jde o skutečný výpis z účtu firmy a zkontroloval(a) jsem ho.</label><div><button type="submit" class="ait-btn p"'+(AIT.csv.rows.length?'':' disabled')+'>Nahrát pohyby</button></div>':'')+'</form>';
 h+='<p style="margin-top:10px">Pohybů: '+esc(c.all||0)+' · ke kontrole <b>'+esc(c.unmatched||0)+'</b> · spárováno '+esc(c.matched||0)+' · přeskočeno '+esc(c.ignored||0)+'</p>';
 h+=R.length?'<ul class="ait-l">'+R.slice(0,40).map(function(t){var cand=t.candidates||[];
  return '<li><span class="ait-tag'+(t.status==='matched'?' g':t.status==='unmatched'?' w':'')+'">'+esc({matched:'spárováno',unmatched:'ke kontrole',ignored:'přeskočeno'}[t.status])+'</span><b>'+esc(fM(Number(t.amount_cents)/100))+'</b> '+esc(t.currency)+' · '+esc(fD(t.booked_on))+(t.variable_symbol?' · VS '+esc(t.variable_symbol):'')+' <small class="mut">'+esc(t.description||'')+'</small>'
   +(t.status==='matched'?'<div class="mut">Faktura '+esc(t.invoice_number||'')+'</div>':'')
   +(t.status==='unmatched'?(cand.length?cand.map(function(k){return '<div class="ait-row" style="margin-top:6px"><span>Odpovídá faktuře <b>'+esc(k.number)+'</b> ('+esc(k.customer||'')+', '+esc(fM(k.total))+')</span><button type="button" class="ait-btn ok" data-ait="bank-match" data-id="'+esc(t.id)+'" data-inv="'+esc(k.id)+'" data-no="'+esc(k.number)+'">Potvrdit úhradu</button></div>'}).join(''):'<div class="mut">'+(Number(t.amount_cents)>0?'Žádná neuhrazená faktura se stejným VS a částkou.':'Odchozí platba.')+'</div>')
     +'<div><button type="button" class="ait-btn" data-ait="bank-ignore" data-id="'+esc(t.id)+'">Přeskočit</button></div>':'')
   +(t.status==='ignored'?'<div><button type="button" class="ait-btn" data-ait="bank-restore" data-id="'+esc(t.id)+'">Vrátit ke kontrole</button></div>':'')+'</li>'}).join('')+'</ul>':'<p class="mut">Zatím žádné pohyby. Nahrajte výpis CSV.</p>';
 return h+'<small class="mut">Úhradu faktury potvrzujete vy. Párujeme jen přesnou shodu variabilního symbolu, částky a měny.</small></div>'}
function aitBody(){if(DEMO)return '<div class="card2"><h3>V ukázce se AI tým nespouští</h3><p>Po přihlášení ke skutečné firmě zde zadáte úkoly šesti AI pracovníkům a schválíte jejich návrhy.</p></div>';
 if(AIT.err)return '<div class="draft"><b>AI tým není k dispozici.</b> '+esc(AIT.err)+'</div>';if(!AIT.st||AIT.cid!==APP.cid)return '<p class="mut">Načítám…</p>';
 return AIT.tab==='prehled'?aitOverview():aitModule(AIT.tab)}
function aitHtml(){aitCss();return '<div class="ait" id="ait"><h2 style="margin:0 0 4px">AI tým</h2><p class="mut" style="margin:0 0 10px">Šest AI pracovníků nad daty vaší firmy. Navrhují, vy schvalujete.</p><nav class="ait-tabs" aria-label="AI pracovníci"><button type="button" data-ait-tab="prehled"'+(AIT.tab==='prehled'?' aria-current="page"':'')+'>Přehled</button>'
 +AIT_MODS.map(function(m){return '<button type="button" data-ait-tab="'+m[0]+'"'+(AIT.tab===m[0]?' aria-current="page"':'')+'>'+esc(m[1])+'</button>'}).join('')+'</nav><div id="aitBody">'+aitBody()+'</div></div>'}
VIEWS.aitym=function(){if(APP.role==='employee')return '<div class="card2 soonc"><h2>AI tým</h2><p>AI tým spravuje vlastník nebo správce.</p></div>';return aitHtml()};
AFTER.aitym=function(){if(APP.role!=='employee'){aitLoad();aitChatLoad()}};
async function aitChatLoad(){var m=AIT.tab;if(m==='prehled'||AIT.chatLoaded[APP.cid+m]||DEMO)return;try{var r=await getSb().rpc('ai_chat_history',{cid:APP.cid,p_module:m});if(!r.error){AIT.chat[m]=r.data||[];AIT.chatLoaded[APP.cid+m]=true;aitPaint()}}catch(e){}}
/* ---------- volání AI (idempotenční klíč přežije obnovení stránky i výpadek spojení) ---------- */
async function aitApi(slot,body){
 var lk='vxait:'+APP.cid+':'+slot,p=null;try{p=JSON.parse(localStorage.getItem(lk)||'null')}catch(e){}
 if(!p||JSON.stringify(p.b)!==JSON.stringify(body))p={k:aitKey(),b:body};try{localStorage.setItem(lk,JSON.stringify(p))}catch(e){}
 var keep=false,out=null;
 try{var ses=(await getSb().auth.getSession()).data.session;if(!ses){toast('Přihlášení vypršelo. Přihlaste se znovu.','err');return null}
  var r=await fetch('/api/ai-worker',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+ses.access_token},body:JSON.stringify(Object.assign({cid:APP.cid,key:p.k},body))});
  var j=await r.json().catch(function(){return {}});
  if(r.ok)out=j;else if(r.status===409&&j.error==='in_progress'){keep=true;toast('Úloha se ještě zpracovává. Za chvíli obnovte stav.','ok')}
  else toast(j.message||({auth:'Přihlášení vypršelo.',plan:'AI tým je dostupný v tarifu PRO a vyšším.',forbidden:'AI tým spouští vlastník nebo správce firmy.',not_configured:'AI není na serveru nastavená.'}[j.error])||'Požadavek se nepovedl.','err')
 }catch(e){keep=true;toast('Spojení se přerušilo. Zkuste to znovu; stejný požadavek se neprovede ani nezaplatí dvakrát.','err')}
 if(!keep){try{localStorage.removeItem(lk)}catch(e){}}return out}
if(!window.__aitBound){window.__aitBound=true;
 document.addEventListener('click',async function(e){
  var tb=e.target.closest&&e.target.closest('#ait [data-ait-tab]');if(tb){AIT.tab=tb.getAttribute('data-ait-tab');AIT.vat=null;AIT.csv=null;appTab('aitym');return}
  var b=e.target.closest&&e.target.closest('#ait [data-ait]');if(!b)return;var a=b.getAttribute('data-ait'),id=b.getAttribute('data-id');
  if(a==='act-ok'||a==='act-no'){var x=((AIT.st&&AIT.st.actions)||[]).filter(function(q){return q.id===id})[0];if(!x)return;b.disabled=true;
   var d=await aitRpc('ai_action_decide',{p_action:id,p_expected_hash:x.payload_hash,p_approve:a==='act-ok'},a==='act-ok'?'Schváleno a provedeno.':'Návrh zamítnut.');if(d){try{await refresh()}catch(q){}}await aitLoad();return}
  if(a==='job-run'){if(AIT.busy['job:'+id])return;AIT.busy['job:'+id]=true;aitPaint();var o=await aitApi('job:'+id,{op:'run_job',job_id:id});AIT.busy['job:'+id]=false;if(o)toast('Úloha je hotová. Zkontrolujte výsledek a návrhy.','ok');await aitLoad();return}
  if(a==='job-cancel'){await aitRpc('ai_job_cancel',{p_job:id},'Úloha zrušena.');await aitLoad();return}
  if(a==='sch-toggle'){await aitRpc('ai_schedule_save',{p_module:b.getAttribute('data-m'),p_kind:b.getAttribute('data-k'),p_cadence:b.getAttribute('data-c'),p_brief:'',p_enabled:b.getAttribute('data-on')==='1'},'Plán uložen.');await aitLoad();return}
  if(a==='sch-stop'){if(!confirm('Zastavit všechny pravidelné plány a zrušit čekající úlohy?'))return;await aitRpc('ai_schedule_stop_all',{},'Automatizace je zastavená.');await aitLoad();return}
  if(a==='doc-ok'||a==='doc-no'){var r=((AIT.acc&&AIT.acc.documents)||[]).filter(function(q){return q.id===id})[0];if(!r)return;var dup=false;
   if(a==='doc-ok'&&r.duplicate_of){if(!confirm('Doklad vypadá jako duplicita dříve nahraného. Opravdu ho schválit jako další výdaj?'))return;dup=true}
   b.disabled=true;var d2=await aitRpc('acc_document_decide',{p_id:id,p_expected_hash:r.doc_hash,p_approve:a==='doc-ok',p_allow_duplicate:dup},a==='doc-ok'?'Doklad schválen.':'Doklad zamítnut.');if(d2){try{await refresh()}catch(q){}}await aitLoad();return}
  if(a==='doc-edit'){var r2=((AIT.acc&&AIT.acc.documents)||[]).filter(function(q){return q.id===id})[0];if(!r2)return;var d3=r2.doc||{},F=[['supplier_name','Dodavatel','text'],['supplier_ico','IČO','text'],['document_number','Číslo dokladu','text'],['issue_date','Datum vystavení','date'],['due_date','Splatnost','date'],['total_amount','Celkem','number'],['vat_amount','DPH','number'],['vat_rate','Sazba DPH %','number'],['category','Kategorie','text']];
   modal('<h3>Opravit údaje dokladu</h3><p class="mut">Původní návrh AI zůstane uložený pro kontrolu.</p><form id="aitDocF" data-id="'+esc(id)+'" novalidate><div class="fg">'+F.map(function(f){return '<div class="f"><label for="aitd_'+f[0]+'">'+f[1]+'</label><input id="aitd_'+f[0]+'" type="'+f[2]+'"'+(f[2]==='number'?' step="any" min="0"':'')+' value="'+esc(d3[f[0]]==null?'':d3[f[0]])+'"></div>'}).join('')
    +'<div class="f"><label for="aitd_document_type">Druh</label><select id="aitd_document_type">'+[['received_invoice','Přijatá faktura'],['receipt','Účtenka'],['issued_invoice','Vystavená faktura'],['other','Jiný']].map(function(o){return '<option value="'+o[0]+'"'+(d3.document_type===o[0]?' selected':'')+'>'+o[1]+'</option>'}).join('')+'</select></div></div><div class="dact"><button class="btn btn-main" type="submit">Uložit opravu</button></div></form>');return}
  if(a==='acc-export'){var f=(A('ait_vf')||{}).value,t=(A('ait_vt')||{}).value,x2=await aitRpc('acc_export',{p_from:f,p_to:t});if(!x2)return;
   var q=function(v){v=v==null?'':String(v);return /[";\n]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v},L=['typ;datum;doklad;protistrana;popis;castka;dph;sazba;mena;stav'];
   (x2.entries||[]).forEach(function(r){L.push(['zaznam',r.date,'','',r.title,(r.kind==='expense'?'-':'')+r.amount,'','','CZK',''].map(q).join(';'))});
   (x2.documents||[]).forEach(function(r){L.push(['prijaty doklad',r.issue_date,r.document_number,r.supplier_name,r.description||r.category,r.total_amount,r.vat_amount,r.vat_rate,r.currency,'schvaleno'].map(q).join(';'))});
   (x2.invoices||[]).forEach(function(r){L.push(['vystavena faktura',r.issued_on,r.number,r.customer,'',r.total,'','',r.currency,r.paid_at?'uhrazeno':'neuhrazeno'].map(q).join(';'))});
   var u=URL.createObjectURL(new Blob(['﻿'+L.join('\r\n')],{type:'text/csv;charset=utf-8'})),l=document.createElement('a');l.href=u;l.download='vexaronet-evidence-'+f+'-'+t+'.csv';document.body.appendChild(l);l.click();l.remove();setTimeout(function(){URL.revokeObjectURL(u)},2000);toast('Export je připravený ('+(L.length-1)+' řádků).','ok');return}
  if(a==='bank-match'){if(!confirm('Potvrzujete, že platba skutečně dorazila na účet a patří k faktuře '+b.getAttribute('data-no')+'? Faktura se označí jako uhrazená.'))return;b.disabled=true;
   var r3=await getSb().rpc('bank_reconciliation',{cid:APP.cid,op:'match',doc:{id:id,invoice_id:b.getAttribute('data-inv'),confirmed:true}});if(r3.error)toast(r3.error.message,'err');else{toast('Úhrada potvrzena.','ok');try{await refresh()}catch(q2){}}await aitLoad();return}
  if(a==='bank-ignore'){var n=prompt('Důvod přeskočení (např. vlastní převod):');if(!n)return;var r4=await getSb().rpc('bank_reconciliation',{cid:APP.cid,op:'ignore',doc:{id:id,note:n}});if(r4.error)toast(r4.error.message,'err');await aitLoad();return}
  if(a==='bank-restore'){var r5=await getSb().rpc('bank_reconciliation',{cid:APP.cid,op:'restore',doc:{id:id}});if(r5.error)toast(r5.error.message,'err');await aitLoad();return}});
 document.addEventListener('change',function(e){if(e.target&&e.target.id==='ait_bf'){var f=e.target.files&&e.target.files[0];if(!f)return;if(f.size>2e6){toast('Výpis je příliš velký (nejvýše 2 MB).','err');return}
  var fr=new FileReader();fr.onload=function(){AIT.csv=VXBANK.parse(String(fr.result),'CZK');AIT.csv.name=f.name;aitPaint()};fr.readAsText(f)}});
 document.addEventListener('submit',async function(e){var f=e.target;if(!f||!f.id||f.id.indexOf('ait')!==0)return;e.preventDefault();
  if(f.id==='aitRun'){if(AIT.busy.run)return;var m=f.getAttribute('data-m'),k=A('ait_kind').value,br=A('ait_brief').value.trim();AIT.busy.run=true;aitPaint();
   var o=await aitApi('run:'+m,{op:'run',module:m,kind:k,brief:br});AIT.busy.run=false;if(o){toast(o.reused?'Tento požadavek už byl zpracován.':'Hotovo. Zkontrolujte výsledek a návrhy ke schválení.','ok');if(A('ait_brief'))A('ait_brief').value=''}await aitLoad();return}
  if(f.id==='aitChatF'){if(AIT.busy.chat)return;var m2=f.getAttribute('data-m'),msg=A('ait_msg').value.trim();if(msg.length<2)return;AIT.chat[m2]=(AIT.chat[m2]||[]).concat([{role:'user',content:msg}]);A('ait_msg').value='';AIT.busy.chat=true;aitPaint();
   var o2=await aitApi('chat:'+m2,{op:'chat',module:m2,message:msg});AIT.busy.chat=false;if(o2&&o2.reply)AIT.chat[m2].push({role:'assistant',content:o2.reply});else AIT.chat[m2].pop();aitPaint();aitLoad();return}
  if(f.id==='aitSch'){await aitRpc('ai_schedule_save',{p_module:f.getAttribute('data-m'),p_kind:A('ait_sk').value,p_cadence:A('ait_sc').value,p_brief:'',p_enabled:true},'Plán je schválený a zapnutý.');await aitLoad();return}
  if(f.id==='aitLim'){var u=A('ait_lu').value.trim(),r=A('ait_lr').value.trim(),nu=u?VXAP.usdToNusd(u):null,nr=r?VXAP.usdToNusd(r):null;if((u&&nu==null)||(r&&nr==null)){toast('Zadejte částku v USD, např. 0,10.','err');return}
   await aitRpc('autopilot_set_limits',{p_per_user_nusd:nu==null?null:Number(nu),p_per_run_nusd:nr==null?null:Number(nr)},'Limity uloženy.');await aitLoad();return}
  if(f.id==='aitReg'){await aitRpc('acc_settings_save',{p_regime:A('ait_reg').value,p_vat_payer:A('ait_vat').checked},'Režim evidence uložen.');await aitLoad();return}
  if(f.id==='aitVat'){var v=await aitRpc('acc_vat_summary',{p_from:A('ait_vf').value,p_to:A('ait_vt').value});if(v){AIT.vat=v;aitPaint()}return}
  if(f.id==='aitCsv'){if(!AIT.csv||!AIT.csv.rows.length)return;var acc=A('ait_ba').value.trim();if(acc.length<3){toast('Vyplňte označení účtu (aspoň 3 znaky).','err');return}if(!A('ait_bc').checked){toast('Potvrďte, že jde o skutečný výpis z účtu firmy.','err');return}
   var r6=await getSb().rpc('bank_reconciliation',{cid:APP.cid,op:'import',doc:{id:(crypto.randomUUID?crypto.randomUUID():aitKey()),account_key:acc,file_name:AIT.csv.name||'vypis.csv',confirmed:true,rows:AIT.csv.rows}});
   if(r6.error){toast(r6.error.message,'err');return}toast('Nahráno '+r6.data.inserted+' nových pohybů'+(r6.data.duplicates?', '+r6.data.duplicates+' už v evidenci bylo':'')+'.','ok');AIT.csv=null;await aitLoad();return}
  if(f.id==='aitDocF'){var id=f.getAttribute('data-id'),r7=((AIT.acc&&AIT.acc.documents)||[]).filter(function(q){return q.id===id})[0];if(!r7)return;var g=function(k){var el=A('aitd_'+k);return el?String(el.value).trim():''},num=function(k){var s=g(k).replace(',','.');return s===''?null:Number(s)};
   var doc=Object.assign({},r7.doc,{supplier_name:g('supplier_name')||null,supplier_ico:g('supplier_ico')||null,document_number:g('document_number')||null,issue_date:g('issue_date')||null,due_date:g('due_date')||null,total_amount:num('total_amount'),vat_amount:num('vat_amount'),vat_rate:num('vat_rate'),category:g('category')||null,document_type:g('document_type')});
   if([doc.total_amount,doc.vat_amount,doc.vat_rate].some(function(x){return x!=null&&!(x>=0)})){toast('Částky musí být čísla 0 nebo vyšší.','err');return}
   var d=await aitRpc('acc_document_update',{p_id:id,p_expected_hash:r7.doc_hash,p_doc:doc},'Údaje dokladu opraveny.');if(d){var mm=A('appModal');if(mm)mm.remove();await aitLoad()}return}})}
