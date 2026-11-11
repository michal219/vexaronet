/* Vexaronet: převod bankovního výpisu CSV na řádky pro bank_reconciliation (import). Čistá logika bez DOM.
   Rozpozná oddělovač (; , tab), hlavičku s běžnými českými i anglickými názvy sloupců, data D.M.RRRR i RRRR-MM-DD a částky "1 234,50".
   Když výpis nemá ID pohybu, vytvoří stabilní ID z data, částky, VS a pořadí shodných řádků (opakovaný import téhož souboru nic nezdvojí). */
var VXBANK=(function(){
 function splitLine(l,d){var o=[],c='',q=false;for(var i=0;i<l.length;i++){var ch=l[i];if(q){if(ch==='"'){if(l[i+1]==='"'){c+='"';i++}else q=false}else c+=ch}else if(ch==='"')q=true;else if(ch===d){o.push(c);c=''}else c+=ch}o.push(c);return o.map(function(x){return x.trim()})}
 function norm(s){return String(s||'').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^a-z0-9]+/g,' ').trim()}
 var COLS={date:['datum','datum zauctovani','datum provedeni','datum pohybu','booking date','date','zauctovano'],amount:['objem','castka','castka v mene uctu','amount','castka pohybu'],currency:['mena','currency','mena uctu'],
  vs:['vs','variabilni symbol','variable symbol'],id:['id pohybu','id transakce','id operace','transaction id','reference','cislo pohybu','identifikace transakce'],
  desc:['zprava pro prijemce','poznamka','popis','nazev protiuctu','protiucet','message','description','zprava','uzivatelska identifikace']};
 function pick(h,names){for(var i=0;i<names.length;i++){var k=h.indexOf(names[i]);if(k>=0)return k}return -1}
 function toDate(s){s=String(s||'').trim();var m=/^(\d{1,2})\.\s?(\d{1,2})\.\s?(\d{4})/.exec(s);if(m)return m[3]+'-'+('0'+m[2]).slice(-2)+'-'+('0'+m[1]).slice(-2);m=/^(\d{4})-(\d{2})-(\d{2})/.exec(s);return m?m[1]+'-'+m[2]+'-'+m[3]:null}
 function toCents(s){s=String(s||'').replace(/[\s ]/g,'').replace(/[A-Za-z]+$/,'');if(!s)return null;if(/,\d{1,2}$/.test(s))s=s.replace(/\./g,'').replace(',','.');else s=s.replace(/,/g,'');
  if(!/^[+-]?\d+(\.\d{1,2})?$/.test(s))return null;var neg=s[0]==='-',p=s.replace(/^[+-]/,'').split('.'),c=Number(p[0])*100+Number(((p[1]||'')+'00').slice(0,2));return neg?-c:c}
 /* Vrací {rows, errors, skipped, columns}. rows mají tvar, který očekává databáze. */
 function parse(text,defCurrency){
  var lines=String(text||'').replace(/^﻿/,'').split(/\r?\n/).filter(function(l){return l.trim()}),errors=[],rows=[],skipped=0;
  if(lines.length<2)return {rows:[],errors:['Soubor neobsahuje žádné pohyby.'],skipped:0};
  var hi=-1,d=';',h,best=0;
  for(var i=0;i<Math.min(lines.length,30);i++){['\t',';',','].forEach(function(dl){var hh=splitLine(lines[i],dl).map(norm),sc=(pick(hh,COLS.date)>=0?1:0)+(pick(hh,COLS.amount)>=0?1:0);if(sc===2&&hh.length>best){best=hh.length;hi=i;d=dl;h=hh}})}
  if(hi<0)return {rows:[],errors:['Ve výpisu jsme nenašli sloupce s datem a částkou. Exportujte výpis jako CSV s hlavičkou.'],skipped:0};
  var c={date:pick(h,COLS.date),amount:pick(h,COLS.amount),currency:pick(h,COLS.currency),vs:pick(h,COLS.vs),id:pick(h,COLS.id),desc:pick(h,COLS.desc)},seen={};
  for(var j=hi+1;j<lines.length;j++){var f=splitLine(lines[j],d);if(f.length<2){skipped++;continue}
   var dt=toDate(f[c.date]),am=toCents(f[c.amount]);
   if(!dt||am==null){skipped++;if(errors.length<5)errors.push('Řádek '+(j+1)+': nečitelné datum nebo částka.');continue}
   if(am===0){skipped++;continue}
   var cur=(c.currency>=0?String(f[c.currency]||'').toUpperCase():'')||defCurrency||'CZK',vs=c.vs>=0?String(f[c.vs]||'').replace(/\D/g,'').replace(/^0+(?=\d)/,'').slice(0,10):'';
   if(cur!=='CZK'&&cur!=='EUR'){skipped++;if(errors.length<5)errors.push('Řádek '+(j+1)+': měna '+cur+' není podporovaná.');continue}
   var id=c.id>=0?String(f[c.id]||'').trim().slice(0,160):'';
   if(!id){var k=dt+':'+am+':'+vs;seen[k]=(seen[k]||0)+1;id='r:'+k+':'+seen[k]}
   rows.push({external_id:id,booked_on:dt,amount_cents:String(am),currency:cur,variable_symbol:vs,description:c.desc>=0?String(f[c.desc]||'').slice(0,500):''})}
  if(rows.length>1000){errors.push('Výpis má '+rows.length+' pohybů; najednou lze nahrát nejvýše 1000. Rozdělte ho na kratší období.');rows=rows.slice(0,1000)}
  return {rows:rows,errors:errors,skipped:skipped,columns:c}}
 return {parse:parse,toCents:toCents,toDate:toDate}
})();
if(typeof module!=='undefined')module.exports=VXBANK;
