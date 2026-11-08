# Dokončení AI části: úkoly, stav a další krok

Průběžný stav, aby šlo po přerušení pokračovat bez nového průzkumu. Poslední aktualizace je v sekci **Stav práce** dole.
Podklady: `docs/AUTOPILOT.md` (limity a režimy), `docs/AI_ONBOARDING_FAZE1.md` (profil firmy), `docs/SECURITY_STATUS.md`, `docs/PRAVNI_SOULAD.md`.

## Společná pravidla pro každý AI modul (akceptační kritéria)

1. **Data správné firmy:** firma podle `cid` a členství. Pracuje s **potvrzeným** profilem firmy (`profile_get` → `active`), ne s textem z prohlížeče.
2. **Server vynucuje:**
   - roli (vlastník/správce) a tarif PRO+;
   - **peněžní limit Autopilota**: `autopilot_reserve` s tokenem uživatele před voláním AI, `autopilot_settle` (jen service_role) po něm podle skutečné spotřeby tokenů;
   - platformní vypínač `paid_runs_enabled`.
3. **Ukládání a stav:** výsledek AI se uloží v DB i se vazbou na běh (`run_id`). Lidské schválení se zapisuje s otiskem schváleného obsahu.
4. **Opakování a obnovení:**
   - každý požadavek nese idempotenční klíč;
   - stejný klíč znovu nevolá AI a vrátí uložený výsledek;
   - běžící požadavek vrátí `in_progress`;
   - po obnovení stránky jde stav načíst z DB.
5. **Chyby:** chyba poskytovatele nebo neplatný výstup se vypořádá jako `failed` podle skutečné spotřeby a nic neuloží. Uživatel uvidí srozumitelnou hlášku.
6. **Žádné falešné výsledky:** co nemá zdroj dat, zobrazí „Nepřipojeno“ nebo „–“. Externí závislost je evidovaná níže.
7. **Test:** databázový test pod rolemi a end-to-end test skutečného endpointu proti skutečné PostgreSQL (simulovaný jen poskytovatel AI a e-mailu). U UI test v prohlížeči.

## AI Marketing Autopilot: průchod a úkoly

| Krok | Stav před touto prací | Implementovatelné nyní | Vyžaduje vaše údaje nebo rozhodnutí | Externí závislost |
|---|---|---|---|---|
| 1. Firemní onboarding | ruční formulář profilu (nasazeno v DB, UI ve větvi) | vstup z dashboardu do profilu, kontrola potvrzení | – | – |
| 2. Potvrzený profil | `profile_confirm` jen člověkem (nasazeno) | strategie se bez potvrzeného profilu nespustí | – | – |
| 3. Strategie | jen popisek „zatím nelze“ | **AI návrh strategie z profilu** (cíl s měřitelnou metrikou, cílovky, kanály, témata, frekvence), úpravy, schválení člověkem, verze | zapnout placené běhy a limit firmy | Gemini API (klíč už existuje; účtování a ceník ověřit při zapnutí) |
| 4. Generování obsahu | `/api/marketing`: jednotlivý text, bez profilu a bez peněžního limitu | **dávka návrhů příspěvků ze schválené strategie** do konceptů (`marketing_posts`) s vazbou na strategii a běh | totéž | totéž |
| 5. Náhled a úpravy | náhled a úprava existují | otisk obsahu: po úpravě je nutné nové schválení | – | – |
| 6. Schválení | změna stavu z prohlížeče | **schválení na serveru** (člověk, vlastník/správce, otisk obsahu) | – | – |
| 7. Kalendář | týdenní kalendář z `marketing_posts` | beze změny (už čte skutečná data) | – | – |
| 8. Dostupné publikování | žádné | **publikace na web firmy ve Vexaronetu** (sekce Novinky, plánovaná podle data), **ruční zveřejnění** se záznamem odkazu | – | Facebook/Instagram: Meta Graph API (aplikace, App Review, ověření firmy, OAuth firmy). Google Business Profile API (schválení přístupu). TikTok, LinkedIn: vlastní schvalovací procesy. E-mail zákazníkům firmy: ověřená doména odesílatele (Resend) a souhlasy zákazníků |
| 9. Vyhodnocení výsledků | grafy poptávek a zákazníků z DB | **výsledky příspěvků:** skutečné poptávky, zákazníci, rezervace a objednávky v okně po zveřejnění proti stejnému oknu před ním (souvislost, ne prokázaný účinek), ručně zadané metriky z kanálů (s uvedením zdroje), plnění cíle strategie | – | Dosah a prokliky: Meta Insights, Google Analytics/Search Console, nebo vlastní analytika jen se souhlasem (připraveno, vypnuto) |

