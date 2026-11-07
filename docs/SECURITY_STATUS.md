# Stav zabezpečení Vexaronetu

Stav k 2026-11-09. Produkce (`micymdbqgzeckiqyvvkn`, vexaronet.com) byla kontrolována **jen čtením**: katalog databáze, kód edge funkcí, nastavení cron. Žádné pokusné útoky, žádné změny dat.
Tento dokument **netvrdí, že je aplikace zcela bezpečná**. Popisuje, co bylo ověřeno, co zůstává otevřené a co nebylo možné prověřit.

## Jak číst stav

| Stav | Význam |
|---|---|
| **Ověřený problém** | Potvrzeno důkazem (katalog, kód, test). |
| **Podezření** | Riziko, které jsem nepotvrdil, nebo jsem ho nemohl ověřit. |
| **Opraveno v produkci** | Oprava je nasazená a ověřená. |
| **Opraveno ve větvi** | Oprava je v `claude/happy-bell-5266nk` a otestovaná, ale **zatím není nasazená**. |
| **Vyvráceno** | Prověřeno, problém nenastává. |

Závažnost: **Vysoká** = může vést ke ztrátě nebo úniku dat, případně k nekontrolovaným nákladům. **Střední** = zneužití s omezeným dopadem. **Nízká** = zpevnění nebo druhá pojistka.

## Blokuje ostré používání

| # | Nález | Proč blokuje |
|---|---|---|
| H-1 | Žádná záloha mimo databázi | Při ztrátě nebo poškození projektu není z čeho obnovit. |
| F-1, B-1 | AI endpointy bez serverového limitu (oprava čeká na nasazení) | Kdokoli s účtem PRO, a u `/api/chat` kdokoli, může generovat náklady na Gemini. |
| B-2 | Přehled firmy jde na libovolný e-mail (oprava čeká na nasazení) | Člen týmu může vynést data a zneužít doménu k rozesílání. |
| G-1 až G-3 | Nastavení Supabase Auth nejsou ověřená | Uniklá hesla, délka hesla a adresy pro obnovu hesla se nastavují ručně v dashboardu. |
| B-5 | Veřejná rezervace a e-shop jdou zahltit | Platí jen, pokud je firmy používají veřejně. Jinak je ponechte vypnuté. |
| B-7 | 8 edge funkcí bez ověření JWT mimo repozitář | 3 z nich jsem neprošel. Patří jiné aplikaci nad stejnou databází, takže je musí převzít nebo prověřit vlastník. |

Ostatní nálezy jsou zpevnění, ostré používání neblokují. Je ale vhodné je nasadit spolu s opravami výše.

---

## A. Oddělení firem a role

| # | Stav | Závažnost | Důkaz | Dopad | Oprava / doporučení | Ověření |
|---|---|---|---|---|---|---|
| A-1 | Opraveno v produkci | – | RLS je zapnuté na všech tabulkách v `public` a `private`. Každá politika firemní tabulky ověřuje členství nebo uživatele (kontroly 1 a 3). Dříve chybělo RLS na 4 tabulkách v `private`, opraveno migrací `security_hardening_least_privilege`. | – | – | `db/test/prod/94_kontrola_opravneni.sql`: produkce OK. `tests/db/run_hardening_local.sh` (sekce D): vlastník firmy A nepřečte, nezmění, nesmaže ani nepřesune zboží firmy B, a to ani se znalostí ID. Zaměstnanec nezapíše. |
| A-2 | Vyvráceno | – | `company_members`: přihlášený smí měnit jen `display_name`. `subscriptions` nejde zapisovat vůbec, `companies` nejde vkládat ani mazat. | Členství, role ani tarif nejdou změnit přímým voláním API. | – | Kontroly 9 a 10 (produkce OK). |
| A-3 | Opraveno v produkci | – | AI endpointy dřív braly tarif „první firmy“ a neověřovaly roli. Teď `src/ai_guard.js` ověřuje přihlášení, `cid`, roli vlastník/správce a tarif TÉŽE firmy (s tokenem uživatele, přes RLS). | – | – | `tests/ai_endpoints.test.mjs` (cizí cid, zaměstnanec, START, prošlá zkušební doba). |
| A-4 | Podezření, zmírněné | Nízká | `client_notes.notes_manage` (UPDATE) ověřuje jen `created_by = auth.uid()` bez členství a sloupec `company_id` jde měnit. | Přesun poznámky do cizí firmy zastaví trigger `crm_same_company`. Běží s právy volajícího a cizího zákazníka přes RLS nevidí (`customer_id` je povinný). Bývalý člen poznámku bez SELECT politiky nezmění. | Doporučení: politiku doplnit o členství a UPDATE omezit na `body`, `kind`. Aplikace poznámky neupravuje. | Prověřeno čtením politik, triggeru a definice sloupců. Pokus v produkci nebyl. |
| A-5 | Ověřený problém | Nízká až střední | `customers`, `jobs`, `tasks` mají dvě sady povolujících politik: `members_*` (každý člen, bez `writable`) a `manager_*` (vlastník/správce + `writable`). Platí ta volnější. | Zaměstnanec smí zakládat a upravovat zákazníky, zakázky a úkoly. To je zřejmě záměr. Firma s prošlým předplatným ale může dál zapisovat, a obejde tak režim „jen ke čtení“. Mezi firmami data neunikají. | **Rozhodnutí vlastníka:** má zaměstnanec zapisovat a má platit zámek po expiraci? Pak doplnit `private.writable(company_id)` do `members_*`. Pozor, týká se to i druhé aplikace (B-7). | Text politik v katalogu. |
| A-6 | Záměr | Informace | `company_team` ukáže každému členovi e-maily kolegů. | Zaměstnanec zná e-maily týmu. | Ponechat, nebo omezit na vlastníka/správce. | – |
| A-7 | Opraveno ve větvi | – | Viz B-2 (přehled firmy jen na vlastní e-mail). | – | – | – |

