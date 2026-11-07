# AI onboarding Vexaronetu – implementační specifikace

Stav: **návrh k implementaci**, 2026-11-07. Zatím nebyl změněn funkční kód, databáze ani nasazení.

> **Stav implementace (fáze 1a, větev `claude/happy-bell-5266nk`, nenasazeno):** hotový je ruční profil firmy, tedy část kroků 1–5
> a oddílů 4, 5, 8 a 10 této specifikace, bez AI. Rozdíly oproti návrhu v oddílu 4:
> - Místo `onboarding_sessions` / `onboarding_answers` / `profile_versions` / `profile_field_evidence` jsou zatím 4 tabulky
>   `private.company_profile_drafts`, `_versions`, `_active_profile`, `_events`. Koncept má revizi, potvrzená verze je neměnná a nese otisk obsahu.
>   Původní odpovědi a evidence zdrojů přijdou s AI částí (fáze 2), dnes jsou všechny údaje ručně zadané uživatelem.
> - Profil má dvě části: `shared` (patří hlavní firmě) a `local` (lokalita a odlišnosti, má ji i pobočka).
> - Role: potvrdit smí `owner` i `admin`, Editor se nezavádí. Ruční profil je ve všech tarifech, AI část bude jen PRO a vyšší.
> - Konflikt revize = SQLSTATE `PT409` (HTTP 409), neplatná data `PT422`, jiná verze schématu `PT412`.
> - Popis, důkazy a otevřené body: `docs/ai-onboarding-faze1-technicke-body.md`, `docs/TESTOVACI_PROSTREDI.md`, `docs/UKOLY_PRED_PROVOZEM.md`.

Vychází z dodané specifikace („Implementační specifikace AI onboardingu“) a je přizpůsobená
**skutečnému stacku**. Projekt se nepřepisuje do Next.js a nevzniká druhý systém firem.

Podklady:
- databázový snapshot `db/snapshot/` (živá DB `micymdbqgzeckiqyvvkn`, jen čtení),
- audit a plán `docs/AI_ONBOARDING_FAZE1.md` (tento dokument ho v části datového modelu
  onboardingu nahrazuje).

Značky:
| Značka | Význam |
|---|---|
| **[DB✓]** | Ověřeno v živé DB (snapshot 2026-11-07). |
| **[DB?]** | Před implementací vyžaduje ověření v databázi. |
| **[EXT?]** | Vyžaduje ověření nastavení Cloudflare nebo Supabase mimo databázi. |
| **[ROZH]** | Čeká na rozhodnutí vlastníka produktu. |

---

## 0. Přizpůsobení stacku

| Původní specifikace | Vexaronet (skutečnost) |
|---|---|
| Next.js / TypeScript | Statická aplikace v jednom `index.html`, který generuje `build.py`. Nové UI bude samostatný modul `src/onboarding_ui.js`, který se vloží zástupným znakem jako `src/crm_ui.js` (`build.py:2324`). Typy se popíšou JSDocem, bez kompilace. |
| Route Handlers / Server Actions | **Datové operace:** Supabase RPC volané z prohlížeče s JWT uživatele, tedy SECURITY DEFINER funkce ve vzoru DB (`public` obálka → `private` jádro, `search_path=''`) **[DB✓]**. **AI operace:** Cloudflare Pages Functions `functions/api/onboarding-*.js` (drží `GEMINI_API_KEY`). |
| `organization_id` | `company_id` → `public.companies(id)`. Členství `public.company_members`, role `owner` / `admin` / `employee` **[DB✓]**. |
| Zod | Jedno **JSON Schema** jako zdroj pravdy (`src/onboarding_schema.js`), viz oddíl 5. Používá ho prohlížeč, Cloudflare funkce i DB (`jsonb_matches_schema`, rozšíření `pg_jsonschema` je nainstalované **[DB✓]**). Bez npm závislostí. |
| SSR přihlášení Supabase pro Next.js | Neplatí. Prohlížeč používá supabase-js s veřejným klíčem. Cloudflare funkce ověřují JWT přes `auth/v1/user`, jako ostatní `functions/api/*.js`. Token jde v hlavičce `Authorization`, ne v cookie, takže CSRF se neuplatní. |
| Trvalá fronta a worker | Fronta = tabulka běhů v Postgresu se zámkem (lease), stejně jako stávající `*_jobs` / `*_finish` v DB **[DB✓]**. Zpracovává ji Cloudflare funkce (`context.waitUntil`). Zaseknuté běhy obnovuje `pg_cron` + `pg_net` voláním chráněného endpointu, stejně jako ranní přehled (`digest.js`, `DIGEST_SECRET`). |
| AI poskytovatel | Google Gemini (`GEMINI_API_KEY`, `GEMINI_MODEL`), jak už projekt používá. |
| Feature flag | Proměnná `ONBOARDING_AI` v Cloudflare (vypne nové AI běhy) a sloupec v DB pro konkrétní firmy (pilot). Formulář a uložená data zůstanou dostupná i při vypnutí. |
| Role Vlastník / Správce / Editor / Čtenář | Viz oddíl 8. Role Editor a Čtenář v DB neexistují **[DB✓]**. |

---

