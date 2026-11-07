# AI Autopilot: první fáze

Stav: 2026-11-08, větev `claude/happy-bell-5266nk`. **Nic není nasazené, produkční databáze se nezměnila.**
Placená volání AI se v rámci Autopilota **nespouštějí a nespouštěla se**. Tento dokument říká, co je hotové a ověřené, co ne a co čeká na váš souhlas.

## 1. Co fáze obsahuje

| Část | Stav |
|---|---|
| Horní lišta režimů: Autopilot (přehled), AI Marketing, AI Obchodník, AI CEO, AI Účetnictví, AI Weby a e-shopy, AI Automatizace | hotovo, ověřeno UI testem (`tests/autopilot_ui.py`, desktop i mobil) |
| Přehled Autopilota: připravenost, měsíční limit a spotřeba, ceník modelu, formulář pro nastavení limitu | hotovo, ověřeno UI testem se zamockovaným Supabase |
| Databáze: ceník, měsíční limit, atomická rezervace nákladu, vypořádání, platformní vypínač | hotovo, ověřeno lokálně (71 kontrol); **na Supabase neověřeno** |
| Kontrola volajícího v AI endpointech (firma, role, tarif) | hotovo, ověřeno testem skutečných souborů s mockem (43 kontrol) |
| Samotné AI běhy Autopilota, fronta návrhů ke schválení, worker | **není** (viz oddíl 6) |

### Režimy a jejich skutečný stav

Lišta ukazuje stav podle skutečnosti v kódu, nic nepředstírá:

| Režim | Otevře | Štítek | Co skutečně funguje |
|---|---|---|---|
| AI Marketing | Marketing | omezeně | AI návrh příspěvků, newsletterů, reklam a plán obsahu (PRO+). Nic se nepublikuje. |
| AI Obchodník | Obchodní případy | **připravujeme** | CRM, případy a nabídky fungují. AI obchodník není. |
| AI CEO | AI CEO | omezeně | Zdraví firmy, doporučení, chat nad daty (PRO+). Jen radí. |
| AI Účetnictví | AI Účetní | omezeně | Vytěžení dokladů ke kontrole, odpovědi z evidence. |
| AI Weby a e-shopy | Jednoduchý web | omezeně | AI návrh textů webu (PRO+). E-shop a sklad fungují bez AI. |
| AI Automatizace | Automatizace | omezeně | Pravidla navrhují úkoly ke schválení. Běh na pozadí není. |

Režimy mimo tarif zobrazují štítek PRO+ a otevřou existující zámek tarifu. Zaměstnanec lištu nevidí. Společné záložky
(zákazníci, finance, reporty) zůstanou v naposledy zvoleném režimu.

## 2. Jak se limit vynucuje (databáze, ne prohlížeč)

Migrace `db/migrations/20261108110000_autopilot_limity.sql` (+ rollback). Zamýšlený průběh budoucího AI běhu:

1. Přihlášený vlastník nebo správce zavolá `autopilot_reserve(cid, režim, model, max_vstup, max_výstup, klíč)`.
   Databáze v jedné transakci pod zámkem hlavní firmy ověří identitu, roli, tarif, platformní vypínač a limit, a **rezervuje nejvyšší možnou cenu**.
   Když by měsíční součet překročil limit, rezervace se odmítne (HTTP 402) a poskytovatel AI se nevolá.
2. Teprve potom server zavolá poskytovatele s `maxOutputTokens` rovným rezervované hodnotě.
3. Server (jen `service_role`) zavolá `autopilot_settle` se skutečnou spotřebou z odpovědi poskytovatele. Rezervace se nahradí skutečnou cenou.
   Opakované vypořádání nic nepřičte podruhé. Skutečná cena nad rezervací se uloží jako **přečerpání** (neskrývá se).
4. Nedokončené rezervace se po 15 minutách označí `expired` a počítají se v plné výši (bezpečná strana). Pozdní dokončení je upraví na skutečnost.

Cena se počítá z ceníku v databázi: `gemini-3.5-flash-lite` = 300 nUSD za vstupní a 2 500 nUSD za výstupní token (0,30 a 2,50 USD za 1 M tokenů).
Peníze se počítají celočíselně v nanodolarech. Ceník je **ověřen z oficiální stránky ceníku Google (Standard) 2026-11-07**;
účtované zvlášť jsou vyhledávání Google a cachování kontextu, které Autopilot nesmí používat. Model bez ověřené ceny se odmítne.

### Placené běhy jsou vypnuté ze tří nezávislých důvodů (musí platit všechny)

1. **Platformní vypínač** `private.autopilot_platform.paid_runs_enabled` je po migraci `false`. Žádná API funkce ani role ho nemění (test).
   Opakovaná migrace ho nepřepíše.
2. **Firma musí mít nastavený limit.** Bez limitu se rezervace odmítne.
3. **Tarif hlavní firmy PRO nebo vyšší** (`private.booking_plan_allowed`, stejná funkce jako v produkci).

Schválený předběžný limit 0,25 USD měsíčně na firmu lze nastavit v přehledu Autopilota (tlačítko „Doporučených 0,25 USD“).
Nastavení limitu žádné volání AI nespustí.

### Co ověřily testy (71 kontrol, `tests/db/run_autopilot_local.sh`)

