/* Propojení sociálních sítí (Facebook stránky, Instagram profesionální účty) – UI. Server: /api/social, RPC social_*.
   Viz docs/SOCIALNI_SITE.md. Token účtu se do prohlížeče nikdy nedostane; zde jsou jen názvy účtů a stav publikací.
   Zveřejnit lze jen schválený text a vždy až po výslovném kliknutí člověka. Nic se neplánuje ani nepublikuje samo. */
var SOC={st:null,na:false,err:null,cid:null,busy:false,ret:null};
var SOCRET={connected:['Účty jsou propojené. Najdete je v AI Marketing → Integrace.','ok'],no_pages:['Přihlášení proběhlo, ale Meta nevrátila žádnou stránku, kde můžete tvořit obsah. Zkontrolujte, že jste při přihlášení vybrali stránku a že k ní máte plný přístup.','err'],
 denied:['Propojení jste u Meta zrušili. Nic se neuložilo.','ok'],state:['Propojení se nepodařilo ověřit (vypršelo nebo bylo zahájeno v jiném prohlížeči). Zkuste to znovu.','err'],
 exchange:['Meta nepotvrdila přihlášení. Zkuste to znovu.','err'],pages:['Seznam stránek se od Meta nepodařilo načíst. Zkuste to znovu.','err'],not_configured:['Propojení se sítěmi Meta zatím není provozovatelem nastavené.','err']};
(function(){try{var q=new URLSearchParams(location.search),v=q.get('social');if(!v)return;SOC.ret=SOCRET[v]?v:null;q.delete('social');var s=q.toString();history.replaceState(null,'',location.pathname+(s?'?'+s:'')+location.hash);
 /* po návratu z Meta otevře přihlášenému uživateli rovnou záložku Integrace; hláška se ukáže po načtení stavu */
 if(SOC.ret)window.addEventListener('load',function(){setTimeout(async function(){try{var c=getSb(),r=c&&await c.auth.getSession();if(!r||!r.data||!r.data.session)return;await openApp();APD.tab='integrace';appTab('autopilot')}catch(e){}},300)})}catch(e){}})();
function socAccounts(){return (SOC.st&&Array.isArray(SOC.st.accounts)?SOC.st.accounts:[])}
function socPubs(postId){return (SOC.st&&Array.isArray(SOC.st.publications)?SOC.st.publications:[]).filter(function(x){return String(x.post_id)===String(postId)})}
function socName(a){return a.provider==='instagram'?(a.username?'@'+a.username:a.name):a.name}
function socLabel(p){return p==='instagram'?'Instagram':'Facebook'}
function socErr(j,s){j=j||{};var M={not_configured:'Propojení se sítěmi Meta zatím není provozovatelem nastavené.',not_deployed:'Propojení sítí ještě není v databázi nasazené.',plan:'Propojení sítí je dostupné v tarifu PRO a vyšším.',
  forbidden:'Účty propojuje a příspěvky zveřejňuje vlastník nebo správce firmy.',auth:'Přihlášení vypršelo. Přihlaste se znovu.',not_approved:'Zveřejnit lze jen schválený a od schválení nezměněný příspěvek.',
  account_not_found:'Účet už není propojený. Propojte ho znovu.',image_required:'Instagram vyžaduje obrázek. Zadejte veřejnou adresu obrázku (https).',invalid_image_url:'Adresa obrázku musí začínat https:// a nesmí obsahovat mezery.',
  text_too_long:'Text je pro tuto síť příliš dlouhý (Instagram nejvýše 2200 znaků).',already_published:'Tento příspěvek už na tomto účtu zveřejněný je.',in_progress:'Zveřejnění právě probíhá. Chvíli počkejte.',
  unknown_outcome:'Minulý pokus skončil bez odpovědi sítě. Podívejte se na síť, zda příspěvek vyšel, a potvrďte výsledek níže. Do té doby se znovu nepublikuje.',
  reauth:'Přístup k účtu vypršel nebo byl odvolán. Propojte účet znovu.',too_many_attempts:'Příliš mnoho rozpracovaných propojení. Zkuste to za 10 minut.',read_only:'Účet firmy je jen pro čtení.',unavailable:'Služba teď není dostupná. Zkuste to později.'};
 return M[j.error]||(j.error==='provider_error'&&j.message?'Síť příspěvek odmítla: '+j.message:null)||j.message||('Požadavek se nepovedl (chyba '+s+').')}
