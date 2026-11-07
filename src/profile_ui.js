/* ===== Profil firmy pro AI: ruční vyplnění, automatické ukládání, verze, potvrzení =====
   Datové operace jdou přes RPC public.profile_* (oprávnění, konflikty revize a validaci vynucuje databáze).
   Tento kód řeší jen formulář a rychlou odezvu. Nic zde nevolá placenou AI. */
IC.firmaprofil='M5 4h14v16H5zM8 8h8M8 12h8M8 16h5';
var PS={cid:null,info:null,doc:null,rev:0,hash:null,dirty:false,saving:false,timer:null,status:'',conflict:null,schemaOk:true,errors:[],loadedCid:null};
var FP_METRIC=[['revenue','Tržby'],['jobs','Počet zakázek'],['new_customers','Noví zákazníci'],['leads','Poptávky'],['other','Jiná metrika']];
var FP_CH=[['facebook','Facebook'],['instagram','Instagram'],['google_business','Firma na Googlu'],['web','Web'],['email','E-mail'],['other','Jiný kanál']];
var FP_INC=[['ads','Reklama'],['content','Tvorba obsahu'],['tools','Nástroje'],['other','Jiné']];
var FP_LAB={'local.geography:required':'Město nebo obsluhovaná oblast','shared.identity.displayName:required':'Název firmy','shared.services:required':'Popis činnosti nebo alespoň jedna služba','shared.audience.description:required':'Popis zákazníků',
 'shared.financialContext.revenueCurrency:required':'Měna tržeb','shared.financialContext.revenuePeriod:required':'Období tržeb','shared.financialContext.budgetCurrency:required':'Měna rozpočtu','shared.financialContext.budgetPeriod:required':'Perioda rozpočtu','shared.unknowns:blocking':'Nevyřešená nejasnost'};
function fpLabel(code){if(FP_LAB[code])return FP_LAB[code];var m=/^shared\.goals\[(\d+)\]\.(dueDate|baselineMinor):required$/.exec(code);if(m)return 'Cíl '+(Number(m[1])+1)+': '+(m[2]==='dueDate'?'termín':'výchozí hodnota');return code}
function fpStyle(){if(document.getElementById('fpCss'))return;var s=document.createElement('style');s.id='fpCss';s.textContent='.fp .fe{display:block;color:#ff9aa8;font-size:.82rem;margin-top:4px}.fp .fsec{margin-bottom:18px}.fp .frow{display:grid;grid-template-columns:2fr 3fr 1fr auto;gap:8px;align-items:end;margin-bottom:8px}.fp .frow2{display:grid;grid-template-columns:3fr 1fr auto;gap:8px;align-items:end;margin-bottom:8px}.fp .fst{display:inline-block;padding:3px 10px;border-radius:999px;font-size:.82rem;background:rgba(139,108,255,.16)}.fp .fst.ok{background:rgba(60,200,120,.16)}.fp .fst.bad{background:rgba(220,60,80,.18)}.fp .fcalc{padding:10px 14px;border-radius:12px;background:rgba(139,108,255,.1);margin-top:8px;font-size:.92rem}.fp .fgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}.fp textarea{min-height:76px}@media(max-width:640px){.fp .frow,.fp .frow2{grid-template-columns:1fr}}';document.head.appendChild(s)}
function fpId(p){return 'fp_'+p.replace(/[^a-zA-Z0-9]/g,'_')}
function fpGet(o,p){var k=p.split('.'),i;for(i=0;i<k.length;i++){if(o==null)return undefined;o=o[k[i]]}return o}
function fpSet(o,p,v){var k=p.split('.'),i,c=o;for(i=0;i<k.length-1;i++){var key=k[i],nx=/^\d+$/.test(k[i+1]);if(c[key]==null)c[key]=nx?[]:{};c=c[key]}c[k[k.length-1]]=v}
function fpMinor(s){s=String(s==null?'':s).replace(/\s/g,'').replace(',','.');if(s==='')return undefined;var n=Number(s);if(!isFinite(n)||n<0)return NaN;return Math.round(n*100)}
function fpBp(s){s=String(s==null?'':s).replace(/\s/g,'').replace(',','.').replace('%','');if(s==='')return undefined;var n=Number(s);if(!isFinite(n)||n<0)return NaN;return Math.round(n*100)}
function fpShowMinor(m){return m==null?'':String(m/100).replace('.',',')}
function fpShowBp(b){return b==null?'':String(b/100).replace('.',',')}
function fpCanon(o){if(Array.isArray(o))return '['+o.map(fpCanon).join(',')+']';if(o&&typeof o==='object')return '{'+Object.keys(o).sort().map(function(k){return JSON.stringify(k)+':'+fpCanon(o[k])}).join(',')+'}';return JSON.stringify(o)}
function fpField(p,label,o){o=o||{};var v=fpGet(PS.doc,p),id=fpId(p),ro=o.ro?' disabled':'',t=o.t||'text',val=o.fmt?o.fmt(v):(v==null?'':v),inp;
 if(t==='textarea')inp='<textarea id="'+id+'" data-p="'+p+'" data-t="text" data-dt="text" maxlength="'+(o.max||1000)+'"'+ro+'>'+esc(val)+'</textarea>';
 else if(t==='select')inp='<select id="'+id+'" data-p="'+p+'" data-t="select"'+ro+'><option value="">– nevyplněno –</option>'+o.opts.map(function(x){return '<option value="'+esc(x[0])+'"'+(x[0]===v?' selected':'')+'>'+esc(x[1])+'</option>'}).join('')+'</select>';
 else inp='<input id="'+id+'" data-p="'+p+'" data-t="text" data-dt="'+(o.dt||'text')+'" type="'+(t==='date'?'date':'text')+'" value="'+esc(val)+'" maxlength="'+(o.max||300)+'"'+(o.ph?' placeholder="'+esc(o.ph)+'"':'')+ro+'>';
 return '<div class="f'+(o.full?' full':'')+'"><label for="'+id+'">'+label+'</label>'+inp+(o.help?'<small class="mut">'+o.help+'</small>':'')+'<small class="fe" data-fe="'+p+'"></small></div>'}