## 1. Cíl a hranice

Onboarding vytvoří **uživatelem potvrzený, verzovaný profil firmy**. AI ho použije při
přípravě marketingových doporučení a návrhů.

Výstupy:
- profil firmy se zdrojem každého údaje,
- přehled nejasností a chybějících informací,
- měřitelný obchodní cíl,
- první marketingový plán (30 dní a rámec šestiměsíčního cíle),
- nastavení oprávnění a schvalování.

Hranice MVP:
- Dokončení onboardingu **nikdy** nepublikuje obsah, nepřipojuje reklamní účty ani neutrácí peníze.
- AI jen připravuje návrhy.
- Onboarding nepředstírá úplnost. Získá minimum pro užitečný první výstup, zbytek doplňuje postupně.

---

## 2. Výchozí data testovací firmy Autoservis Konina

Původní odpovědi se ukládají **beze změny**. Jazykové opravy jsou samostatný návrh.

| # | `field_key` | Oblast | Zadaný údaj (doslova) | Zpracování |
|---|---|---|---|---|
| 1 | `identity.name` | Název | autoservis konina | Navrhnout „Autoservis Konina“, potvrdit zobrazovaný název. |
| 2 | `identity.activity` | Činnost | autoservisem, chpivanim auta, ůprava výfuku a další | Autoservis a úpravy výfuků lze rozpoznat. „chpivanim auta“ → otázka. |
| 3 | `identity.website` | Web | vexaronet.com | Nepotvrzený web firmy. Může jít o adresu samotného Vexaronetu → otázka. |
| 4 | `services.raw` | Služby | výměna a předelani výfuku, a další | Navrhnout „Výměna a úpravy výfuků“. Další služby nedoplňovat. |
| 5 | `audience.raw` | Zákazník | řidičí v okoklí prahy | Navrhnout „Řidiči v okolí Prahy“. Doplnit lokalitu a dojezd. |
| 6 | `positioning.claims` | Výhoda | ryachlost, cena, kvalita | Tvrzení firmy, nikoli prokázané srovnání s konkurencí. |
| 7 | `financial.revenue` | Měsíční tržby | 146000 | Číslo 146 000. Potvrdit měnu, období a význam. |
| 8 | `financial.budget` | Rozpočet | 5000 | Číslo 5 000. Potvrdit měnu, periodicitu a co zahrnuje. |
| 9 | `channels.raw` | Kanály | facebook, instagram | Normalizovat na Facebook, Instagram. **Neznamená připojené účty.** |
| 10 | `goal.raw` | Cíl | zvýšit prodeje o 35 % | Upřesnit metriku (tržby, zakázky…). |
| 11 | `goal.horizon` | Horizont | 6 měsíců | Doplnit datum zahájení. |
| 12 | `problem.raw` | Problém | málo nových zákazníků | Zaměření plánu na získávání nových zákazníků. |

**Podmíněný výpočet (deterministický, v aplikaci):**
- Po potvrzení „měsíční tržby 146 000 Kč, růst o 35 %“ je cíl **197 100 Kč měsíčně**,
  rozdíl **51 100 Kč**.
- Výpočet probíhá v celých haléřích a v bazických bodech:
  `cíl = výchozí × (10 000 + bp) / 10 000`, kde 35 % = 3 500 bp.
  `14 600 000 × 13 500 / 10 000 = 19 710 000 haléřů`.
  Zaokrouhlení: polovina nahoru, na haléře.
- Závazný je výpočet DB funkcí `private.goal_target(...)`. JavaScript zobrazuje jen náhled
  stejného vzorce.
- Do potvrzení jde o **scénář**, ne schválený cíl. Bez ceny zakázky, kapacity a konverzních dat
  systém neurčuje počet poptávek a neslibuje dosažení cíle.

---

## 3. UX onboardingu

### Umístění v aplikaci
- Nový modul `src/onboarding_ui.js` (zástupný znak `@@ONB@@` v `build.py`). Nahradí kartu
  `onboard()` (`build.py:955`).
- Spouští se:
  - po prvním otevření aplikace vlastníkem nebo správcem, pokud firma nemá potvrzený profil,
  - kdykoli z Nastavení („Profil firmy pro AI“).
- Registrace přestane ukládat `onboarded:true`, `features` a `ui_industry` do metadat uživatele
  (`build.py:670`, `:2247`, `:2249`). Stav onboardingu patří **firmě**.
- Veškerý text od uživatele i od AI se vykresluje přes `esc()` nebo `textContent`. Žádné
  `innerHTML` s neošetřeným výstupem modelu.

### Kroky
Kroky, otázky a chování odpovídají původní specifikaci:

1. **Firma a služby.** Název, činnost, služby, web nebo „Nemáme web“. Lze vložit volný popis;
   AI nabídne strukturované shrnutí, původní odpověď zůstává viditelná. Pro testovací firmu:
   - „Co znamená ‚chpivanim auta‘? Myslíte chiptuning, nebo jinou službu?“
     Chiptuning se bez potvrzení **nesmí** objevit v nabídce.
   - „Patří vexaronet.com vašemu autoservisu, nebo jde o adresu Vexaronetu?“
   - Načtení webu je samostatná volba (zapne se až po splnění bezpečnosti, oddíl 9).
     Onboarding funguje i bez něj.
