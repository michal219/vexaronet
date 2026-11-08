/* ===== AI Marketing Autopilot: průchod strategie → obsah → schválení → publikace → výsledky =====
   Data: mkt_state / mkt_results (DB, podle firmy a role), AI jen přes /api/ai-marketing (limity a vypínač vynucuje server).
   Idempotenční klíč požadavku se drží v localStorage, takže obnovení stránky ani opakované kliknutí nespustí AI podruhé.
   Viz docs/AI_DOKONCENI.md. */
var MK={st:null,res:null,err:null,cid:null,busy:{},loaded:false};
var MK_MET={poptavky:'poptávek',zakaznici:'nových zákazníků',rezervace:'rezervací',objednavky:'objednávek'};
var MK_SYS={poptavky:'Poptávky',zakaznici:'Noví zákazníci',rezervace:'Rezervace',objednavky:'Objednávky'};
var MK_RMET={dosah:'Dosah',zobrazeni:'Zobrazení',prokliky:'Prokliky',reakce:'Reakce',komentare:'Komentáře',sdileni:'Sdílení',zpravy:'Zprávy',jine:'Jiné'};
function mkLs(k){try{var v=localStorage.getItem(k);return v?JSON.parse(v):null}catch(e){return null}}
function mkLsSet(k,v){try{localStorage.setItem(k,JSON.stringify(v))}catch(e){}}
function mkLsDel(k){try{localStorage.removeItem(k)}catch(e){}}
function mkPendKey(a){return 'vxmk:'+APP.cid+':'+a}
function mkDbErr(e){var m=String(e&&e.message||e||'');
 if(/stale/.test(m))return 'Obsah se mezitím změnil. Načetli jsme aktuální verzi, zkontrolujte ji a akci zopakujte.';
 if(/empty_body/.test(m))return 'Příspěvek nemá text. Doplňte ho a pak schvalte.';
 if(/not_approved/.test(m))return 'Zveřejnit lze jen schválený a od schválení nezměněný příspěvek.';
 if(/no_site/.test(m))return 'Firma nemá zapnutý web ve Vexaronetu. Zapněte ho v sekci Web.';
 if(/invalid_url/.test(m))return 'Odkaz musí začínat https://.';
 if(/not_published/.test(m))return 'Výsledky lze zadat jen u zveřejněného příspěvku.';
 if(/permission|forbidden|42501|read_only|not_member/.test(m))return 'K této akci nemáte oprávnění, nebo je účet jen pro čtení.';
 if(/invalid|check|violates/.test(m))return 'Údaje neprošly kontrolou: '+m;
 return 'Akce se nepovedla: '+m}
function mkApiErr(j,s){j=j||{};
 var M={paid_runs_disabled:'Placené AI běhy zatím nejsou zapnuté provozovatelem. Nic se neúčtovalo.',budget_not_set:'Nastavte měsíční limit nákladů na AI (Finance & ROI). Nic se neúčtovalo.',
  budget_exceeded:'Měsíční limit nákladů na AI je vyčerpaný. Nic se neúčtovalo.',profile_not_confirmed:'Nejdřív potvrďte profil firmy.',strategy_not_approved:'Nejdřív schvalte strategii.',
  busy:'Právě běží jiné AI požadavky. Zkuste to za chvíli.',plan:'AI marketing je dostupný v tarifu PRO a vyšším.',forbidden:'AI marketing spouští vlastník nebo správce firmy.',auth:'Přihlášení vypršelo. Přihlaste se znovu.',
  previous_failed:'Předchozí pokus se nepovedl. Zkuste to znovu.',invalid_ai_output:'AI vrátila návrh, který neprošel kontrolou. Nic se neuložilo, zkuste to znovu.',upstream:'Služba AI je nedostupná. Nic se neuložilo, zkuste to později.',
  not_configured:'AI marketing není na serveru nastavený.',limit_unavailable:'Limit nákladů teď nejde ověřit. Zkuste to později.',key_conflict:'Požadavek se neshoduje s předchozím. Zkuste to znovu.'};
 return M[j.error]||j.message||('Požadavek se nepovedl (chyba '+s+').')}
