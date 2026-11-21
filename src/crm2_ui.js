/* ===== CRM 2: stavy klientů, země EU, štítky, připomenutí, karta klienta, duplicity, úspěšnost obchodů ===== */
var CRMCS=[['active','Aktivní'],['lead','Potenciální'],['inactive','Neaktivní']];
function crmCsL(k){var x=CRMCS.filter(function(s){return s[0]===k})[0];return x?x[1]:'Aktivní'}
var CRMLOST=['Příliš drahé','Vybral konkurenci','Bez odezvy','Nevhodné načasování','Nesplňujeme požadavky','Jiný důvod'];
APP.crmF={st:'',tag:'',cc:''};APP.crmTagList=[];
/* Zjistí, zda je v databázi použitá migrace CRM 2 (schema_crm2.sql). Dokud není, aplikace funguje po staru a nic nerozbije. */
async function crmProbe(){
 if(APP.crm2&&APP.crm2.cust&&APP.crm2.task&&APP.crm2.deal)return;
 var c=getSb(),P={cust:true,task:true,deal:true};
 try{var a=await c.from('customers').select('status,country_code,tags,next_contact_on').limit(1);P.cust=!a.error;
  var b=await c.from('tasks').select('customer_id').limit(1);P.task=!b.error;
  var d=await c.from('deals').select('lost_reason,closed_at').limit(1);P.deal=!d.error}catch(e){P={cust:false,task:false,deal:false}}
 APP.crm2=P}
