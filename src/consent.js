/* ===== Souhlas s nepovinnými službami: analytika návštěvnosti a nahrávání relací =====
   Právní základ: § 89 odst. 3 zák. č. 127/2005 Sb. (předchozí souhlas pro ukládání/přístup v zařízení), čl. 7 odst. 3 GDPR
   (odvolání stejně snadné jako udělení). Viz docs/PRAVNI_SOULAD.md, oblast 3.
   - Bez souhlasu se NIC nenačte ani neodešle (ani skript nahrávání).
   - Lišta má rovnocenná tlačítka „Odmítnout vše“ a „Přijmout vše“; volba jde kdykoli změnit v „Nastavení soukromí“.
   - Po odvolání se sběr okamžitě zastaví a neodeslaná data se zahodí.
   - V produkci je vše vypnuté: dokud provozovatel nenastaví cílový endpoint (OPTIONAL_CFG), kategorie se nenabízí a lišta se nezobrazí.
   Nezbytné úložiště (přihlášení, světlý/tmavý režim, tato volba) souhlas nevyžaduje (výjimka v § 89 odst. 3). */
var VXCONSENT=(function(){
 var KEY='vx_consent_v1',VER=1;
 /* Konfigurace provozovatele. endpoint:null = služba vypnutá. Testy ji nastavují přes window.VX_OPTIONAL_CFG. */
 var OPTIONAL_CFG={analytics:{endpoint:null},recording:{endpoint:null}};
 var CFG=(typeof window!=='undefined'&&window.VX_OPTIONAL_CFG)||OPTIONAL_CFG;
 var CATS=[
  {id:'analytics',name:'Analytika návštěvnosti',desc:'Počítá zobrazené stránky (jen adresa stránky bez parametrů, šířka obrazovky a doména, odkud jste přišli). Bez cookies a bez propojení s účtem.'},
  {id:'recording',name:'Nahrávání relací',desc:'Zaznamenává pohyb po veřejných stránkách webu, abychom našli chyby v ovládání. Texty a obsah polí jsou nahrazeny hvězdičkami; přihlášená aplikace, formuláře, chat a dialogy se nenahrávají vůbec.'}];
 var running={},state=null;
 function enabledCats(){return CATS.filter(function(c){return CFG[c.id]&&typeof CFG[c.id].endpoint==='string'&&/^(\/|https:\/\/)/.test(CFG[c.id].endpoint)})}
 function read(){try{var v=JSON.parse(localStorage.getItem(KEY)||'null');return v&&v.v===VER?v:null}catch(e){return null}}
 function write(ch){state={v:VER,ts:new Date().toISOString(),analytics:!!ch.analytics,recording:!!ch.recording};try{localStorage.setItem(KEY,JSON.stringify(state))}catch(e){}return state}
 function cleanPath(){return location.pathname}
 /* keepalive má v prohlížečích limit 64 kB; větší dávky (první snímek stránky) se posílají běžně */
 function post(url,body){var j=JSON.stringify(body);try{return fetch(url,{method:'POST',headers:{'content-type':'application/json'},body:j,keepalive:j.length<60000,credentials:'omit',referrerPolicy:'no-referrer'}).catch(function(){})}catch(e){}}
 /* ---- analytika: jen počet zobrazení stránek ---- */
 var A={on:false,last:'',pv:function(){if(!A.on)return;var p=cleanPath();if(p===A.last)return;A.last=p;
   var ref='';try{ref=document.referrer?new URL(document.referrer).hostname:''}catch(e){}
   post(CFG.analytics.endpoint,{t:'pageview',path:p,ref:ref===location.hostname?'':ref,w:Math.round((window.innerWidth||0)/100)*100})},
  start:function(){if(A.on)return;A.on=true;A.last='';window.addEventListener('popstate',A.pv);window.addEventListener('hashchange',A.pv);A.pv()},
  stop:function(){A.on=false;window.removeEventListener('popstate',A.pv);window.removeEventListener('hashchange',A.pv)}};
 /* ---- nahrávání relací (rrweb, hostováno lokálně) ---- */
 var REC_SRC='/assets/vendor/rrweb-record-2.2.1/record.min.js';
 var BLOCK='#vxapp,#dlg,dialog,form,#chat,.aichat,iframe,video,audio,canvas,[data-vx-private],a[href^="mailto:"],a[href^="tel:"],.apdm,.modal,#appToast';
 /* Druhá vrstva maskování (nad nastavením rrweb): adresy bez parametrů a fragmentu, textové atributy nahrazené hvězdičkami.
    rrweb totiž převádí relativní odkazy na plné adresy (včetně parametrů stránky) a atributy jako alt/aria-label nemaskuje. */
 function stripUrl(u){if(typeof u!=='string'||!u)return u;if(/^data:/i.test(u))return 'data:';try{var x=new URL(u,location.href);return x.origin+x.pathname}catch(e){return ''}}
 function maskStr(v){return typeof v==='string'?v.replace(/\S/g,'*'):v}
 function scrubAttrs(a){if(!a||typeof a!=='object')return;Object.keys(a).forEach(function(k){var lk=k.toLowerCase();
  if(lk==='href'||lk==='src'||lk==='action'||lk==='poster'||lk==='xlink:href')a[k]=stripUrl(a[k]);
  else if(lk==='srcset')a[k]='';
  else if(/^(aria-|data-|on)/.test(lk)||['alt','title','content','placeholder','value','label','name','id','for','list','summary','datetime','cite','download'].indexOf(lk)>=0)a[k]=maskStr(a[k])})}
 function walk(n){if(!n||typeof n!=='object')return;if(n.attributes)scrubAttrs(n.attributes);if(n.type===3&&typeof n.textContent==='string'&&!n.isStyle)n.textContent=n.textContent.replace(/\S/g,'*');if(Array.isArray(n.childNodes))n.childNodes.forEach(walk)}
 var R={on:false,stopFn:null,buf:[],timer:null,
  sanitize:function(ev){if(!ev||!ev.data)return ev;
   if(ev.type===4){ev.data.href=location.origin+cleanPath()}
   else if(ev.type===2){walk(ev.data.node)}
   else if(ev.type===3&&ev.data.source===0){(ev.data.adds||[]).forEach(function(a){walk(a.node)});(ev.data.attributes||[]).forEach(function(x){scrubAttrs(x.attributes)});(ev.data.texts||[]).forEach(function(t){if(typeof t.value==='string')t.value=t.value.replace(/\S/g,'*')})}
   return ev},
  load:function(cb){if(window.rrwebRecord&&window.rrwebRecord.record)return cb();var s=document.createElement('script');s.src=REC_SRC;s.integrity='sha384-r/Gt+YL1IU/sqU5iTt4AnQFvGX40I2QxeuHZ7+A+L+XMaE21PdMg+WWDZiaF/qQY';s.async=true;s.dataset.vxConsent='recording';s.onload=cb;s.onerror=function(){};document.head.appendChild(s)},
  flush:function(){if(!R.on||!R.buf.length)return;var b=R.buf;R.buf=[];post(CFG.recording.endpoint,{t:'rec',path:cleanPath(),events:b})},
  start:function(){if(R.on)return;R.on=true;R.load(function(){if(!R.on||!window.rrwebRecord)return;
   R.stopFn=window.rrwebRecord.record({emit:function(ev){if(R.on)R.buf.push(R.sanitize(ev))},
    maskAllInputs:true,maskInputOptions:{password:true,email:true,tel:true,text:true,textarea:true,select:true,number:true,search:true,url:true,date:true,color:true},
    maskTextSelector:'*',blockSelector:BLOCK,ignoreSelector:'input,textarea,select',
    recordCanvas:false,collectFonts:false,inlineStylesheet:false,inlineImages:false,recordCrossOriginIframes:false,
    slimDOMOptions:'all',sampling:{mousemove:false,scroll:500,input:'last',media:800}});
   R.timer=setInterval(R.flush,4000)})},
  stop:function(){R.on=false;if(R.timer)clearInterval(R.timer);R.timer=null;R.buf=[];if(R.stopFn){try{R.stopFn()}catch(e){}}R.stopFn=null}};
 var MOD={analytics:A,recording:R};
 function apply(){var st=state||read()||{},en=enabledCats().map(function(c){return c.id});
  Object.keys(MOD).forEach(function(k){var want=en.indexOf(k)>=0&&st[k]===true;if(want&&!running[k]){running[k]=true;MOD[k].start()}else if(!want&&running[k]){running[k]=false;MOD[k].stop()}})}
 function set(ch){write(ch);apply();hideBanner();announce()}
 function announce(){var e=document.getElementById('vxcSt');if(e)e.textContent='Uloženo.'}
 /* ---- UI ---- */
 function css(){if(document.getElementById('vxcCss'))return;var s=document.createElement('style');s.id='vxcCss';s.textContent=
  '.vxcb{position:fixed;left:16px;right:16px;bottom:16px;z-index:3000;max-width:760px;margin:0 auto;background:#0f1433;color:#eef1ff;border:1px solid rgba(150,175,255,.35);border-radius:16px;padding:16px 18px;box-shadow:0 20px 50px rgba(0,0,0,.45);font:inherit;font-size:.93rem}'
  +'.vxcb p{margin:0 0 12px}.vxcb .vxcr{display:flex;flex-wrap:wrap;gap:10px}.vxcb button,.vxcd button{font:inherit;cursor:pointer;border-radius:10px;padding:10px 16px;min-height:44px;flex:1 1 160px;border:1px solid rgba(150,175,255,.6);background:#1d2560;color:#fff;font-weight:600}'
  +'.vxcb button.vxcl{flex:0 1 auto;background:none;border-color:transparent;text-decoration:underline;font-weight:400}'
  +'.vxcd{position:fixed;inset:0;z-index:3001;background:rgba(4,6,24,.72);display:grid;place-items:center;padding:16px}.vxcd>div{width:min(560px,100%);max-height:88vh;overflow:auto;background:#0f1433;color:#eef1ff;border:1px solid rgba(150,175,255,.35);border-radius:16px;padding:18px}'
  +'.vxcd label{display:flex;gap:10px;align-items:flex-start;padding:10px 0;border-bottom:1px solid rgba(150,175,255,.15)}.vxcd label input{margin-top:4px;width:20px;height:20px}.vxcd small{display:block;color:#b8c0e6}.vxcd .vxcr{display:flex;flex-wrap:wrap;gap:10px;margin-top:14px}'
  +'.vxcb button:focus-visible,.vxcd button:focus-visible{outline:2px solid #a78bfa;outline-offset:2px}';document.head.appendChild(s)}
 function hideBanner(){var b=document.getElementById('vxcBanner');if(b)b.remove()}
 function showBanner(){if(document.getElementById('vxcBanner'))return;css();var b=document.createElement('div');b.id='vxcBanner';b.className='vxcb';b.setAttribute('role','region');b.setAttribute('aria-label','Souhlas s nepovinnými službami');
  b.innerHTML='<p><b>Nepovinné služby.</b> S vaším souhlasem bychom použili '+enabledCats().map(function(c){return c.name.toLowerCase()}).join(' a ')+'. Bez souhlasu web funguje stejně. Volbu můžete kdykoli změnit v „Nastavení soukromí“ v patičce.</p>'
   +'<div class="vxcr"><button type="button" data-vxc="reject">Odmítnout vše</button><button type="button" data-vxc="accept">Přijmout vše</button><button type="button" class="vxcl" data-vxc="settings">Nastavení</button></div>';
  document.body.appendChild(b)}
 function openSettings(){css();var en=enabledCats(),st=state||read()||{};var o=document.createElement('div');o.className='vxcd';o.id='vxcDlg';o.setAttribute('role','dialog');o.setAttribute('aria-modal','true');o.setAttribute('aria-labelledby','vxcT');
  o.innerHTML='<div><h3 id="vxcT" style="margin:0 0 8px">Nastavení soukromí</h3>'
   +(en.length?'<p>Nezbytné úložiště (přihlášení, režim zobrazení, tato volba) je vždy zapnuté. Nepovinné služby:</p>'+en.map(function(c){return '<label><input type="checkbox" data-vxcat="'+c.id+'"'+(st[c.id]?' checked':'')+'><span><b>'+c.name+'</b><small>'+c.desc+'</small></span></label>'}).join('')
     +'<div class="vxcr"><button type="button" data-vxc="reject">Odmítnout vše</button><button type="button" data-vxc="accept">Přijmout vše</button><button type="button" data-vxc="save">Uložit volbu</button><button type="button" data-vxc="close">Zavřít</button></div>'
    :'<p>Web nepoužívá žádnou nepovinnou analytiku, reklamní cookies ani nahrávání relací. Ukládá jen to, co je nezbytné pro fungování (přihlášení, světlý/tmavý režim).</p><div class="vxcr"><button type="button" data-vxc="close">Zavřít</button></div>')
   +'<p id="vxcSt" role="status" aria-live="polite" style="margin:10px 0 0"></p></div>';
  document.body.appendChild(o);var f=o.querySelector('button,input');if(f)f.focus();
  function kd(e){if(e.key==='Escape'){e.stopImmediatePropagation();close()}}function close(){o.remove();window.removeEventListener('keydown',kd,true)}
  window.addEventListener('keydown',kd,true);o.addEventListener('click',function(e){if(e.target===o)close()});o._close=close}
 function onClick(e){var b=e.target.closest&&e.target.closest('[data-vxc],[data-privacy]');if(!b)return;
  if(b.hasAttribute('data-privacy')){e.preventDefault();openSettings();return}
  var a=b.getAttribute('data-vxc'),dlg=document.getElementById('vxcDlg');
  if(a==='accept')set({analytics:true,recording:true});
  else if(a==='reject')set({analytics:false,recording:false});
  else if(a==='settings'){openSettings();return}
  else if(a==='save'){var ch={};[].forEach.call(document.querySelectorAll('#vxcDlg [data-vxcat]'),function(i){ch[i.getAttribute('data-vxcat')]=i.checked});set(ch)}
  if(dlg&&dlg._close&&a!=='save')dlg._close()}
 function init(){document.addEventListener('click',onClick);state=read();if(enabledCats().length&&!state)showBanner();apply()}
 if(typeof document!=='undefined'){if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init()}
 return {read:read,openSettings:openSettings,enabledCats:enabledCats,_set:set,BLOCK:BLOCK}
})();