function fpRows(base,items,cols,max,addLab){var h='';(items||[]).forEach(function(it,i){h+='<div class="'+(cols.length===3?'frow':'frow2')+'" data-row="'+base+'.'+i+'">'+cols.map(function(c){return fpField(base+'.'+i+'.'+c[0],c[1],c[2]||{})}).join('')+'<button type="button" class="btn btn-ghost btn-sm" data-fp="del" data-base="'+base+'" data-i="'+i+'" aria-label="Odebrat řádek">×</button></div>'});
 if((items||[]).length<max)h+='<button type="button" class="btn btn-ghost btn-sm" data-fp="add" data-base="'+base+'">'+addLab+'</button>';return h}
function fpChecks(p,opts,cur,key){return '<div class="chks">'+opts.map(function(o){var on=(cur||[]).some(function(c){return (key?c[key]:c)===o[0]});return '<label class="chk"><input type="checkbox" data-multi="'+p+'" data-key="'+(key||'')+'" value="'+o[0]+'"'+(on?' checked':'')+'><span>'+o[1]+'</span></label>'}).join('')+'</div>'}
function fpShared(ro){
 var d=PS.doc.shared||{},h='';
 h+='<section class="card2 fsec"><h3>1. Firma a služby</h3><div class="fg">'
  +fpField('shared.identity.displayName','Název firmy <i>*</i>',{ro:ro,max:120,help:'Tak, jak se má objevit v textech od AI.'})
  +fpField('shared.identity.website','Web firmy',{ro:ro,ph:'https://…',help:'Nechte prázdné, pokud web nemáte. Zadejte adresu vašeho webu, ne adresu Vexaronetu.'})
  +fpField('shared.identity.activity','Čím se firma zabývá',{t:'textarea',full:true,ro:ro,help:'Vlastními slovy. Nic nevymýšlejte, AI vychází jen z toho, co zde napíšete.'})
  +'</div><h4>Služby</h4>'+(ro?'':'')+fpRows('shared.services.items',(d.services||{}).items,[['name','Název',{max:120,ro:ro}],['description','Popis',{max:500,ro:ro}],['priority','Priorita',{t:'select',ro:ro,opts:[['high','Vysoká'],['normal','Běžná'],['low','Nízká']]}]],30,'+ Služba')
  +'</section>';
 h+='<section class="card2 fsec"><h3>2. Zákazníci</h3><div class="fg">'
  +fpField('shared.audience.description','Kdo jsou vaši zákazníci <i>*</i>',{t:'textarea',full:true,ro:ro})
  +fpField('shared.audience.segments','Skupiny zákazníků',{t:'text',full:true,ro:ro,dt:'list',fmt:function(v){return (v||[]).join(', ')},help:'Oddělte čárkou, např. řidiči osobních aut, firemní vozový park.'})
  +'</div></section>';
 var fc=d.financialContext||{},g=(d.goals||[])[0]||{};
 h+='<section class="card2 fsec"><h3>3. Výchozí situace a cíl</h3><p class="mut">Čísla jsou nepovinná. Kde si nejste jistí, nechte prázdné, AI si hodnotu nedomyslí. Částky v celých korunách, měnu a období vyberte vždy.</p><div class="fgrid">'
  +fpField('shared.financialContext.revenueMinor','Tržby firmy',{dt:'money',ro:ro,fmt:fpShowMinor})
  +fpField('shared.financialContext.revenueCurrency','Měna tržeb',{t:'select',ro:ro,opts:[['CZK','Kč'],['EUR','Euro']]})
  +fpField('shared.financialContext.revenuePeriod','Za jaké období',{t:'select',ro:ro,opts:[['month','Měsíc'],['year','Rok']]})
  +fpField('shared.financialContext.budgetMinor','Marketingový rozpočet',{dt:'money',ro:ro,fmt:fpShowMinor})
  +fpField('shared.financialContext.budgetCurrency','Měna rozpočtu',{t:'select',ro:ro,opts:[['CZK','Kč'],['EUR','Euro']]})
  +fpField('shared.financialContext.budgetPeriod','Perioda rozpočtu',{t:'select',ro:ro,opts:[['month','Měsíc'],['quarter','Čtvrtletí'],['year','Rok'],['one_time','Jednorázově']]})
  +'</div><p class="mut" style="margin-top:10px">Co rozpočet zahrnuje:</p>'+fpChecks('shared.financialContext.budgetIncludes',FP_INC,fc.budgetIncludes)
  +'<h4>Hlavní cíl</h4><div class="fgrid">'
  +fpField('shared.goals.0.metric','Co chcete zvýšit',{t:'select',ro:ro,opts:FP_METRIC})
  +fpField('shared.goals.0.baselineMinor','Výchozí hodnota',{dt:'money',ro:ro,fmt:fpShowMinor,help:'U tržeb v korunách, u počtů v kusech.'})
  +fpField('shared.goals.0.growthBp','Zvýšit o (%)',{dt:'pct',ro:ro,fmt:fpShowBp})
  +fpField('shared.goals.0.startDate','Začátek',{t:'date',ro:ro})
  +fpField('shared.goals.0.dueDate','Termín',{t:'date',ro:ro})
  +'</div><div class="fcalc" id="fpCalc" aria-live="polite"></div></section>';
 h+='<section class="card2 fsec"><h3>4. Kanály, značka a omezení</h3><p class="mut">Kanály jsou jen vaše přání. Žádný účet se tím nepropojuje a nic se nepublikuje.</p>'+fpChecks('shared.channels',FP_CH,d.channels,'channel')
  +'<div class="fg" style="margin-top:12px">'
  +fpField('shared.brand.tone','Tón komunikace',{ro:ro,max:200,ph:'např. přátelský, věcný'})
  +fpField('shared.brand.ordering','Jak si zákazník objedná',{ro:ro,max:500,ph:'telefon, online rezervace…'})
  +fpField('shared.brand.assets','Dostupné fotografie a logo',{ro:ro,max:500})
  +fpField('shared.brand.forbidden','Co nenabízíme nebo se nemá zmiňovat',{dt:'list',ro:ro,fmt:function(v){return (v||[]).join(', ')},help:'Oddělte čárkou. AI to nepoužije.'})
  +'</div><h4>Čím se chlubíte</h4><p class="mut">Jsou to vaše tvrzení. AI je nepovažuje za doložené a nevytvoří z nich srovnání s konkurencí ani záruky.</p>'
  +fpRows('shared.positioning.claims',(d.positioning||{}).claims,[['text','Tvrzení',{max:300,ro:ro}],['evidence','Doložení',{t:'select',ro:ro,opts:[['none','Nedoloženo'],['owner_statement','Tvrzení majitele'],['documented','Doloženo']]}]],10,'+ Tvrzení')
  +'<div class="fg" style="margin-top:12px">'+fpField('shared.constraints.notes','Další omezení nabídky',{t:'textarea',full:true,ro:ro,help:'Slevy, ceny, služby, které nechcete propagovat.'})+'</div></section>';
 return h}