## Další AI moduly (společný seznam z `src/autopilot_core.js`)

| Modul | Hotovo dnes | Implementovatelné nyní | Rozhodnutí / údaje | Externí |
|---|---|---|---|---|
| AI CEO (`/api/advisor`) | chat nad souhrnem čísel z prohlížeče, kontrola volajícího, `reserve_ai` | souhrn počítaný serverem z DB a potvrzený profil, peněžní limit Autopilota, uložení doporučení a jeho stav (přijato/odmítnuto) | – | Gemini |
| AI Účetnictví (`/api/accountant`) | vytěžení dokladu, dotazy | uložení vytěženého návrhu jako konceptu výdaje ke schválení (dnes se jen vrací), peněžní limit | tarif `accountant` mimo `reserve_ai` (viz SECURITY_STATUS F-2) | – |
| AI Weby a e-shopy (`/api/web-ai`) | návrh textů webu | návrh z potvrzeného profilu, uložení jako koncept webu, schválení, peněžní limit | – | – |
| AI Obchodník | jen CRM bez AI | návrh dalšího kroku a nabídky k obchodnímu případu z CRM, schválení | – | odesílání e-mailů zákazníkům: ověřená doména |
| AI Automatizace | pravidla navrhují úkoly | AI návrh pravidel (schválení člověkem) | – | běh na pozadí: plánovač (pg_cron je k dispozici) |

## Zapnutí placených běhů (připravený krok, ne nasazení)

Viz `docs/AUTOPILOT.md` a krok v sekci „Nasazení“ níže. Podmínky:
1. Ověřit ceník modelu v `private.ai_model_prices` proti oficiálnímu ceníku k datu zapnutí.
2. Nastavit limit firmy (vlastník v dashboardu, schváleno 0,25 USD/měsíc).
3. `update private.autopilot_platform set paid_runs_enabled = true` (jen SQL, žádná API funkce to nedělá).
4. Sledovat `private.autopilot_runs` a `private.autopilot_events`.

Návrat je `paid_runs_enabled = false`: běžící rezervace doběhnou a další se odmítnou.

## Stav práce

(průběžně doplňováno níže)

### 2026-11-08: AI Marketing, krok 1 (databáze) – HOTOVO ve větvi
- **Migrace:** `db/migrations/20261112100000_ai_marketing.sql` (+ rollback). Obsahuje strategie s verzemi, vazby příspěvků na strategii a běh, schválení s otiskem obsahu a trigger, který po změně schváleného obsahu vrátí příspěvek do konceptu. Dále publikaci na web firmy (veřejná `public_site_news`, jen schválené, nezměněné a s datem do dneška) a ruční zveřejnění s odkazem https. Výsledky jsou dvojí: systémové (poptávky, zákazníci, rezervace, objednávky 7 dní po proti 7 dnům před) a ručně zadané se zdrojem. Plnění cíle strategie se počítá ze skutečných dat.
- **Test:** `tests/db/run_ai_marketing_local.sh` má **37 kontrol** a prošel včetně přesného rollbacku.
- **Další krok:** endpoint `/api/ai-marketing` (strategie a dávka příspěvků) s `autopilot_reserve` a `autopilot_settle` a end-to-end test.

### 2026-11-08: AI Marketing, krok 2 (endpoint) – HOTOVO ve větvi
- **Endpoint:** `functions/api/ai-marketing.js`, POST `{action:'strategy'|'posts', cid, key, count?, from?}`.
  - Postup: přihlášení, role vlastník/správce, PRO+ → potvrzený profil z DB (`profile_get`; text z prohlížeče se ignoruje) → u příspěvků schválená strategie → `autopilot_reserve` (klíč `akce:key`) → Gemini → kontrola a normalizace výstupu → `mkt_strategy_store` / `mkt_posts_store` (service_role) → `autopilot_settle` podle `usageMetadata`.
  - Chyby: 401/403 oprávnění a tarif, 403 `paid_runs_disabled`, 402 `budget_not_set`/`budget_exceeded`, 412 `profile_not_confirmed`/`strategy_not_approved`, 409 `in_progress`/`previous_failed` (nový pokus = nový klíč), 502 chyba poskytovatele nebo neplatný výstup (běh `failed`, nic se neuloží).
  - Potřebné proměnné prostředí: `GEMINI_API_KEY`, `SUPABASE_SERVICE_KEY` (volitelně `GEMINI_MODEL`). Bez nich vrací 503.