2. **Zákazníci a lokalita.** Provozovna nebo obsluhovaná oblast, dojezdová vzdálenost, typičtí
   zákazníci, prioritní služby, kapacita pro nové zakázky. Přesná adresa jen tam, kde ji funkce
   potřebuje. „Okolí Prahy“ ≠ potvrzená adresa v Praze.
3. **Výchozí situace a cíle.** Význam a období tržeb, měna a periodicita rozpočtu, co rozpočet
   zahrnuje, cílová metrika, výchozí hodnota a termín, počet nových zákazníků. U čísel volba
   „Nevím“. Chybějící číslo AI nenahradí odhadem.
4. **Značka a omezení.** Tón, způsob objednání, fotografie a logo, nenabízené služby,
   schvalovatel, omezení nabídky. Před reklamním návrhem musí být vyjasněné zveřejňované ceny,
   slevy a tvrzení. AI nevytváří záruky, reference ani tvrzení typu „nejlevnější v Praze“.
5. **Kontrola profilu.** Původní odpovědi vedle navrženého profilu. Každý údaj má stav:
   - Potvrzeno uživatelem,
   - Zadané, dosud nepotvrzené,
   - Návrh AI,
   - Odvozený výpočet,
   - Chybí nebo je v rozporu.

   „Potvrdit profil“ potvrzuje **konkrétní verzi**. Neblokující nejasnosti mohou zůstat otevřené
   a omezí navazující výstupy.
6. **První plán.** Po potvrzení vznikne návrh plánu na 30 dní a rámec šestiměsíčního cíle.
   Plán obsahuje hypotézy k vyhodnocení, ne předpověď výsledků.

### Společné chování
- **Automatické ukládání:** po opuštění pole nebo 1,5 s po posledním psaní. Stav „Ukládám /
  Uloženo / Konflikt / Offline“. Obnovení stránky pokračuje od poslední uložené revize.
- **Formulář je základ, chat jen pomáhá.** Nejvýše 3 doplňující otázky v jedné dávce.
- **Ovládání a přístupnost:** mobilní zobrazení (stávající CSS mřížka `.fg`), ovládání
  klávesnicí, chyba u konkrétního pole (`aria-describedby`).
- **Výpadek AI** neztratí odpovědi ani nezablokuje ruční dokončení. Tlačítko „Pokračovat bez AI“
  je vždy k dispozici.
- **Konflikt:** úprava ze dvou oken vrátí konflikt verze (`expectedRevision`, oddíl 10) a nabídne
  „Načíst novější“ nebo „Porovnat“. Nikdy tiché přepsání.

---

## 4. Datový model

### Principy
- Žádné `organizations`. Každá entita má `company_id → public.companies(id) on delete cascade`.
- **Tabulky jsou ve schématu `private`.**
  - `authenticated` má na `private` USAGE, ale práva na tabulky jen tam, kde je dostane **[DB✓]**.
  - Klient k nim přistupuje výhradně přes RPC.
  - RLS bude přesto zapnuté (druhá pojistka); politiky nejsou potřeba, protože role nemají
    na tabulky práva.
- **Vazby mezi záznamy jsou složené cizí klíče** `(company_id, x_id)` → `(company_id, id)`.
  Záznam jiné firmy tak nejde propojit ani chybou v kódu.
- **Peníze:** `bigint` v nejmenší jednotce (haléře, eurocenty) a měna `CZK|EUR`
  (stejná sada jako `companies.currency` **[DB✓]**). Procenta v bazických bodech; procentní růst
  a procentní body se rozlišují typem metriky.
- **Prázdné a nulové hodnoty:** `NULL` = neznámé, `0` = skutečná nula.
- **Čas:** okamžiky v `timestamptz` (UTC). Obchodní datum `date` a časová zóna (`Europe/Prague`)
  zvlášť.
- **Neměnnost:** potvrzené verze, rozhodnutí a audit jsou neměnné; trigger zakáže UPDATE a DELETE.
  Oprava = nová verze.

