# Vexaronet: zdrojový kód (balíček pro kupce)

Aplikace pro OSVČ a malé firmy: zákazníci a CRM pro celou EU, zakázky, kalendář a rezervace, sklad, faktury, e-shop, zaměstnanci a docházka. Je to **beta verze**, části označené „připravujeme“ nejsou hotové.

## Co potřebujete
- účet na Supabase (databáze a přihlášení), hosting statického webu se serverovými funkcemi (např. Cloudflare Pages), Python 3 a Node.js 20+
- vlastní doménu a e-mailovou službu (např. Resend) pro e-maily z aplikace

## Postup nasazení
1. V Supabase vytvořte nový projekt. **Pozor: úplný export celého databázového schématu (cca 100 tabulek a 190 funkcí) zatím v balíčku není.** Soubory `schema*.sql`, `db/migrations` a `db/snapshot` jsou dílčí a z nich samotných databázi od nuly spolehlivě nepostavíte. Úplný skript dodá prodávající samostatně. Do té doby nasazení nezačínejte.
2. Zkopírujte `config.local.example.json` na `config.local.json` a doplňte adresu projektu a veřejný *publishable* klíč (Supabase → Project Settings → API). **Tajný klíč (service_role) nikdy nevkládejte do webu.** Soubor `config.local.json` se při aktualizacích nepřepisuje.
3. Sestavte web: `python3 build.py`
4. Nahrajte na hosting a nastavte proměnné prostředí a tajemství (viz `NAVOD.md`).
5. V Supabase → Authentication → URL Configuration nastavte adresu svého webu.
6. Přepište texty, značku (název, logo, kontakty) a právní stránky (podmínky, ochrana údajů, cookies) tak, aby odpovídaly **vašemu** provozu. Součástí balíčku jsou jen vzory.

## Testy
`tests/` obsahuje automatické testy (Node a Python s Playwrightem). Spouštějí se proti lokálně sestavenému webu.

## Edice zdrojového kódu
V `config.local.json` je `"edition": "source"`. Aplikace pak nehlídá limity tarifů (START apod.). Na straně databáze nastavte svou firmu v tabulce `subscriptions` na plán `enterprise`, jinak server část funkcí odmítne.

## Upozornění
- Zabezpečení, zálohy, provoz a právní soulad (smlouvy, ochrana údajů, daně a účetnictví) jsou odpovědností provozovatele.
- Fakturace je zatím jen pro dodavatele z ČR a Slovenska. Sazby DPH a ostatní údaje o zemích EU jsou orientační a před ostrým použitím je ověřte.
- Zkontrolujte, že aplikace po úpravě neodkazuje na původní projekt (adresa databáze, e-maily, odkazy na stahování).

## Aktualizace
Postup je v `AKTUALIZACE.md` (nové verze, databázové migrace, upozornění v aplikaci).