async function mkLoad(){
 if(DEMO||APP.role==='employee'||!APP.cid)return;
 var cid=APP.cid;
 try{var sb=getSb(),r=await Promise.all([sb.rpc('mkt_state',{cid:cid}),sb.rpc('mkt_results',{cid:cid})]);if(APP.cid!==cid)return;
  if(r[0].error){MK.err=/function|schema cache|does not exist/i.test(r[0].error.message||'')?'AI marketing ještě není v databázi nasazený.':mkDbErr(r[0].error);MK.st=null}else if(!r[0].data||!r[0].data.profile){MK.st=null;MK.err='Stav AI marketingu má neočekávaný tvar.'}else{MK.st=r[0].data;MK.err=null}
  MK.res=r[1].error?null:(r[1].data||[]);MK.cid=cid}
 catch(e){MK.err='Stav AI marketingu se nepodařilo načíst. Zkontrolujte připojení.'}
 MK.loaded=true;mkPaint()}
function mkPaint(){var S={strat:mkStratHtml,card:mkCardHtml,gen:mkGenHtml,res:mkResHtml};
 document.querySelectorAll('#apd [data-mk-slot]').forEach(function(el){var f=S[el.getAttribute('data-mk-slot')];if(f)el.innerHTML=f()})}
function mkSlot(n){return '<div data-mk-slot="'+n+'">'+(DEMO||(MK.loaded&&MK.cid===APP.cid)?({strat:mkStratHtml,card:mkCardHtml,gen:mkGenHtml,res:mkResHtml}[n]()):'<p class="mut">Načítám…</p>')+'</div>'}
function mkReady(){if(DEMO)return apdEmpty('V ukázce se AI marketing nespouští.','Po přihlášení ke skutečné firmě zde uvidíte strategii, návrhy a výsledky z vašich dat.');
 if(MK.err)return apdEmpty('AI marketing není k dispozici.',MK.err);if(!MK.st)return '<p class="mut">Načítám…</p>';return ''}
function mkPendHtml(a,label){var p=mkLs(mkPendKey(a));if(!p||MK.busy[a])return '';
 return '<div class="ad-empty" style="margin:10px 0"><span><b>'+esc(label)+' nebyl dokončen.</b><br>Mohl se přerušit obnovením stránky. Kontrola použije stejný požadavek, AI se znovu nezaplatí, pokud už výsledek existuje.</span><button type="button" class="ad-btn2 ad-pr" data-apd-act="mk-resume" data-id="'+a+'">Zkontrolovat</button></div>'}
function mkBusyHtml(a){return MK.busy[a]?'<p class="mut" role="status">AI pracuje… Výsledek se uloží jako koncept ke kontrole.</p>':''}
/* ---------- strategie ---------- */
function mkDocHtml(d){d=d||{};var g=d.goal||{};
 return '<div class="ad-kv">'
  +'<div><span>Cíl</span><b>'+esc((g.target||'–')+' '+(MK_MET[g.metric]||g.metric||'')+' za '+(g.days||'–')+' dní')+'</b></div>'
  +'<div><span>Komu</span><b style="font-weight:500">'+esc(d.audience||'–')+'</b></div>'
  +'<div><span>Čím se odlišujeme</span><b style="font-weight:500">'+esc(d.positioning||'–')+'</b></div>'
  +(d.tone?'<div><span>Tón</span><b style="font-weight:500">'+esc(d.tone)+'</b></div>':'')
  +'<div><span>Kanály</span><b style="font-weight:500">'+(d.channels||[]).map(function(c){return esc(c.channel)+(c.why?' <small class="mut">('+esc(c.why)+')</small>':'')}).join(', ')+'</b></div>'
  +'<div><span>Témata</span><b style="font-weight:500">'+(d.themes||[]).map(function(t){return esc(t.title)+(t.angle?' <small class="mut">– '+esc(t.angle)+'</small>':'')}).join('<br>')+'</b></div>'
  +'<div><span>Frekvence</span><b>'+esc((d.cadence_per_week||'–')+'× týdně')+'</b></div>'
  +(d.notes?'<div><span>Poznámky</span><b style="font-weight:500">'+esc(d.notes)+'</b></div>':'')+'</div>'}