function fpLocal(ro){
 return '<section class="card2 fsec"><h3>Lokalita'+(PS.info.is_root?'':' této pobočky')+'</h3><div class="fg">'
  +fpField('local.geography.city','Město <i>*</i>',{ro:ro,max:120})
  +fpField('local.geography.address','Adresa provozovny',{ro:ro,help:'Nepovinné. „Okolí Prahy“ není adresa.'})
  +fpField('local.geography.serviceArea','Obsluhovaná oblast',{ro:ro,help:'Např. okolí Prahy.'})
  +fpField('local.geography.radiusKm','Dojezd (km)',{dt:'int',ro:ro,max:3})
  +fpField('local.localNotes','Lokální odlišnosti',{t:'textarea',full:true,ro:ro,help:'Čím se tato provozovna liší od ostatních.'})
  +'</div></section>'}
function fpSharedSummary(){
 var s=PS.info.shared_from_root;if(!s)return '<div class="draft">Hlavní firma zatím nemá potvrzený profil. Společné údaje (služby, zákazníci, značka) vyplní a potvrdí vlastník nebo správce hlavní firmy.</div>';
 var d=s.data||{},id=d.identity||{};
 return '<section class="card2 fsec"><h3>Společné údaje hlavní firmy</h3><p class="mut">Jen ke čtení, spravuje je hlavní firma (potvrzená verze '+esc(s.version)+').</p><ul class="rows"><li><b>Název</b><span>'+esc(id.displayName||'–')+'</span></li><li><b>Činnost</b><span>'+esc(id.activity||'–')+'</span></li><li><b>Služby</b><span>'+esc(((d.services||{}).items||[]).map(function(x){return x.name}).join(', ')||'–')+'</span></li><li><b>Zákazníci</b><span>'+esc((d.audience||{}).description||'–')+'</span></li></ul></section>'}
