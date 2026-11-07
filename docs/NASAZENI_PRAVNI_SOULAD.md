# Nasazení oprav právního souladu: přehled, dopady a návrat

Stav k 10. 11. 2026. **Nic z toho není nasazené. Tento dokument nasazení neautorizuje.** Před každou částí je potřeba výslovný souhlas vlastníka.
Obsah oprav je popsaný v `docs/PRAVNI_SOULAD.md`. Produkci jsem jen četl:
- `private.platform_admins`: 0 záznamů;
- `newsletter_subscribers` se souhlasem: 3;
- tabulky marketingu a DSA neexistují;
- cron pro novinky neexistuje.

## Závislosti a pořadí

Větev `claude/happy-bell-5266nk` obsahuje tři nezávislé sady:
- nenasazený **dashboard** (`8d586f0`);
- **bezpečnostní opravy** (`01fcaff`, `98bacf4`, `b0d47ad`);
- **právní soulad** (commit s tímto dokumentem).

Právní soulad staví na bezpečnostních opravách: `_headers`, SRI a `src/ai_guard.js`. Postup na samostatné větvi z `main`:
1. `git cherry-pick 01fcaff 98bacf4 b0d47ad <commit právního souladu>`. Dashboard nepřenášet.
2. `python3 build.py`. Rozdíl `index.html` proti `main` nesmí obsahovat dashboard (`apd`).

Doporučené pořadí: **(1) DB DSA → (2) web a funkce → (3) DB marketing, až budou údaje odesílatele.**
Části 1 a 3 jsou na sobě nezávislé. Když se nasadí web (2) bez DSA migrace (1), formulář `/nahlasit/` vrátí „nepodařilo se, napište na info@…“. Funguje to tedy, jen bez evidence.

## Předpoklady (ruční kroky vlastníka)

| Co | Kde | Pro co |
|---|---|---|
| `SUPABASE_SERVICE_KEY` | Cloudflare Pages, Settings, Variables and Secrets | `/api/dsa-notice`, `/api/newsletter` (už potřebný pro chat podle bezpečnostních oprav) |
| `RESEND_API_KEY` | totéž (už existuje) | potvrzení DSA, vyrozumění, novinky |
| `OPERATOR_NAME`, `OPERATOR_ADDRESS` | totéž | **bez nich se novinky neodešlou** |
| `DSA_CONTACT_EMAIL` (nepovinné) | totéž | jiné kontaktní místo než info@vexaronet.com |
| `MARKETING_DISPATCH_SECRET` | totéž a plánovač | spouštění dávek novinek |
| Správce platformy | `insert into private.platform_admins(user_id) values ('<uuid účtu>')` | rozhodování o oznámeních DSA, plánování novinek |
| Identifikace provozovatele v textech | `build.py` (LEGAL), pak build | obchodní podmínky, zásady, `/dsa/` |

## 1) Databáze: DSA (`20261110110000_dsa_oznameni.sql`)

- **Mění:** jen nové objekty, tedy `private.dsa_notices`, `private.dsa_events` (jen pro připisování) a funkce `dsa_*`. Stávající tabulky a funkce se nemění, `sites`, `shop_settings` a `booking_profiles` se jen čtou.
- **Dopad:** žádný na stávající aplikace, ani na druhou aplikaci nad DB.
- **Ověření:** `tests/db/run_legal_local.sh` lokálně. Po nasazení jen čtením: `select to_regclass('private.dsa_notices'), has_function_privilege('anon','public.dsa_submit(jsonb,text)','execute')` má vrátit tabulku a `false`. Volitelně zkušební oznámení v transakci s vynuceným rollbackem.
- **Návrat:** `20261110110000_dsa_oznameni_rollback.sql`. **Před ním exportovat** `private.dsa_notices` a `private.dsa_events`: evidence může být potřeba pro dozor nebo spor.

## 2) Web a Cloudflare funkce