function mkProgHtml(){var p=MK.st&&MK.st.progress;if(!p)return '';var pct=p.target>0?Math.min(100,Math.round(p.value/p.target*100)):0,left=Math.max(0,Math.ceil((new Date(p.until).getTime()-Date.now())/864e5));
 return '<div style="margin:12px 0"><div style="display:flex;justify-content:space-between;gap:8px"><span>Plnění cíle: <b>'+esc(p.value+' z '+p.target+' '+(MK_MET[p.metric]||''))+'</b></span><span class="mut">'+(left?'zbývá '+left+' dní':'období skončilo')+'</span></div>'
  +'<div class="ad-bar" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="'+pct+'" aria-label="Plnění cíle strategie" style="margin-top:6px"><i style="width:'+pct+'%"></i></div>'
  +'<small class="mut">Počítáno ze skutečných záznamů ve Vexaronetu od schválení strategie. Ukazuje vývoj, ne prokázaný účinek marketingu.</small></div>'}
function mkStratHtml(){var w=mkReady();if(w)return w;var st=MK.st,s=st.strategy,a=st.approved;
 if(!st.profile.confirmed)return apdEmpty('Profil firmy není potvrzený.','Strategie vychází jen z potvrzeného profilu firmy. Vyplňte ho a potvrďte.')+'<div style="margin-top:12px"><button type="button" class="ad-btn2 ad-pr" data-tab="firmaprofil">Otevřít profil firmy</button></div>';
 var h=mkPendHtml('strategy','Návrh strategie')+mkBusyHtml('strategy');
 if(!s)return h+apdEmpty('Strategie zatím není nastavená.','AI navrhne cíl, cílové zákazníky, kanály, témata a frekvenci z potvrzeného profilu (verze '+st.profile.version+'). Návrh pak upravíte a schválíte.')
  +'<div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:12px"><button type="button" class="ad-btn2 ad-pr" data-apd-act="mk-gen-strategy"'+(MK.busy.strategy?' disabled':'')+'>Vytvořit návrh strategie</button><button type="button" class="ad-btn2" data-tab="firmaprofil">Profil firmy</button></div>';
 var draft=s.status==='draft';
 h+='<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:10px"><span class="ad-tag">'+(draft?'Koncept – čeká na schválení':'Schváleno')+'</span><small class="mut">verze '+s.version+' · '+(s.source==='ai'?'návrh AI':'ruční úprava')+' · z profilu v'+esc(s.profile_version||'–')+(s.approved_at?' · schváleno '+esc(fD(s.approved_at)):'')+'</small></div>';
 if(draft&&a)h+='<p class="mut">Platí schválená verze '+a.version+'. Tento koncept začne platit až po schválení.</p>';
 if(st.profile.version&&s.profile_version&&st.profile.version!==s.profile_version)h+='<p class="mut">Profil firmy se od návrhu změnil (nyní verze '+st.profile.version+'). Zvažte nový návrh.</p>';
 h+=mkDocHtml(s.doc)+(s.status==='approved'?mkProgHtml():'');
 h+='<div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:12px">'
  +(draft?'<button type="button" class="ad-btn2 ad-go" data-apd-act="mk-appr-strategy">'+ico('tick',16)+'Schválit strategii</button>':'')
  +'<button type="button" class="ad-btn2" data-apd-act="mk-edit-strategy">'+ico('edit',16)+(draft?'Upravit':'Upravit (vznikne nová verze)')+'</button>'
  +'<button type="button" class="ad-btn2" data-apd-act="mk-gen-strategy"'+(MK.busy.strategy?' disabled':'')+'>'+ico('sparkle',16)+'Nový návrh od AI</button>'
  +(a?'<button type="button" class="ad-btn2 ad-pr" data-apd="obsah">Navrhnout příspěvky '+ico('arr',16)+'</button>':'')+'</div>';
 return h}
function mkCardHtml(){if(DEMO)return '<p style="margin:0 0 10px">Cíl: <span class="ad-na">v ukázce se nenastavuje</span></p>';if(MK.err||!MK.st)return '<p class="mut" style="margin:0 0 10px">'+esc(MK.err||'Načítám…')+'</p>';
 var a=MK.st.approved,s=MK.st.strategy;if(!a)return '<p style="margin:0 0 10px">Cíl: <span class="ad-na">'+(s?'strategie čeká na schválení':MK.st.profile.confirmed?'zatím nenastaven':'nejdřív potvrďte profil firmy')+'</span></p>';
 var g=a.doc.goal||{};return '<p style="margin:0 0 4px">Cíl: <b>'+esc(g.target+' '+(MK_MET[g.metric]||'')+' za '+g.days+' dní')+'</b></p>'+mkProgHtml()}