function fpHead(){
 var i=PS.info,a=i.active,st='<span class="fst'+(a?' ok':'')+'" id="fpState">'+(a?'Potvrzeno: verze '+esc(a.version):'Zatím nepotvrzeno')+'</span>';
 var h='<div class="bar2"><div><h2 style="margin:0">Profil firmy pro AI</h2><p class="mut" style="margin:4px 0 0">Údaje, ze kterých bude AI vycházet. Vyplňujete ručně a vy je potvrzujete. AI nic nepublikuje a neutrácí.</p></div><div>'+st+' <span class="fst" id="fpSave" role="status" aria-live="polite"></span></div></div>';
 if(!i.can_write)h+='<div class="draft">Účet je teď jen pro čtení (skončila zkušební doba nebo předplatné). Profil si můžete prohlédnout, ukládat půjde po obnovení tarifu.</div>';
 if(!PS.schemaOk)h+='<div class="draft"><b>Aplikace a databáze mají jinou verzi formuláře.</b> Aby se nic nepoškodilo, ukládání je vypnuté. Obnovte stránku (Ctrl+F5).</div>';
 h+='<div id="fpConflict"></div>';return h}
function fpFoot(ro){
 var v=(PS.info.versions||[]);
 return '<section class="card2 fsec"><h3>Potvrzení profilu</h3><p class="mut">Potvrdit smí vlastník nebo správce. Potvrzuje se přesně ta verze, kterou vidíte. Pozdější úpravy vytvoří novou verzi a ta stará zůstane v historii.</p><div id="fpMissing"></div><div class="dact"><button type="button" class="pri" id="fpConfirm" data-fp="confirm"'+(ro?' disabled':'')+'>Potvrdit profil</button></div>'
  +(v.length?'<h4>Historie verzí</h4><ul class="rows">'+v.map(function(x){return '<li><b>Verze '+esc(x.version)+(PS.info.active&&PS.info.active.version===x.version?' (platná)':'')+'</b><span>'+fD(x.confirmed_at,true)+(x.by_me?' · potvrdili jste vy':'')+'</span></li>'}).join('')+'</ul>':'')+'</section>'}
