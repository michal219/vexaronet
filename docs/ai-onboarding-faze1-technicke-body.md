# AI onboarding – technické body před implementací (fáze 1a)

Stav: 2026-11-07. K tomuto dokumentu patří kód ve větvi `claude/happy-bell-5266nk`. Nic z něj není nasazené
a produkční databáze nebyla změněna (čtecí dotazy do katalogu a `pg_cron` bez textu příkazů).

Značky: **[OVĚŘENO]** přečteno z živé DB nebo prokázáno testem, **[NEOVĚŘENO]** zatím nelze nebo nebylo ověřeno.

## 1. Kdo spolehlivě spouští worker a obnovuje úlohy i po zavření prohlížeče

**Zjištění z živé DB [OVĚŘENO]:**
- Rozšíření `pg_cron` 1.6.4 a `pg_net` 0.20.4 jsou nainstalované a aktivní.
- Běží 6 naplánovaných úloh (`vexaronet-mobile-reminders`, `-registration-welcome`, `-customer-care`,
  `-daily-company-backups`, `-booking-challenge-cleanup`, `-expire-unfinished-enquiries`).
- Tři z nich (`mobile-reminders`, `registration-welcome`, `customer-care`) volají ven přes `http_post`. Fronta s odesíláním
  mimo databázi tedy v projektu už funguje bez prohlížeče.
- Za posledních 7 dní: minutové úlohy proběhly po 10 080×, `customer-care` (po 5 min) 2 016×, vše `succeeded`, žádné selhání.
- Text příkazů jsem schválně nečetl (mohl by obsahovat tajemství). **[NEOVĚŘENO]** zůstává, na jaký endpoint tyto úlohy
  volají a kde mají uložené tajemství. Před implementací workeru je nutné převzít stejný způsob (viz níže).

**Návrh pro AI části (fáze 2, teď nic z toho neexistuje):**
1. Zařazení do fronty = řádek v tabulce běhů (`attempt`, `lease_id`, `lease_until`, `idempotency_key`).
2. Okamžité spuštění: Cloudflare funkce po zařazení zavolá zpracování (`context.waitUntil`). Není to záruka.
3. **Záruka:** `pg_cron` každou minutu zavolá přes `pg_net` chráněný endpoint workeru. Ten převezme nejvýše N běhů
   s vypršeným zámkem. Spadlý worker tak nechá práci, kterou převezme další minutový cyklus.
4. Po 3 pokusech běh přejde do `failed` a uživatel dostane možnost dokončit ručně.
5. Výsledek ke staré revizi odpovědí se neuloží (`stale`).

**Co nelze ověřit bez dalších služeb [NEOVĚŘENO]:** časové a CPU limity Cloudflare Pages Functions na vašem tarifu,
způsob uložení tajemství v existujících cron úlohách (Vault, nebo text v příkazu). Pokud limity nestačí, stejné DB funkce
obslouží Cloudflare Cron Trigger nebo Supabase Edge Function.
**Pro tuto fázi worker není potřeba** (žádné AI volání), nic se nenasazuje.

## 2. Servisní klíč nesmí umožnit obejít lidské potvrzení

Implementováno a otestováno (`db/test/10_profile_tests.sql`, 65 kontrol, lokální PostgreSQL):

| Obrana | Důkaz |
|---|---|
| Každá funkce `profile_*` začíná `private.profile_actor`: vyžaduje `auth.uid()` (ověřenou identitu z JWT), roli JWT `authenticated`, členství `owner`/`admin` ve firmě a zapisovatelné předplatné. | Testy „service_role nemůže potvrdit profil“, „bez identity se nepotvrdí ani jako postgres“, „token s rolí postgres, ale cizí identitou, neprojde“ |
| Servisní klíč nemá uživatelskou identitu (JWT bez `sub`), takže `profile_actor` vždy odmítne. | totéž |
| `EXECUTE` na `profile_*` mají jen `authenticated`; `anon` a `service_role` ne (výchozí práva v `public` je jim dávají, proto je migrace odebírá výslovně). | test „matice práv“ |
| Tabulky profilu mají RLS a žádná práva pro `anon`, `authenticated` ani `service_role`. Klíč tedy nemůže „potvrdit“ přímým zápisem do tabulky. | test „ani service_role nemá práva na tabulky“ |
| `confirmed_by` se plní z `auth.uid()`, není to parametr. Potvrzení nese přesnou revizi a otisk obsahu. | testy potvrzení |
| Potvrzené verze a události nejdou upravit ani vlastníkem tabulky (trigger). | test neměnnosti |