function mkStrategyForm(d){d=d||{};var g=d.goal||{},ch={};(d.channels||[]).forEach(function(c){ch[c.channel]=c.why||''});
 var f=function(id,l,v,ta,max){return '<div class="f" style="margin-bottom:8px"><label for="'+id+'">'+l+'</label>'+(ta?'<textarea id="'+id+'" rows="3" maxlength="'+(max||1000)+'">'+esc(v||'')+'</textarea>':'<input id="'+id+'" maxlength="'+(max||300)+'" value="'+esc(v||'')+'">')+'</div>'};
 return '<h3>Upravit strategii</h3><form id="mkSf" novalidate><div style="display:flex;gap:8px;flex-wrap:wrap"><div class="f"><label for="mk_gm">Cíl – metrika</label><select id="mk_gm">'+Object.keys(MK_MET).map(function(k){return '<option value="'+k+'"'+(g.metric===k?' selected':'')+'>'+esc(MK_SYS[k])+'</option>'}).join('')+'</select></div>'
  +'<div class="f"><label for="mk_gt">Cílová hodnota</label><input id="mk_gt" type="number" min="1" max="10000" value="'+esc(g.target||'')+'"></div><div class="f"><label for="mk_gd">Za dní (7–180)</label><input id="mk_gd" type="number" min="7" max="180" value="'+esc(g.days||30)+'"></div>'
  +'<div class="f"><label for="mk_cad">Příspěvků týdně</label><input id="mk_cad" type="number" min="1" max="14" value="'+esc(d.cadence_per_week||2)+'"></div></div>'
  +f('mk_au','Komu (cíloví zákazníci)',d.audience,1,1000)+f('mk_po','Čím se odlišujeme',d.positioning,1,1000)+f('mk_to','Tón komunikace',d.tone,0,300)
  +'<fieldset style="border:1px solid var(--line);border-radius:10px;padding:8px;margin-bottom:8px"><legend>Kanály (1–6)</legend>'+MKCH.map(function(c,i){return '<div style="display:flex;gap:8px;align-items:center;margin:4px 0"><label style="min-width:130px"><input type="checkbox" id="mk_c'+i+'"'+(c in ch?' checked':'')+'> '+esc(c)+'</label><input id="mk_cw'+i+'" maxlength="300" placeholder="proč tento kanál" aria-label="Proč '+esc(c)+'" value="'+esc(ch[c]||'')+'" style="flex:1"></div>'}).join('')+'</fieldset>'
  +f('mk_th','Témata (2–8, jedno na řádek, „název | úhel pohledu“)',(d.themes||[]).map(function(t){return t.title+(t.angle?' | '+t.angle:'')}).join('\n'),1,4000)
  +f('mk_no','Poznámky',d.notes,1,2000)+'<p id="mkSfMsg" class="mut" role="alert"></p><button type="submit" class="ad-btn2 ad-go" style="background:#1f7a4d;color:#fff;border:0;border-radius:9px;padding:8px 16px">Uložit</button></form>'}
function mkStrategyRead(){var v=function(id){var e=A(id);return e?String(e.value||'').trim():''},chs=[];
 MKCH.forEach(function(c,i){if(A('mk_c'+i)&&A('mk_c'+i).checked)chs.push({channel:c,why:v('mk_cw'+i)||c})});
 var th=v('mk_th').split('\n').map(function(l){var p=l.split('|');return {title:String(p[0]||'').trim(),angle:String(p.slice(1).join('|')||'').trim()}}).filter(function(t){return t.title});
 var d={goal:{metric:v('mk_gm'),target:Math.round(Number(v('mk_gt'))),days:Math.round(Number(v('mk_gd')))},audience:v('mk_au'),positioning:v('mk_po'),tone:v('mk_to'),channels:chs,themes:th,cadence_per_week:Math.round(Number(v('mk_cad')))};
 if(v('mk_no'))d.notes=v('mk_no');var e=[];
 if(!(d.goal.target>=1&&d.goal.target<=10000))e.push('cílová hodnota 1–10000');if(!(d.goal.days>=7&&d.goal.days<=180))e.push('období 7–180 dní');
 if(d.audience.length<10)e.push('cílové zákazníky (aspoň 10 znaků)');if(d.positioning.length<10)e.push('odlišení (aspoň 10 znaků)');
 if(chs.length<1)e.push('aspoň jeden kanál');if(th.length<2||th.length>8)e.push('2–8 témat');if(th.some(function(t){return t.title.length<3||t.title.length>120}))e.push('název tématu 3–120 znaků');
 if(!(d.cadence_per_week>=1&&d.cadence_per_week<=14))e.push('frekvenci 1–14');return {doc:d,errors:e}}