- **Test:** `PSQL="runuser -u postgres -- psql" node tests/ai_marketing_e2e.test.mjs` → **13 testů prošlo** (skutečná PostgreSQL přes převodník PostgREST, simulovaný jen Gemini). Ověřeno: oprávnění, tarif, vypínač, limit, profil z DB, idempotence, in_progress, chyby a vypořádání nákladů, příspěvky jen ze schválené strategie a v povolených kanálech a datech.
- **Další krok:** UI dashboardu (záložka Strategie, dávka návrhů v Obsahu, schválení přes `mkt_post_approve`, publikace, výsledky v Analýze) a sekce Novinky na webu firmy (`public_site_news`). K tomu UI test.

### 2026-11-08: AI Marketing, krok 3 (UI a web firmy) – HOTOVO ve větvi
- **UI:** `src/ai_marketing_ui.js` (připojeno za `src/autopilot_dash.js` v `build.py`). Vzhled dashboardu zůstává podle reference, mění se jen obsah karet.
  - **Strategie:** kontrola potvrzeného profilu, „Vytvořit návrh strategie“ přes endpoint, zobrazení konceptu a verze, úprava (formulář, otisk zobrazené verze), schválení, plnění cíle ze skutečných dat.
  - **Přehled:** karta strategie ukazuje cíl a plnění. Schválení v Aktuálních úkolech jde přes `mkt_post_approve` (SHA-256 otisk shodný s DB) místo přímého zápisu.
  - **Obsah:** dávka návrhů ze schválené strategie (počet, od data); původní generátor zůstává.
  - **Kalendář:** náhled s kroky schválit / zveřejnit na webu firmy / zaznamenat ruční zveřejnění s https odkazem / zrušit zveřejnění.
  - **Analýza:** výsledky zveřejněných příspěvků (poptávky, zákazníci, rezervace a objednávky 7 dní po proti 7 dnům před, s upozorněním na souvislost) a ruční výsledky se zdrojem.
  - **Opakování a obnovení:** idempotenční klíč s parametry v `localStorage`. Po přerušení nebo obnovení stránky se zobrazí „nebyl dokončen“ a „Zkontrolovat“ pošle stejný klíč, takže AI se neplatí dvakrát. Při 409 `in_progress` klíč zůstává, po úspěchu nebo definitivní chybě se smaže.
  - **Bez migrace v DB**, v ukázce a pro zaměstnance se nic nespouští. UI zobrazí srozumitelnou hlášku.
- **Web firmy:** sekce **Novinky** v `siteHTML` z `public_site_news` (escapovaná). Bez novinek se nezobrazí. Starší DB bez funkce web nerozbije.
- **Opravená chyba během testu:** zavření dialogu přes `remove()` nechávalo posluchač Esc, který blokoval další dialogy. Nyní se dialog zavírá přes jeho vlastní tlačítko.
- **Testy:**
  - `python3 tests/ai_marketing_ui.py`: všechny kontroly prošly (36). Pokrývá průchod profil → strategie → úprava → schválení → dávka → obnovení stránky se stejným klíčem → schválení s otiskem → publikace → výsledky → web firmy, dále ukázku, zaměstnance a stav bez migrace.
  - `tests/autopilot_ui.py` a regresní UI testy prošly (viz níže).
- **Nasazení:** připravený krok s dopady a návratem je v `docs/NASAZENI_AI_MARKETING.md` (nenasazeno; placené běhy zůstávají vypnuté).

#### Stav průchodu Marketing Autopilota
| Krok | Stav ve větvi | Zbývá / závislost |
|---|---|---|
| Onboarding a potvrzený profil | hotovo (profil nasazen dříve) | – |
| Strategie (AI návrh, úprava, schválení, verze) | hotovo, testy DB 37 + e2e 13 + UI | zapnout placené běhy (vaše rozhodnutí) |
| Generování obsahu (dávka ze strategie) | hotovo | totéž |
| Náhled, úpravy, schválení s otiskem | hotovo | – |
| Kalendář | hotovo (čte skutečná data) | – |
| Publikování | web firmy a ruční záznam hotovo | Facebook/Instagram: Meta Graph API + App Review + ověření firmy; Google Business Profile API; e-mail zákazníkům: ověřená doména a souhlasy |
| Vyhodnocení | systémová data z DB a ruční metriky se zdrojem hotovo | dosah a prokliky: Meta Insights / GA / Search Console |
| Nasazení | připraveno (`docs/NASAZENI_AI_MARKETING.md`) | váš souhlas s nasazením (spolu s dashboardem `8d586f0`) |

- **Další krok:** AI CEO (`/api/advisor`). Souhrn počítaný serverem z DB a z potvrzeného profilu, peněžní limit přes `autopilot_reserve`/`autopilot_settle`, uložení doporučení se stavem přijato/odmítnuto, e2e a UI test.