## B. Veřejné endpointy

Cloudflare (`functions/api/*`): `chat` a `subscribe` jsou bez přihlášení, `book` volá veřejné `public_book`, `digest`, `invite` a AI endpointy vyžadují token.
Supabase Edge Functions bez ověření JWT: `public-booking`, `customer-care`, `business-web`, `business-suite`, `business-gmail`, `help-chat`, `ai-design`, `ai-workspace`. Viz B-7.

| # | Stav | Závažnost | Důkaz | Dopad | Oprava | Ověření |
|---|---|---|---|---|---|---|
| B-1 | Opraveno ve větvi | Střední | `/api/chat` volal Gemini jen s limitem v paměti jedné instance (12 za minutu na IP) a bez limitu pro celou platformu. | Kdokoli mohl generovat náklady. | Před voláním AI se volá `reserve_help_chat` v DB (200 denně celkem, 20 za hodinu na návštěvníka, IP se neukládá). **Vyžaduje `SUPABASE_SERVICE_KEY` v Cloudflare.** Bez něj chat vrací 503 (fail closed). | `tests/ai_endpoints.test.mjs` (chat: 503 bez klíče, 429 po limitu, ukládá se jen otisk). |
| B-2 | Opraveno ve větvi | Střední | `/api/digest` posílal firemní přehled (faktury po splatnosti, zakázky, sklad) na **libovolnou adresu z požadavku**. | Únik firemních dat ven. Doména vexaronet.com se dala zneužít ke spamu. | Přehled jde jen na e-mail přihlášeného uživatele. AI shrnutí jen po `reserve_ai`. | Testy digest: útočníkova adresa se nepoužije, cizí firma dostane 403. |
| B-3 | Opraveno ve větvi | Nízká | `subscribe` vracel návštěvníkovi maskovaný `NOTIFY_EMAIL` a text chyby Resendu. `invite` a `digest` vracely text chyby poskytovatele. | Prozrazení konfigurace. | Klient dostane jen `sent`, `failed` nebo `not_configured`. Detail jde do logu. | Testy subscribe a digest. |
| B-4 | Ověřený problém, částečně opraveno ve větvi | Nízká až střední | `custom_inquiries` má anon INSERT s `WITH CHECK (true)`, `newsletter_subscribers` kontroluje jen e-mail a souhlas. Publishable klíč je veřejný, takže přímý zápis přes PostgREST obchází limit v `/api/subscribe`. | Spam do poptávek a přihlášek, zbytečná data. | Migrace D: limity délky a formátu e-mailu v politikách. **Limit počtu RLS neumí**, proto doporučuji CAPTCHA (Cloudflare Turnstile), případně přesun zápisu do funkce s limitem. | `run_hardening_local.sh` (sekce B, C). |
| B-5 | Ověřený problém | Střední (zneužití) | `public_book` a `public_shop_order` jsou pro anon (kontrola 6, záměr). Rezervace nemá ověření e-mailu a jen 3 za hodinu na e-mail, přičemž e-mail je libovolný. Objednávka hned odečte sklad a vystaví fakturu (číslo z řady) bez platby, limit je 30 za hodinu na obchod. Přímé RPC obchází limity Cloudflare. | Zahlcení termínů, falešní zákazníci, vyčerpání skladu a čísel faktur. Data jiných firem neunikají. | **Rozhodnutí:** Turnstile nebo ověření e-mailu kódem (druhá aplikace už má `booking_challenges`), limit na firmu za hodinu v DB, rezervace skladu až po potvrzení. | Těla funkcí v katalogu. |
| B-6 | Vyvráceno | – | Veřejné funkce vracejí jen záměrně veřejná data: zveřejněný profil, aktivní služby a zboží, sklad zaokrouhlený na nejvýš 50, platební údaje u objednávky. | – | – | Těla `public_shop`, `public_site` a `public_booking_info`. |
| B-7 | Podezření (neověřeno celé) | ? | V produkci běží 13 edge funkcí, jejichž kód v tomto repozitáři není (původ: další aplikace nad stejnou DB, např. `vexaronet-business…chatgpt.site`). Prošel jsem `help-chat`, `ai-workspace`, `business-web`, `business-gmail` a `ai-design`: ověřují JWT přes `auth.getUser`, kontrolují vstupy (zod, regex, magic bytes), limit vede DB, OAuth má PKCE a šifrovaný token. **Neprošel jsem** `public-booking`, `customer-care` a `business-suite` (také bez JWT), ani `invoice-service`, `vexaronet-ai` a `send-*`. | Neznámý. Změny těchto funkcí nemají v repozitáři historii. | Vlastník: rozhodnout, kdo funkce spravuje, uložit jejich kód do verzí, zbylé prověřit. Nepoužívané vypnout. | `list_edge_functions` a `get_edge_function` (jen čtení). |
| B-8 | Informace | Nízká | Limity v Cloudflare funkcích (`limited()`) jsou v paměti jedné instance. | Při rozložení zátěže je jde obejít. | Pro AI už rozhoduje DB limit (F-1). Pro ostatní zvážit pravidla Cloudflare Rate Limiting. | – |