/* ---------- obsah: dávka návrhů ze schválené strategie ---------- */
function mkGenHtml(){var w=mkReady();if(w)return w;var a=MK.st.approved;
 if(!a)return apdEmpty('Dávku návrhů vytvoří AI ze schválené strategie.','Nejdřív v záložce Strategie nechte navrhnout a schvalte strategii.')+'<div style="margin-top:10px"><button type="button" class="ad-btn2 ad-pr" data-apd="strategie">Přejít na strategii</button></div>';
 var c=Math.min(14,(a.doc.cadence_per_week||2)*2),td=apdIso(apdD0(0));
 return mkPendHtml('posts','Návrh příspěvků')+mkBusyHtml('posts')
  +'<p style="margin:0 0 8px">Podle schválené strategie (verze '+a.version+'): '+esc((a.doc.channels||[]).map(function(x){return x.channel}).join(', '))+'. Návrhy se uloží jako <b>koncepty</b>; nic se nezveřejní bez vašeho schválení.</p>'
  +'<div style="display:flex;gap:10px;flex-wrap:wrap;align-items:end"><div class="f"><label for="mk_pc">Počet příspěvků</label><input id="mk_pc" type="number" min="1" max="14" value="'+c+'"></div><div class="f"><label for="mk_pf">Od data (14 dní)</label><input id="mk_pf" type="date" min="'+td+'" value="'+td+'"></div>'
  +'<button type="button" class="ad-btn2 ad-pr" data-apd-act="mk-gen-posts"'+(MK.busy.posts?' disabled':'')+'>'+ico('sparkle',16)+'Navrhnout příspěvky</button></div>'}