### Entity (návrh, `private` schéma)
| Tabulka | Klíčová pole | Poznámka |
|---|---|---|
| `onboarding_sessions` | `id`, `company_id`, `status`, `current_step`, `revision int`, `schema_version`, `started_by`, `created_at`, `updated_at` | Nejvýše jedna aktivní session na firmu (částečný unikátní index `where status <> 'archived'`). Stavy: oddíl 7. |
| `onboarding_answers` | `session_id`, `company_id`, `field_key`, `raw_value jsonb`, `normalized jsonb`, `normalized_by ('user'\|'ai'\|'calc')`, `author`, `revision`, `created_at` | Jen přidávání. Aktuální hodnota = poslední revize pole. Původní odpověď se nikdy nepřepíše. |
| `open_questions` | `session_id`, `company_id`, `field_key`, `kind ('unclear'\|'missing'\|'conflict')`, `question`, `blocking bool`, `status`, `answer_revision` | Viditelný seznam nejasností (z původního `unknowns`). |
| `profile_versions` | `id`, `company_id`, `version int`, `profile jsonb`, `schema_version`, `status ('draft'\|'confirmed'\|'superseded')`, `source_revision`, `content_hash`, `confirmed_by`, `confirmed_at` | `unique (company_id, version)`. CHECK `jsonb_matches_schema(...)`. Potvrzená verze je neměnná. |
| `company_active_profile` | `company_id pk`, `profile_version_id` | Ukazatel na aktivní verzi. Mění se atomicky v `profile_confirm`. |
| `profile_field_evidence` | `profile_version_id`, `company_id`, `path`, `state` (5 stavů z kroku 5), `source ('answer'\|'ai'\|'calc'\|'web')`, `source_ref`, `confirmed_at` | Zdroj a stav každého pole. |
| `business_goals` | `id`, `company_id`, `profile_version_id`, `metric`, `unit`, `baseline_minor`, `target_minor`, `growth_bp`, `currency`, `period`, `start_date`, `due_date`, `state ('scenario'\|'confirmed')` | `target_minor` počítá `private.goal_target`. |
| `agent_runs` | `id`, `company_id`, `session_id`, `role`, `input_revision`, `idempotency_key`, `status`, `attempt`, `lease_until`, `lease_id`, `model`, `prompt_version`, `tokens_in`, `tokens_out`, `cost_microusd`, `error_code`, `result jsonb`, časy | `unique (company_id, idempotency_key)`. Stavy: oddíl 7. |
| `artifacts` | `id`, `company_id`, `kind ('plan_30d'\|'content')`, `version`, `source_profile_version_id`, `body jsonb`, `content_hash`, `checks jsonb`, `status` | Neměnné po vzniku. Nová úprava = nová verze. |
| `approval_requests` | `id`, `company_id`, `kind ('profile'\|'plan'\|'content'\|'external_action')`, `target_id`, `target_hash`, `requested_by`, `expires_at`, `status` | Platnost se váže na `target_hash`. |
| `approval_decisions` | `id`, `request_id`, `company_id`, `decision`, `actor` (vždy `auth.uid()`), `comment`, `created_at` | Neměnné. Zapisuje jen funkce volaná uživatelem; worker nemá EXECUTE. |
| `audit_events` | `company_id`, `actor`, `operation`, `object_type`, `object_id`, `object_version`, `correlation_id`, `created_at` | **[DB?]** Nejdřív ověřit, zda lze použít existující `public.audit_logs` a `private.log_change`. Struktura nebyla čtena. |
| `integration_connections` | – | **Mimo MVP.** V DB už existuje `private.suite_gmail_connections` **[DB✓]**; vzor posoudit až ve fázi 5. |

### Vztah k existujícím datům
- **Název firmy:** při potvrzení profilu nabídnout zaškrtávátko „Použít i jako název firmy
  v aplikaci“. Teprve pak se změní `companies.name` (nová funkce `company_update_basics`;
  dnes žádná funkce název nemění **[DB✓]**).
- **Obory a moduly:** do `companies.workspace_config` (`industries`, `hiddenModules`) **[DB✓]**.
  **[ROZH]** závisí na tom, zda nad DB běží jiný frontend.
- **Fakturační údaje** (`user_business_profiles`) nejsou součástí onboardingu. Finanční kontext
  marketingu ≠ fakturace.
- **Starší návrh tabulky `company_onboarding`** z `AI_ONBOARDING_FAZE1.md` se nahrazuje
  entitami výše.

---

## 5. Validace a datové kontrakty

**Jeden zdroj pravdy:** `src/onboarding_schema.js` exportuje JSON Schema (draft 2020-12, podmnožina)
pro odpovědi, profil a výstupy jednotlivých AI rolí. Používá se na třech místech:

| Kde | Jak |
|---|---|
| Prohlížeč | Malý validátor bez závislostí (`src/jsonschema_mini.js`: typy, enum, délky, required, `additionalProperties:false`, min a max). Vkládá ho `build.py`. |
| Cloudflare funkce | Import stejného modulu. Validace vstupu i výstupu modelu před zápisem. |
| Databáze | `jsonb_matches_schema(schema, profile)` v CHECK a v RPC. Schéma se do migrace vkládá generovaně z `src/onboarding_schema.js`; test hlídá shodu. |

Pravidla:
| Oblast | Pravidlo |
|---|---|
| Text | `trim`, limit délky podle pole. Původní odpověď se uloží zvlášť a nezměněná. |
| Finance | Nezáporné celé číslo v nejmenší jednotce, explicitní měna a periodicita. Rozpočtový limit navíc potvrzuje owner nebo admin. |
| Cíl | „Měřitelný“ = vyplněná metrika, výchozí hodnota, jednotka a termín. Jinak stav `scenario`. |
| Procenta | Bazické body (`int`). Typ `growth_pct` × `percentage_points`. |
| Web | Jen `http`/`https`, bez `user:pass@`, bez IP literálů a portů mimo 80/443. Bezpečnost načítání řeší server (oddíl 9). |
| AI JSON | Přesné schéma, omezené enumy a délky, odmítnutí neznámých polí. **Jeden** opravný pokus (model dostane chyby validace), potom ruční doplnění. |
| Rozpory | Nikdy tiše nevybírat. Vznikne `open_questions.kind='conflict'`. |
| Jazyk | Jazykovou opravu lze nabídnout automaticky. **Změna významu vyžaduje potvrzení** (stav „Návrh AI“, dokud ho uživatel nepotvrdí). |

