# Veřejný výstup webu, serverový klíč a náhledy (2026-11-08)

## Nález
Cloudflare Pages nasazoval jako výstup **kořen repozitáře**. Na https://vexaronet.com proto byly veřejně dostupné i interní soubory, ověřeno odpovědí 200:
- `/docs/SECURITY_STATUS.md`, `/db/migrations/*.sql`, `/src/ai_guard.js`, `/build.py`, `/tests/…`;
- schémata, `*.md` a další soubory v kořeni.

Zdroj serverových funkcí (`/functions/…`) a `/.git/` vracely 404.

V repozitáři jsem nenašel žádnou hodnotu tajného klíče (`git grep` na `sb_secret_…` a JWT). To ale **dokazuje jen to, že kontroly únik neodhalily, ne že k úniku nemůže dojít.**
Stejné soubory jsou dostupné i na všech dosavadních nasazeních Cloudflare Pages (adresy `<hash>.<projekt>.pages.dev` a náhledy větví). Ty změna nového nasazení neopraví.

## Oprava v kódu
1. **Allowlist veřejných souborů.** `build.py` skládá složku `public/` jen z těchto položek:
   - soubory: `index.html`, `404.html`, `sw.js`, `manifest.webmanifest`, `robots.txt`, `sitemap.xml`, `_headers`, `_redirects`;
   - složky: `assets/` (písma, ikony, `supabase-js`, `rrweb`, licence) a vygenerované stránky `podminky/`, `ochrana-udaju/`, `cookies/`, `dsa/`, `nahlasit/`, `odhlasit/`.
   - Žádný soubor z `src/` web za běhu nenačítá, všechno je vložené do `index.html`.
   - Serverové funkce se dál sestavují z `functions/` v kořeni repozitáře. Pages je bere z kořene projektu, ne z výstupní složky.
2. **Test `tests/public_dir.py`** (11 kontrol):
   - `public/` odpovídá čerstvému sestavení;
   - nejvyšší úroveň je přesně allowlist a neobsahuje žádné interní přípony ani složky;
   - každý lokální odkaz vede do `public/`;
   - v `public/` není název ani tvar serverového klíče;
   - prohlížeč nad serverem, který servíruje jen `public/`, načte všech 7 stránek bez chyby 404 a bez chyb JS a `supabase-js` projde kontrolou SRI;
   - interní cesty vrací 404.
3. **Klíče jen v hlavičce `apikey`.** Dokumentace Supabase („Migrating to publishable and secret API keys“, Known limitations) uvádí: *„You can't send a publishable or secret key in the `Authorization: Bearer ...` header. Send it on the `apikey` header instead.“*
   - Kód dřív posílal tajný klíč i v `Authorization` (limit chatu, DSA, novinky, AI marketing, přehled, správa DSA) a veřejný klíč jako `Bearer` (rezervace, odběr).
   - Nově jde klíč jen v `apikey`. `Authorization` nese výhradně JWT přihlášeného uživatele.
   - Bez `Authorization` brána Supabase doplní interní JWT podle `apikey`. Starý klíč `service_role` (JWT) se zkopíruje do `Authorization`, takže kód funguje s oběma druhy klíčů.
   - **Ověřeno proti produkčnímu API:** jen `apikey` s veřejným klíčem vrátí 200 a databáze vidí roli `anon`. Funkce vyhrazená serveru je odmítnuta (`42501`).
   - S `sb_secret_` se to ověří skutečným požadavkem chatu po nastavení klíče.
   - Test `tests/key_headers.test.mjs` kontroluje všechny požadavky na Supabase z chatu, DSA, odhlášení, AI marketingu, odběru a rezervací. Na původním kódu selže.
   - Tajné klíče Supabase podle dokumentace navíc vrací 401, pokud je použije prohlížeč (podle `User-Agent`).

## Kroky vlastníka v Cloudflare (po sloučení PR s opravou)
1. **Výstupní složka:** Workers & Pages → projekt webu → **Settings → Build → Build configuration → Edit**:
   - Build command: ponechat prázdné (web je sestavený v repozitáři);
   - **Build output directory: `public`**;
   - Root directory: ponechat prázdné (kořen; zde je `functions/`). Uložit.
2. **Serverový klíč:**
   - Supabase → Project Settings → API Keys → Secret keys → vytvořit nový klíč pojmenovaný `cloudflare-pages` a zkopírovat ho;
   - Cloudflare → Settings → **Variables and Secrets** → Production → Add → Type **Secret**, název `SUPABASE_SERVICE_KEY` → Save.
   - Klíč nikam jinam neukládat a neposílat.