## C. Supabase: práva, RLS, funkce

| # | Stav | Závažnost | Důkaz | Dopad | Oprava | Ověření |
|---|---|---|---|---|---|---|
| C-1 | Opraveno v produkci | – | RLS na 4 tabulkách v `private`, odebraná nadbytečná práva anon na 3 tabulkách a EXECUTE pro PUBLIC/anon na `clock_in`, `clock_out` a `shop_cancel_order`. | – | Migrace `security_hardening_least_privilege` (2026-11-07). | `docs/BEZPECNOSTNI_OPRAVY.md`, smoke 93. |
| C-2 | Opraveno ve větvi (D-1) | Nízká | anon má `arwdDxtm` na ~20 tabulkách v `public` a authenticated má TRUNCATE, REFERENCES a TRIGGER na 18 tabulkách (kontroly 7 a 8: NÁLEZ). Výchozí práva Supabase pro nové tabulky. | Dnes to blokuje RLS (anon nemá žádnou politiku) a PostgREST, který TRUNCATE nenabízí. Je to jen jediná vrstva obrany. | Migrace `20261109100000_zprisneni_prav.sql`: anon jen INSERT do dvou formulářů a SELECT veřejného profilu, authenticated bez TRUNCATE, REFERENCES a TRIGGER. | `run_hardening_local.sh`: 30 kontrol, beze změny mimo dotčené objekty, přesný rollback. |
| C-3 | Opraveno ve větvi (D-3) | Nízká | 11 SECURITY DEFINER funkcí má `search_path=public` nebo `public, auth`, bez `pg_temp` na konci (kontrola 5: NÁLEZ). | Teoretické zastínění tabulek dočasnou tabulkou. Přes PostgREST dočasnou tabulku vytvořit nejde. | Stejná migrace přidá `pg_temp` na konec. Těla funkcí se nemění. | `run_hardening_local.sh` (sekce E). |
| C-4 | Vyvráceno | – | Všech 52 funkcí v `private` dostupných pro authenticated má `search_path=''` a kontrolu volajícího přímo nebo přes `member_role`, `writable` či pomocné funkce. Ručně jsem prošel `create_company_for_plan`, `web_asset_registered`, `capture_campaign_core`, `public_profile_allowed` a funkce týmu a pozvánek. | – | – | Katalog, kontrola 4. |
| C-5 | Podezření | Nízká | Výchozí práva (default privileges) dají anon vše na každou NOVOU tabulku. | Nová tabulka bez RLS by byla veřejná. | Každá migrace musí zapnout RLS a odebrat práva. Kontroly 1 a 7 to zachytí, spouštět je po každé migraci. | – |
| C-6 | Vyvráceno | – | anon nemá přístup do `private`, `vault` ani `cron`. Veřejný je jen bucket `site-images` (obrázky webu). | – | – | Kontroly 11 a 12. |

