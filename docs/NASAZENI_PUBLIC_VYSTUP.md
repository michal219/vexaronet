# Výstupní složka `public/`: interní soubory přestanou být veřejné

**Stav:** připraveno ve větvi `claude/modest-ptolemy-pdhyzg`, **nenasazeno**. Nasadit lze až se souhlasem vlastníka.

## Problém (ověřeno 2026-11-08)
Cloudflare Pages servíruje celý kořen repozitáře. Na https://vexaronet.com vrací HTTP 200 např.
`/docs/SECURITY_STATUS.md`, `/db/migrations/*.sql`, `/src/ai_guard.js`, `/build.py`, `/tests/…`, `/tools/…`,
`/schema*.sql`, `*.md` v kořeni, `/android/…`, `/desktop/…`, `/netlify.toml`.
Tajné hodnoty v nich nejsou, ale popisují zabezpečení a schéma databáze.

## Co web skutečně potřebuje
Zjištěno z odkazů v `index.html`, `404.html`, `sw.js`, `manifest.webmanifest` a stránkách, které generuje `build.py`:

| Cesta | Proč |
|---|---|
| `index.html`, `404.html` | aplikace a web; `404.html` zapíná na Pages odpověď 404 pro neexistující adresy |
| `manifest.webmanifest`, `sw.js` | PWA (ikony v `assets/`) |
| `robots.txt`, `sitemap.xml` | vyhledávače |
| `_headers`, `_redirects` | hlavičky zabezpečení (CSP, HSTS …) a `/cenik`; Pages je čte jen z výstupní složky |
| `assets/` | ikony, `og-image.jpg`, `prehled.webp`, fonty, `vendor/supabase-js-2.45.4/supabase.js` (SRI), `vendor/rrweb-record-2.2.1/` |
| `podminky/`, `ochrana-udaju/`, `cookies/`, `dsa/`, `nahlasit/`, `odhlasit/` | statické stránky z `build.py` |

`base.css` se vkládá do `index.html` při sestavení, samostatně se nenačítá. Zmínky `docs/…`, `db/…`, `tests/…`, `src/…` v `index.html` jsou jen v komentářích.
Pages Functions jsou ve `functions/api/` a importují `../../src/ai_guard.js` a `../../src/legal_server.js`. Ty se sbalí do funkcí při nasazení, takže `src/` ve výstupní složce být nemusí.

## Řešení
- `tools/build_public.py` (jen standardní knihovna Pythonu, bez Node) zkopíruje do `public/` pouze cesty ze seznamu `PUBLIC`.
  Pak zkontroluje, že všechny lokální odkazy ze stránek, `sw.js` a manifestu ve `public/` existují; jinak skončí chybou.
- `build.py` ho spouští na konci, takže `python3 build.py` připraví i `public/`.
- `public/` je v `.gitignore` a necommituje se. Sestaví ho Cloudflare build příkazem ze souborů v gitu.
- **Nový veřejný soubor nebo složku je nutné přidat do `PUBLIC` v `tools/build_public.py`.**

**Proč ne `functions/_middleware.js`:** middleware by běžel u každého požadavku, tedy i u statických souborů.
Každý takový požadavek by se počítal do limitu Functions (Free 100 000 za den) a přidal by latenci.
Dnes se Functions volají jen pro `/api/*`. Navíc by blokoval jen vyjmenované cesty, takže nový interní soubor by byl veřejný.
Seznam povolených souborů funguje opačně: nový soubor je neveřejný, dokud ho někdo výslovně nepřidá.

## Kroky pro vlastníka (Cloudflare dashboard)
1. **Workers & Pages** → projekt webu vexaronet.com → **Settings** → **Build** (dříve *Builds & deployments*) → **Build configuration** → **Edit**.
2. Nastavit:
   - **Framework preset:** `None`
   - **Build command:** `python3 tools/build_public.py`
   - **Build output directory:** `public`
   - **Root directory (advanced):** ponechat prázdné (kořen repozitáře), aby Pages dál našly `functions/`.
3. **Save.** Uložení samo nic nenasadí, současná produkce běží dál.
4. **Ověřit na náhledu větve.** Jsou-li zapnuté náhledové deploymenty:
   - v **Deployments** u větve `claude/modest-ptolemy-pdhyzg` zvolit **Retry deployment**, nebo do větve pushnout;
   - ověřit na adrese náhledu (viz „Ověření“).
   - Pokud se větev nesestaví, náhled nevznikne a produkce zůstane beze změny.
