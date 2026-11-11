/* ===== Vývojová fáze: omezený počet firem a odpočet do plného spuštění =====
   Stav čte z veřejné funkce public.registration_status() (migrace 20261114100000). Rozhoduje databáze: trigger na public.companies
   odmítne novou firmu nad limit, i když by prohlížeč měl starý stav. Tady jen zobrazujeme stav a po naplnění nabízíme přihlášení.
   Pozvaní zaměstnanci existujících firem se mohou registrovat dál (nezakládají novou firmu). */
var REG={st:null,launch:'2026-12-09',max:10,loaded:false};
function regLaunch(){return (REG.st&&REG.st.launch_on)||REG.launch}
function regDays(){var p=String(regLaunch()).split('-').map(Number),t=Date.UTC(p[0],p[1]-1,p[2]),n=new Date(),d=Date.UTC(n.getFullYear(),n.getMonth(),n.getDate());return Math.round((t-d)/864e5)}
function regDaysTxt(n){return n===1?'1 den':(n>=2&&n<=4?n+' dny':n+' dní')}
function regOpen(){return !(REG.st&&REG.st.limited&&REG.st.open===false)}
function regDateTxt(){var p=String(regLaunch()).split('-').map(Number);return p[2]+'. '+p[1]+'. '+p[0]}
function regCss(){if(document.getElementById('regCss'))return;var s=document.createElement('style');s.id='regCss';s.textContent=
 '.regbar{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin:0 0 18px;padding:12px 16px;border-radius:14px;border:1px solid rgba(139,108,255,.45);background:linear-gradient(120deg,rgba(91,155,255,.14),rgba(139,92,246,.16));line-height:1.45}'
 +'.regbar .regd{display:grid;place-items:center;min-width:76px;padding:6px 10px;border-radius:12px;background:rgba(10,12,40,.55);border:1px solid rgba(150,175,255,.35);text-align:center}'
 +'.regbar .regd b{font-size:1.6rem;line-height:1}.regbar .regd small{font-size:.72rem;opacity:.85}.regbar p{margin:0;flex:1;min-width:220px}'
 +'.regbar .regs{display:inline-block;margin-top:4px;font-weight:700}.regbar.regx{border-color:rgba(255,190,90,.6);background:rgba(255,190,90,.1)}'
 +'.regnote{padding:10px 12px;border-radius:12px;border:1px solid rgba(255,190,90,.55);background:rgba(255,190,90,.1);margin:0 0 12px;line-height:1.45}';
 document.head.appendChild(s)}
function regPaint(){
 regCss();var b=document.getElementById('regBar');if(!b)return;var d=regDays(),open=regOpen(),st=REG.st;
 var cnt=d>0?'<span class="regd" aria-hidden="true"><b>'+d+'</b><small>'+(d===1?'den':(d<=4?'dny':'dní'))+'</small></span>':'';
 var lead=d>0?'<b>Vexaronet je ve vývoji.</b> Do plného spuštění zbývá <b>'+regDaysTxt(d)+'</b> (plánováno na '+regDateTxt()+').':'<b>Vexaronet spouštíme.</b> Plné spuštění je naplánováno na '+regDateTxt()+'.';
 var slots='';
 if(st&&st.limited){slots=open?'<span class="regs">Volná místa pro testovací firmy: '+st.remaining+' z '+st.max+'.</span>':'<span class="regs">Všech '+st.max+' míst pro testovací firmy je obsazeno. Registrace nových firem je do spuštění uzavřená, přihlášení funguje dál.</span>'}
 b.className='regbar'+(open?'':' regx');b.hidden=false;
 b.innerHTML=cnt+'<p>'+lead+' Teď přijímáme jen '+((st&&st.max)||REG.max)+' firem, které nám dají zpětnou vazbu a pomohou s nápady na další funkce.<br>'+slots+'</p>';
 b.setAttribute('aria-label',(d>0?'Do spuštění zbývá '+regDaysTxt(d)+'. ':'')+(open?'Registrace je otevřená.':'Registrace je uzavřená.'));
 document.querySelectorAll('[data-early]').forEach(function(x){if(!x.dataset.regTxt)x.dataset.regTxt=x.textContent;x.textContent=open?x.dataset.regTxt:'Přihlásit se'})}
async function regLoad(){/* přes vlastní doménu (functions/api/registration.js), ne přímo na Supabase: žádný cizí server při načtení */
 try{var r=await fetch('/api/registration',{headers:{accept:'application/json'}});if(r.ok){var d=await r.json();if(d&&typeof d==='object'&&!d.error)REG.st=d}}catch(e){}
 REG.loaded=true;regPaint()}
/* Uzavřená registrace: místo formuláře nové firmy nabídneme přihlášení; pozvaní zaměstnanci se registrovat mohou. */
function regGuardAuth(mode){
 if(regOpen())return;var f=document.getElementById('authForm');if(!f)return;var top=f.parentNode;
 if(mode==='login'&&!document.getElementById('regNote')){var n=document.createElement('p');n.id='regNote';n.className='regnote';
  n.innerHTML='<b>Registrace nových firem je do spuštění uzavřená</b> (všech '+(REG.st.max||REG.max)+' testovacích míst je obsazeno). Přihlášení funguje dál. Pozval vás zaměstnavatel do jeho firmy? <button type="button" class="lnkb" data-auth="signup">Registrace pro pozvané</button>';
  top.insertBefore(n,f)}
 if(mode==='signup'){var inv=document.getElementById('aInv');if(inv){inv.checked=true;inv.disabled=true;inv.dispatchEvent(new Event('change',{bubbles:true}))}
  var co=document.getElementById('aCo');if(co){var w=co.closest('.f');if(w)w.hidden=true}
  if(!document.getElementById('regNote')){var m=document.createElement('p');m.id='regNote';m.className='regnote';
   m.innerHTML='<b>Zakládání nových firem je do spuštění uzavřené.</b> Registrovat se mohou jen zaměstnanci, které do své firmy pozval její vlastník. Použijte e-mail, na který přišla pozvánka.';top.insertBefore(m,f)}}}
(function(){
 /* showAuth je funkce ve stejném rozsahu skriptu (ne globální): přepíšeme její vazbu, takže ji použijí všechna volání. */
 var orig=typeof showAuth==='function'?showAuth:null;
 if(orig)showAuth=function(mode){
  if(mode==='signup'&&!regOpen()&&!showAuth._inv){mode='login'}
  showAuth._inv=false;orig(mode);regGuardAuth(mode)};
 document.addEventListener('click',function(e){var t=e.target.closest&&e.target.closest('#regNote [data-auth="signup"]');if(t){e.preventDefault();e.stopImmediatePropagation();showAuth._inv=true;showAuth('signup')}},true);
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',regLoad);else regLoad()})();