async function socLoad(){
 if(DEMO||APP.role==='employee'||!APP.cid)return;
 var cid=APP.cid;
 try{var r=await getSb().rpc('social_state',{cid:cid});if(APP.cid!==cid)return;
  if(r.error){SOC.st=null;SOC.na=/function|schema cache|does not exist/i.test(r.error.message||'');SOC.err=SOC.na?null:'Stav propojení se nepodařilo načíst.'}
  else{SOC.st=r.data||{accounts:[],publications:[]};SOC.na=false;SOC.err=null}SOC.cid=cid}
 catch(e){SOC.err='Stav propojení se nepodařilo načíst. Zkontrolujte připojení.'}
 socPaint();if(SOC.ret){var m=SOCRET[SOC.ret];SOC.ret=null;toast(m[0],m[1])}}
function socPaint(){var h=A('socHead'),l=A('socList');if(h)h.outerHTML=socHeadHtml();if(l)l.outerHTML=socIntegrHtml()}
/* karta v hlavičce dashboardu */
function socHeadHtml(){var ac=socAccounts(),fb=ac.some(function(a){return a.provider==='facebook'}),ig=ac.some(function(a){return a.provider==='instagram'}),on='opacity:1;filter:none;';
 var need=ac.some(function(a){return a.last_error==='reauth'});
 return '<div class="vxd-card vxd-acc" id="socHead"><div><b>Propojené účty</b><div class="vxd-ic" aria-label="'+(ac.length?'Propojeno účtů: '+ac.length:'Žádný účet není propojený')+'">'
  +'<span class="vxd-soc" style="'+(fb||ig?on:'')+'background:#0a7cff">∞</span><span class="vxd-soc" style="'+(ig?on:'')+'background:linear-gradient(135deg,#f9a03f,#e1306c)">IG</span><span class="vxd-soc" style="'+(fb?on:'')+'background:#1877f2">f</span><span class="vxd-soc" style="background:#111">♪</span><span class="vxd-soc" style="background:#e62117">▶</span></div></div>'
  +'<div><small class="mut">'+(ac.length?(need?'Nutné propojit znovu':'Propojeno: '+ac.length):'Nepřipojeno')+'</small><button type="button" class="vxd-btn2 vxd-pr" data-apd-act="connect" style="margin-top:6px">'+(ac.length?'Spravovat':'Připojit')+'</button></div></div>'}
