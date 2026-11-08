/* Vexaronet: společná kontrola volajícího AI endpointů (Cloudflare funkce).
   Ověřuje, KDO volá a ZA KTEROU firmu, dřív než se zavolá poskytovatel AI:
     1) přihlášení (JWT uživatele),  2) platné id firmy (cid) z požadavku,
     3) členství v této firmě a role vlastník/správce (stejně jako v aplikaci),  4) tarif TÉŽE firmy.
   Všechny dotazy jdou s tokenem uživatele, takže odpovědi filtruje databáze (RLS). Servisní klíč se tu nepoužívá.
   Tarif se čte z řádku firmy, ke které uživatel patří; pobočka má tarif synchronizovaný z hlavní firmy (trigger v DB).
   Pravidlo tarifu zůstává jako dosud: povolený tarif a ne prošlá zkušební doba, ne expired/canceled. */
var VXGUARD=(function(){
 var UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
 function fail(status,error){return {ok:false,status:status,error:error}}
 function planOk(sub,plans,now){
  if(!sub)return false;var p=String(sub.plan||'').toLowerCase();if(plans.indexOf(p)<0)return false;
  if(sub.status==='expired'||sub.status==='canceled')return false;
  if(sub.status==='trial'&&sub.trial_end&&new Date(sub.trial_end)<now)return false;
  return true}
 /* opts: {fetchFn, sbUrl, sbKey, token, cid, plans:[...], now?:Date} */
 async function guardAi(o){
  var f=o.fetchFn,now=o.now||new Date();
  if(!o.token)return fail(401,'auth');
  var missing=o.cid===undefined||o.cid===null||o.cid==='';
  if(!missing&&(typeof o.cid!=='string'||!UUID.test(o.cid)))return fail(400,'bad_request');
  if(missing&&!o.legacyResolve)return fail(400,'bad_request');
  var H={apikey:o.sbKey,authorization:'Bearer '+o.token},uid;
  try{var u=await f(o.sbUrl+'/auth/v1/user',{headers:H});if(!u.ok)return fail(401,'auth');uid=(await u.json()).id}catch(e){return fail(401,'auth')}
  if(!uid||!UUID.test(String(uid)))return fail(401,'auth');
  /* PŘECHODNÉ (staré otevřené stránky a PWA neposílají cid): firmu určí server, ale jen když je uživatel vlastníkem nebo správcem
     právě JEDNÉ firmy. Jinak 400 (více firem) nebo 403 (žádná). Role, členství a tarif se ověřují stejně jako s cid.
     Odstranit, až se stará verze přestane používat (docs/NASAZENI_2026-11-07.md). */
  if(missing){
   var cands=[];
   try{var r0=await f(o.sbUrl+'/rest/v1/company_members?select=company_id,role&user_id=eq.'+uid,{headers:H});var rr=r0.ok?await r0.json():[];
    cands=(Array.isArray(rr)?rr:[]).filter(function(x){return x&&(x.role==='owner'||x.role==='admin')&&UUID.test(String(x.company_id))})}catch(e){return fail(403,'forbidden')}
   if(cands.length===0)return fail(403,'forbidden');
   if(cands.length>1)return fail(400,'bad_request');
   o=Object.assign({},o,{cid:cands[0].company_id})}
  var role=null;
  try{var m=await f(o.sbUrl+'/rest/v1/company_members?select=role&company_id=eq.'+o.cid+'&user_id=eq.'+uid+'&limit=1',{headers:H});
   var rows=m.ok?await m.json():[];role=rows&&rows[0]&&rows[0].role}catch(e){return fail(403,'forbidden')}
  if(role!=='owner'&&role!=='admin')return fail(403,'forbidden');
  var sub=null;
  try{var s=await f(o.sbUrl+'/rest/v1/subscriptions?select=plan,status,trial_end&company_id=eq.'+o.cid+'&limit=1',{headers:H});
   var sr=s.ok?await s.json():[];sub=sr&&sr[0]}catch(e){return fail(403,'plan')}
  if(!planOk(sub,o.plans,now))return fail(403,'plan');
  return {ok:true,uid:uid,role:role,plan:String(sub.plan).toLowerCase(),cid:o.cid}}
 /* Serverový limit AI v databázi (public.reserve_ai -> private.reserve_ai_core): atomicky (zámek) hlídá
    denní limit platformy, denní a měsíční limit firmy a 3 volání za minutu na uživatele, a znovu ověří členství,
    zapisovatelnost a tarif hlavní firmy. Volá se s tokenem uživatele těsně před voláním poskytovatele AI.
    Selže-li cokoli (i nedostupná DB), AI se nezavolá (fail closed).
    opts: {fetchFn, sbUrl, sbKey, token, cid} */
 async function reserveAi(o){
  if(!o.token)return fail(401,'auth');
  if(typeof o.cid!=='string'||!UUID.test(o.cid))return fail(400,'bad_request');
  var r,j=null;
  try{r=await o.fetchFn(o.sbUrl+'/rest/v1/rpc/reserve_ai',{method:'POST',headers:{apikey:o.sbKey,authorization:'Bearer '+o.token,'content-type':'application/json'},body:JSON.stringify({cid:o.cid})})}
  catch(e){return fail(503,'limit_unavailable')}
  if(r.ok)return {ok:true};
  try{j=await r.json()}catch(e){j=null}
  var msg=String(j&&j.message||''),code=String(j&&j.code||'');
  if(/limit|Zkuste AI znovu/i.test(msg))return {ok:false,status:429,error:'limit',message:msg.slice(0,200)};
  if(/Starter|tarif/i.test(msg))return fail(403,'plan');
  if(/Forbidden/i.test(msg)||code==='42501'||r.status===401||r.status===403)return fail(403,'forbidden');
  return fail(503,'limit_unavailable')}
 /* Veřejný chat bez přihlášení: limit v databázi pro celou platformu (public.reserve_help_chat: 200 denně celkem,
    20 za hodinu na jednoho návštěvníka). Návštěvník se pozná jen podle otisku SHA-256(IP|tajemství|den), IP se neukládá.
    Funkce je jen pro service_role, proto potřebuje SUPABASE_SERVICE_KEY v Cloudflare. Bez klíče nebo při chybě DB
    se AI nezavolá (fail closed). opts: {fetchFn, sbUrl, serviceKey, ip, now?} */
 async function reservePublicChat(o){
  if(!o.serviceKey)return fail(503,'not_configured');
  var day=(o.now||new Date()).toISOString().slice(0,10),hex;
  try{var buf=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(String(o.ip||'unknown').slice(0,100)+'|'+o.serviceKey+'|'+day));
   hex=Array.from(new Uint8Array(buf)).map(function(b){return b.toString(16).padStart(2,'0')}).join('')}catch(e){return fail(503,'limit_unavailable')}
  var r;
  try{r=await o.fetchFn(o.sbUrl+'/rest/v1/rpc/reserve_help_chat',{method:'POST',headers:{apikey:o.serviceKey,'content-type':'application/json'},body:JSON.stringify({p_actor:hex})})}
  catch(e){return fail(503,'limit_unavailable')}
  if(!r.ok)return fail(503,'limit_unavailable');
  var v=null;try{v=await r.json()}catch(e){v=null}
  return v===true?{ok:true}:fail(429,'rate')}
 return {guardAi:guardAi,reserveAi:reserveAi,reservePublicChat:reservePublicChat,planOk:planOk,UUID:UUID}
})();
if(typeof module!=='undefined')module.exports=VXGUARD;