function fpRender(){
 var root=A('fpRoot');if(!root)return;var ro=!PS.info.can_write||!PS.schemaOk;
 root.innerHTML=fpHead()+(PS.info.is_root?fpShared(ro):fpSharedSummary())+fpLocal(ro)+fpFoot(ro);
 fpUpdateStatus();fpUpdateDerived()}
/* ---- čtení formuláře ----
   Základem je kopie uloženého dokumentu: pole, která formulář nezobrazuje (např. doplní je pozdější krok), zůstanou.
   Pole zobrazená ve formuláři jsou závazná: prázdné pole se z dokumentu odstraní. Seznamy se přestaví od nuly. */
function fpDel(o,p){var k=p.split('.'),i,c=o;for(i=0;i<k.length-1;i++){c=c[k[i]];if(c==null)return}delete c[k[k.length-1]]}
function fpReadForm(){
 var root=A('fpRoot'),isRoot=PS.info.is_root,doc=JSON.parse(JSON.stringify(PS.doc||VXPCORE.emptyDoc(isRoot))),bad=[],restG=[];
 if(!doc.local)doc.local={};if(isRoot&&!doc.shared)doc.shared={};
 if(isRoot){var sh=doc.shared;if(sh.services)delete sh.services.items;if(sh.positioning)delete sh.positioning.claims;delete sh.channels;if(sh.financialContext)delete sh.financialContext.budgetIncludes;restG=(sh.goals||[]).slice(1);delete sh.goals}
 [].forEach.call(root.querySelectorAll('[data-p]'),function(el){
  var p=el.getAttribute('data-p'),t=el.getAttribute('data-t'),dt=el.getAttribute('data-dt')||'text',val=el.value,out;
  if(t==='select'){out=val===''?undefined:val}
  else if(dt==='money'){out=fpMinor(val);if(out!==out){bad.push(p);out=undefined}}
  else if(dt==='pct'){out=fpBp(val);if(out!==out){bad.push(p);out=undefined}}
  else if(dt==='int'){var s=String(val).replace(/\s/g,'');if(s===''){out=undefined}else if(!/^\d+$/.test(s)){bad.push(p);out=undefined}else out=Number(s)}
  else if(dt==='list'){out=val.split(',').map(function(x){return x.trim()}).filter(Boolean);if(!out.length)out=undefined}
  else{out=val===''?undefined:val}
  if(out===undefined)fpDel(doc,p);else fpSet(doc,p,out)});
 [].forEach.call(root.querySelectorAll('input[data-multi]:checked'),function(el){var p=el.getAttribute('data-multi'),k=el.getAttribute('data-key'),cur=fpGet(doc,p)||[];cur.push(k?(function(){var o={};o[k]=el.value;return o})():el.value);fpSet(doc,p,cur)});
 if(isRoot){
  var sv=(doc.shared.services||{}).items;if(sv){sv=sv.filter(function(x){return x&&x.name});if(sv.length)doc.shared.services.items=sv;else delete doc.shared.services.items}
  var cl=(doc.shared.positioning||{}).claims;if(cl){cl=cl.filter(function(x){return x&&x.text}).map(function(x){if(!x.evidence)x.evidence='owner_statement';return x});if(cl.length)doc.shared.positioning.claims=cl;else delete doc.shared.positioning.claims}
  var g=(doc.shared.goals||[])[0],gl=[];if(g&&Object.keys(g).length){if(!g.metric)g.metric='revenue';gl.push(g)}
  gl=gl.concat(restG);if(gl.length)doc.shared.goals=gl;else delete doc.shared.goals}
 return {doc:doc,bad:bad}}
