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
  if(typeof o.cid!=='string'||!UUID.test(o.cid))return fail(400,'bad_request');
  var H={apikey:o.sbKey,authorization:'Bearer '+o.token},uid;
  try{var u=await f(o.sbUrl+'/auth/v1/user',{headers:H});if(!u.ok)return fail(401,'auth');uid=(await u.json()).id}catch(e){return fail(401,'auth')}
  if(!uid||!UUID.test(String(uid)))return fail(401,'auth');
  var role=null;
  try{var m=await f(o.sbUrl+'/rest/v1/company_members?select=role&company_id=eq.'+o.cid+'&user_id=eq.'+uid+'&limit=1',{headers:H});
   var rows=m.ok?await m.json():[];role=rows&&rows[0]&&rows[0].role}catch(e){return fail(403,'forbidden')}
  if(role!=='owner'&&role!=='admin')return fail(403,'forbidden');
  var sub=null;
  try{var s=await f(o.sbUrl+'/rest/v1/subscriptions?select=plan,status,trial_end&company_id=eq.'+o.cid+'&limit=1',{headers:H});
   var sr=s.ok?await s.json():[];sub=sr&&sr[0]}catch(e){return fail(403,'plan')}
  if(!planOk(sub,o.plans,now))return fail(403,'plan');
  return {ok:true,uid:uid,role:role,plan:String(sub.plan).toLowerCase(),cid:o.cid}}
 return {guardAi:guardAi,planOk:planOk,UUID:UUID}
})();
if(typeof module!=='undefined')module.exports=VXGUARD;