## D. Tajemství

| # | Stav | Závažnost | Důkaz | Dopad | Oprava / postup |
|---|---|---|---|---|---|
| D-1 | Vyvráceno | – | Prohledán pracovní strom, `index.html` i všech 64 commitů historie (vzory JWT, `sb_secret_`, Google `AIza`, Resend `re_`, `ghp_`, privátní klíče): **nic nenalezeno**. Frontend a funkce obsahují jen veřejný `sb_publishable_…` (ověřen typ klíče). Tajné klíče (`GEMINI_API_KEY`, `RESEND_API_KEY`, `SUPABASE_SERVICE_KEY`, `DIGEST_SECRET`) jsou jen v proměnných Cloudflare. Cron úlohy čtou klíče z Supabase Vault, v příkazech nejsou literály. | – | Postup rotace při podezření na únik je níže (I-2). |
| D-2 | Ověřený problém | Nízká až střední | `.github/workflows/apps.yml` při každém buildu vygeneruje nový podpisový klíč APK s heslem uloženým přímo v souboru. | Podpis APK se mění s každým buildem, takže uživatel nemůže ověřit, že aktualizace pochází od stejného autora, a Android ji nenainstaluje přes starou verzi. | Vytvořit trvalý klíč, uložit ho do GitHub Secrets a heslo z workflow odstranit (ruční krok). |

## E. XSS, soubory, SSRF

| # | Stav | Závažnost | Důkaz | Dopad | Oprava | Ověření |
|---|---|---|---|---|---|---|
| E-1 | Vyvráceno | – | Data se do HTML vkládají přes `esc()`, URL obrázků a odkazů musí být `https:`. Odpovědi AI se vykreslují jako text. Náhled webu je v `iframe sandbox=""`. | – | – | `tests/xss_ui.py`: 20 obrazovek se škodlivými daty (zákazník, zakázka, příspěvek, nabídka, zboží s `javascript:` URL, název firmy, odpověď AI). Nic se nespustilo, v DOM nevznikl žádný `on*=` a řetězce se vykreslily jako text. |
| E-2 | Opraveno ve větvi | Střední | Web neposílal CSP, `X-Frame-Options` ani `nosniff` (soubor `_headers` chyběl). | Clickjacking a slabší obrana při případném XSS. | `_headers`: CSP (skripty jen vlastní a supabase-js, spojení jen na vlastní web a Supabase, `frame-ancestors 'none'`, `object-src 'none'`), `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`, HSTS. CSP zatím povoluje `'unsafe-inline'`, protože aplikace je jeden soubor s vloženým skriptem. | `tests/xss_ui.py` běží se skutečnými hlavičkami z `_headers`: CSP nic z aplikace nezablokovala a rámování je zakázané. |
| E-3 | Opraveno ve větvi | Nízká | `supabase-js` se načítal z CDN bez kontrolního součtu. | Kompromitace CDN by spustila cizí kód s přístupem k sezení. | `integrity="sha384-…"` a `crossorigin`. Ověřeno, že soubor na jsDelivr je bajtově shodný s balíčkem na npm. | Build, UI testy. |
| E-4 | Vyvráceno | – | Buckety jsou soukromé (kromě obrázků webu), s limitem velikosti a MIME. Nahrávání kontrolují politiky role a složky firmy. AI Účetní kontroluje MIME a velikost a soubor neukládá. `ai-workspace` kontroluje magic bytes. | – | – | Katalog `storage`, kód. |
| E-5 | Vyvráceno | – | Žádný endpoint v repozitáři nenačítá URL od uživatele. Volají se jen pevné adresy (Supabase, Gemini, Resend) a ID se kontrolují regulárním výrazem. | – | – | Kód. |

## F. AI