---

## 6. AI profil

Struktura `CompanyProfile` z původní specifikace platí beze změny. Ve Vexaronetu se popíše
JSON Schematem a JSDocem:

```js
/** @typedef {{ schemaVersion:number, identity:object, services:object[], audience:object,
 *   geography:object, positioning:object, brand:object, financialContext:object,
 *   goals:object[], channels:object[], constraints:object, unknowns:object[] }} CompanyProfile */
```

Pravidla:
- Zdroj a stav polí vede `profile_field_evidence`, ne text profilu.
- **Oprávnění k externím akcím se nikdy nečtou z profilu ani z odpovědi modelu.** Rozhoduje jen
  DB (role v `company_members`, schválení, limity).
- **Minimalizace kontextu:** každá role dostane jen potřebné sekce. Plánovač obsahu nedostane
  `financialContext` s tržbami, jen odvozený cíl. Výběr sekcí je pevný v kódu role, ne v promptu.

**Stav testovacího profilu před potvrzením:**
- Název: návrh „Autoservis Konina“.
- Služby: návrh „autoservis“ a „výměna a úpravy výfuků“.
- Lokalita: okolí Prahy, bez potvrzeného rádiusu.
- Kanály: uvedené Facebook a Instagram (nepřipojené).
- Problém: málo nových zákazníků.
- Otevřené otázky: web, význam „chpivanim auta“, měna, rozpočet, cílová metrika.
- Externí provádění: vypnuto (v MVP neexistuje).

---

## 7. Orchestrace agentů

Řízený workflow, žádná autonomní komunikace agentů. Role jsou samostatná volání Gemini
s pevným promptem (`prompt_version`) a výstupním schématem.

| Role | Vstup | Výstup | Smí |
|---|---|---|---|
| Normalizátor | odpovědi (aktuální revize) | `normalized` návrhy polí | nic neaktivuje |
| Analytik nejasností | návrh + pravidla | `open_questions` (nejvýše 3 na dávku) | bez externích nástrojů |
| Sestavovač profilu | vyjasněné odpovědi | `profile_versions.status='draft'` | nesmí potvrdit |
| Plánovač | **potvrzená** verze profilu | `artifacts.kind='plan_30d'` | bez publikování a útrat |
| Kontrolor | profil + návrh | `artifacts.checks` | nesmí schválit |

Kontrolor je jen pomocná kontrola. Finanční, autorizační a stavová pravidla vynucuje DB.

**Stavy onboardingu** (`onboarding_sessions.status`):
`draft → clarification_required → ready_for_review → confirmed`, plus `archived`.
- Bez nejasností lze přejít z `draft` rovnou do `ready_for_review`.
- Změna připraveného návrhu vrátí stav k validaci.
- Úprava potvrzeného profilu založí novou session nebo verzi.

**Stavy běhu** (`agent_runs.status`): `queued → running → succeeded | failed | cancelled`, plus `stale`.

### Průběh ve Vexaronetu
1. Prohlížeč uloží odpovědi přes RPC `onboarding_save` (zvýší `revision`).
2. Prohlížeč zavolá `POST /api/onboarding-run` s `{cid, role, expectedRevision, idempotencyKey}`.
3. Cloudflare funkce:
   - ověří JWT,
   - zavolá s tokenem uživatele RPC `onboarding_enqueue`. DB ověří členství, roli, tarif,
     feature flag, nákladový limit a idempotenci, a vrátí `run_id` (nový nebo existující),
   - odpoví `202 {runId}`.
4. Ve `context.waitUntil` funkce s klíčem `SUPABASE_SERVICE_KEY`:
   - vezme zámek (`onboarding_claim(run_id)` → `lease_id`),
   - načte jen kontext role,
   - zavolá Gemini, zvaliduje výstup,
   - zapíše `onboarding_finish(run_id, lease_id, result, usage)`.
   Funkce `claim` a `finish` smí volat jen service role (bez EXECUTE pro `anon`
   i `authenticated`), stejně jako stávající `ai_workspace_finish` **[DB✓]**.
5. `onboarding_finish` zapíše výsledek jen tehdy, když `input_revision = session.revision`.
   Jinak běh označí `stale` a výsledek neaplikuje.
6. Prohlížeč se ptá na stav: RPC `onboarding_run_status(cid, run_id)`, interval 2 s, nejvýše 60 s,
   pak „Pokračovat bez AI“.
7. Zaseknutý běh (vypršelý `lease_until`) obnoví `pg_cron` každou minutu přes `pg_net`
   → `POST /api/onboarding-worker` s tajemstvím `ONBOARDING_WORKER_SECRET`.
   Po vyčerpání pokusů přejde běh do `failed`.

### Limity
| Limit | Výchozí hodnota |
|---|---|
| Časový limit volání Gemini | 25 s |
| Opakované pokusy | 2 (jen při dočasné chybě poskytovatele: 429, 5xx, timeout) |
| Opravný pokus při nevalidním JSON | 1 |
| Kola doplňujících otázek | nejvýše 3, pak ruční dokončení |