function fpErrors(codes){
 var root=A('fpRoot');if(!root)return;[].forEach.call(root.querySelectorAll('[data-fe]'),function(e){e.textContent=''});var other=[];
 codes.forEach(function(c){var path=c.slice(0,c.lastIndexOf(':')).replace(/^\$\./,'').replace(/\[(\d+)\]/g,'.$1'),el=root.querySelector('[data-fe="'+path+'"]');if(el)el.textContent=VXPCORE.explain(c);else other.push(c)});
 if(other.length)fpSetStatus('Některé údaje nejsou ve správném tvaru ('+other.length+').','bad')}
function fpSetStatus(t,cls){PS.status=t;var e=A('fpSave');if(e){e.textContent=t;e.className='fst'+(cls?' '+cls:'')}}
function fpUpdateStatus(){fpSetStatus(PS.dirty?'Neuložené změny…':(PS.rev?'Uloženo (revize '+PS.rev+')':'Zatím nic uloženo'),PS.dirty?'':'ok')}
function fpUpdateDerived(){
 var root=A('fpRoot');if(!root||!PS.info)return;
 var r=fpReadForm(),doc=r.doc,isRoot=PS.info.is_root,calc=A('fpCalc');
 if(calc&&isRoot){var g=((doc.shared||{}).goals||[])[0],cur=(((doc.shared||{}).financialContext||{}).revenueCurrency)||'CZK',un=(g&&g.metric==='revenue')?(cur==='EUR'?' €':' Kč'):'';
  if(g&&g.baselineMinor!=null&&g.growthBp!=null){var t=VXPCORE.goalTarget(g.baselineMinor,g.growthBp),isM=g.metric==='revenue',f=function(m){return isM?(m/100).toLocaleString('cs-CZ',{maximumFractionDigits:2}):String(m/100)};
   calc.innerHTML='Cílová hodnota (výpočet): <b>'+esc(f(t))+esc(un)+'</b>, rozdíl <b>'+esc(f(t-g.baselineMinor))+esc(un)+'</b>. Jde o scénář, ne slib. Bez ceny zakázky, kapacity a údajů o poptávkách nelze říct, kolik zákazníků je k tomu potřeba.'}
  else calc.textContent='Vyplňte výchozí hodnotu a o kolik procent ji chcete zvýšit, cíl se dopočítá.'}
 var miss=VXPCORE.incomplete(doc,isRoot).map(fpLabel),m=A('fpMissing'),b=A('fpConfirm');
 if(m)m.innerHTML=miss.length?'<div class="draft">K potvrzení ještě chybí: '+miss.map(esc).join('; ')+'.</div>':'<p class="mut">Vše potřebné je vyplněno.</p>';
 if(b)b.disabled=!!miss.length||!PS.info.can_write||!PS.schemaOk||(!PS.rev&&!PS.dirty)}
/* ---- ukládání ---- */
function fpFormCanon(){var r=fpReadForm();return fpCanon(VXPCORE.trimDeep(r.doc))+'|'+r.bad.join(',')}
function fpSchedule(){if(!PS.dirty&&fpFormCanon()===PS.lastSent){fpUpdateDerived();return}PS.dirty=true;fpUpdateStatus();fpUpdateDerived();clearTimeout(PS.timer);PS.timer=setTimeout(fpSave,1500)}
async function fpSave(force){
 if(!PS.info||!A('fpRoot')||!PS.schemaOk||!PS.info.can_write||PS.conflict&&!force)return false;
 if(PS.saving){PS.again=true;return false}
 clearTimeout(PS.timer);var r=fpReadForm();
 if(r.bad.length){fpErrors(r.bad.map(function(p){return '$.'+p+':type'}));fpSetStatus('Zkontrolujte vyznačená pole.','bad');return false}
 var doc=VXPCORE.trimDeep(r.doc),errs=VXPCORE.validateDoc(VXPSCHEMA,doc,PS.info.is_root);
 if(errs.length){fpErrors(errs);fpSetStatus('Zkontrolujte vyznačená pole.','bad');return false}
 fpErrors([]);PS.saving=true;fpSetStatus('Ukládám…','');
 var res=await getSb().rpc('profile_save_draft',{cid:PS.cid,expected_revision:PS.rev,schema_version:VXPSCHEMA.version,doc:doc});
 PS.saving=false;
 if(res.error){var m=VXPCORE.mapRpcError(res.error);
  if(m.kind==='conflict'){PS.conflict=m;fpShowConflict(m);fpSetStatus('Konflikt verzí','bad')}
  else if(m.kind==='validation'){fpErrors(m.errors);fpSetStatus(m.message,'bad')}
  else if(m.kind==='schema'){PS.schemaOk=false;fpRender();toast(m.message,'err')}
  else fpSetStatus(m.message,'bad');
  return false}
 var d=res.data;PS.rev=d.revision;PS.hash=d.hash;PS.doc=d.data;PS.dirty=false;PS.conflict=null;PS.lastSent=fpFormCanon();fpUpdateStatus();fpUpdateDerived();
 if(PS.again){PS.again=false;PS.dirty=true;setTimeout(fpSave,50)}
 return true}
