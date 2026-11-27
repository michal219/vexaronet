# Vexaronet: zdrojový kód aplikace, která běží ve vašem počítači

Vexaronet je aplikace pro OSVČ a malé firmy: zákazníci a CRM, obchodní případy, nabídky, zakázky, úkoly, kalendář, faktury, finance, zaměstnanci a reporty. Je to **beta verze**.

**Aplikace běží přímo u vás v počítači. Nepotřebujete web, server, databázi ani účet. Nic se nikam neodesílá.**

V balíčku je dvojí: hotová aplikace (stačí spustit) a zdrojový kód, ze kterého si ji sami sestavíte a upravíte.

---

## A) Rychlé spuštění hotové aplikace (bez instalace čehokoli)

1. Rozbalte celý balíček (pravé tlačítko → Extrahovat vše). Nespouštějte nic přímo ze zip souboru.
2. Otevřete složku `lokalni-aplikace`.
3. Dvakrát klikněte na **`Vexaronet.html`**. Otevře se v prohlížeči (doporučeno Chrome nebo Edge).
4. Aplikace je při prvním spuštění prázdná. Přidejte zákazníky. Před vystavením faktury vyplňte „Fakturační údaje“.

**Kde jsou vaše data:** v prohlížeči na tomto počítači. Proto:
- používejte pořád stejný prohlížeč a ne anonymní okno,
- nemažte v prohlížeči „data webů“ a „cookies a data stránek“,
- pravidelně klikněte na „Stáhnout zálohu“ a soubor uložte mimo počítač (USB, cloud). Na jiný počítač data přenesete tlačítkem „Obnovit ze zálohy“.

## B) Sestavení aplikace ze zdrojového kódu

Potřebujete jen **Python 3** (zdarma, https://www.python.org/downloads/). Při instalaci na Windows zaškrtněte „Add python.exe to PATH“.

- **Windows:** dvakrát klikněte na `SPUSTIT.bat`.
- **macOS / Linux:** v terminálu ve složce balíčku spusťte `sh spustit.sh`.

Skript sestaví aplikaci do složky `Vexaronet-lokalni` a otevře ji v prohlížeči. Stejnou složku pak můžete zkopírovat, kam chcete, a spouštět dvojklikem na `Vexaronet.html`.

### Jak aplikaci upravit
1. Upravte soubory v `src/` (části aplikace, každý soubor má v názvu, co řeší: například `crm_ui.js` zákazníci, `faktury_ui.js` faktury) nebo `build.py` (hlavní část aplikace a texty) či `base.css` (vzhled).
2. Znovu spusťte `SPUSTIT.bat` (nebo `sh spustit.sh`). Změny se projeví hned.
3. Zkontrolujte, že vše funguje, a před ostrým používáním si udělejte zálohu dat.

### Test (volitelné)
`tests/lokalni_verze.py` ověří lokální aplikaci automaticky. Potřebuje Python s balíčkem Playwright (`pip install playwright` a `playwright install chromium`) a spustí se příkazem `python3 tests/lokalni_verze.py`.

## Co v lokální verzi je a není
- **Je:** zákazníci a CRM pro celou EU (kontrola tvaru IČ DPH a IBAN), obchodní případy, nabídky, zakázky, úkoly, kalendář, faktury, finance, zaměstnanci, reporty, záloha a obnova do souboru.
- **Není:** e-shop, sklad, pobočky, weby, online rezervace pro veřejnost a AI funkce. Ty vyžadují server a v lokální verzi jsou vypnuté. Kód některých z nich je v `src/` a `build.py`, ale bez serveru nefunguje a nepodporujeme jej.
- **Faktury jsou zjednodušené:** číslují se podle roku, sčítají se částky položek, DPH se nepočítá a nehlídá se návaznost číselné řady. Doklad zkontrolujte, než ho pošlete zákazníkovi, a nepovažujte ho za účetně ověřený. Před ostrým používáním ho má zkontrolovat účetní.
- Odesílání e-mailů a nahrávání souborů nefunguje.

## Problémy
- **Nic se neotevře nebo je prázdná stránka:** otevřete soubor v Chrome nebo Edge, ne v prohlížeči uvnitř jiné aplikace.
- **Zmizela data:** obnovte je tlačítkem „Obnovit ze zálohy“. Bez zálohy je nelze vrátit.
- **`SPUSTIT.bat` hlásí, že nenašel Python:** nainstalujte Python 3 (viz výše) a zkuste to znovu.
- Cokoli dalšího: info@vexaronet.com. Individuální podporu nezaručujeme.

## Licence
Software smíte používat ve své firmě a upravovat pro vlastní potřebu. **Nesmíte ho prodávat, pronajímat ani dál šířit.** Plné znění je v `LICENCE.txt`.

## Aktualizace
Novou verzi si stáhněte na vexaronet.com. Hotovou aplikaci aktualizujete výměnou souboru `Vexaronet.html` (složku `assets` nechte), data v prohlížeči zůstanou. **Před výměnou si stáhněte zálohu.**