- Idempotency key: `sha256(company_id | role | input_revision | workflow_version)`.
  Klient ho může poslat, ale server ho vždy přepočítá.
- Nákladový limit na firmu a měsíc je v DB (`private.ai_budget`) a vynucuje ho `onboarding_enqueue`.
  Cena se počítá z `usageMetadata` Gemini.
  **[ROZH]** vztah ke stávajícímu `public.reserve_ai` (limit 100 požadavků denně na celou platformu,
  20 denně na firmu) **[DB✓]**.

**[EXT?]** Ověřit limity `waitUntil` a CPU v Cloudflare Pages pro daný tarif. Pokud nestačí,
zpracování přesunout do samostatného Workeru s Cron Trigger (stejné DB funkce, beze změny modelu).

---

## 8. Schvalování

Čtyři oddělená rozhodnutí:
1. potvrzení profilu,
2. schválení plánu,
3. schválení obsahu,
4. povolení externí akce (mimo MVP).

Schválení plánu ≠ souhlas s publikováním ani s rozpočtem.

- Každé rozhodnutí se váže na `target_id` a `target_hash` (sha256 kanonického JSON).
- Změna textu, účtu, termínu, publika nebo rozpočtu změní hash a zneplatní související schválení.

**Mapování rolí na existující model** **[DB✓]**:
| Specifikace | Vexaronet | Smí |
|---|---|---|
| Vlastník / správce | `owner`, `admin` | Odpovědi, potvrzení profilu, schválení plánu a obsahu, finanční limity. |
| Editor | **neexistuje** | **[ROZH]** V MVP se nezavádí: vyžadovalo by změnu `company_members_role_check` a všech politik a funkcí, které role vyjmenovávají. |
| Čtenář | `employee` (nejbližší) | V MVP onboarding nevidí, stejně jako dnes nevidí AI CEO a finance (`allowed()`, `build.py:774`). |
| AI / worker | service role přes `onboarding_finish` | **Nemá EXECUTE** na `approval_decide`. Rozhodnutí vždy nese `actor = auth.uid()` člověka. |

**[ROZH]** Smí profil potvrdit i `admin`, nebo jen `owner`? Specifikace říká vlastník/správce.
Návrh: oba.

Externí akce (fáze 5): server těsně před provedením znovu ověří členství, roli, platné schválení
nad stejným hashem, připojený účet a limit. Výdaj rezervuje atomicky
(`pg_advisory_xact_lock` na firmu, stejně jako stávající funkce **[DB✓]**).

---

## 9. Bezpečnost

**Izolace firem**
- Tabulky onboardingu jsou v `private` bez práv pro `anon` i `authenticated`; RLS zapnuté.
- Každá RPC začíná kontrolou:
  `auth.uid() is not null and private.member_role(cid) in ('owner','admin') and private.writable(cid)`
  (vzor `invoice_action_core` **[DB✓]**).
- Všechny dotazy uvnitř funkcí filtrují `company_id = cid`; složené cizí klíče brání křížení firem.
- `cid` od klienta není důkaz. Cloudflare funkce ho nepoužijí k ničemu jinému než k volání RPC
  s tokenem uživatele; ověření dělá DB.

**Server a tajemství**
- `GEMINI_API_KEY`, `SUPABASE_SERVICE_KEY` a `ONBOARDING_WORKER_SECRET` jsou jen v proměnných
  Cloudflare.
- Nikdy v `build.py`, `index.html`, promptu ani logu. V prohlížeči zůstává jen veřejný klíč
  (`SB_KEY`).
- Logy obsahují `run_id`, `company_id`, kód chyby a délku, nikdy obsah odpovědí ani hlavičky.

**Nedůvěryhodný obsah**
- Odpovědi a web jsou v promptu ohraničené jako data (`<firm_data>…</firm_data>`) s pokynem,
  že nejde o instrukce.
- Nic z výstupu modelu nemění oprávnění, stav ani schválení. Model vrací jen JSON podle schématu,
  ten se validuje a zapisuje jako návrh.
- Žádné nástroje a funkce pro model v MVP (žádné function calling).

**Načítání webu** (volitelné, za feature flagem, až po testech)
- Jen `http`/`https`, porty 80 a 443, `redirect:'manual'` a kontrola **každého** přesměrování
  (nejvýše 3).
- Před každým požadavkem DNS dotaz přes DoH a odmítnutí privátních, loopback, link-local,
  CGNAT a metadata rozsahů (IPv4 i IPv6).
- Limit 1 MB, 8 s, jen `text/html`. Odstranit skripty, do promptu jen text.
- **[EXT?]** Ověřit chování `fetch` v Cloudflare Workers vůči interním adresám. Kontrola zůstane
  v kódu bez ohledu na výsledek.

**Data a audit**
- Gemini dostává jen nutné sekce (oddíl 6).
- Před produkcí ověřit podmínky Google AI (uchovávání a trénink na datech) a doplnit
  `ochrana-udaju/` **[EXT?]**.