3. **Nové nasazení:** Deployments → poslední produkční nasazení → ⋯ → **Retry deployment**. Nastavení výstupu i proměnné platí až pro nové nasazení.
4. **Dřívější nasazení a náhledy:**
   - Nejrychlejší: **Settings → General → Access policy → Enable**. Cloudflare Access pak chrání náhledová a dřívější nasazení na `*.<projekt>.pages.dev` přihlášením.
   - Případně smazat staré deployments v záložce Deployments (⋯ → Delete deployment). Aktuální produkční smazat nejde.
   - Ověřit i adresu `<projekt>.pages.dev` (alias produkce). Po kroku 1 obsahuje jen `public/`.
5. Napsat mi **název projektu na pages.dev** a jednu starou adresu nasazení. Přidám je do povolených hostů a ověřím je.

## Ověření po krocích (provede Claude)
- **Produkce:** interní cesty vrací 404, veřejné stránky 200, `supabase-js` a SRI fungují, hlavičky `_headers` platí.
- **Chat:** skutečný dotaz vrátí odpověď a přibude záznam limitu v databázi.
- **Formulář `/nahlasit/`:** zkušební oznámení vlastníka označené „TEST“ se uloží do `private.dsa_notices` a do evidence a vlastníkovi přijde potvrzení.
- **Náhledy:** podle adres od vlastníka.

## Stav 2026-11-08 (průběžně)
- **PR #3** (`public/`, klíče jen v `apikey`): sloučeno. Rezervace s veřejným klíčem jen v `apikey` v produkci fungují (databáze odpověděla věcnou chybou `not_found`).
- **`SUPABASE_SERVICE_KEY`:** vlastník ho nastavil. Dočasná diagnostika bez obsahu klíče (PR #5, už odstraněná) ukázala formát `sb_secret` a jen ASCII znaky.
- **Skutečná příčina 503 u chatu (PR #6):** `src/ai_guard.js` volal `o.fetchFn(...)` jako metodu objektu a Cloudflare Workers to odmítá („Illegal invocation“).
  - Rozbité bylo i AI s limitem `reserve_ai` (AI CEO, generátor marketingových textů, AI pro weby, AI v přehledu), a to od nasazení bezpečnostních oprav.
  - Lokální testy to nezachytily, protože Node takové volání dovolí. `tests/key_headers.test.mjs` teď podvrhuje `fetch` se stejnou kontrolou jako Workers.
- **Ověřeno po PR #6:** `POST /api/chat` vrátil 200 se skutečnou odpovědí AI. V `private.help_chat_limits` přibyl záznam `all` (1) a otisk návštěvníka (1). Funkce `reserve_help_chat` je spustitelná jen pro service_role, takže nový `sb_secret_` klíč funguje s hlavičkou `apikey`.
- **Čeká na vlastníka:**
  - výstupní složka `public` v Cloudflare a Retry deployment;
  - ochrana nebo smazání starých nasazení a název projektu na pages.dev;
  - zkušební oznámení přes `/nahlasit/`.
- Do té doby jsou interní soubory na produkční doméně stále dostupné, ověřeno: `/docs/SECURITY_STATUS.md` a `/build.py` vrací 200.
## Ověření po potvrzení vlastníka (2026-11-08, 10:12 UTC)
- **Chat:** `POST /api/chat` vrátil 200 se skutečnou odpovědí AI.
- **Formulář hlášení:**
  - `POST /api/dsa-notice` (stejný požadavek jako stránka `/nahlasit/`) vrátil 200 s referenčním číslem `DSA-20261108-1F3DCBF6`.
  - V `private.dsa_notices` je stav `received`, cíl `web/test-nasazeni`, otisk IP a v evidenci událost `prijato`.
  - Oznámení je označené jako TEST a zůstává v evidenci; doba uchování viz `PRAVNI_SOULAD.md` bod 9.
  - Potvrzovací e-mail: `ack: failed`. Adresa oznamovatele byla záměrně nedoručitelná (`@example.invalid`), takže odeslání přes Resend tímto testem **ověřené není**.
- **Validace formuláře:** neúplné údaje, chybějící potvrzení dobré víry, URL `javascript:` i vyplněné skryté pole vrací 400, GET vrací 405.
- **Interní soubory:** na produkční doméně jsou stále dostupné (`/docs/…`, `/build.py`, `/db/…`, `/src/…` vrací 200). Výstupní složka `public` v Cloudflare ještě nastavená není.