function crmTagsOf(c){return String(c&&c.tags||'').split(',').map(function(t){return t.trim()}).filter(Boolean)}
function crmNormTags(t){var seen={},o=[];String(t||'').split(',').forEach(function(x){x=x.trim().replace(/\s+/g,' ');var k=x.toLowerCase();if(x&&!seen[k]){seen[k]=1;o.push(x.slice(0,30))}});return o.join(', ')}
/* Kontrola údajů klienta před uložením. Vrací text chyby, nebo prázdný řetězec. Upravuje hodnoty (IČ DPH velkými písmeny bez mezer, web s https://). */
function crmCustCheck(r,id){
 var cur=id?crmCust(id):null,cc=r.country_code!==undefined?r.country_code:(cur?cur.country_code:null);
 if(r.dic===null)r.dic='';if(r.ico===null)r.ico='';
 if(r.dic){var v=VXEU.vatOk(r.dic,cc);if(!v.ok)return v.reason;r.dic=v.normalized;
  if(!crm2On('cust')&&!/^CZ[0-9]{8,10}$/.test(r.dic))return 'Databáze zatím podporuje jen české DIČ (CZ…). Zahraniční IČ DPH půjde ukládat po aktualizaci databáze.'}
 if(r.ico){if(cc==='CZ'&&!/^[0-9]{8}$/.test(r.ico))return 'České IČO musí mít 8 číslic.';if(!crm2On('cust')&&!/^[0-9]{8}$/.test(r.ico))return 'Databáze zatím podporuje jen české IČO (8 číslic). Zahraniční čísla půjdou ukládat po aktualizaci databáze.'}
 if(r.website){if(!/^https?:\/\//i.test(r.website))r.website='https://'+r.website;if(r.website.length>300||/\s/.test(r.website))return 'Zkontrolujte adresu webu.'}
 if(r.tags!=null)r.tags=crmNormTags(r.tags);
 if(r.source&&r.source.length>100)return 'Zdroj klienta je příliš dlouhý.';
 return ''}
function crmToday(){return locD(new Date())}
function crmDays(a,b){return Math.round((new Date(b)-new Date(a))/864e5)}
function crmLastContact(cid){var l=0;APP.d.client_notes.rows.forEach(function(n){if(n.customer_id===cid){var t=new Date(n.created_at).getTime();if(t>l)l=t}});return l}
/* ---- co je potřeba vyřídit ---- */
function crmDue(){var d=APP.d,td=crmToday(),out=[],now=Date.now();
 d.customers.rows.forEach(function(c){if(c.next_contact_on&&c.next_contact_on<=td)out.push({k:'cust',id:c.id,cid:c.id,t:'Kontaktovat: '+custName(c),w:c.next_contact_on})});
 d.tasks.rows.forEach(function(t){if(!t.completed&&t.customer_id&&t.due_at&&locD(t.due_at)<=td&&crmCust(t.customer_id))out.push({k:'task',id:t.id,cid:t.customer_id,t:t.title+' · '+custName(crmCust(t.customer_id)),w:locD(t.due_at)})});
 d.deals.rows.forEach(function(x){if(x.stage!=='won'&&x.stage!=='lost'&&x.expected_close&&x.expected_close<td)out.push({k:'deal',id:x.id,cid:x.customer_id,t:'Případ po očekávaném uzavření: '+x.title,w:x.expected_close})});
 d.quotes.rows.forEach(function(q){var age=Math.floor((now-new Date(q.created_at))/864e5);if(q.status==='sent'&&age>=7)out.push({k:'quote',id:q.id,cid:q.customer_id,t:'Nabídka bez odpovědi '+age+' dní: '+(q.number||q.title||''),w:locD(q.created_at)})});
 return out.sort(function(a,b){return a.w<b.w?-1:1})}
function crmDueHtml(){var du=crmDue();if(!du.length)return '<div class="card2 c2due ok"><b>Dnes k vyřízení</b><p class="mut">Nic nehoří. Připomenutí kontaktů, úkoly u klientů, nabídky bez odpovědi i opožděné případy se objeví tady.</p></div>';
 var td=crmToday();
 return '<div class="card2 c2due"><b>Dnes k vyřízení <em>'+du.length+'</em></b><ul class="rows">'+du.slice(0,8).map(function(x){var late=x.w<td;
  var btn=x.k==='cust'?'<button type="button" class="lnk" data-c2="cdone:'+esc(x.id)+'">Hotovo</button><button type="button" class="lnk" data-c2="csnooze:'+esc(x.id)+'">Odložit o 7 dní</button>':
   x.k==='task'?'<button type="button" class="lnk" data-c2="tdone:'+esc(x.id)+':list">Splněno</button>':
   x.k==='deal'?'<button type="button" class="lnk" data-tab="pripady">Otevřít případy</button>':'<button type="button" class="lnk" data-tab="nabidky">Otevřít nabídky</button>';
  return '<li><div>'+(x.cid?'<b data-c2="card:'+esc(x.cid)+'" tabindex="0" role="button">':'<b>')+esc(x.t)+'</b><small class="'+(late?'c2late':'')+'">'+(late?'po termínu od ':'dnes · ')+fD(x.w)+'</small></div><span class="c2act">'+btn+'</span></li>'}).join('')+'</ul>'+(du.length>8?'<p class="mut fine">A dalších '+(du.length-8)+'.</p>':'')+'</div>'}
/* ---- seznam klientů ---- */
VIEWS.zakaznici=function(){
 var d=APP.d,x=d.customers,rs=x.rows.slice(),n2=crm2On('cust'),F=APP.crmF,td=crmToday();
 var h=csTools('customers')+'<div class="bar2"><input class="srch" type="search" placeholder="Hledat klienta…" aria-label="Hledat"><span class="c2tools">'+(n2?'<button type="button" class="btn btn-ghost btn-sm" data-c2="dups">Najít duplicity</button>':'')+'<button type="button" class="btn btn-main btn-sm" data-new="customers">+ Nový zákazník</button></span></div>'+errBox(x);
 if(!n2)h+='<div class="card2 note"><b>Rozšířené CRM čeká na aktualizaci databáze.</b> Země, stavy klientů, štítky, připomenutí a sloučení duplicit se zapnou, jakmile bude v databázi provedena migrace <code>schema_crm2.sql</code>. Základní evidence klientů funguje dál.</div>';
 if(n2){
  var ccs={},tg={},lead=0,stale=0,now=Date.now();
  rs.forEach(function(c){if(c.country_code)ccs[c.country_code]=1;crmTagsOf(c).forEach(function(t){tg[t]=(tg[t]||0)+1});if(c.status==='lead')lead++;
   if((c.status||'active')==='active'){var lc=crmLastContact(c.id),base=lc||new Date(c.created_at).getTime();if(now-base>90*864e5)stale++}});
  var due=crmDue().length;
  h+='<div class="ivkpi"><div><small>Klientů</small><b>'+rs.length+'</b><em>'+Object.keys(ccs).length+' '+plural(Object.keys(ccs).length,'stát','státy','států')+'</em></div><div><small>Potenciální</small><b>'+lead+'</b><em>zatím neobchodovali</em></div><div><small>K vyřízení dnes</small><b>'+due+'</b><em>kontakty, úkoly, nabídky</em></div><div><small>Bez záznamu 90+ dní</small><b>'+stale+'</b><em>aktivní klienti k oživení</em></div></div>';
  h+=crmDueHtml();
  var tl=Object.keys(tg).sort(function(a,b){return tg[b]-tg[a]||a.localeCompare(b,'cs')}).slice(0,12);APP.crmTagList=tl;
  h+='<div class="c2chips" role="group" aria-label="Filtr klientů">'+[['','Všichni']].concat(CRMCS).map(function(s){return '<button type="button" class="c2chip" data-c2="f:st:'+s[0]+'" aria-pressed="'+(F.st===s[0])+'">'+esc(s[1])+'</button>'}).join('')
   +(Object.keys(ccs).length>1?'<select class="c2sel" id="c2cc" aria-label="Stát"><option value="">Všechny státy</option>'+Object.keys(ccs).sort().map(function(k){return '<option value="'+k+'"'+(F.cc===k?' selected':'')+'>'+esc(VXEU.nameOf(k))+'</option>'}).join('')+'</select>':'')
   +tl.map(function(t,i){return '<button type="button" class="c2chip tag" data-c2="f:tag:'+i+'" aria-pressed="'+(F.tag===t)+'">#'+esc(t)+'</button>'}).join('')+'</div>';
  rs=rs.filter(function(c){return (!F.st||(c.status||'active')===F.st)&&(!F.cc||c.country_code===F.cc)&&(!F.tag||crmTagsOf(c).indexOf(F.tag)>=0)})}
 if(!rs.length)return h+'<p class="mut">'+(x.rows.length?'Filtru neodpovídá žádný klient.':'Zatím žádní zákazníci.')+'</p>';
 rs.sort(function(a,b){return String(custName(a)).localeCompare(String(custName(b)),'cs')});
 var td2=crmToday();
 return h+'<ul class="rows big" id="lst">'+rs.map(function(c){var tg2=crmTagsOf(c),ov=c.next_contact_on&&c.next_contact_on<=td2;
  return '<li data-c2="card:'+esc(c.id)+'" tabindex="0" role="button"><div><b>'+esc(custName(c))+'</b><small>'+[c.email,c.phone,c.country_code&&n2?VXEU.nameOf(c.country_code):''].filter(Boolean).map(esc).join(' · ')+(tg2.length?' · '+tg2.map(function(t){return '#'+esc(t)}).join(' '):'')+'</small></div>'
   +(n2?'<span class="c2r"><span class="c2b '+esc(c.status||'active')+'">'+esc(crmCsL(c.status))+'</span>'+(c.next_contact_on?'<small class="'+(ov?'c2late':'')+'">kontakt '+fD(c.next_contact_on)+'</small>':'')+'</span>':'')+'</li>'}).join('')+'</ul>'};
/* ---- karta klienta ---- */
function crmRelated(cid){var d=APP.d;return {jobs:d.jobs.rows.filter(function(j){return j.customer_id===cid}),deals:d.deals.rows.filter(function(x){return x.customer_id===cid}),quotes:d.quotes.rows.filter(function(q){return q.customer_id===cid}),
 notes:d.client_notes.rows.filter(function(n){return n.customer_id===cid}),tasks:d.tasks.rows.filter(function(t){return t.customer_id===cid}),res:d.reservations.rows.filter(function(r){return r.customer_id===cid}),
 inv:d.invoices.rows.filter(function(f){var cs=f.customer_snapshot&&typeof f.customer_snapshot==='object'?f.customer_snapshot:{},c=crmCust(cid);return cs.id===cid||(c&&cs.name&&cs.name===custName(c))})}}
function crmEvents(cid){var R=crmRelated(cid),ev=[];
 R.jobs.forEach(function(j){ev.push({t:j.created_at,k:'Zakázka',s:j.title+(j.price!=null?' · '+fM(j.price):'')})});
 R.inv.forEach(function(f){ev.push({t:f.issued_on||f.created_at,k:'Faktura',s:(f.number||'koncept')+' · '+fM(f.total,f.currency)+' · '+ivStatus(f).t})});
 R.quotes.forEach(function(q){ev.push({t:q.created_at,k:'Nabídka',s:(q.number||'')+' · '+fM(q.total,q.currency)+' · '+(CRMQ[q.status]||'')})});
 R.deals.forEach(function(x){ev.push({t:x.closed_at||x.created_at,k:x.stage==='won'?'Vyhraný případ':(x.stage==='lost'?'Prohraný případ':'Obchodní případ'),s:x.title+' · '+fM(x.value)+(x.stage==='lost'&&x.lost_reason?' · '+x.lost_reason:'')})});
 R.res.forEach(function(r){ev.push({t:r.starts_at,k:'Rezervace',s:r.title})});
 R.tasks.filter(function(t){return t.completed}).forEach(function(t){ev.push({t:t.due_at||t.created_at,k:'Splněný úkol',s:t.title})});
 R.notes.forEach(function(n){ev.push({t:n.created_at,k:CRMK[n.kind]||'Poznámka',s:n.body})});
 return ev.sort(function(a,b){return new Date(b.t)-new Date(a.t)})}
function crmCard(cid){var c=crmCust(cid);if(!c)return;APP.crmC=cid;var R=crmRelated(cid),n2=crm2On('cust'),t2=crm2On('task');
 var paid={},open=0;R.inv.forEach(function(f){if(f.paid_at){var cu=f.currency||'CZK';paid[cu]=(paid[cu]||0)+Number(f.total||0)}});R.deals.forEach(function(x){if(x.stage!=='won'&&x.stage!=='lost')open+=Number(x.value||0)});
 var paidT=Object.keys(paid).map(function(k){return fM(Math.round(paid[k]*100)/100,k)}).join(' + ')||'–';
 var openTasks=R.tasks.filter(function(t){return !t.completed}).sort(function(a,b){return new Date(a.due_at||'2999')-new Date(b.due_at||'2999')});
 var ev=crmEvents(cid),tg=crmTagsOf(c),vat=c.dic&&VXEU.vatOk(c.dic,c.country_code).ok;
 modal('<div class="c2card"><div class="c2h"><div><h3>'+esc(custName(c))+'</h3><div class="c2meta">'+(n2?'<span class="c2b '+esc(c.status||'active')+'">'+esc(crmCsL(c.status))+'</span>':'')+(c.country_code&&n2?'<span>'+esc(VXEU.nameOf(c.country_code))+'</span>':'')+(tg.length?tg.map(function(t){return '<span class="c2b tag">#'+esc(t)+'</span>'}).join(''):'')+'</div></div></div>'
  +'<ul class="rows c2info">'+(c.email?'<li><b>E-mail</b><span><a href="mailto:'+esc(c.email)+'">'+esc(c.email)+'</a></span></li>':'')+(c.phone?'<li><b>Telefon</b><span><a href="tel:'+esc(String(c.phone).replace(/[^+\d]/g,''))+'">'+esc(c.phone)+'</a></span></li>':'')
  +(c.billing_address?'<li><b>Adresa</b><span>'+esc(c.billing_address)+'</span></li>':'')+(c.ico?'<li><b>IČO / reg. číslo</b><span>'+esc(c.ico)+'</span></li>':'')+(c.dic?'<li><b>IČ DPH</b><span>'+esc(c.dic)+(vat?' <em class="mut">(tvar sedí, platnost ověřte ve VIES)</em>':'')+'</span></li>':'')
  +(c.website?'<li><b>Web</b><span><a href="'+esc(c.website)+'" target="_blank" rel="noopener noreferrer">'+esc(c.website)+'</a></span></li>':'')+(c.source?'<li><b>Zdroj</b><span>'+esc(c.source)+'</span></li>':'')
  +(c.next_contact_on?'<li><b>Další kontakt</b><span class="'+(c.next_contact_on<=crmToday()?'c2late':'')+'">'+fD(c.next_contact_on)+'</span></li>':'')+'</ul>'
  +(c.notes?'<p class="mut c2note">'+esc(c.notes)+'</p>':'')
  +'<div class="ivkpi"><div><small>Zaplaceno</small><b>'+paidT+'</b><em>'+R.inv.filter(function(f){return f.paid_at}).length+' faktur</em></div><div><small>Otevřené případy</small><b>'+fM(open)+'</b><em>'+R.deals.filter(function(x){return x.stage!=='won'&&x.stage!=='lost'}).length+' případů</em></div><div><small>Zakázky</small><b>'+R.jobs.length+'</b><em>'+R.res.length+' rezervací</em></div></div>'
  +'<div class="dact c2acts"><button type="button" class="btn btn-main btn-sm" data-c2="edit:'+esc(cid)+'">Upravit údaje</button><button type="button" class="btn btn-ghost btn-sm" data-c2="deal:'+esc(cid)+'">+ Obchodní případ</button><button type="button" class="btn btn-ghost btn-sm" data-c2="quote:'+esc(cid)+'">+ Nabídka</button></div>'
  +'<section class="c2sec"><h4>Zapsat kontakt</h4><form id="c2Note"><div class="fg"><div class="f"><label for="c2K">Druh</label><select id="c2K">'+Object.keys(CRMK).map(function(k){return '<option value="'+k+'">'+CRMK[k]+'</option>'}).join('')+'</select></div>'
  +(n2?'<div class="f"><label for="c2N">Další kontakt</label><select id="c2N"><option value="">neměnit</option><option value="0">bez připomenutí</option><option value="3">za 3 dny</option><option value="7">za týden</option><option value="14">za 2 týdny</option><option value="30">za měsíc</option><option value="90">za 3 měsíce</option></select></div>':'')
  +'<div class="f full"><label for="c2B">Zápis <i>*</i></label><textarea id="c2B" rows="2" maxlength="4000"></textarea></div></div><div class="st" id="entSt" role="status"></div><div class="dact"><button class="pri sm" type="submit">Uložit záznam</button></div></form></section>'
  +(t2?'<section class="c2sec"><h4>Úkoly u klienta</h4>'+(openTasks.length?'<ul class="rows">'+openTasks.map(function(t){var late=t.due_at&&locD(t.due_at)<crmToday();return '<li><div><b>'+esc(t.title)+'</b><small class="'+(late?'c2late':'')+'">'+(t.due_at?fD(t.due_at):'bez termínu')+'</small></div><button type="button" class="lnk" data-c2="tdone:'+esc(t.id)+':card">Splněno</button></li>'}).join('')+'</ul>':'<p class="mut fine">Žádné otevřené úkoly.</p>')
   +'<form id="c2Task" class="c2tf"><input id="c2TT" maxlength="200" placeholder="Nový úkol (např. Poslat kalkulaci)" aria-label="Nový úkol"><input id="c2TD" type="date" aria-label="Termín"><button class="btn btn-ghost btn-sm" type="submit">+ Úkol</button></form></section>':'')
  +'<section class="c2sec"><h4>Historie</h4>'+(ev.length?'<ul class="rows tl">'+ev.map(function(e){return '<li><div><b>'+esc(e.k)+'</b><small>'+fD(e.t)+'</small></div><span>'+esc(e.s)+'</span></li>'}).join('')+'</ul>':'<p class="mut">U tohoto klienta zatím nic není.</p>')+'</section>'
  +'<div class="dact"><button class="btn btn-ghost btn-sm" type="button" data-app="mclose">Zavřít</button></div></div>');
 var mb=document.querySelector('#appModal .mbox');if(mb)mb.classList.add('wide')}
/* ---- úspěšnost obchodů ---- */
var _crmPv=VIEWS.pripady;
VIEWS.pripady=function(){
 var rs=APP.d.deals.rows,lim=Date.now()-90*864e5,closed=rs.filter(function(x){return (x.stage==='won'||x.stage==='lost')&&new Date(x.closed_at||x.updated_at||x.created_at).getTime()>=lim}),
  won=closed.filter(function(x){return x.stage==='won'}),lost=closed.filter(function(x){return x.stage==='lost'}),
  rate=closed.length?Math.round(100*won.length/closed.length):null,avg=won.length?Math.round(won.reduce(function(s,x){return s+Number(x.value||0)},0)/won.length):null,
  cyc=won.filter(function(x){return x.closed_at}).map(function(x){return crmDays(x.created_at,x.closed_at)}),cycA=cyc.length?Math.round(cyc.reduce(function(a,b){return a+b},0)/cyc.length):null,
  rc={};lost.forEach(function(x){if(x.lost_reason)rc[x.lost_reason]=(rc[x.lost_reason]||0)+1});var top=Object.keys(rc).sort(function(a,b){return rc[b]-rc[a]})[0];
 var stale=rs.filter(function(x){return x.stage!=='won'&&x.stage!=='lost'&&Date.now()-new Date(x.updated_at||x.created_at)>14*864e5});
 var st='<div class="ivkpi"><div><small>Úspěšnost za 90 dní</small><b>'+(rate==null?'–':rate+' %')+'</b><em>'+won.length+' vyhráno, '+lost.length+' prohráno</em></div><div><small>Průměrný vyhraný obchod</small><b>'+(avg==null?'–':fM(avg))+'</b><em>'+(cycA==null?'doba uzavření zatím neznámá':'uzavření průměrně za '+cycA+' dní')+'</em></div><div><small>Nejčastější důvod prohry</small><b class="c2sm">'+(top?esc(top):'–')+'</b><em>'+(top?rc[top]+'×':'zapisuje se při prohře')+'</em></div></div>'
  +(stale.length?'<div class="card2 note"><b>Bez pohybu 14+ dní:</b> '+stale.slice(0,5).map(function(x){return esc(x.title)}).join(', ')+(stale.length>5?' a další ('+stale.length+')':'')+'. Posuňte je dál, nebo je uzavřete jako prohrané.</div>':'');
 return _pv_wrap(st)};
function _pv_wrap(st){var h=_crmPv();var i=h.indexOf('<div class="kbn">');return i<0?h+st:h.slice(0,i)+st+h.slice(i)}
async function crmMove(id,dir){var d=APP.d.deals.rows.filter(function(x){return x.id===id})[0];if(!d)return;var i=CRMST.findIndex(function(s){return s[0]===d.stage})+dir;if(i<0||i>=CRMST.length)return;
 if(CRMST[i][0]==='lost'&&crm2On('deal')){crmLostAsk(id);return}
 var r=await getSb().from('deals').update({stage:CRMST[i][0],probability:CRMST[i][2],updated_at:new Date().toISOString()}).eq('id',id);if(r.error){toast('Případ se nepodařilo posunout: '+r.error.message,'err');return}await refresh();appTab('pripady')}
function crmLostAsk(id){var d=APP.d.deals.rows.filter(function(x){return x.id===id})[0];if(!d)return;
 modal('<h3>Proč se případ nepodařil?</h3><p class="mut">„'+esc(d.title)+'“ se označí jako prohraný. Důvod pomůže příště. Ukáže se v přehledu úspěšnosti.</p><form id="c2Lost" data-id="'+esc(id)+'"><div class="fg"><div class="f full"><label for="c2LR">Důvod</label><select id="c2LR">'+CRMLOST.map(function(r){return '<option>'+esc(r)+'</option>'}).join('')+'</select></div><div class="f full"><label for="c2LT">Poznámka (nepovinné)</label><input id="c2LT" maxlength="200"></div></div><div class="st" id="entSt" role="status"></div><div class="dact"><button class="pri" type="submit">Označit jako prohraný</button><button class="btn btn-ghost" type="button" data-app="mclose">Zrušit</button></div></form>')}
/* ---- duplicity ---- */
function crmNorm(s){return String(s||'').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/\b(s\.?\s?r\.?\s?o\.?|a\.?\s?s\.?|spol|gmbh|sp\.? z o\.?o\.?|ltd|inc|sro|ag|bv|sa|kg|oy|ab)(?=\W|$)/g,' ').replace(/[^a-z0-9]+/g,' ').trim()}
function crmDupGroups(){var rs=APP.d.customers.rows,par=rs.map(function(_,i){return i}),why={};
 function find(i){while(par[i]!==i){par[i]=par[par[i]];i=par[i]}return i}
 function uni(a,b,r){var x=find(a),y=find(b);if(x!==y)par[x]=y;why[a]=why[a]||{};why[a][r]=1;why[b]=why[b]||{};why[b][r]=1}
 var keys={};
 rs.forEach(function(c,i){
  var e=String(c.email||'').trim().toLowerCase(),p=String(c.phone||'').replace(/\D/g,'').slice(-9),ic=String(c.ico||'').replace(/[^A-Za-z0-9]/g,'').toUpperCase(),n=crmNorm(custName(c));
  [['e:'+e,e,'stejný e-mail'],['p:'+p,p.length>=9,'stejný telefon'],['i:'+ic,ic.length>=6,'stejné IČO'],['n:'+n,n.length>=3,'podobný název']].forEach(function(k){if(!k[1])return;if(keys[k[0]]!==undefined)uni(keys[k[0]],i,k[2]);else keys[k[0]]=i})});
 var g={};rs.forEach(function(c,i){var r=find(i);(g[r]=g[r]||[]).push(i)});
 return Object.keys(g).filter(function(k){return g[k].length>1}).map(function(k){var idx=g[k],reasons={};idx.forEach(function(i){Object.keys(why[i]||{}).forEach(function(r){reasons[r]=1})});
  var cs=idx.map(function(i){return rs[i]});return {cs:cs,why:Object.keys(reasons)}})}
function crmDupWeight(c){var R=crmRelated(c.id);return R.jobs.length*3+R.deals.length*3+R.quotes.length*2+R.notes.length+R.res.length+R.tasks.length+(c.email?1:0)+(c.phone?1:0)+(c.ico?1:0)}
function crmDups(){var gs=crmDupGroups();APP.crmDG=gs;
 modal('<h3>Možné duplicity</h3><p class="mut">Hledáme klienty se stejným e-mailem, telefonem, IČO nebo podobným názvem. Při sloučení se zakázky, rezervace, případy, nabídky, záznamy a úkoly přesunou na vybraného klienta, prázdná pole se doplní a duplicita se <b>archivuje</b> (nesmaže). Fakturám se nic nemění.</p>'
  +(gs.length?gs.map(function(g,gi){var best=g.cs.slice().sort(function(a,b){return crmDupWeight(b)-crmDupWeight(a)})[0];
   return '<section class="card2 c2dup" data-g="'+gi+'"><small class="mut">'+esc(g.why.join(', '))+'</small><ul class="rows">'+g.cs.map(function(c){return '<li><label class="chk"><input type="radio" name="dk'+gi+'" value="'+esc(c.id)+'"'+(c.id===best.id?' checked':'')+'><span><b>'+esc(custName(c))+'</b> <small class="mut">'+[c.email,c.phone,c.ico].filter(Boolean).map(esc).join(' · ')+'</small></span></label></li>'}).join('')+'</ul><div class="dact"><button type="button" class="btn btn-ghost btn-sm" data-c2="merge:'+gi+'">Sloučit do vybraného</button></div></section>'}).join(''):'<p class="mut">Žádné duplicity jsme nenašli.</p>')
  +'<div class="st" id="entSt" role="status"></div><div class="dact"><button class="btn btn-ghost btn-sm" type="button" data-app="mclose">Zavřít</button></div>');
 var mb=document.querySelector('#appModal .mbox');if(mb)mb.classList.add('wide')}
async function crmMerge(gi){var g=APP.crmDG&&APP.crmDG[gi];if(!g)return;var sec=document.querySelector('.c2dup[data-g="'+gi+'"]'),sel=sec&&sec.querySelector('input:checked');if(!sel)return;
 var keep=sel.value,others=g.cs.filter(function(c){return c.id!==keep});
 if(!confirm('Sloučit '+others.length+' '+plural(others.length,'záznam','záznamy','záznamů')+' do klienta „'+custName(crmCust(keep))+'“? Duplicity se archivují, jejich zakázky a historie se přesunou. Zpět to jde jen ručně.'))return;
 var b=sec.querySelector('button[data-c2]');if(b)b.disabled=true;
 try{for(var i=0;i<others.length;i++){var r=await getSb().rpc('crm_merge_customers',{cid:APP.cid,keep_id:keep,drop_id:others[i].id});if(r.error)throw r.error}
  await refresh();appTab('zakaznici');crmDups();toast('Klienti sloučeni.','ok')}
 catch(ex){if(b)b.disabled=false;entMsg('Sloučení se nepodařilo: '+String(ex&&ex.message||ex))}}
/* ---- ovládání ---- */
async function crmUpd(t,id,row,msg){var r=await getSb().from(t).update(row).eq('id',id).eq('company_id',APP.cid);if(r.error){toast('Nepodařilo se uložit: '+r.error.message,'err');return false}await refresh();if(msg)toast(msg,'ok');return true}
document.addEventListener('click',async function(e){var t=e.target.closest('#vxapp [data-c2]');if(!t)return;var p=t.dataset.c2.split(':'),k=p[0];
 if(k==='card'){crmCard(p[1]);return}
 if(k==='edit'){closeModal();openForm('customers',p[1]);return}
 if(k==='deal'){closeModal();openForm('deals',null,{customer_id:p[1],stage:'new',probability:10});return}
 if(k==='quote'){closeModal();quoteEditor(null,{customer_id:p[1]});return}
 if(k==='dups'){crmDups();return}
 if(k==='merge'){crmMerge(Number(p[1]));return}
 if(k==='f'){if(p[1]==='st')APP.crmF.st=p[2];else if(p[1]==='tag'){var tg=APP.crmTagList[Number(p[2])];APP.crmF.tag=APP.crmF.tag===tg?'':tg}appTab('zakaznici');return}
 if(k==='cdone'){if(await crmUpd('customers',p[1],{next_contact_on:null},'Připomenutí splněno.'))appTab(APP.tab);return}
 if(k==='csnooze'){if(await crmUpd('customers',p[1],{next_contact_on:locD(new Date(Date.now()+7*864e5))},'Odloženo o 7 dní.'))appTab(APP.tab);return}
 if(k==='tdone'){if(await crmUpd('tasks',p[1],{completed:true},'Úkol splněn.')){if(p[2]==='card')crmCard(APP.crmC);else appTab(APP.tab)}return}});
document.addEventListener('keydown',function(e){if(e.key!=='Enter'&&e.key!==' ')return;var t=e.target;if(t&&t.matches&&t.matches('#vxapp [data-c2="card"],#vxapp li[data-c2^="card:"],#vxapp b[data-c2^="card:"]')){e.preventDefault();t.click()}});
document.addEventListener('change',function(e){if(e.target&&e.target.id==='c2cc'){APP.crmF.cc=e.target.value;appTab('zakaznici')}});
document.addEventListener('submit',async function(e){var f=e.target;
 if(f.id==='c2Note'){e.preventDefault();e.stopImmediatePropagation();var b=A('c2B').value.trim();if(!b){entMsg('Napište text záznamu.');return}
  var r=await getSb().from('client_notes').insert({company_id:APP.cid,customer_id:APP.crmC,kind:A('c2K').value,body:b});if(r.error){entMsg('Záznam se nepodařilo uložit: '+r.error.message);return}
  var nx=A('c2N');if(nx&&nx.value!==''){var dd=Number(nx.value);await getSb().from('customers').update({next_contact_on:dd?locD(new Date(Date.now()+dd*864e5)):null}).eq('id',APP.crmC).eq('company_id',APP.cid)}
  await refresh();crmCard(APP.crmC);toast('Záznam uložen.','ok');return}
 if(f.id==='c2Task'){e.preventDefault();e.stopImmediatePropagation();var tt=A('c2TT').value.trim();if(!tt){toast('Napište, co je potřeba udělat.','err');return}var dv=A('c2TD').value;
  var r2=await getSb().from('tasks').insert({company_id:APP.cid,title:tt.slice(0,200),due_at:dv?new Date(dv+'T12:00:00').toISOString():null,customer_id:APP.crmC});if(r2.error){toast('Úkol se nepodařilo uložit: '+r2.error.message,'err');return}
  await refresh();crmCard(APP.crmC);toast('Úkol přidán.','ok');return}
 if(f.id==='c2Lost'){e.preventDefault();e.stopImmediatePropagation();var id=f.dataset.id,rs=A('c2LR').value,tx=A('c2LT').value.trim(),reason=(rs+(tx?': '+tx:'')).slice(0,300);
  var r3=await getSb().from('deals').update({stage:'lost',probability:0,lost_reason:reason,updated_at:new Date().toISOString()}).eq('id',id);if(r3.error){entMsg('Nepodařilo se uložit: '+r3.error.message);return}
  closeModal();await refresh();appTab('pripady');toast('Případ označen jako prohraný.','ok')}},true);
