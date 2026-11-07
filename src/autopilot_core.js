/* Vexaronet AI Autopilot: čistá logika (bez DOM) pro přepínač režimů a nastavení limitu.
   Peníze se převádějí celočíselně (nanodolary), nikdy přes desetinná čísla. */
var VXAP=(function(){
 var MAX_NUSD=50000000000n; /* 50 USD, stejný strop jako databáze */
 /* "0,25" nebo "0.25" -> "250000000" (nUSD, text). Neplatné vstupy vrací null. */
 function usdToNusd(s){
  s=String(s==null?'':s).trim().replace(/\s/g,'').replace(',','.');
  var m=/^(\d{1,3})(?:\.(\d{1,9}))?$/.exec(s);if(!m)return null;
  var n=BigInt(m[1])*1000000000n+BigInt((m[2]||'').padEnd(9,'0'));
  return n>MAX_NUSD?null:n.toString()}
 function nusdToUsd(n){return Number(n)/1e9}
 function fmtUsd(n,max){if(n==null)return '–';return nusdToUsd(n).toLocaleString('cs-CZ',{minimumFractionDigits:2,maximumFractionDigits:max==null?4:max})+' USD'}
 /* cena za 1 M tokenů v USD z ceny za jeden token v nUSD (300 nUSD/token = 0,30 USD / 1 M) */
 function perMillionUsd(nusdPerToken){return Number(nusdPerToken)/1000}
 var MODES=[
  {id:'marketing',name:'AI Marketing',tab:'marketing',tabs:['marketing','zakaznici'],state:'lim',needs:'pro',text:'Návrhy příspěvků, newsletterů a reklam a plán obsahu. Nic se samo nepublikuje ani neodesílá.'},
  {id:'obchodnik',name:'AI Obchodník',tab:'pripady',tabs:['pripady','nabidky','zakaznici'],state:'soon',needs:'pro',text:'Obchodní případy a nabídky (CRM) fungují. Samotný AI obchodník zatím není hotový.'},
  {id:'ceo',name:'AI CEO',tab:'ceo',tabs:['ceo','reporty','finance'],state:'lim',needs:'pro',text:'Zdraví firmy, doporučení a chat nad vašimi daty. Radí, nic neprovádí.'},
  {id:'ucetnictvi',name:'AI Účetnictví',tab:'ucetni',tabs:['ucetni','faktury','finance','reporty'],state:'lim',needs:'accountant',text:'Vytěžení dokladů ke kontrole a odpovědi z vaší evidence. Účetní a daňové věci ověřte s odborníkem.'},
  {id:'weby_eshopy',name:'AI Weby a e-shopy',tab:'weby',tabs:['weby','eshop','sklad','online'],state:'lim',needs:'pro',text:'AI návrh textů webu. E-shop, sklad a online rezervace fungují bez AI.'},
  {id:'automatizace',name:'AI Automatizace',tab:'automatizace',tabs:['automatizace'],state:'lim',needs:'start',text:'Pravidla navrhují úkoly, které potvrdíte vy. Běh na pozadí a automatické zprávy zákazníkům zatím nejsou.'}];
 var STATE={on:'dostupné',lim:'omezeně',soon:'připravujeme'};
 /* Některé záložky (zákazníci, finance, reporty) patří do více režimů. Když je otevřená záložka v preferovaném
    (naposledy zvoleném) režimu, zůstane ten; jinak se vezme první režim, který ji obsahuje. */
 function modeOfTab(tab,prefer){var i;if(tab==='autopilot')return 'home';
  for(i=0;i<MODES.length;i++)if(MODES[i].id===prefer&&MODES[i].tabs.indexOf(tab)>=0)return prefer;
  for(i=0;i<MODES.length;i++)if(MODES[i].tabs.indexOf(tab)>=0)return MODES[i].id;return null}
 /* Připravenost k placeným AI během: každý bod musí platit. Vrací seznam {ok,text}. */
 function readiness(st,profileOk){
  return [
   {ok:!!st.plan_allowed,text:'Tarif hlavní firmy je PRO nebo vyšší'},
   {ok:profileOk===true,text:profileOk==null?'Profil firmy potvrzen (nelze zjistit)':'Profil firmy je potvrzený'},
   {ok:st.monthly_limit_nusd!=null&&Number(st.monthly_limit_nusd)>0,text:'Měsíční limit je nastaven'},
   {ok:!!st.platform_paid_runs_enabled,text:'Placené běhy povolil provozovatel platformy'}]}
 return {usdToNusd:usdToNusd,fmtUsd:fmtUsd,perMillionUsd:perMillionUsd,MODES:MODES,STATE:STATE,modeOfTab:modeOfTab,readiness:readiness,MAX_NUSD:MAX_NUSD}
})();
if(typeof module!=='undefined')module.exports=VXAP;