/* záložka Integrace */
function socIntegrHtml(){var ac=socAccounts(),emp=APP.role==='employee';
 var rows=ac.map(function(a){return '<li>'+apdChanIcon(socLabel(a.provider),30)+'<div><b>'+esc(socName(a))+'</b><small class="mut">'+esc(socLabel(a.provider))+(a.provider==='instagram'?' · profesionální účet':' · stránka')+' · propojeno '+esc(fD(String(a.connected_at||'').slice(0,10)))
   +(a.last_error==='reauth'?' · <b style="color:#ffb86b">přístup vypršel, propojte znovu</b>':a.last_error?' · poslední pokus selhal':'')+'</small></div><button type="button" class="vxd-btn2" data-apd-act="soc-disconnect" data-id="'+esc(a.id)+'">Odpojit</button></li>'}).join('');
 var info=SOC.na?'<div class="vxd-empty" style="margin:10px 0"><span><b>Propojení sítí ještě není v databázi nasazené.</b><br>Funkce je připravená, čeká na nasazení provozovatelem.</span></div>'
  :SOC.err?'<div class="vxd-empty" style="margin:10px 0"><span>'+esc(SOC.err)+'</span></div>':'';
 var other=[['TikTok','Jen video; publikace přes rozhraní TikTok vyžaduje samostatné schválení aplikace.'],['YouTube','Jen video; zatím nepodporováno.'],['Meta Ads','Reklamní účty zatím nejsou podporované; výdaje a výsledky kampaní Vexaronet nezná.'],['Google Ads','Zatím nepodporováno.']];
 return '<div class="vxd-tabbody" id="socList"><section class="vxd-card"><div class="vxd-ch"><span class="vxd-ci">'+ico('link',24)+'</span><h3>Integrace</h3></div>'+info
  +'<h4 style="margin:10px 0 4px">Facebook a Instagram</h4>'
  +(rows?'<ul class="vxd-lst">'+rows+'</ul>':'<p class="mut">Zatím není propojená žádná stránka ani účet.</p>')
  +(emp?'<p class="mut fine">Účty propojuje vlastník nebo správce firmy.</p>':'<p style="margin:10px 0"><button type="button" class="vxd-btn2 vxd-pr" data-apd-act="soc-connect"'+(SOC.busy||SOC.na?' disabled':'')+'>'+(ac.length?'Propojit další nebo obnovit přístup':'Propojit Facebook a Instagram')+'</button></p>')
  +'<p class="mut fine">Přihlásíte se u Meta a sami vyberete stránky, ke kterým Vexaronet dostane přístup. Potřebujete stránku na Facebooku, kde můžete tvořit obsah; Instagram musí být profesionální účet propojený s touto stránkou. '
  +'Vexaronet smí jen zveřejnit příspěvek, který jste schválili a u kterého kliknete na Zveřejnit. Nic nepublikuje sám, nečte zprávy ani komentáře. Přístupový klíč je uložený zašifrovaně na serveru a odpojením se smaže; oprávnění aplikace navíc zrušíte ve svém účtu Facebook (Nastavení → Firemní integrace).</p>'
  +'<h4 style="margin:14px 0 4px">Další sítě</h4><ul class="vxd-lst">'+other.map(function(x){return '<li><span class="vxd-chn" style="width:30px;height:30px;background:#6b73a8">'+esc(x[0].charAt(0))+'</span><div><b>'+esc(x[0])+'</b><small class="mut">'+esc(x[1])+'</small></div><span class="mut">Nepodporováno</span></li>'}).join('')+'</ul>'
  +'</section></div>'}
async function socApi(body){var ses=(await getSb().auth.getSession()).data.session;if(!ses)return {s:401,j:{error:'auth'}};
 try{var r=await fetch('/api/social',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+ses.access_token},body:JSON.stringify(Object.assign({cid:APP.cid},body))});var j=null;try{j=await r.json()}catch(e){j=null}return {s:r.status,j:j||{}}}
 catch(e){return {s:0,j:{message:'Server neodpověděl. Zkontrolujte připojení.'}}}}
