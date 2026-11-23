#!/usr/bin/env python3
"""Sestaví lokální verzi Vexaronetu: složka s jedním HTML souborem, který se otevře dvojklikem v prohlížeči.
Data zůstávají v prohlížeči daného počítače (bez webu, bez účtu), k tomu je záloha do souboru.
Výstup: vexaronet-lokalni.zip"""
import os, re, shutil, subprocess, sys, tempfile, zipfile, json
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = tempfile.mkdtemp(prefix='vx-local-')
R = T + '/r'
shutil.copytree(ROOT, R, ignore=shutil.ignore_patterns('.git', 'node_modules', '__pycache__', '*.zip'))
json.dump({'edition': 'local'}, open(R + '/config.local.json', 'w'))
subprocess.run([sys.executable, R + '/build.py'], check=True, stdout=subprocess.DEVNULL)
html = open(R + '/index.html', encoding='utf-8').read()
# cesty relativně k souboru, ať jde otevřít z disku
html = html.replace('url(/assets/', 'url(assets/').replace('"/assets/', '"assets/')
html = re.sub(r'<link rel="manifest"[^>]*>', '', html)
html = re.sub(r'<link rel="preload"[^>]*fonts[^>]*>', '', html)
ver = open(ROOT + '/VERSION').read().strip()
README = f"""VEXARONET – LOKÁLNÍ VERZE {ver}

CO TO JE
Aplikace pro malé firmy (zákazníci a CRM, obchodní případy, nabídky, zakázky, úkoly, kalendář, faktury, finance,
zaměstnanci, reporty). Běží jen na tomto počítači. Nepotřebujete web, účet ani internet.

JAK SPUSTIT
1. Rozbalte celou složku "Vexaronet" (ne jen jeden soubor) třeba na plochu nebo do Dokumentů.
2. Dvakrát klikněte na soubor "Vexaronet.html". Otevře se v prohlížeči (doporučeno Chrome nebo Edge).
3. Při prvním spuštění je aplikace prázdná. Začněte přidáním zákazníků. U faktur nejdřív vyplňte "Fakturační údaje".

KDE JSOU DATA (DŮLEŽITÉ)
Data se ukládají do prohlížeče na tomto počítači. Proto:
- Používejte pořád stejný prohlížeč a nespouštějte aplikaci v anonymním okně.
- Nemažte v prohlížeči "data webů" ani "cookies a data stránek" pro soubory.
- Pravidelně klikejte v levém menu na "Stáhnout zálohu" a soubor uložte mimo počítač (USB, cloud).
- Na jiný počítač nebo do jiného prohlížeče data přenesete tlačítkem "Obnovit ze zálohy".

OMEZENÍ (PROSÍM PŘEČTĚTE)
- Je to beta verze. Části označené "připravujeme" nejsou hotové.
- Faktury jsou v lokální verzi zjednodušené: číslují se podle roku, sčítají se částky položek, DPH se nepočítá
  a nekontroluje se návaznost číselné řady. Doklad vždy zkontrolujte, než ho pošlete zákazníkovi, a nepovažujte ho
  za účetně ověřený. Před ostrým používáním ho má zkontrolovat účetní.
- Odesílání e-mailů a nahrávání souborů v lokální verzi nefunguje.
- E-shop, sklad, pobočky, weby a AI funkce v této verzi nejsou.
- Data nejsou nikde jinde zálohovaná. Když se smaže prohlížeč bez zálohy, data jsou pryč.
- Aplikace nic neposílá na internet.
"""
OUT = ROOT + '/vexaronet-lokalni.zip'
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('Vexaronet/Vexaronet.html', html)
    for d, _, fs in os.walk(R + '/assets'):
        for f in fs:
            full = os.path.join(d, f)
            rel = os.path.relpath(full, R)
            if 'og-image' in f: continue
            z.write(full, 'Vexaronet/' + rel)
    z.writestr('Vexaronet/PRECTI-MNE.txt', README)
shutil.rmtree(T, ignore_errors=True)
print('Hotovo:', OUT)