| # | Stav | Závažnost | Důkaz | Dopad | Oprava | Ověření |
|---|---|---|---|---|---|---|
| F-1 | Opraveno ve větvi | Střední | `advisor`, `marketing`, `web-ai`, `accountant` a AI shrnutí v `digest` měly jen limit v paměti instance. Existující atomický DB limit `reserve_ai` nevolaly. | Náklady na Gemini omezoval jen počet účtů. | Před každým voláním AI se volá `public.reserve_ai(cid)` s tokenem uživatele. Hlídá 100 volání denně na platformu, 20 denně a 300 měsíčně na firmu a 3 za minutu na uživatele (advisory lock, odolné vůči souběhu). Znovu ověří členství, zapisovatelnost a tarif. Selhání znamená, že se AI nezavolá. | 73 testů v `tests/ai_endpoints.test.mjs`: rezervace pro správnou firmu před AI, vyčerpaný limit vrací 429, nedostupná DB 503, odmítnutý volající limit nečerpá. |
| F-2 | Ověřený problém | Nízká až střední | `reserve_ai` přijímá jen tarify PRO+. AI Účetní v tarifu `accountant` má jen měsíční limit dokladů, který se kontroluje a zapisuje ve dvou krocích, takže souběžné požadavky ho mohou překročit. | Menší než F-1 (tarif `accountant` je placený a limit 3 za minutu na uživatele v paměti platí). | Rozšířit `reserve_ai_core` o tarif `accountant` (změna DB, sdílená s druhou aplikací), nebo počítání dokladů přesunout do atomické funkce. | – |
| F-3 | Informace | – | **Nákladový limit Autopilota (0,25 USD/měsíc) zatím neplatí pro žádný endpoint.** Autopilot nic nespouští a `paid_runs_enabled = false` (kontrola 13). Počtem požadavků jsou limitované: `/api/chat` (`reserve_help_chat`), `/api/advisor`, `/api/marketing`, `/api/web-ai`, `/api/accountant` (PRO+), `/api/digest` (`reserve_ai`, po nasazení větve). Edge funkce `help-chat` má vlastní DB limit. U `vexaronet-ai`, `ai-design`, `business-web` a `ai-workspace` jsem limity neověřil (B-7). | Limit počtu není limit ceny. | Napojení na peněžní limit je další fáze Autopilota (`docs/AUTOPILOT.md`). | – |
| F-4 | Vyvráceno | – | AI nic samo nezapisuje. Endpointy vracejí text nebo návrh. Profil potvrzuje jen člověk (JWT role authenticated, vlastník/správce), vyúčtování Autopilota smí jen `service_role`. | – | – | `tests/db/run_local.sh` a `run_autopilot_local.sh`. |

## G. Přihlášení a Supabase Auth

| # | Stav | Závažnost | Důkaz | Doporučení (ruční nastavení) |
|---|---|---|---|---|
| G-1 | Ověřený problém | Střední | Advisor Supabase: ochrana proti uniklým heslům (HaveIBeenPwned) je vypnutá. | Authentication, Policies nebo Password security: zapnout. Na bezplatném plánu nemusí být dostupné. |
| G-2 | Podezření | Nízká až střední | UI vyžaduje heslo o 8 znacích, nastavení serveru neznám (výchozí 6). API jde volat přímo. | Authentication, Providers, Email: minimální délka 8 a složitost. |
| G-3 | Podezření | Střední | Obnova hesla používá `redirectTo: location.origin`. Povolené adresy přesměrování jsem nemohl přečíst. | Authentication, URL Configuration: Site URL `https://vexaronet.com` a Redirect URLs jen vlastní domény, žádné zástupné znaky. |
| G-4 | Vyvráceno | – | Odhlášení volá `auth.signOut()` (výchozí rozsah: všechna sezení) a zavře aplikaci. Service worker necachuje `/api/` ani Supabase (jiný původ). | – |
| G-5 | Doporučení | – | Potvrzení e-mailu: přijetí pozvánky ho vyžaduje (`email_confirmed_at`). Zda je povinné pro přihlášení, jsem neověřil. MFA není. | Zapnout „Confirm email“, zvážit MFA pro vlastníky a CAPTCHA (Turnstile) u registrace a obnovy hesla. |

## H. Zálohy

| # | Stav | Závažnost | Důkaz | Dopad | Oprava |
|---|---|---|---|---|---|
| H-1 | Ověřený problém | **Vysoká** | Bezplatný plán Supabase nemá spravované zálohy ani PITR. Cron `vexaronet-daily-company-backups` ukládá zálohy do **téže** databáze. | Při smazání nebo poškození projektu, chybě migrace či kompromitaci účtu nejsou data obnovitelná. | Placený plán (denní zálohy a PITR), nebo pravidelný `pg_dump` mimo Supabase (šifrovaně, s omezeným přístupem) a **vyzkoušená obnova** do testovacího projektu. |
| H-2 | Informace | – | Zálohy před nasazením (`private.deploy_backup_20261107_*`, `..._20261109_*`) obsahují jen práva a nastavení, ne data. | – | – |

