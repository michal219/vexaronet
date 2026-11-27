# Vexaronet: zdrojový kód a aplikace pro počítač

Aplikace pro OSVČ a malé firmy: zákazníci a CRM pro celou EU, obchodní případy, nabídky, zakázky, úkoly, kalendář, faktury, finance, zaměstnanci a reporty. Je to **beta verze**, části označené „připravujeme“ nejsou hotové.

**Běží u vás v počítači. Na žádný web ani server ji dávat nemusíte.**

## Spuštění (bez instalace)
1. Rozbalte celý balíček.
2. Ve složce `lokalni-aplikace/` dvakrát klikněte na `Vexaronet.html`. Otevře se v prohlížeči (doporučeno Chrome nebo Edge).
3. Začněte přidáním zákazníků. U faktur nejdřív vyplňte „Fakturační údaje“.

Data se ukládají v prohlížeči na tomto počítači. Pravidelně klikejte na „Stáhnout zálohu“ a soubor uložte mimo počítač. Podrobnosti a omezení jsou v `lokalni-aplikace/PRECTI-MNE.txt`. Faktury jsou zjednodušené (bez DPH), před použitím je zkontrolujte s účetním.

## Úprava a nové sestavení
Potřebujete jen Python 3. Upravte soubory v `src/` nebo `build.py` a spusťte `python3 tools/export_local.py`. Vznikne nový `vexaronet-lokalni.zip` s upravenou aplikací.

V lokální verzi jsou vypnuté složitější části (e-shop, sklad, pobočky, weby, AI). Zdrojový kód těchto částí v balíčku je, ale nepodporujeme jej a bez serveru nefunguje.

## Testy
`tests/` obsahuje automatické testy (Python s Playwrightem). Test `tests/lokalni_verze.py` ověřuje lokální aplikaci.

## Licence
Software smíte používat ve své firmě a upravovat pro vlastní potřebu. **Nesmíte ho prodávat, pronajímat ani dál šířit.** Plné znění je v `LICENCE.txt`.

## Aktualizace
Novou verzi si stáhněte na vexaronet.com. Lokální verzi aktualizujete výměnou souboru `Vexaronet.html` (složku `assets` nechte). Data v prohlížeči zůstanou. Před výměnou si stáhněte zálohu.
