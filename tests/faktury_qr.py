"""QR generátor (src/qr.js): vygeneruje matice, dekóduje je OpenCV a porovná text. Pokrývá verze 1 až 10."""
import json, subprocess, sys
import numpy as np, cv2
bad=[]
def chk(c,m):
    print(('OK   ' if c else 'FAIL ')+m)
    if not c: bad.append(m)
texts=['A','SPD*1.0*ACC:CZ6508000000192000145399*AM:1234.50*CC:CZK*X-VS:20260001*MSG:FAKTURA 20260001*DT:20261116',
 'x'*20,'y'*40,'z'*70,'Ahoj světe '*6,'Q'*110,'R'*140,'S'*170,'T'*200,'U'*230,
 'SPD*1.0*ACC:SK3112000000198742637541*AM:0.01*CC:EUR*X-VS:2026999999*MSG:FAKTURA 2026999999*RN:VEXARONET S R O*DT:20261231']
js="const Q=require('./src/qr.js');const t=JSON.parse(process.argv[1]);console.log(JSON.stringify(t.map(x=>{try{return Q.matrix(x)}catch(e){return null}})))"
out=subprocess.run(['node','-e',js,json.dumps(texts)],capture_output=True,text=True,check=True).stdout
mats=json.loads(out)
det=cv2.QRCodeDetector()
for t,m in zip(texts,mats):
    if m is None:
        chk(len(t.encode())>213,f'příliš dlouhý text ({len(t)}) správně odmítnut'); continue
    a=np.array(m,dtype=np.uint8);n=a.shape[0]
    img=np.pad((1-a)*255,4,constant_values=255).astype(np.uint8)
    img=cv2.resize(img,None,fx=10,fy=10,interpolation=cv2.INTER_NEAREST)
    d,_,_=det.detectAndDecode(img)
    chk(d==t,f'verze {(n-17)//4}, {len(t)} znaků: dekódováno správně')
print('HOTOVO' if not bad else 'CHYB: %d'%len(bad)); sys.exit(1 if bad else 0)