/* ---------- výsledky ---------- */
function mkResHtml(){var w=mkReady();if(w)return w;var R=MK.res||[];
 if(!R.length)return apdEmpty('Zatím žádný zveřejněný příspěvek.','Po zveřejnění (na webu firmy nebo ručně se záznamem odkazu) zde uvidíte skutečné poptávky, zákazníky, rezervace a objednávky v 7 dnech po zveřejnění proti 7 dnům před ním a výsledky, které zadáte z kanálu.');
 var td=apdIso(apdD0(0));
 return '<p class="mut fine">Srovnání ukazuje souvislost v čase, ne prokázaný účinek příspěvku. Dosah a prokliky z Facebooku, Instagramu či Googlu zatím nejsou propojené; můžete je opsat ručně i se zdrojem.</p><ul class="ad-lst">'+R.map(function(r){
  var dt=r.web_publish_on||String(r.published_at||'').slice(0,10);
  var sys=Object.keys(MK_SYS).map(function(m){var x=(r.system||{})[m]||{};return '<div><span>'+esc(MK_SYS[m])+'</span><b>'+esc(x.after==null?'–':String(x.after))+' <small class="mut">(před: '+esc(x.before==null?'–':String(x.before))+')</small></b></div>'}).join('');
  var done=Object.keys(r.system||{}).every(function(m){return r.system[m].complete});
  var man=(r.manual||[]).map(function(x){return '<li>'+esc(MK_RMET[x.metric]||x.metric)+': <b>'+esc(Number(x.value).toLocaleString('cs-CZ'))+'</b> <small class="mut">('+esc(fD(x.from)+'–'+fD(x.to)+', zdroj: '+x.source)+')</small></li>'}).join('');
  return '<li style="display:block"><div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">'+apdChanIcon(r.channel==='web'?'Web nebo blog':r.channel,28)+'<b>'+esc(r.title)+'</b><small class="mut">'+esc((r.channel==='web'?'web firmy':r.channel)+' · '+(dt?fD(dt):''))+'</small>'+(r.published_url&&/^https:\/\//.test(r.published_url)?'<a href="'+esc(r.published_url)+'" target="_blank" rel="noopener noreferrer">odkaz</a>':'')+'</div>'
   +'<div class="ad-kv" style="margin-top:8px">'+sys+'</div><small class="mut">'+(done?'7 dní po zveřejnění vs. 7 dní před.':'Okno 7 dní po zveřejnění ještě běží.')+'</small>'
   +(man?'<ul style="margin:8px 0 0 18px">'+man+'</ul>':'')
   +'<details style="margin-top:8px"><summary>Zadat výsledek z kanálu</summary><div style="display:flex;gap:8px;flex-wrap:wrap;align-items:end;margin-top:6px">'
   +'<div class="f"><label for="mkr_m_'+esc(r.post_id)+'">Metrika</label><select id="mkr_m_'+esc(r.post_id)+'">'+Object.keys(MK_RMET).map(function(k){return '<option value="'+k+'">'+esc(MK_RMET[k])+'</option>'}).join('')+'</select></div>'
   +'<div class="f"><label for="mkr_v_'+esc(r.post_id)+'">Hodnota</label><input id="mkr_v_'+esc(r.post_id)+'" type="number" min="0" step="1"></div>'
   +'<div class="f"><label for="mkr_f_'+esc(r.post_id)+'">Od</label><input id="mkr_f_'+esc(r.post_id)+'" type="date" value="'+esc(dt)+'" max="'+td+'"></div>'
   +'<div class="f"><label for="mkr_t_'+esc(r.post_id)+'">Do</label><input id="mkr_t_'+esc(r.post_id)+'" type="date" value="'+td+'" max="'+td+'"></div>'
   +'<div class="f"><label for="mkr_s_'+esc(r.post_id)+'">Zdroj</label><input id="mkr_s_'+esc(r.post_id)+'" maxlength="120" placeholder="např. statistiky Facebooku"></div>'
   +'<button type="button" class="ad-btn2 ad-pr" data-apd-act="mk-res-add" data-id="'+esc(r.post_id)+'">Uložit</button></div></details></li>'}).join('')+'</ul>'}
/* ---------- akce ---------- */
async function mkSha(t){var b=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(t));return Array.prototype.map.call(new Uint8Array(b),function(x){return ('0'+x.toString(16)).slice(-2)}).join('')}
function mkPostHash(p){return mkSha((p.title||'')+'\x1f'+(p.body||'')+'\x1f'+(p.channel||''))}
async function mkCall(action,extra){
 if(MK.busy[action])return;var lk=mkPendKey(action),pend=mkLs(lk);
 if(!pend)pend={key:'m'+Date.now().toString(36)+Math.random().toString(36).slice(2,12),extra:extra||{},at:Date.now()};
 mkLsSet(lk,pend);MK.busy[action]=true;mkPaint();var keep=false;
 try{var ses=(await getSb().auth.getSession()).data.session;if(!ses){toast(mkApiErr({error:'auth'}),'err');return}
  var r=await fetch('/api/ai-marketing',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+ses.access_token},body:JSON.stringify(Object.assign({},pend.extra,{action:action,cid:APP.cid,key:pend.key}))});
  var j=await r.json().catch(function(){return {}});
  if(r.ok)toast(action==='strategy'?'Návrh strategie je uložený jako koncept. Zkontrolujte ho a schvalte.':'Návrhy příspěvků jsou uložené jako koncepty ke schválení.','ok');
  else if(r.status===409&&j.error==='in_progress'){keep=true;toast('Požadavek se ještě zpracovává. Za chvíli ho zkontrolujte.','ok')}
  else toast(mkApiErr(j,r.status),'err');
 }catch(e){keep=true;toast('Spojení se přerušilo. Stav zkontrolujte tlačítkem „Zkontrolovat“; AI se nezaplatí dvakrát.','err')}
 finally{if(!keep)mkLsDel(lk);MK.busy[action]=false}
 if(action==='posts'){try{await refresh()}catch(e){}appTab(APP.tab)}await mkLoad()}
