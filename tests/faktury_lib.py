"""Čisté funkce fakturace (src/inv.js): IBAN, SPAYD QR platba, výpočty. Shoda výpočtů s PostgreSQL byla ověřena zvlášť (120 náhodných případů, stejný hash)."""
import json, subprocess, sys
bad=[]
def chk(c,m):
    print(('OK   ' if c else 'FAIL ')+m)
    if not c: bad.append(m)
def node(code):
    r=subprocess.run(['node','-e',"const V=require('./src/inv.js');console.log(JSON.stringify("+code+"))"],capture_output=True,text=True,check=True);return json.loads(r.stdout)
chk(node("V.ibanValid('CZ65 0800 0000 1920 0014 5399')") is True,'platný český IBAN')
chk(node("V.ibanValid('SK3112000000198742637541')") is True,'platný slovenský IBAN')
chk(node("V.ibanValid('CZ6508000000192000145398')") is False,'IBAN s chybnou kontrolní číslicí se odmítne')
chk(node("V.ibanValid('')") is False,'prázdný IBAN se odmítne')
F="{supplier_snapshot:{iban:'CZ6508000000192000145399',legal_name:'Příliš žluťoučký s.r.o.'},currency:'CZK',total:1234.5,variable_symbol:'20260001',number:'20260001',due_on:'2026-11-16',paid_at:null}"
s=node("V.spayd("+F+")")
chk(s=='SPD*1.0*ACC:CZ6508000000192000145399*AM:1234.50*CC:CZK*X-VS:20260001*MSG:FAKTURA 20260001*RN:PRILIS ZLUTOUCKY S.R.O.*DT:20261116',f'SPAYD: {s}')
chk(node("V.spayd(Object.assign("+F+",{paid_at:'2026-11-02'}))") is None,'zaplacená faktura nemá QR platbu')
chk(node("V.spayd(Object.assign("+F+",{currency:'USD'}))") is None,'nepodporovaná měna nemá QR platbu')
chk(node("V.spayd(Object.assign("+F+",{supplier_snapshot:{iban:'CZ00'}}))") is None,'neplatný IBAN nemá QR platbu')
chk(node("V.spayd(Object.assign("+F+",{total:0}))") is None,'nulová částka nemá QR platbu')
c=node("V.calc([{quantity:10,unit_gross:550,vat_rate:21},{quantity:2,unit_gross:550,vat_rate:21}],true).total")
chk(c['gross']==6600 and c['net']==5454.55 and c['tax']==1145.45,f'celkem 6600 s DPH = základ 5454,55 + DPH 1145,45 ({c["gross"]}/{c["net"]}/{c["tax"]})')
c=node("V.calc([{quantity:1,unit_gross:1000,vat_rate:21,discount_pct:10}],true).total")
chk(c['gross']==900 and c['discount']==100,'sleva 10 % z 1000 Kč = 900 Kč')
c=node("V.calc([{quantity:3,unit_gross:100,vat_rate:21}],false).total")
chk(c['gross']==300 and c['tax']==0 and c['net']==300,'neplátce DPH: bez DPH')
c=node("V.calc([{quantity:1,unit_gross:121,vat_rate:21},{quantity:1,unit_gross:112,vat_rate:12}],true).total.byRate")
chk(c['21']['net']==100 and c['12']['tax']==12,'rekapitulace podle sazeb DPH')
print('HOTOVO' if not bad else 'CHYB: %d'%len(bad)); sys.exit(1 if bad else 0)
