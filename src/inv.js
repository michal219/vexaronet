/* Vexaronet: čisté funkce fakturace (bez DOM), použité v aplikaci a v testech.
   Zaokrouhlování odpovídá databázové funkci invoice_action: g=round(q*u,2), net=round(g/(1+r/100),2), tax=g-net. */
var VXINV=(function(){
 function r2(x){return Math.round((x+Number.EPSILON)*100)/100}
 function ibanValid(v){v=String(v||'').replace(/\s/g,'').toUpperCase();if(!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$/.test(v))return false;
  var s=v.slice(4)+v.slice(0,4),r=0,i,c;for(i=0;i<s.length;i++){c=s.charCodeAt(i);var d=c>=65?String(c-55):String.fromCharCode(c);for(var k=0;k<d.length;k++)r=(r*10+(d.charCodeAt(k)-48))%97}return r===1}
 /* položka: {quantity,unit_gross,vat_rate,discount_pct?}; plátce: vat_payer. Sleva v % se odečte z ceny řádku s DPH. */
 function hu(num,den){return Math.floor((2*num+den)/(2*den))} /* celé číslo: zaokrouhlení num/den půl nahoru (kladná čísla) */
 function line(it,vatPayer){var qm=Math.round((Number(it.quantity)||0)*1000),uc=Math.round((Number(it.unit_gross)||0)*100),dc=Math.round(Math.min(100,Math.max(0,Number(it.discount_pct)||0))*100),
   bc=hu(qm*uc,1000),gc=dc?hu(bc*(10000-dc),10000):bc,rate=vatPayer?Number(it.vat_rate):null,
   nc=(vatPayer&&isFinite(rate))?(Number.isInteger(rate)?hu(gc*100,100+rate):Math.round(gc/(1+rate/100))):gc;
   return {base:bc/100,discount:(bc-gc)/100,gross:gc/100,net:nc/100,tax:(gc-nc)/100,rate:vatPayer?rate:null}}
 /* Souhrn: DPH se pro rekapitulaci počítá ze součtu cen s DPH po sazbách (zpětným výpočtem), ne ze součtu zaokrouhlených řádků. */
 function calc(items,vatPayer){var L=(items||[]).map(function(i){return line(i,vatPayer)}),t={gross:0,net:0,tax:0,discount:0,byRate:{}};
  L.forEach(function(l){t.gross=r2(t.gross+l.gross);t.discount=r2(t.discount+l.discount);var k=String(l.rate==null?'-':l.rate);var b=t.byRate[k]||(t.byRate[k]={rate:l.rate,gross:0,net:0,tax:0});b.gross=r2(b.gross+l.gross)});
  Object.keys(t.byRate).forEach(function(k){var b=t.byRate[k];if(b.rate==null||!isFinite(b.rate)){b.net=b.gross;b.tax=0}else{var gc=Math.round(b.gross*100);b.net=(Number.isInteger(b.rate)?hu(gc*100,100+b.rate):Math.round(gc/(1+b.rate/100)))/100;b.tax=r2(b.gross-b.net)}t.net=r2(t.net+b.net);t.tax=r2(t.tax+b.tax)});
  return {lines:L,total:t}}
 function ascii(s){return String(s||'').normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^A-Za-z0-9 .,\/:+\-]/g,' ').replace(/\s+/g,' ').trim()}
 /* Český QR platba (SPAYD 1.0). Vrací řetězec, nebo null, když chybí platné údaje. */
 function spayd(f){
  var sp=f&&f.supplier_snapshot&&typeof f.supplier_snapshot==='object'?f.supplier_snapshot:{},iban=String(sp.iban||'').replace(/\s/g,'').toUpperCase(),cur=f&&f.currency||'CZK',tot=Number(f&&f.total);
  if(!ibanValid(iban)||(cur!=='CZK'&&cur!=='EUR')||!(tot>0)||tot>9999999.99||f.paid_at)return null;
  var vs=String(f.variable_symbol||'').replace(/\D/g,'').slice(0,10),msg=ascii('FAKTURA '+(f.number||'')).slice(0,60).toUpperCase(),rn=ascii(sp.legal_name).slice(0,35).toUpperCase(),
   due=String(f.due_on||'').replace(/-/g,'').slice(0,8),s='SPD*1.0*ACC:'+iban+'*AM:'+tot.toFixed(2)+'*CC:'+cur;
  if(vs)s+='*X-VS:'+vs;if(msg)s+='*MSG:'+msg;if(rn)s+='*RN:'+rn;if(/^\d{8}$/.test(due))s+='*DT:'+due;
  return s.replace(/\*{2,}/g,'*')}
 return {r2:r2,ibanValid:ibanValid,line:line,calc:calc,spayd:spayd,ascii:ascii}
})();
if(typeof module!=='undefined')module.exports=VXINV;