Pravidlo pro budoucí AI kroky: servisní klíč bude jen v Cloudflare a bude volat výhradně funkce `claim` a `finish` pro běhy.
`finish` smí zapsat jen **návrh** (stav `proposal`). Žádná funkce dostupná servisnímu klíči neobsahuje potvrzení ani schválení.
Veřejný endpoint workeru je navíc chráněný tajemstvím, ale i kdyby ho někdo zneužil, potvrzení neprovede.

## 3. Sdílená validace: prohlížeč, Cloudflare, databáze

Jeden zdroj pravdy je `src/onboarding_schema.json` (podmnožina JSON Schema, 13 klíčových slov, bez `$ref` a `pattern`).

| Místo | Jak je napojené | Stav |
|---|---|---|
| Prohlížeč | `build.py` vloží schéma i validátor (`src/jsonschema_mini.js`, `src/profile_core.js`) do `index.html` | [OVĚŘENO] testem, schéma v `index.html` je shodné se zdrojem |
| Cloudflare | tytéž soubory se importují jako ES modul + JSON (`tests/profile_core.test.mjs` to dělá) | [OVĚŘENO] v Node 22; [NEOVĚŘENO] v bundleru wrangleru, použije se až ve fázi 2 |
| Databáze | kopie schématu je v migraci mezi značkami, hlídá ji `tools/sync_profile_schema.py --check`; validátor je funkce `private.vx_json_validate` | [OVĚŘENO] |

**Kontrola shody verzí:**
1. Drift při vývoji: `tools/sync_profile_schema.py --check` (je součástí `tests/db/run_local.sh`).
2. Shodné chování: `tests/profile_parity.py` vyhodnotí 122 společných vektorů JavaScriptem i databází a vyžaduje identický výsledek
   (validace, úplnost, odvození cíle, ořez textu). Cíl se navíc kontroluje proti nezávislému výpočtu v Pythonu.
3. Za běhu: prohlížeč porovná schéma z `profile_schema_info()` s vloženým schématem; při rozdílu vypne ukládání.
   Každé uložení nese `schema_version`, databáze jinou verzi odmítne (PT412).

Kontrola shody našla při první implementaci **dvě skutečné chyby** v databázových funkcích: chybějící pole se
vyhodnotilo jako `NULL` místo `false`, takže by databáze dovolila potvrdit profil bez lokality, názvu a popisu zákazníků.
Obě jsou opravené a vektory je hlídají. Parita je doložená na vektorech, nedokazuje shodu pro všechny možné vstupy.
Proto je podmnožina schválně malá a nepodporované klíčové slovo ve schématu vyhodí výjimku.

## 4. Konflikt revizí a HTTP 409

Nespoléháme na automatické chování. Databáze konflikt vyhodí výslovně: `raise exception 'revision_conflict' using errcode = 'PT409'`,
`detail = {"current_revision": N}`. PostgREST mapuje SQLSTATE `PTxxx` na HTTP stav `xxx`. Použité kódy:
`PT409` konflikt revize nebo otisku, `PT412` jiná verze schématu, `PT422` neplatná data (v `details` je seznam chyb),
`PT404` neexistující verze, `42501` oprávnění (PostgREST: 403, bez přihlášení 401).

Klient (`VXPCORE.mapRpcError`) konflikt pozná ze **tří nezávislých signálů** (kód `PT409`, HTTP stav 409, text `revision_conflict`).
Při konfliktu nikdy nepřepíše data tiše: nabídne „Načíst novější verzi“ nebo výslovné „Přepsat mojí verzí“.

- [OVĚŘENO] SQLSTATE a obsah chyb v databázi (testy), mapování v klientu (Node a UI testy).
- [NEOVĚŘENO] skutečný HTTP stav, který vrátí PostgREST na Supabase. K tomu je připraven
  `tests/db/check_http_status.mjs`, který se spustí v bezplatném testovacím projektu (`docs/TESTOVACI_PROSTREDI.md`).

## 5. `ai_proposals` a `ai_operations`: znovu použít, nebo ne

**Zjištění z živé DB [OVĚŘENO]:**
- `private.ai_operations`: `kind` je omezeno na `document` a `autopilot`, `status` na `processing/review/approved/rejected/failed`;
  sloupce pro soubor (`file_*`, `file_hash`), `brief`, `output`, `ai_output`, `lease`, `retry_count`, `reviewed_by`. V tabulce je 1 řádek.