async function mkRpc(fn,args,okMsg){try{var r=await getSb().rpc(fn,Object.assign({cid:APP.cid},args));if(r.error){toast(mkDbErr(r.error),'err');if(/stale/.test(r.error.message||'')){try{await refresh()}catch(e){}appTab(APP.tab)}return null}if(okMsg)toast(okMsg,'ok');return r.data||{}}catch(e){toast(mkDbErr(e),'err');return null}}
async function mkApprovePost(p,b){if(!p)return;if(!String(p.body||'').trim()){toast(mkDbErr('empty_body'),'err');return}if(b)b.disabled=true;
 var d=await mkRpc('mkt_post_approve',{p_post:p.id,p_expected_hash:await mkPostHash(p)},'Příspěvek je schválený a naplánovaný.');
 if(b)b.disabled=false;if(d){try{await refresh()}catch(e){}appTab(APP.tab);await mkLoad()}}
function mkClose(o){var x=o&&o.querySelector('[data-apdm]');if(x)x.click();else if(o)o.remove()}
function mkItem(id){return ((MK.st&&MK.st.items)||[]).filter(function(i){return String(i.post_id)===String(id)})[0]||null}
/* náhled příspěvku s dostupnými kroky: schválení, publikace na web firmy, záznam ručního zveřejnění, zrušení */
function mkPreview(p){var it=mkItem(p.id),td=apdIso(apdD0(0)),site=APP.d&&APP.d.sites&&APP.d.sites.rows&&APP.d.sites.rows[0];
 var h='<h3>'+esc(p.title)+'</h3><p class="mut">'+esc(p.channel||'bez kanálu')+' · '+esc(MKST[p.status]||p.status)+(p.planned_on?' · '+esc(fD(p.planned_on)):'')+(it&&it.ai?' · návrh AI':'')+'</p>'+(p.body?'<pre>'+esc(p.body)+'</pre>':'<p class="mut">Koncept zatím nemá žádný text.</p>');
 if(DEMO||APP.role==='employee'){apdModal(h);return}
 var ok=it&&it.approved,pub=it&&it.published_channel;
 if(it&&it.changed_after_approval)h+='<p class="mut">Text se po schválení změnil, proto je nutné ho schválit znovu.</p>';
 if(!ok)h+='<p><button type="button" class="ad-btn2" data-mkm="appr">Schválit</button> <small class="mut">Schvaluje se přesně tento text; po úpravě je nutné schválit znovu.</small></p>';
 else if(pub)h+='<p>Zveřejněno: <b>'+esc(pub==='web'?'web firmy':pub)+'</b>'+(it.web_publish_on?' od '+esc(fD(it.web_publish_on)):'')+(it.published_url&&/^https:\/\//.test(it.published_url)?' · <a href="'+esc(it.published_url)+'" target="_blank" rel="noopener noreferrer">odkaz</a>':'')+'</p><p><button type="button" class="ad-btn2" data-mkm="unpub">Zrušit zveřejnění</button></p>';
 else h+='<fieldset style="border:1px solid #4a56b0;border-radius:10px;padding:8px;margin:8px 0"><legend>Zveřejnit na webu firmy ve Vexaronetu</legend>'+(site&&site.enabled?'<label for="mkm_on">Od data</label> <input id="mkm_on" type="date" min="'+td+'" value="'+esc(p.planned_on&&p.planned_on>=td?p.planned_on:td)+'"> <button type="button" class="ad-btn2" data-mkm="web">Zveřejnit v sekci Novinky</button>':'<small>Web firmy není zapnutý. Zapněte ho v sekci Web.</small>')+'</fieldset>'
  +'<fieldset style="border:1px solid #4a56b0;border-radius:10px;padding:8px;margin:8px 0"><legend>Zveřejnili jste ho sami jinde?</legend><label for="mkm_ch">Kanál</label> <select id="mkm_ch">'+MKCH.map(function(c){return '<option'+(c===p.channel?' selected':'')+'>'+esc(c)+'</option>'}).join('')+'</select> <label for="mkm_url">Odkaz (https, nepovinné)</label> <input id="mkm_url" type="url" maxlength="1000" placeholder="https://"> <button type="button" class="ad-btn2" data-mkm="manual">Zaznamenat zveřejnění</button>'
  +'<br><small class="mut">Vexaronet zatím nepublikuje na Facebook, Instagram ani jiné sítě; zde jen zaznamenáte, že jste příspěvek zveřejnili.</small></fieldset>';
 apdModal(h);var m=document.querySelectorAll('.apdm');m=m[m.length-1];if(!m)return;
 m.addEventListener('click',async function(e){var b=e.target.closest&&e.target.closest('[data-mkm]');if(!b)return;var k=b.getAttribute('data-mkm'),d=null;b.disabled=true;
  if(k==='appr'){mkClose(m);await mkApprovePost(p,null);return}
  if(k==='web')d=await mkRpc('mkt_publish',{p_post:p.id,p_channel:'web',p_on:(A('mkm_on')||{}).value||null},'Příspěvek se zobrazí v sekci Novinky na webu firmy.');
  if(k==='manual'){var u=String((A('mkm_url')||{}).value||'').trim();if(u&&!/^https:\/\/\S+$/.test(u)){toast(mkDbErr('invalid_url'),'err');b.disabled=false;return}d=await mkRpc('mkt_publish',{p_post:p.id,p_channel:(A('mkm_ch')||{}).value,p_url:u||null},'Zveřejnění je zaznamenané.')}
  if(k==='unpub')d=await mkRpc('mkt_unpublish',{p_post:p.id},'Zveřejnění je zrušené.');
  b.disabled=false;if(d){mkClose(m);try{await refresh()}catch(x){}appTab(APP.tab);await mkLoad()}})}
async function mkAct(a,b,id){
 if(a==='mk-gen-strategy'){var s=MK.st&&MK.st.strategy;if(s&&!confirm('Vytvořit nový návrh strategie? Spotřebuje část měsíčního limitu nákladů na AI. Stávající verze zůstanou uložené.'))return;mkCall('strategy',{});return}
 if(a==='mk-gen-posts'){var c=Math.round(Number((A('mk_pc')||{}).value)||0),f=(A('mk_pf')||{}).value||'';if(!(c>=1&&c<=14)){toast('Počet příspěvků musí být 1–14.','err');return}mkCall('posts',{count:c,from:f});return}
 if(a==='mk-resume'){var p=mkLs(mkPendKey(id));if(p)mkCall(id,p.extra);return}
 if(a==='mk-appr-strategy'){var s2=MK.st&&MK.st.strategy;if(!s2)return;b.disabled=true;var d=await mkRpc('mkt_strategy_approve',{p_id:s2.id,p_expected_hash:s2.hash},'Strategie je schválená. Teď můžete nechat navrhnout příspěvky.');b.disabled=false;await mkLoad();return}
 if(a==='mk-edit-strategy'){var s3=MK.st&&MK.st.strategy;if(!s3)return;apdModal(mkStrategyForm(s3.doc));var fm=A('mkSf');if(!fm)return;
  fm.addEventListener('submit',async function(e){e.preventDefault();var x=mkStrategyRead(),msg=A('mkSfMsg');if(x.errors.length){msg.textContent='Doplňte: '+x.errors.join(', ')+'.';return}
   var sb=fm.querySelector('[type=submit]');sb.disabled=true;var d2=await mkRpc('mkt_strategy_edit',{p_id:s3.id,p_expected_hash:s3.hash,p_doc:x.doc},s3.status==='approved'?'Uloženo jako nový koncept. Platí dál schválená verze, dokud nový koncept neschválíte.':'Koncept strategie je uložený.');
   sb.disabled=false;if(d2){mkClose(fm.closest('.apdm'));await mkLoad()}});return}
 if(a==='mk-res-add'){var g=function(k){var e=A('mkr_'+k+'_'+id);return e?String(e.value||'').trim():''},v=Number(g('v'));
  if(g('v')===''||!(v>=0)){toast('Zadejte hodnotu 0 nebo vyšší.','err');return}if(!g('f')||!g('t')||g('f')>g('t')){toast('Zkontrolujte období.','err');return}if(g('s').length<3){toast('Uveďte zdroj (aspoň 3 znaky), např. statistiky Facebooku.','err');return}
  b.disabled=true;var d3=await mkRpc('mkt_result_add',{p_post:id,p_metric:g('m'),p_value:v,p_from:g('f'),p_to:g('t'),p_source:g('s')},'Výsledek je uložený.');b.disabled=false;if(d3)await mkLoad();return}}