5. **Sloučit PR do `main`.** Produkční build už poběží s novým nastavením.
   - Pozor: když se nastavení změní a do `main` se pushne cokoli **před** sloučením, build selže (chybí `tools/build_public.py`).
   - Cloudflare pak ponechá předchozí deployment, takže web nespadne.
6. **Ověřit produkci** (viz níže).

**Návrat:**
- Okamžitě: **Deployments** → předchozí produkční deployment → **Rollback to this deployment**.
- Trvale: v Build configuration vymazat Build command a Build output directory vrátit na prázdné (kořen), pak **Retry deployment**.

## Ověření
Interní cesty musí vracet 404, veřejné 200 (`/cenik` vrací 308 jako dnes):

```bash
B=https://vexaronet.com; for p in /docs/SECURITY_STATUS.md /db/migrations/ /src/ai_guard.js /build.py /tests/legal.py /tools/build_public.py /schema.sql /NAVOD.md /README.md /android/ /desktop/ /netlify.toml /base.css; do echo "$p $(curl -s -o /dev/null -w '%{http_code}' $B$p)"; done
```

```bash
B=https://vexaronet.com; for p in / /podminky/ /ochrana-udaju/ /cookies/ /dsa/ /nahlasit/ /odhlasit/ /sw.js /manifest.webmanifest /robots.txt /sitemap.xml /assets/vendor/supabase-js-2.45.4/supabase.js /assets/icon-192.png /neexistuje; do echo "$p $(curl -s -o /dev/null -w '%{http_code}' $B$p)"; done
```

```bash
curl -sI https://vexaronet.com/ | grep -iE "content-security-policy|x-frame-options|strict-transport"
```

V prohlížeči ověřit: úvodní stránku, přihlášení (supabase-js se načte bez chyby SRI), registraci service workeru (PWA) a chat a formuláře volající `/api/*`.

## Lokální ověření (2026-11-08, před nasazením)
- `wrangler pages dev public` (wrangler 3.114, stejná logika jako Pages: `_headers`, `_redirects`, `404.html`, `functions/`).
- **Interní cesty → 404:** `/docs/SECURITY_STATUS.md`, `/db/migrations/`, `/src/ai_guard.js`, `/build.py`, `/tests/legal.py`, `/tools/…`, `/schema.sql`, `/schema_crm.sql`, `/NAVOD.md`, `/README.md`, `/android/`, `/desktop/`, `/netlify.toml`, `/netlify/`, `/base.css`, `/functions/api/chat.js`, `/_headers`, `/.gitignore`.
- **Veřejné → 200:** `/`, všech šest statických stránek, `sw.js` (`Cache-Control: no-cache`), manifest, `robots.txt`, `sitemap.xml`, ikony, obrázky, fonty, supabase-js, rrweb, `/?app=1`.
  `/neexistuje` vrací 404 se stránkou `404.html`. `/cenik` vrací 308 stejně jako produkce.
- **Hlavičky zabezpečení z `_headers`** jsou na `/` všechny: CSP, X-Frame-Options, HSTS, Permissions-Policy, Referrer-Policy, COOP, nosniff.
- **SRI:** hash servírovaného `supabase.js` odpovídá atributu `integrity` v `index.html`.
- **Prohlížeč:** service worker se zaregistruje, `window.supabase.createClient` existuje, manifest se načte, v konzoli nejsou chyby a žádný požadavek nevrátil 4xx/5xx.
- **API přes Functions:** `chat`, `book`, `subscribe`, `unsubscribe`, `dsa-notice` a `newsletter` odpovídají vlastním kódem (405/400/303).
  Bez tajných klíčů vrací `chat` 503 `not_configured`. Funkce se tedy sbalily i s importy z `src/`.
- **UI testy s asercemi:** všechny prošly. `legal` a `demo_btn` běžely proti `wrangler pages dev public` na :8765.
  `ai_marketing_ui` 39, `autopilot_ui` 59, `profile_ui` 37, `legal_ui` 41, `xss_ui` 32, `eshop` 40, `legal` 57, `demo_btn` 38, `obory` 48, `web` 13, `appmode` 13, `imp` 11, `faktury_lib` 13, `eshop_import` 14.
- **JS testy:** `ai_endpoints` 73, `autopilot_core` 10 a `profile_core` 13 prošly.
  `legal_e2e` a `ai_marketing_e2e` potřebují lokální PostgreSQL. Bez něj selhávají stejně i bez této změny.
- `python3 build.py` nezmění `index.html` ani právní stránky; rozdíl proti `main` je nulový.