| Změna | Dopad | Riziko | Návrat |
|---|---|---|---|
| Fonty a supabase-js lokálně, CSP bez Google a jsDelivr | Žádné požadavky na cizí servery. Vzhled stejný (stejné fonty, variabilní). | Prohlížeč bez podpory variabilních fontů dostane záložní písmo. | revert commitu |
| `src/consent.js` (správa souhlasu) | V produkci vše vypnuté: žádná lišta, jen odkaz „Nastavení soukromí“ s informací. | Žádné. | revert |
| Věk při registraci a u novinek | Nové povinné políčko. Mladším 18 let firma nevznikne, mladší 15 let nemohou odebírat novinky. | Méně registrací od nezletilých (záměr). | revert |
| E-shop: „Objednávka zavazující k platbě“, souhrn, místo „souhlasu“ informace | Zákazník e-shopu vidí jasný souhrn. | Žádné (stejný průběh). | revert |
| Žádost o tarif: „Odeslat nezávaznou žádost“ s cenou, obdobím a obnovováním | Jen text. | Žádné. | revert |
| `/dsa/`, `/nahlasit/`, `/odhlasit/`, odkaz „Nahlásit obsah“ na veřejných stránkách firem, úpravy podmínek, zásad a cookies | Nové stránky a texty. | Odkaz „Nahlásit obsah“ je vidět na webech firem (záměr podle čl. 16). | revert |
| `/api/dsa-notice`, `/api/dsa-admin` | Přijímání a vyřizování oznámení. | Bez migrace (1) vrací 503 s kontaktem. | revert |
| `/api/unsubscribe`, `/api/newsletter` | Odhlášení a odesílání novinek. | Bez migrace (3) odhlášení vrací 503. Odkazy ale zatím nikdo nedostal. | revert |

- **Staré otevřené stránky a PWA:** `sw.js` je network-first a `no-cache`, po obnovení se načte nová verze. Starý `index.html` v cache odkazuje na Google Fonts, které nová CSP blokuje: zobrazí se záložní písmo, funkčnost zůstává.
- **Ověření po nasazení:**
  1. `curl -sI https://vexaronet.com/` vrací CSP bez `fonts.googleapis.com`;
  2. načtení stránky v prohlížeči s vývojářskými nástroji: 0 požadavků na cizí domény;
  3. registrace ukazuje potvrzení věku;
  4. `/dsa/` a `/nahlasit/` se otevřou;
  5. testovací e-shop ukazuje „Objednávka zavazující k platbě“ (bez odeslání).

## 3) Databáze: marketing (`20261110100000_marketing_odhlaseni.sql`)

- **Mění:** jen nové objekty, tedy `private.marketing_*` a funkce `marketing_*`. `newsletter_subscribers` se jen čte.
- **Kdy:** až budou údaje odesílatele a rozhodnutí novinky rozesílat. Do té doby se žádné novinky nepošlou, a tedy není z čeho se odhlašovat.
- **Plánovač:** pg_cron s `net.http_post` na `https://vexaronet.com/api/newsletter` s `{"action":"dispatch"}` a hlavičkou `x-dispatch-secret` (tajemství uložit do Vault, ne do příkazu). Případně ruční spuštění.
- **Ověření:** `tests/db/run_legal_local.sh` a `tests/legal_e2e.test.mjs` lokálně. Po nasazení první zprávu poslat jen testovací adrese (dočasně `consent` jen u ní), vyzkoušet odkaz pro odhlášení a ověřit, že další dávka odhlášené adrese nepřijde.
- **Návrat:** `20261110100000_marketing_odhlaseni_rollback.sql`. **Před ním exportovat `private.marketing_suppressions`**: odhlášené adresy se nesmí znovu oslovit.

## Co se nemění

Stávající databázové funkce a tabulky, druhá aplikace (edge funkce) i transakční e-maily (registrace, obnova hesla, pozvánky, rezervace, přehled).