- `private.ai_proposals`: `operation_id`, `event_key` (unikátní s firmou), `action` jsonb, `result` jsonb, `status` `review/approved/rejected`. 0 řádků.
- Obsluhují funkce `ai_workspace`, `ai_design_*`, `suite_*`, které aplikace v tomto repozitáři nevolá.
  Nevíme, jestli je používá jiná aplikace.

**Rozhodnutí: nepoužívat.**
1. Pro `kind = 'onboarding'` by bylo nutné změnit `CHECK` na existující tabulce. Existující konfiguraci zatím neměníme.
2. Význam je jiný (zpracování dokumentů a autopilot s `event_key`). Chybí vazba schválení na verzi a otisk obsahu, model, verze promptu a náklady.
3. Schválení v nich je obecné `reviewed_by`, bez otisku schvalovaného obsahu.

Převezmeme jen **vzor**: zámek `lease` + `retry_count`, stavy `review → approved/rejected`, RLS bez politik a přístup výhradně přes
funkce `SECURITY DEFINER`. Vlastní tabulka běhů přijde ve fázi 2. K sjednocení se lze vrátit, až bude jasné, komu tabulky patří.

## 6. Návrh nákladového limitu AI (placené běhy zůstávají vypnuté)

Model v projektu: `gemini-3.5-flash-lite` (výchozí v `functions/api/*.js`). Cena podle dokumentace Google
(https://ai.google.dev/gemini-api/docs/gemini-3, zjištěno 2026-11-07, před zapnutím znovu ověřit):
**0,30 USD / 1 M vstupních tokenů, 2,50 USD / 1 M výstupních tokenů** (výstup zahrnuje i „přemýšlecí“ tokeny).

Očekávaná volání na jeden průchod onboardingem (spec, oddíl 7): normalizace 1, doplňující otázky 1–3, sestavení profilu 1,
plán 1, kontrola 1, tedy typicky 5–7, nejvýše 9 volání. Přidáváme jeden opravný pokus u nevalidního JSON a dva pokusy při výpadku.

| Veličina | Návrh | Odvození |
|---|---|---|
| Vstup jednoho volání | ≤ 4 000 tokenů | prompt ≤ 1 500 + vybrané sekce profilu ≤ 2 500 |
| Výstup jednoho volání | ≤ 2 000 tokenů (`maxOutputTokens`) | včetně přemýšlecích tokenů |
| Nejvyšší cena jednoho volání | **0,0062 USD** | 4 000 × 0,30 / 1 M + 2 000 × 2,50 / 1 M |
| Pevný strop volání na jeden průchod | 12 | 9 běžných + opravy a opakování |
| Nejvyšší cena jednoho průchodu | **0,074 USD** | 12 × 0,0062 |
| Průchodů na firmu a měsíc | 3 | opakování po změně profilu |
| **Nejvyšší měsíční cena na firmu** | **0,22 USD** (36 volání) | 3 × 0,074 |

Peněžní limit **nenastavuji**. Je to rozhodnutí majitele. Navrhuji:
- Limit se ukládá v databázi (`monthly_limit_microusd`, `NULL` = placené běhy vypnuté) a vynucuje ho server před zařazením běhu
  (nejvyšší cena zařazovaného běhu se rezervuje atomicky, skutečná se po doběhnutí upraví podle `usageMetadata`).
- Dokud hodnota není nastavená, funkce zařazení AI běh **odmítne**. Ručně vyplněný profil funguje dál.
- Při změně `GEMINI_MODEL` se strop přepočítá podle tabulky cen v kódu. Neznámý model se odmítne.
- Navrhovaná hodnota k nastavení: **0,25 USD měsíčně na firmu** (0,22 zaokrouhleno nahoru), jednorázově 0,08 USD na průchod.
  Je to technický strop odvozený z čísel výše, ne rozpočet.
- Existující funkce v `functions/api/` posílají parametr `temperature`, který Google u řady 3.x označuje jako zastaralý
  (stejná stránka dokumentace). Na tuto fázi nemá vliv, ale před fází 2 je to nutné ověřit.

## 7. Co fáze 1a obsahuje

Ruční profil firmy: databázové tabulky a funkce, formulář v aplikaci, automatické ukládání, verzování, potvrzení,
profil pro hlavní firmu (společné údaje) a pobočku (jen lokalita a lokální odlišnosti), jednoznačný výběr aktivní firmy.
Žádné AI volání, žádný worker, žádná změna existující konfigurace ani AI limitů. Seznam testů a co zbývá ověřit:
`docs/TESTOVACI_PROSTREDI.md`. Souvisejí úkoly před provozem: `docs/UKOLY_PRED_PROVOZEM.md`.