- Retence, export a výmaz: smazání firmy kaskádou maže onboarding. Export přes RPC
  `onboarding_export(cid)`. Lhůty doplní `PRAVNI_PODKLADY.md`.
- Audit: aktér, operace, objekt, verze, korelační ID. Bez tokenů, obsahu odpovědí
  a uvažování modelu. Jen INSERT; UPDATE a DELETE zakáže trigger.

**Související nálezy z auditu** (řešit před pilotem; seznam v `AI_ONBOARDING_FAZE1.md`):
RLS na 4 tabulkách v `private`, práva `anon` na `ai_usage` / `company_invites` / `plan_requests`,
ochrana proti uniklým heslům.

---

## 10. Rozhraní a spolehlivost

| Operace | Kde | Chování |
|---|---|---|
| Založit / obnovit onboarding | RPC `onboarding_open(cid)` | Vrátí aktivní session (založí ji). owner/admin. |
| Načíst stav | RPC `onboarding_state(cid)` | Session, aktuální odpovědi, otázky, poslední verze profilu, evidence. |
| Uložit odpovědi | RPC `onboarding_save(cid, expected_revision, answers jsonb)` | Při nesouladu revize `raise sqlstate 'PT409'` → PostgREST vrátí **HTTP 409** **[EXT?]** (ověřit mapování ve verzi PostgREST na Supabase). |
| Spustit analýzu | `POST /api/onboarding-run` | `202 {runId}`. Duplicitní klíč vrátí existující běh. |
| Stav běhu | RPC `onboarding_run_status(cid, run_id)` | Průběh a bezpečná chybová zpráva (kód + český text, bez detailů poskytovatele). |
| Potvrdit profil | RPC `profile_confirm(cid, version_id, content_hash)` | Atomicky: validace schématu, shoda hashe, role, žádné blokující otázky → `confirmed`, přepnutí `company_active_profile`, audit, rozhodnutí typu `profile`. |
| Vytvořit plán | `POST /api/onboarding-run` s `role:'planner'`, `profileVersionId` | Jen nad potvrzenou verzí. |
| Rozhodnout o návrhu | RPC `approval_decide(cid, request_id, target_hash, decision, comment)` | Jen člověk (`auth.uid()`), shoda hashe, nevypršelá žádost. |
| Worker (interní) | `POST /api/onboarding-worker` + RPC `onboarding_claim` / `onboarding_finish` | Jen se `ONBOARDING_WORKER_SECRET` a service role. |

**Metriky** (tabulka `agent_runs` + agregační RPC pro správce platformy):
délka kroků, chybovost podle `error_code`, tokeny a cena, počet opravných pokusů, stáří fronty,
opuštěné kroky (`current_step` bez změny 7 dní). Bez obsahu odpovědí.

---

## 11. Implementační fáze

| Fáze | Výstup | Podmínka dokončení |
|---|---|---|
| 0. Příprava | Testovací DB, ověřené body [DB?] a [EXT?], oprava cesty v `build.py` (dnes zapisuje do `/tmp/vexaronet-saas/`), výběr aktivní firmy, `cid` v AI voláních | Snapshot obnovený v testovací DB; rozhodnutí z oddílu 13 uzavřená. |
| 1. Formulář a ukládání | Migrace tabulek a RPC (bez AI), `src/onboarding_schema.js`, `src/onboarding_ui.js`, autosave, konflikty, ruční potvrzení profilu, audit | Spolehlivé dokončení bez AI; testy izolace (kritéria 9, 10, 12, 15, 16, 24). |
| 2. AI profil | `/api/onboarding-run`, worker, Normalizátor, Analytik, Sestavovač, evidence, verzování, limity | Kritéria 1–8, 11, 13, 14, 20, 21, 25, 26. |
| 3. Plán a schvalování | Plánovač, Kontrolor, `artifacts`, `approval_*` | Plán z konkrétní potvrzené verze; kritéria 17–19. |
| 4. Pilot | Autoservis Konina, feature flag, metriky, pg_cron sweeper | Kritéria 27, 28; všech 28 kritérií splněno. |
| 5. Externí integrace | OAuth, publikování, reklama | Samostatná specifikace; mimo tento dokument. |

- Nasazení vždy v pořadí: migrace (testovací DB → produkce po schválení) → Cloudflare funkce
  → `index.html`.
- Vypnutí `ONBOARDING_AI` zachová formulář, uložené odpovědi i potvrzené profily.

---

## 12. Akceptační kritéria

Kritéria 1–28 z původní specifikace platí **beze změny**. Způsob ověření ve Vexaronetu:

| Kritéria | Jak ověřit |
|---|---|
| 1–8 (testovací firma) | SQL test na testovací DB: seed 12 odpovědí → kontrola `raw_value`, otázek, stavů evidence. Výpočet 197 100 / 51 100 přes `private.goal_target`. Výstup AI se v testu nahradí pevnou odpovědí. |
| 9–14 (UX a odolnost) | Playwright test `tests/onboarding_ui.py` se zamockovaným Supabase (vzor `tests/smoke.py`): obnovení stránky, dvě okna → 409, výpadek `/api/onboarding-run`, dokončení bez webu, nevalidní JSON, zastaralá revize. |
| 15–24 (schvalování a bezpečnost) | SQL testy rolí na testovací DB: owner, admin, employee, cizí uživatel, anon. Přímé volání RPC a REST na `private` tabulky musí selhat. Worker nesmí volat `approval_decide`. Grep `index.html` a logů na klíče. Test SSRF validátoru (privátní IP, přesměrování). |
| 25–28 (provoz) | Simulace limitu a pádu workeru (vypršelý lease → sweeper → jediný výsledek díky idempotenci). Dotaz na metriky. Přepnutí `ONBOARDING_AI`. |

