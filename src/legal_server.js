/* Sdílené pomocné funkce pro Cloudflare endpointy oblasti právního souladu (odhlášení z marketingu, oznámení DSA).
   Viz docs/PRAVNI_SOULAD.md. Údaje provozovatele se NEVYMÝŠLEJÍ: berou se z proměnných prostředí Cloudflare
   (OPERATOR_NAME, OPERATOR_ADDRESS, DSA_CONTACT_EMAIL). Bez nich se marketing neodešle a DSA e-maily použijí jen zveřejněný kontakt. */
var VXLEGAL=(function(){
 var SB_URL='https://micymdbqgzeckiqyvvkn.supabase.co',SB_KEY='sb_publishable_Owl1zZ5ZoGJVPxkjRVAOJw_8O6mLDwW',SITE='https://vexaronet.com';
 var PUBLIC_CONTACT='info@vexaronet.com'; /* už zveřejněný kontakt (právní texty); jako kontaktní místo DSA ho musí potvrdit provozovatel */
 function json(o,status,extra){return new Response(JSON.stringify(o),{status:status||200,headers:Object.assign({'content-type':'application/json; charset=utf-8','cache-control':'no-store'},extra||{})})}
 async function sha256hex(s){var b=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(String(s)));return Array.from(new Uint8Array(b)).map(function(x){return x.toString(16).padStart(2,'0')}).join('')}
 async function ipHash(req,secret){var ip=(req.headers.get('cf-connecting-ip')||'unknown').slice(0,100);return sha256hex(ip+'|'+(secret||'')+'|'+new Date().toISOString().slice(0,10))}
 function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
 function dsaContact(env){return (env&&env.DSA_CONTACT_EMAIL)||PUBLIC_CONTACT}
 /* odeslání e-mailu přes Resend; vrací {ok,id} a nikdy nevrací text chyby poskytovatele klientovi */
 async function sendMail(env,fetchFn,m){var key=env&&env.RESEND_API_KEY;if(!key)return {ok:false,reason:'not_configured'};
  try{var r=await fetchFn('https://api.resend.com/emails',{method:'POST',headers:{authorization:'Bearer '+key,'content-type':'application/json'},
    body:JSON.stringify(Object.assign({from:(env.INVITE_FROM||'Vexaronet <info@vexaronet.com>'),to:[m.to],subject:m.subject,text:m.text},m.html?{html:m.html}:{},m.headers?{headers:m.headers}:{},m.reply_to?{reply_to:m.reply_to}:{}))});
   if(!r.ok){console.error('mail',r.status);return {ok:false,reason:'failed'}}var j=await r.json().catch(function(){return {}});return {ok:true,id:j&&j.id||null}}
  catch(e){console.error('mail',e);return {ok:false,reason:'failed'}}}
 async function rpc(fetchFn,name,args,key,token){var r=await fetchFn(SB_URL+'/rest/v1/rpc/'+name,{method:'POST',headers:Object.assign({apikey:key,'content-type':'application/json'},token?{authorization:'Bearer '+token}:{}),body:JSON.stringify(args||{})});
  var j=null;try{j=await r.json()}catch(e){}return {ok:r.ok,status:r.status,data:j}}
 return {SB_URL:SB_URL,SB_KEY:SB_KEY,SITE:SITE,PUBLIC_CONTACT:PUBLIC_CONTACT,json:json,sha256hex:sha256hex,ipHash:ipHash,esc:esc,dsaContact:dsaContact,sendMail:sendMail,rpc:rpc}
})();
if(typeof module!=='undefined')module.exports=VXLEGAL;