async function socAct(a,b,id){
 if(mkDemoStop())return;
 if(a==='soc-connect'){if(SOC.busy)return;SOC.busy=true;b.disabled=true;var r=await socApi({op:'begin'});SOC.busy=false;b.disabled=false;
  if(r.s===200&&r.j.url&&/^https:\/\/www\.facebook\.com\//.test(r.j.url)){location.assign(r.j.url);return}
  apdModal('<h3>Propojení se nepodařilo zahájit</h3><p>'+esc(socErr(r.j,r.s))+'</p>');return}
 if(a==='soc-disconnect'){var ac=socAccounts().filter(function(x){return String(x.id)===String(id)})[0];if(!ac)return;
  if(!confirm('Odpojit účet „'+socName(ac)+'“? Uložený přístupový klíč se smaže a Vexaronet na něj už nic nezveřejní.'))return;
  var d=await mkRpc('social_disconnect',{p_account:id},'Účet je odpojený.');if(d)await socLoad()}}
/* část náhledu příspěvku: zveřejnění na propojený účet + stav předchozích pokusů */
function socPublishHtml(p){var ac=socAccounts(),pubs=socPubs(p.id),h='';
 var unk=pubs.filter(function(x){return x.status==='unknown'})[0];
 if(unk)return '<fieldset style="border:1px solid #ffb86b;border-radius:10px;padding:8px;margin:8px 0"><legend>Nejasný výsledek zveřejnění ('+esc(socLabel(unk.provider))+': '+esc(unk.account)+')</legend><p>Síť při posledním pokusu neodpověděla. Podívejte se na účet, zda příspěvek vyšel.</p>'
  +'<label for="mkm_surl">Odkaz na příspěvek (https, nepovinné)</label> <input id="mkm_surl" type="url" maxlength="1000" placeholder="https://"> <button type="button" class="vxd-btn2" data-mkm="soc-yes" data-id="'+esc(unk.id)+'">Vyšel</button> <button type="button" class="vxd-btn2" data-mkm="soc-no" data-id="'+esc(unk.id)+'">Nevyšel, zkusit znovu</button></fieldset>';
 var last=pubs.filter(function(x){return x.status==='failed'})[0];
 if(!ac.length)return '<p class="mut fine">Na Facebook a Instagram lze zveřejnit přímo po propojení účtu v záložce Integrace.</p>';
 var pref=p.channel==='Instagram'?'instagram':'facebook';
 h='<fieldset style="border:1px solid #4a56b0;border-radius:10px;padding:8px;margin:8px 0"><legend>Zveřejnit na propojený účet</legend><label for="mkm_acc">Účet</label> <select id="mkm_acc">'
  +ac.map(function(a){return '<option value="'+esc(a.id)+'" data-p="'+esc(a.provider)+'"'+(a.provider===pref?' selected':'')+'>'+esc(socLabel(a.provider)+': '+socName(a))+'</option>'}).join('')+'</select>'
  +'<div id="mkm_imgw" style="margin-top:6px"><label for="mkm_img">Obrázek pro Instagram (veřejná adresa https, JPEG)</label> <input id="mkm_img" type="url" maxlength="1000" placeholder="https://" style="min-width:260px"></div>'
  +'<p style="margin:8px 0 2px"><button type="button" class="vxd-btn2 vxd-go" data-mkm="soc">Zveřejnit nyní</button></p>'
  +'<small class="mut">Zveřejní se přesně schválený text výše, a to hned a veřejně. Zveřejnění nelze z Vexaronetu vzít zpět; příspěvek smažete přímo na síti.</small>'
  +(last?'<br><small style="color:#ffb86b">Poslední pokus selhal'+(last.error?': '+esc(last.error):'')+'</small>':'')+'</fieldset>';
 return h}
function socPublishBind(m){var s=m.querySelector('#mkm_acc'),w=m.querySelector('#mkm_imgw');if(!s||!w)return;
 function f(){var o=s.options[s.selectedIndex];w.style.display=o&&o.getAttribute('data-p')==='instagram'?'':'none'}s.addEventListener('change',f);f()}
/* vrací true, když se stav změnil a má se překreslit */
async function socPublishAct(k,b,p,m){
 if(k==='soc-yes'||k==='soc-no'){var u=String((m.querySelector('#mkm_surl')||{}).value||'').trim();if(k==='soc-yes'&&u&&!/^https:\/\/\S+$/.test(u)){toast('Odkaz musí začínat https://.','err');return false}
  var d=await mkRpc('social_publish_resolve',{p_pub:b.getAttribute('data-id'),p_published:k==='soc-yes',p_url:k==='soc-yes'&&u?u:null},k==='soc-yes'?'Zveřejnění je zaznamenané.':'Můžete to zkusit znovu.');if(d)await socLoad();return !!d}
 var s=m.querySelector('#mkm_acc'),o=s&&s.options[s.selectedIndex];if(!o)return false;var ig=o.getAttribute('data-p')==='instagram',img=String((m.querySelector('#mkm_img')||{}).value||'').trim();
 if(ig&&!/^https:\/\/\S+$/.test(img)){toast(socErr({error:img?'invalid_image_url':'image_required'}),'err');return false}
 if(!confirm('Zveřejnit příspěvek „'+p.title+'“ nyní veřejně na '+o.textContent+'?'))return false;
 var r=await socApi({op:'publish',post:p.id,account:o.value,image_url:ig?img:null});
 if(r.s===200){toast('Příspěvek je zveřejněný.','ok');await socLoad();return true}
 toast(socErr(r.j,r.s),'err');await socLoad();return r.j&&(r.j.error==='unknown_outcome'||r.j.error==='reauth')}