---

## 13. Plán chybějících částí

Co dnes v projektu chybí a co je potřeba pro MVP (fáze 0–4).

### Databáze (nová migrace, nejdřív testovací DB)
| Chybí | Ověření |
|---|---|
| Tabulky z oddílu 4 v `private`, složené FK, triggery neměnnosti | – |
| RPC `onboarding_open/state/save/enqueue/run_status/export`, `profile_confirm`, `approval_decide`, `company_update_basics`, `my_companies` | **[DB?]** potvrdit, že `member_role` / `writable` / `business_root` jsou stále beze změny (porovnat otisky s manifestem). |
| Service funkce `onboarding_claim/finish`, revoke EXECUTE pro anon a authenticated | **[DB?]** ověřit, jak jsou nastavená výchozí práva (`ALTER DEFAULT PRIVILEGES`) pro nové funkce v `public` a `private`. |
| `private.goal_target`, `private.ai_budget` | **[ROZH]** vztah k `reserve_ai`. |
| Audit | **[DB?]** přečíst strukturu a politiky `public.audit_logs` a tělo `private.log_change`; rozhodnout znovupoužití. |
| pg_cron sweeper | **[DB?]** vypsat existující úlohy `cron.job` (jen názvy a plán), aby nevznikla kolize. |
| JSON Schema v CHECK | **[DB?]** ověřit, že `jsonb_matches_schema` zvládne použité konstrukce (verze `pg_jsonschema` 0.3.3 **[DB✓]**). |
| Feature flag na firmu (pilot) | – |
| Hygiena před pilotem: RLS v `private`, práva `anon`, ochrana proti uniklým heslům | **[ROZH]** + dashboard. |

### Cloudflare (`functions/api/`)
| Chybí | Ověření |
|---|---|
| `onboarding-run.js`, `onboarding-worker.js` | **[EXT?]** limity `waitUntil` a CPU podle tarifu Cloudflare. |
| Sdílený modul (ověření JWT, volání RPC, Gemini, validace, SSRF) | **[EXT?]** umístění, aby se nestal trasou ani veřejným souborem (publikuje se celý kořen). |
| Proměnné `ONBOARDING_AI`, `ONBOARDING_WORKER_SECRET` | **[EXT?]** ověřit, že `SUPABASE_SERVICE_KEY` v Cloudflare existuje (podle `NAVOD.md` ano). |
| Oprava `advisor.js`, `web-ai.js`, `marketing.js` (firma, role, tarif hlavní firmy) | Plán v `AI_ONBOARDING_FAZE1.md`, oddíl 3. |

### Frontend (`build.py`, `src/`)
| Chybí | Ověření |
|---|---|
| `src/onboarding_schema.js`, `src/jsonschema_mini.js`, `src/onboarding_ui.js`, zástupný znak `@@ONB@@` | – |
| Výběr aktivní firmy místo `limit(1)` (`build.py:620`) | – |
| Odstranění `onboarded`, `features` a `ui_industry` z metadat uživatele | **[ROZH]** převod stávajících hodnot (jednorázové předvyplnění). |
| Oprava zápisu `build.py` do `/tmp/vexaronet-saas/` | – |

### Testy
| Chybí | Ověření |
|---|---|
| SQL testy rolí a izolace | **[ROZH]** testovací DB: Supabase branch (placený) nebo samostatný projekt. |
| `tests/onboarding_ui.py`; Python Playwright v prostředí chybí | – |

### Právní a provozní
| Chybí | Ověření |
|---|---|
| Doplnění zásad ochrany údajů o zpracování v Gemini, retence | **[EXT?]** podmínky Google AI; kontrola právníkem. |

---

## 14. Otevřená rozhodnutí
1. **Tarif:** je AI v onboardingu dostupná ve všech tarifech (pomáhá získat zákazníka), nebo jen
   v PRO a vyšších jako ostatní AI? Formulář a ruční profil budou dostupné všem.
2. **Limity:** vztah k `reserve_ai` (100 denně na platformu) a výše nákladového limitu na firmu.
3. **Kdo potvrzuje profil:** `owner` i `admin` (návrh), nebo jen `owner`?
4. **Role Editor:** zavést později, nebo vůbec?
5. **Pobočky:** profil za každou provozovnu, nebo jen za hlavní firmu?
6. **Jiný frontend nad stejnou DB:** existuje? Ovlivní použití `workspace_config` a změny limitů.
7. **Testovací DB:** Supabase branch, nebo samostatný projekt?
8. **Tarif AI Účetní v registraci** (dnes selže) a bezpečnostní hygiena z auditu: kdy řešit?
