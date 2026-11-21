# Aktualizace zdrojového kódu

Kupující dostává aktualizace po zaplacení, a to takto: kód je v **soukromém repozitáři na GitHubu**, do kterého prodávající po zaplacení přidá GitHub účet kupujícího s právem jen ke čtení. Nové verze kupující stáhne sám. Nic se do jeho prostředí neposílá bez jeho vědomí.

## Pro prodávajícího (vydání nové verze)
1. Změny otestujte a zvyšte číslo v souboru `VERSION` (1.1.0 = nové funkce, 1.0.1 = opravy).
2. Do `CHANGELOG.md` napište, co se změnilo. Změny databáze piště vždy jako nový soubor v `db/migrations` (aditivní, opakovatelně spustitelný, s popisem), nikdy neupravujte staré.
3. Nahrajte do soukromého repozitáře a označte vydání: `git tag v1.1.0 && git push --tags`.
4. Zveřejněte `version.json` na adrese, kterou kupující mají v `update_feed` (například `{"version":"1.1.0"}`). Aplikace pak majiteli ukáže upozornění.
5. Přístup: po zaplacení přidat účet kupujícího (read-only), při vrácení peněz nebo porušení podmínek přístup odebrat. Co kupující už stáhl, mu zůstává; rozsah licence určují licenční podmínky.

## Pro kupujícího (přijetí aktualizace)
1. Doporučený způsob: `git remote add upstream <adresa soukromého repozitáře>`, pak `git fetch upstream` a `git merge upstream/main` (vaše vlastní úpravy zůstanou, případné konflikty vyřešíte sami).
2. Vaše nastavení (databáze, klíč, zdroj aktualizací) je v souboru `config.local.json`, který se při aktualizaci nepřepisuje. Vzor: `config.local.example.json`.
3. `python3 tools/update_check.py` vypíše nové databázové migrace. Udělejte zálohu databáze, spusťte je v Supabase SQL editoru a potom `python3 tools/update_check.py --done`.
4. `python3 build.py`, otestujte a nasaďte.

## Upozornění v aplikaci
Pokud je v `config.local.json` vyplněno `update_feed`, aplikace majiteli firmy ukáže upozornění na novější verzi. Je to jen dotaz na číslo verze, nic se nestahuje ani neinstaluje. Nevyplníte-li ho, aplikace se nikam neptá. Adresa zdroje se přidá do pravidel zabezpečení (CSP) automaticky při sestavení.
