/* Vexaronet: čistá logika profilu firmy (bez DOM), použitá v aplikaci a v testech.
   Pravidla zde mají přesné protějšky v databázi (db/migrations/*_profil_firmy.sql):
   normalizace (trim), validace dokumentu, odvozený cíl, kontrola úplnosti.
   Závazná je vždy databáze; tento kód slouží pro rychlou odezvu ve formuláři.
   Shodu hlídá tests/profile_parity.py. */
var VXPCORE=(function(){
 var J=(typeof VXJS!=='undefined')?VXJS:require('./jsonschema_mini.js');
 function trimStr(s){return s.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g,'')}
 function trimDeep(v){
  if(typeof v==='string')return trimStr(v);
  if(Array.isArray(v))return v.map(trimDeep);
  if(v&&typeof v==='object'){var o={};Object.keys(v).forEach(function(k){o[k]=trimDeep(v[k])});return o}
  return v}
 function isObj(v){return v!==null&&typeof v==='object'&&!Array.isArray(v)}
 /* Dokument = {shared:{…}, local:{…}}. Pobočka smí mít jen local. */
 function validateDoc(schema,doc,isRoot){
  if(!isObj(doc))return ['$:type'];
  var out=[];
  Object.keys(doc).forEach(function(k){if(k!=='shared'&&k!=='local')out.push('$.'+k+':additional')});
  if(doc.shared!==undefined){
   if(!isRoot&&isObj(doc.shared)&&Object.keys(doc.shared).length>0)out.push('$.shared:branch_not_allowed');
   else out=out.concat(J.validate(schema.shared,doc.shared,'$.shared'))}
  if(doc.local!==undefined)out=out.concat(J.validate(schema.local,doc.local,'$.local'));
  return out.sort()}
 /* Cíl = základ × (10 000 + bp) / 10 000, zaokrouhleno půl nahoru, v nejmenších jednotkách. BigInt kvůli > 2^53. */
 function goalTarget(baselineMinor,growthBp){
  var r=(BigInt(baselineMinor)*(10000n+BigInt(growthBp))+5000n)/10000n;return Number(r)}
 function applyDerived(doc){
  var d=JSON.parse(JSON.stringify(doc));
  if(d.shared&&Array.isArray(d.shared.goals))d.shared.goals=d.shared.goals.map(function(g){
   var o=Object.assign({},g);
   if(o.baselineMinor!=null&&o.growthBp!=null){o.targetMinor=goalTarget(o.baselineMinor,o.growthBp);o.targetSource='calc'}
   else if(o.targetMinor!=null)o.targetSource='user';
   else delete o.targetSource;
   return o});
  return d}
 function nonEmpty(s){return typeof s==='string'&&s!==''}
 /* Co chybí k potvrzení profilu. Prázdné pole = lze potvrdit. */
 function incomplete(doc,isRoot){
  var out=[],sh=(doc&&doc.shared)||{},lo=(doc&&doc.local)||{},geo=lo.geography||{};
  if(!nonEmpty(geo.city)&&!nonEmpty(geo.serviceArea))out.push('local.geography:required');
  if(isRoot){
   var id=sh.identity||{},sv=sh.services||{},au=sh.audience||{},fc=sh.financialContext||{};
   if(!nonEmpty(id.displayName))out.push('shared.identity.displayName:required');
   if(!nonEmpty(id.activity)&&!(Array.isArray(sv.items)&&sv.items.length>0))out.push('shared.services:required');
   if(!nonEmpty(au.description))out.push('shared.audience.description:required');
   if(fc.revenueMinor!=null){
    if(fc.revenueCurrency==null)out.push('shared.financialContext.revenueCurrency:required');
    if(fc.revenuePeriod==null)out.push('shared.financialContext.revenuePeriod:required')}
   if(fc.budgetMinor!=null){
    if(fc.budgetCurrency==null)out.push('shared.financialContext.budgetCurrency:required');
    if(fc.budgetPeriod==null)out.push('shared.financialContext.budgetPeriod:required')}
   (sh.goals||[]).forEach(function(g,i){
    var has=g.baselineMinor!=null||g.growthBp!=null||g.targetMinor!=null;
    if(has&&g.dueDate==null)out.push('shared.goals['+i+'].dueDate:required');
    if(g.growthBp!=null&&g.baselineMinor==null)out.push('shared.goals['+i+'].baselineMinor:required')});
   (sh.unknowns||[]).forEach(function(u){if(u.blocking===true&&out.indexOf('shared.unknowns:blocking')<0)out.push('shared.unknowns:blocking')})}
  return out.sort()}
 /* Aktivní firma. rows: členství s připojenou firmou {company_id, role, companies:{id,name,parent_company_id,created_at}}.
    1) uložená volba, pokud je pořád mezi členstvími; 2) hlavní firma, kde je uživatel majitel; 3) jakákoli hlavní firma;
    4) nejstarší členství. Při shodě rozhoduje created_at, pak id, takže výsledek nezávisí na pořadí řádků z databáze. */
 function pickCompany(rows,stored){
  rows=(rows||[]).filter(function(r){return r&&r.company_id});
  if(!rows.length)return null;
  if(stored&&rows.some(function(r){return r.company_id===stored}))return stored;
  function c(r){return r.companies||{}}
  function isRoot(r){return !c(r).parent_company_id}
  function rank(r){return (isRoot(r)&&r.role==='owner')?0:isRoot(r)?1:2}
  rows=rows.slice().sort(function(a,b){
   return rank(a)-rank(b)||String(c(a).created_at||'').localeCompare(String(c(b).created_at||''))||String(a.company_id).localeCompare(String(b.company_id))});
  return rows[0].company_id}
 /* Převod chyby z RPC na druh chyby. Konflikt revize se rozpozná explicitně (kód PT409, HTTP 409 nebo text),
    nespoléháme se jen na jednu z těchto vlastností. */
 function mapRpcError(e){
  e=e||{};var code=String(e.code||''),st=Number(e.status||0),msg=String(e.message||''),det=e.details||e.detail||'',parsed=null;
  try{parsed=typeof det==='string'&&det?JSON.parse(det):(det&&typeof det==='object'?det:null)}catch(x){}
  if(code==='PT409'||st===409||/revision_conflict/.test(msg))return {kind:'conflict',current:parsed&&parsed.current_revision!=null?Number(parsed.current_revision):null,message:'Profil mezitím změnil někdo jiný.'};
  if(code==='PT412'||st===412||/schema_mismatch/.test(msg))return {kind:'schema',message:'Aplikace má starší verzi formuláře. Obnovte stránku.'};
  if(code==='PT422'||st===422||/validation_failed/.test(msg))return {kind:'validation',errors:Array.isArray(parsed)?parsed:(parsed&&Array.isArray(parsed.errors)?parsed.errors:[]),message:'Některé údaje nejsou ve správném tvaru.'};
  if(code==='42501'||st===401||st===403)return {kind:'forbidden',message:'K tomuto profilu nemáte oprávnění nebo je účet jen pro čtení.'};
  return {kind:'other',message:msg||'Operace se nepodařila.'}}
 function emptyDoc(isRoot){return isRoot?{shared:{},local:{}}:{local:{}}}
 /* Překlad kódů chyb na text u pole. */
 var RULE={required:'Toto pole je potřeba vyplnit.',minLength:'Text je příliš krátký.',maxLength:'Text je příliš dlouhý.',type:'Nesprávný typ hodnoty.',enum:'Nepovolená hodnota.',format:'Nesprávný formát.',minimum:'Hodnota je příliš malá.',maximum:'Hodnota je příliš velká.',minItems:'Málo položek.',maxItems:'Příliš mnoho položek.',additional:'Neznámé pole.',blocking:'Zbývá nevyřešená nejasnost.',branch_not_allowed:'Společné údaje patří hlavní firmě.'};
 function explain(code){var i=code.lastIndexOf(':'),r=code.slice(i+1);return RULE[r]||'Neplatná hodnota.'}
 return {trimDeep:trimDeep,validateDoc:validateDoc,goalTarget:goalTarget,applyDerived:applyDerived,incomplete:incomplete,pickCompany:pickCompany,mapRpcError:mapRpcError,emptyDoc:emptyDoc,explain:explain}
})();
if(typeof module!=='undefined')module.exports=VXPCORE;