Vypnutí a chybějící limit; práva rolí (zaměstnanec, správce pobočky, cizí firma, `anon`, `service_role` nesmí rezervovat); neplatné vstupy;
rezervace 4 000 + 2 000 tokenů = přesně 6 200 000 nUSD; idempotence a kolize klíče; sdílený limit hlavní firmy a poboček;
nejvýše 3 souběžné rezervace; vypořádání jen `service_role` a jen jednou; vyčerpání limitu **přesně na nanodolar** (rovnost projde, o 2 800 nUSD víc ne);
přečerpání se zaznamená; prošlé rezervace; obnova limitu po přelomu měsíce; tarif START odmítnut; účet jen pro čtení odmítnut;
žádná API role nemá práva na tabulky; limit ani ceník nejdou změnit přímým zápisem ani servisním klíčem; audit s identitou a neměnnost; kaskáda při smazání firmy.

### Co ověřeno NENÍ

- **Chování na skutečném Supabase.** Testy běží v lokální PostgreSQL. Testovací projekt zatím neexistuje (`docs/TESTOVACI_PROSTREDI.md`).
- **Skutečný Gemini.** Neověřeno, zda `maxOutputTokens` omezuje i přemýšlecí tokeny a zda `usageMetadata` vrací úplnou spotřebu. Proto je přečerpání zaznamenáno místo předpokladu.
- **Důvěra v hlášenou spotřebu.** `autopilot_settle` volá backend se spotřebou, kterou mu poskytovatel oznámí. Kdo má servisní klíč, může spotřebu podhlásit.
  Ochrana: klíč je jen v Cloudflare, rezervace předem omezuje horní mez, přečerpání se eviduje.
- Jiná aplikace nad stejnou databází, pokud existuje, o limitu neví.

## 3. Bezpečnost stávajících AI endpointů

Endpointy `advisor`, `web-ai`, `marketing` a `accountant` dřív neurčovaly firmu (tarif se četl jako „první řádek, který uživatel vidí“),
nekontrolovaly roli a při více firmách mohly rozhodnout podle jiné firmy. Nově všechny volají `src/ai_guard.js`, který před zavoláním AI ověří:
přihlášení, platné `cid` z požadavku, členství v této firmě s rolí vlastník nebo správce (jako v aplikaci) a tarif téže firmy. Dotazy jdou s tokenem uživatele (RLS), servisní klíč se nepoužívá.
Aplikace posílá `cid` aktivní firmy.

**Dopady, které je nutné znát před nasazením:**
- Funkce a nový `index.html` musí jít ven **spolu** (jeden deploy). Stará verze aplikace v prohlížeči (cache, PWA) neposílá `cid` a AI vrátí 400, dokud se stránka neobnoví.
- Zaměstnanec už AI endpointy nevolá ani přímo (dřív to API nebránilo; aplikace mu AI nenabízela).
- Pravidlo tarifu zůstává jako dosud (povolený tarif, nevypršela zkouška, není `expired`/`canceled`). Databázová `booking_plan_allowed` je přísnější (u `active` vyžaduje `paid_until`).
  Nový Autopilot používá přísnější databázové pravidlo, starší endpointy dosavadní, aby se nerozbily ručně nastavené účty.
- **Tyto endpointy zatím nespadají pod nový měsíční limit.** Nadále platí jen paměťový limit na instanci. Jejich napojení na rezervaci a vypořádání je další krok (oddíl 5).
- Nalezeno: kód posílá poskytovateli parametr `temperature`, který Google u řady 3.x označuje jako zastaralý. Před placenými běhy ověřit.

## 4. Podmínky pro zapnutí placených běhů

| Podmínka (vaše) | Stav |
|---|---|
| Skutečné vynucování limitu | **navrženo a ověřeno lokálně**, na Supabase čeká na testovací projekt |
| Správný ceník modelu | **ověřeno** z oficiálního ceníku Google 2026-11-07, uloženo s odkazem a datem |
| Funkčnost testovacího prostředí | **neověřeno**: projekt zatím neexistuje, přichystán skript `tests/db/run_on_test_project.sh` |

Dokud nejsou všechny tři splněné a vy to nepotvrdíte, `paid_runs_enabled` zůstává `false`. Až to potvrdíte, zapnutí je jeden příkaz
(spustí se až po vašem výslovném souhlasu, nejdřív na testovacím projektu): `update private.autopilot_platform set paid_runs_enabled = true;`

## 5. Další kroky (po souhlasu a po ověření na testovacím projektu)

1. Založit testovací projekt a spustit `tests/db/run_on_test_project.sh` a `tests/db/check_http_status.mjs`.
2. Cloudflare endpoint prvního AI běhu: rezervace jménem uživatele, volání poskytovatele bez nástrojů a cachování s `maxOutputTokens`, vypořádání z `usageMetadata`, test s mockem a pak s limitem na testovacím projektu.
3. Fronta návrhů ke schválení se vazbou na verzi a otisk obsahu (spec oddíl 8).
4. Napojení stávajících endpointů (CEO, Marketing, Weby, Účetnictví) na rezervaci a vypořádání.
5. Teprve potom zapnutí `paid_runs_enabled` na testovacím projektu a po vašem souhlasu na produkci.

## 6. Co potřebuji od vás

- Založit testovací Supabase projekt (postup v `docs/TESTOVACI_PROSTREDI.md`) a poslat mi jeho ID.
- Souhlas, než cokoli z `db/migrations/` půjde na produkci (jsou 3 nové migrace: profil firmy, bezpečnostní opravy, limity Autopilota).
- Rozhodnutí o prioritě: pokračovat první AI operací (krok 2), nebo napřed napojit stávající endpointy na limit (krok 4).