## I. Postup při bezpečnostním incidentu

1. **Zastavit škody.** Při podezření na únik klíče ho hned zneplatnit (I-2). Při zneužití AI nastavit v Cloudflare prázdný `GEMINI_API_KEY`: endpointy pak vracejí 503. Při zneužití veřejného formuláře nebo rezervací vypnout příslušnou funkci (`enabled=false` v nastavení firmy) nebo dočasně odebrat EXECUTE.
2. **Zajistit stopy, nic nemazat.** Exportovat logy Supabase (API, Postgres, Auth) a Cloudflare za dotčené období, uložit `audit_logs` a výstup `db/test/prod/94_kontrola_opravneni.sql`.
3. **Zjistit rozsah.** Které firmy a záznamy, odkdy, jakým kanálem (logy API podle IP a uživatele, `audit_logs`, `ai_requests`).
4. **Opravit a ověřit.** Nasadit opravu (stejné pořadí jako v `docs/NASAZENI_*`), spustit kontrolu 94 a příslušné testy.
5. **Informovat.** Při úniku osobních údajů: posoudit ohlášení ÚOOÚ do 72 hodin a informovat dotčené firmy (jsou správci údajů svých zákazníků). Kontakt info@vexaronet.com.
6. **Poučit se.** Doplnit nález do tohoto dokumentu a přidat test.

**I-2 Rotace klíčů** (hodnoty nikdy do repozitáře ani do chatu):
- `SUPABASE_SERVICE_KEY` (secret key): Supabase, Project Settings, API Keys. Vytvořit nový secret key, uložit do Cloudflare (Settings, Variables and Secrets) a do Supabase Vault (`vexaronet_*`, pokud ho používá cron), nasadit a pak starý klíč smazat. U legacy JWT klíčů rotace JWT secretu odhlásí všechny uživatele.
- `GEMINI_API_KEY`: Google AI Studio nebo Cloud Console. Vytvořit nový, uložit do Cloudflare a do secrets edge funkcí, starý smazat.
- `RESEND_API_KEY`: Resend, API Keys. Postup stejný.
- `DIGEST_SECRET`, `GMAIL_TOKEN_KEY` a OAuth klienti: přegenerovat. Změna `GMAIL_TOKEN_KEY` zneplatní uložené tokeny Gmailu, uživatelé je musí připojit znovu.
- Publishable klíč je veřejný z principu. Při zneužití ho lze vyměnit a nasadit nový `index.html`.

## Automatizované testy hranic oprávnění

| Test | Co dokazuje | Proti čemu |
|---|---|---|
| `tests/db/run_hardening_local.sh` | Pod skutečnými rolemi anon a authenticated (JWT nároky jako v PostgREST): oddělení firem i se znalostí ID, změna `company_id`, role zaměstnance, anon bez přístupu, veřejné formuláře a profil, TRUNCATE, `search_path`, přesný rollback. | Lokální PostgreSQL s politikami a právy opsanými z produkce. |
| `tests/db/run_security_local.sh`, `run_local.sh`, `run_autopilot_local.sh` | Předchozí opravy, profil firmy (role, oddělení firem, potvrzení jen člověkem) a limity Autopilota. | Lokální PostgreSQL. |
| `db/test/prod/94_kontrola_opravneni.sql` | 14 invariantů (RLS, politiky, `search_path`, EXECUTE pro anon, práva tabulek, role v týmu, tarif, schémata, úložiště, vypínač Autopilota). | **Produkce, jen čtení katalogu.** Dnes 11× OK a 3× NÁLEZ (5, 7, 8), které řeší migrace D. |
| `tests/ai_endpoints.test.mjs` | Skutečný kód Cloudflare funkcí: přihlášení, firma, role, tarif, serverový limit před AI, fail closed, příjemce přehledu, nevracení interních chyb. | Odpovědi DB a poskytovatelů jsou nasimulované. Samotné vynucení v DB dokazují testy výše. |
| `tests/xss_ui.py` | Skutečná aplikace se škodlivými daty a s CSP z `_headers`. | Data dodává simulace Supabase. |

Mock ani skryté UI tu nejsou důkazem zabezpečení. Důkazem je databázový test pod skutečnými rolemi a kontrola produkčního katalogu.