function fpShowConflict(m){var e=A('fpConflict');if(!e)return;
 e.innerHTML='<div class="draft"><b>Profil mezitím změnil někdo jiný</b>'+(m.current!=null?' (už je revize '+m.current+', vy máte '+PS.rev+')':'')+'. Nic jsme nepřepsali. Vyberte, jak pokračovat:<div class="dact"><button type="button" class="btn btn-main btn-sm" data-fp="reload">Načíst novější verzi (moje neuložené změny se zahodí)</button> <button type="button" class="btn btn-ghost btn-sm" data-fp="overwrite">Přepsat mojí verzí</button></div></div>'}
async function fpConfirm(){
 if(PS.dirty||PS.saving){var ok=await fpSave();if(!ok)return}
 var b=A('fpConfirm');if(b)b.disabled=true;
 var res=await getSb().rpc('profile_confirm',{cid:PS.cid,expected_revision:PS.rev,expected_hash:PS.hash});
 if(res.error){var m=VXPCORE.mapRpcError(res.error);
  if(m.kind==='conflict'){PS.conflict=m;fpShowConflict(m)}
  else if(m.kind==='validation'){toast('K potvrzení ještě něco chybí: '+m.errors.map(fpLabel).join('; '),'err')}
  else toast(m.message,'err');
  fpUpdateDerived();return}
 toast(res.data.unchanged?'Profil je beze změny, platí verze '+res.data.version+'.':'Profil potvrzen, platí verze '+res.data.version+'.','ok');
 await fpLoad(true)}
/* ---- načtení ---- */
async function fpLoad(keepScroll){
 var root=A('fpRoot');if(!root)return;
 if(DEMO){root.innerHTML='<div class="draft">V ukázce se profil neukládá. Po založení účtu ho zde vyplníte.</div>';return}
 var c=getSb(),cid=APP.cid;PS.cid=cid;PS.conflict=null;PS.dirty=false;
 var si=await c.rpc('profile_schema_info');
 if(si.error){root.innerHTML='<div class="draft">Profil firmy se nepodařilo načíst. Tato část vyžaduje aktualizaci databáze, která zatím nebyla provedena nebo na ni nemáte oprávnění ('+esc(si.error.message||'')+').</div>';return}
 PS.schemaOk=fpCanon(si.data.schema)===fpCanon(VXPSCHEMA)&&si.data.version===VXPSCHEMA.version;
 var r=await c.rpc('profile_get',{cid:cid});
 if(r.error){var m=VXPCORE.mapRpcError(r.error);root.innerHTML='<div class="draft">'+esc(m.message)+'</div>';return}
 PS.info=r.data;var d=r.data.draft;
 PS.rev=d?d.revision:0;PS.hash=d?d.hash:null;
 PS.doc=d?d.data:(r.data.active?r.data.active.data:VXPCORE.emptyDoc(r.data.is_root));
 if(!PS.doc.local)PS.doc.local={};if(r.data.is_root&&!PS.doc.shared)PS.doc.shared={};
 /* nic uloženého, ale existuje platná verze: formulář vychází z ní; první úprava založí koncept */
 fpRender();PS.lastSent=fpFormCanon()}
