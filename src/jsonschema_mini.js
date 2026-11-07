/* Vexaronet: malý validátor podmnožiny JSON Schema. Stejnou podmnožinu a stejné chybové kódy
   implementuje databázová funkce private.vx_json_validate (db/migrations/*_profil_firmy.sql).
   Shoda obou implementací se hlídá testem tests/profile_parity.py nad společnými vektory.
   Podporováno: type (vč. seznamu a "integer"), enum, minLength, maxLength (v kódových bodech),
   minimum, maximum, minItems, maxItems, items, properties, required, additionalProperties:false,
   format: "date" | "http-url". Nic jiného (žádné $ref, pattern, oneOf…); nepodporované klíčové slovo
   ve schématu vyvolá výjimku, aby se rozdíl neprojevil až v provozu.
   Chyba má tvar "cesta:pravidlo", např. "$.shared.identity.displayName:minLength". */
var VXJS=(function(){
 var KNOWN={type:1,enum:1,minLength:1,maxLength:1,minimum:1,maximum:1,minItems:1,maxItems:1,items:1,properties:1,required:1,additionalProperties:1,format:1,title:1,version:1};
 function cpLen(s){var n=0;for(var i=0;i<s.length;i++){var c=s.charCodeAt(i);if(c>=0xD800&&c<=0xDBFF&&i+1<s.length){var d=s.charCodeAt(i+1);if(d>=0xDC00&&d<=0xDFFF)i++}n++}return n}
 function typeOf(v){return v===null?'null':Array.isArray(v)?'array':typeof v}
 function isDate(s){
  if(!/^(19|20|21)[0-9]{2}-[0-9]{2}-[0-9]{2}$/.test(s))return false;
  var d=new Date(s+'T00:00:00Z');return !isNaN(d.getTime())&&d.toISOString().slice(0,10)===s}
 function isHttpUrl(s){
  if(!/^[!-~]+$/.test(s)||!/^https?:\/\//.test(s))return false;
  var m=/^https?:\/\/([^\/?#]*)/.exec(s),a=m?m[1]:'';
  return a!==''&&a.indexOf('@')<0}
 function sameScalar(a,b){return a===b}
 function walk(sch,v,p,out){
  var k;for(k in sch)if(!KNOWN[k])throw new Error('Nepodporované klíčové slovo schématu: '+k);
  var t=typeOf(v);
  if(sch.type!==undefined){
   var allowed=Array.isArray(sch.type)?sch.type:[sch.type],ok=false;
   allowed.forEach(function(a){if(a===t||(a==='integer'&&t==='number'&&Number.isInteger(v)))ok=true});
   if(!ok){out.push(p+':type');return}}
  if(sch.enum!==undefined){
   var inEnum=false;sch.enum.forEach(function(e){if(sameScalar(e,v))inEnum=true});
   if(!inEnum){out.push(p+':enum');return}}
  if(t==='string'){
   var n=cpLen(v);
   if(sch.minLength!==undefined&&n<sch.minLength)out.push(p+':minLength');
   if(sch.maxLength!==undefined&&n>sch.maxLength)out.push(p+':maxLength');
   if(sch.format==='date'&&!isDate(v))out.push(p+':format');
   if(sch.format==='http-url'&&!isHttpUrl(v))out.push(p+':format')}
  else if(t==='number'){
   if(sch.minimum!==undefined&&v<sch.minimum)out.push(p+':minimum');
   if(sch.maximum!==undefined&&v>sch.maximum)out.push(p+':maximum')}
  else if(t==='array'){
   if(sch.minItems!==undefined&&v.length<sch.minItems)out.push(p+':minItems');
   if(sch.maxItems!==undefined&&v.length>sch.maxItems)out.push(p+':maxItems');
   if(sch.items)v.forEach(function(x,i){walk(sch.items,x,p+'['+i+']',out)})}
  else if(t==='object'){
   (sch.required||[]).forEach(function(r){if(!Object.prototype.hasOwnProperty.call(v,r))out.push(p+'.'+r+':required')});
   Object.keys(v).forEach(function(key){
    var has=sch.properties&&Object.prototype.hasOwnProperty.call(sch.properties,key);
    if(has)walk(sch.properties[key],v[key],p+'.'+key,out);
    else if(sch.additionalProperties===false)out.push(p+'.'+key+':additional')})}}
 function validate(sch,v,p){var out=[];walk(sch,v,p||'$',out);return out.sort()}
 return {validate:validate,cpLen:cpLen,isDate:isDate,isHttpUrl:isHttpUrl}
})();
if(typeof module!=='undefined')module.exports=VXJS;
