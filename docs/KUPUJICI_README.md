# Vexaronet: zdrojový kód (balíček pro kupce)

Aplikace pro OSVČ a malé firmy: zákazníci a CRM pro celou EU, zakázky, kalendář a rezervace, sklad, faktury, e-shop, zaměstnanci a docházka. Je to **beta verze**, části označené „připravujeme“ nejsou hotové.

## Co potřebujete
- účet na Supabase (databáze a přihlášení), hosting statického webu se serverovými funkcemi (např. Cloudflare Pages), Python 3 a Node.js 20+
- vlastní doménu a e-mailovou službu (např. Resend) pro e-maily z aplikace

## Postup nasazení
1. V Supabase vytvořte nový projekt. V SQL editoru spusťte skripty `schema*.sql` a migrace ze složky `db/migrations` (pořadí viz `ARCHITEKTURA.md`).
2. V `build.py` nahraďte `SB_URL` a `SB_KEY` svými hodnotami (Supabase → Project Settings → API; použijte jen veřejný *publishable* klíč). **Tajný klíč (service_role) nikdy nevkládejte do webu.**
3. Sestavte web: `python3 build.py`
4. Nahrajte na hosting a nastavte proměnné prostředí a tajemství (viz `NAVOD.md`).
5. V Supabase → Authentication → URL Configuration nastavte adresu svého webu.
6. Přepište texty, značku (název, logo, kontakty) a právní stránky (podmínky, ochrana údajů, cookies) tak, aby odpovídaly **vašemu** provozu. Součástí balíčku jsou jen vzory.

## Testy
`tests/` obsahuje automatické testy (Node a Python s Playwrightem). Spouštějí se proti lokálně sestavenému webu.

## Upozornění
- Zabezpečení, zálohy, provoz a právní soulad (smlouvy, ochrana údajů, daně a účetnictví) jsou odpovědností provozovatele.
- Fakturace je zatím jen pro dodavatele z ČR a Slovenska. Sazby DPH a ostatní údaje o zemích EU jsou orientační a před ostrým použitím je ověřte.
- Zkontrolujte, že aplikace po úpravě neodkazuje na původní projekt (adresa databáze, e-maily, odkazy na stahování).