VIEWS.firmaprofil=function(){fpStyle();if(APP.role!=='owner'&&APP.role!=='admin')return '<div class="card2 soonc"><h2>Profil firmy</h2><p>Profil firmy upravuje vlastník nebo správce.</p></div>';
 return '<div class="fp" id="fpRoot"><p class="mut">Načítám profil firmy…</p></div>'};
AFTER.firmaprofil=function(){if(APP.role==='owner'||APP.role==='admin')fpLoad()};
if(!window.__fpBound){window.__fpBound=true;
 document.addEventListener('click',function(e){if(PS.dirty&&A('fpRoot')&&e.target.closest&&e.target.closest('[data-tab],[data-app]')&&!e.target.closest('#fpRoot'))fpSave()},true);
 document.addEventListener('input',function(e){if(e.target.closest&&e.target.closest('#fpRoot')&&(e.target.hasAttribute('data-p')))fpSchedule()});
 document.addEventListener('change',function(e){if(e.target.closest&&e.target.closest('#fpRoot')&&(e.target.hasAttribute('data-p')||e.target.hasAttribute('data-multi')))fpSchedule()});
 document.addEventListener('click',async function(e){
  var b=e.target.closest&&e.target.closest('#fpRoot [data-fp]');if(!b)return;var a=b.getAttribute('data-fp');
  if(a==='add'||a==='del'){var r=fpReadForm();PS.doc=VXPCORE.trimDeep(r.doc);if(!PS.info.is_root){}
   var base=b.getAttribute('data-base'),arr=fpGet(PS.doc,base)||[];
   if(a==='add')arr.push({});else arr.splice(Number(b.getAttribute('data-i')),1);fpSet(PS.doc,base,arr);
   /* prázdný řádek se do dokumentu nedostane, proto ho při překreslení jen přidáme do zobrazení */
   fpRender();fpSchedule();return}
  if(a==='confirm'){fpConfirm();return}
  if(a==='reload'){await fpLoad(true);return}
  if(a==='overwrite'){PS.rev=PS.conflict&&PS.conflict.current!=null?PS.conflict.current:PS.rev;PS.conflict=null;A('fpConflict').innerHTML='';await fpSave(true);return}})}

/* ---- Nastavení: aktivní firma a odkaz na profil ---- */
function fpSettingsCards(){
 var ms=APP.mships||[],h='';
 if(ms.length>1){
  var rows=ms.map(function(m){var c=m.companies||{};return {id:m.company_id,name:c.name||m.company_id,branch:!!c.parent_company_id,role:m.role,at:c.created_at||''}}).sort(function(a,b){return String(a.at).localeCompare(String(b.at))||String(a.id).localeCompare(String(b.id))});
  h+='<section class="card2"><h3>Aktivní firma</h3><p class="mut">Účet patří do více firem nebo poboček. Vyberte, se kterou právě pracujete. Oprávnění se vždy ověřují na serveru podle vybrané firmy.</p><form id="coForm" class="fg"><div class="f"><label for="coSel">Firma</label><select id="coSel">'
   +rows.map(function(r){return '<option value="'+esc(r.id)+'"'+(r.id===APP.cid?' selected':'')+'>'+esc(r.name)+(r.branch?' (pobočka)':'')+' – '+esc(ROLEN[r.role]||r.role)+'</option>'}).join('')
   +'</select></div><div class="f"><button class="btn btn-main btn-sm" type="submit">Přepnout</button></div></form></section>'}
 h+='<section class="card2"><h3>Profil firmy pro AI</h3><p class="mut">Společný profil firmy (služby, zákazníci, cíle, značka). Vyplňujete a potvrzujete ho ručně, AI z něj bude vycházet. Dostupné ve všech tarifech.</p><div class="dact"><button type="button" class="btn btn-main btn-sm" data-tab="firmaprofil">Otevřít profil firmy</button></div></section>';
 return h}
document.addEventListener('submit',function(e){
 if(!e.target||e.target.id!=='coForm')return;e.preventDefault();
 var v=A('coSel').value;try{localStorage.setItem('vx_active_company_'+APP.user.id,v)}catch(x){}
 if(v!==APP.cid)openApp()});
