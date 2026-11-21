/* Vexaronet: země EU (čisté funkce bez DOM, použité v aplikaci a v testech).
   Sazby DPH: Evropská komise / TEDB, stav ke konci září 2026 (zdroj: europa.eu "VAT rules and rates").
   Jsou to ORIENTAČNÍ výchozí hodnoty, pro konkrétní zboží a službu rozhoduje národní zákon: před použitím je ověřte u účetního. */
var VXEU=(function(){
 /* kód, název česky, měna, euro?, standardní sazba, snížené sazby, předvolba IČ DPH, délka IBAN, tvar IČ DPH (bez předvolby) */
 var L=[
  ['AT','Rakousko','EUR',1,20,[10,13],'AT',20,/^U\d{8}$/],
  ['BE','Belgie','EUR',1,21,[6,12],'BE',16,/^[01]\d{9}$/],
  ['BG','Bulharsko','EUR',1,20,[9],'BG',22,/^\d{9,10}$/],
  ['HR','Chorvatsko','EUR',1,25,[5,13],'HR',21,/^\d{11}$/],
  ['CY','Kypr','EUR',1,19,[5,9],'CY',28,/^\d{8}[A-Z]$/],
  ['CZ','Česko','CZK',0,21,[12],'CZ',24,/^\d{8,10}$/],
  ['DK','Dánsko','DKK',0,25,[],'DK',18,/^\d{8}$/],
  ['EE','Estonsko','EUR',1,24,[9,13],'EE',20,/^\d{9}$/],
  ['FI','Finsko','EUR',1,25.5,[10,13.5],'FI',18,/^\d{8}$/],
  ['FR','Francie','EUR',1,20,[5.5,10],'FR',27,/^[A-Z0-9]{2}\d{9}$/],
  ['DE','Německo','EUR',1,19,[7],'DE',22,/^\d{9}$/],
  ['GR','Řecko','EUR',1,24,[6,13],'EL',27,/^\d{9}$/],
  ['HU','Maďarsko','HUF',0,27,[5,18],'HU',28,/^\d{8}$/],
  ['IE','Irsko','EUR',1,23,[9,13.5],'IE',22,/^(\d{7}[A-Z]{1,2}|\d[A-Z+*]\d{5}[A-Z])$/],
  ['IT','Itálie','EUR',1,22,[5,10],'IT',27,/^\d{11}$/],
  ['LV','Lotyšsko','EUR',1,21,[5,12],'LV',21,/^\d{11}$/],
  ['LT','Litva','EUR',1,21,[5,12],'LT',20,/^(\d{9}|\d{12})$/],
  ['LU','Lucembursko','EUR',1,17,[8,14],'LU',20,/^\d{8}$/],
  ['MT','Malta','EUR',1,18,[5,7],'MT',31,/^\d{8}$/],
  ['NL','Nizozemsko','EUR',1,21,[9],'NL',18,/^\d{9}B\d{2}$/],
  ['PL','Polsko','PLN',0,23,[5,8],'PL',28,/^\d{10}$/],
  ['PT','Portugalsko','EUR',1,23,[6,13],'PT',25,/^\d{9}$/],
  ['RO','Rumunsko','RON',0,21,[11],'RO',24,/^\d{2,10}$/],
  ['SK','Slovensko','EUR',1,23,[5,19],'SK',24,/^\d{10}$/],
  ['SI','Slovinsko','EUR',1,22,[5,9.5],'SI',19,/^\d{8}$/],
  ['ES','Španělsko','EUR',1,21,[10],'ES',24,/^[A-Z0-9]\d{7}[A-Z0-9]$/],
  ['SE','Švédsko','SEK',0,25,[6,12],'SE',24,/^\d{12}$/]
 ];
 var BY={};L.forEach(function(r){BY[r[0]]={code:r[0],name:r[1],currency:r[2],euro:!!r[3],vat:r[4],reduced:r[5],vatPrefix:r[6],ibanLen:r[7],vatRe:r[8]}});
 var CODES=L.map(function(r){return r[0]});
 var CURRENCIES=['CZK','EUR','PLN','HUF','RON','SEK','DKK'];
 function get(c){return BY[String(c||'').toUpperCase()]||null}
 function list(){return CODES.map(function(c){return BY[c]}).sort(function(a,b){return a.name.localeCompare(b.name,'cs')})}
 function nameOf(c){var x=get(c);return x?x.name:String(c||'')}
 function codeByName(n){var r=L.filter(function(x){return x[1]===n})[0];return r?r[0]:null}
 /* sazby použitelné v rozbalovátku: standardní první, pak snížené, nakonec 0 */
 function rates(c){var x=get(c);if(!x)return [21,12];return [x.vat].concat(x.reduced.slice().sort(function(a,b){return b-a}))}
 function clean(v){return String(v||'').replace(/[\s.\-\/]/g,'').toUpperCase()}
 /* IČ DPH: vrací {ok, country, reason}; předvolba určí stát (řecké EL). Kontroluje JEN tvar, platnost ověřuje VIES. */
 function vatOk(v,country){
  v=clean(v);if(!v)return {ok:true,empty:true};
  var pre=v.slice(0,2),x=null;
  CODES.forEach(function(c){if(BY[c].vatPrefix===pre)x=BY[c]});
  if(!x)return {ok:false,reason:'Neznámá předvolba „'+pre+'“. IČ DPH začíná kódem státu EU (např. CZ, SK, DE, PL).'};
  if(country&&get(country)&&get(country).code!==x.code)return {ok:false,country:x.code,reason:'IČ DPH s předvolbou '+x.vatPrefix+' nepatří k vybranému státu ('+nameOf(country)+').'};
  if(!x.vatRe.test(v.slice(2)))return {ok:false,country:x.code,reason:'Tvar IČ DPH neodpovídá státu '+x.name+'.'};
  return {ok:true,country:x.code,normalized:v}}
 function ibanOk(v){v=String(v||'').replace(/\s/g,'').toUpperCase();if(!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$/.test(v))return false;
  var s=v.slice(4)+v.slice(0,4),r=0,i,c,d,k;for(i=0;i<s.length;i++){c=s.charCodeAt(i);d=c>=65?String(c-55):String.fromCharCode(c);for(k=0;k<d.length;k++)r=(r*10+(d.charCodeAt(k)-48))%97}
  if(r!==1)return false;
  var x=BY[v.slice(0,2)==='GR'?'GR':v.slice(0,2)];return x?v.length===x.ibanLen:true}
 /* Přibližný poznatek, zda je u B2B prodeje do jiného státu EU možný režim přenesené daňové povinnosti. Nejde o daňovou radu. */
 function crossBorderHint(sellerCountry,buyerCountry,buyerVatId){
  if(!sellerCountry||!buyerCountry||sellerCountry===buyerCountry)return '';
  if(!get(sellerCountry)||!get(buyerCountry))return '';
  var v=vatOk(buyerVatId,buyerCountry);
  return v.ok&&!v.empty?'Odběratel má IČ DPH v jiném státě EU. U některých služeb se může uplatnit přenesená daňová povinnost. Ověřte IČ DPH ve VIES a režim s účetním.':'Odběratel je z jiného státu EU. Bez platného IČ DPH může být místem plnění jiný stát. Konzultujte s účetním.'}
 return {list:list,get:get,nameOf:nameOf,codeByName:codeByName,rates:rates,vatOk:vatOk,ibanOk:ibanOk,crossBorderHint:crossBorderHint,CODES:CODES,CURRENCIES:CURRENCIES}
})();
if(typeof module!=='undefined')module.exports=VXEU;
