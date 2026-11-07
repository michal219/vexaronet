# Bezpečnostní opravy pro produkci: dopady a návrat

Stav: 2026-11-09. **Nic z toho není nasazené.** Vše je ve větvi `claude/happy-bell-5266nk` a otestované lokálně (viz `docs/SECURITY_STATUS.md`).
Před nasazením je potřeba výslovný souhlas vlastníka. Nasazují se dvě nezávislé části: **1) změna databáze** a **2) kód webu a Cloudflare funkcí**.

## Předpoklad (ruční krok vlastníka)

V Cloudflare Pages, Settings, Variables and Secrets (Production), musí být nastavený `SUPABASE_SERVICE_KEY` (secret key projektu Supabase).
Bez něj veřejný chat na webu po nasazení odpovídá „nedostupné“ (503), protože bez limitu v databázi se záměrně nespustí. Ostatní funkce klíč nepotřebují.

## 1) Databáze: migrace `20261109100000_zprisneni_prav.sql`

**Co mění** (jen práva a nastavení, ne data ani těla funkcí):
- anon: odebrat všechna práva na tabulkách v `public`, kromě INSERT do `newsletter_subscribers` a `custom_inquiries` a SELECT na `public_profiles`.
- authenticated: odebrat TRUNCATE, REFERENCES a TRIGGER na tabulkách v `public`. SELECT, INSERT, UPDATE a DELETE zůstávají, dál rozhoduje RLS.
- Politiky INSERT formulářů dostanou limity délky a kontrolu e-mailu.
- 11 SECURITY DEFINER funkcí dostane `pg_temp` na konec `search_path`.
- Zálohy původního stavu: `private.deploy_backup_20261109_acl`, `_policy` a `_config`.

**Dopad na Vexaronet (tento repozitář):** žádný. Aplikace používá anon jen pro formulář novinek a poptávek (INSERT) a pro veřejné RPC (rezervace, e-shop, web), které se nemění.
Přihlášený uživatel nepřichází o nic, co aplikace používá. Ověřeno testem `tests/db/run_hardening_local.sh`: 30 kontrol, beze změny mimo dotčené objekty, přesný rollback.

**Dopad na druhou aplikaci nad stejnou DB (edge funkce, B-7):** anon dnes nemůže na dotčených tabulkách nic, protože RLS pro anon nemá politiky. Odebrání práv proto nic, co dnes funguje, nevypne.
Edge funkce pracují se `service_role` nebo s tokenem uživatele, takže se jich změna netýká. Riziko: pokud druhá aplikace vkládá do formulářů delší texty než nové limity (4000 znaků zpráva, 200 jméno a firma), takový vklad selže.

**Kontrola před migrací (jen čtení):** `db/test/prod/94_kontrola_opravneni.sql`. Očekávaný výsledek: NÁLEZ jen u kontrol 5, 7 a 8.
**Aplikace:** Supabase MCP `apply_migration` (název `security_least_privilege_forms_search_path`) nebo SQL editor. Migrace je jedna transakce a dá se spustit opakovaně.
**Ověření po migraci:**
1. Kontrola 94: všech 14 kontrol OK.
2. Na webu odeslat formulář novinek a poptávky. Volitelně jako transakce s vynuceným rollbackem podle vzoru `db/test/prod/93_*`.
3. Otevřít veřejnou rezervaci a e-shop (slug existující firmy). Přihlásit se, otevřít zákazníky, zboží a profil firmy.
4. Sledovat logy API Supabase (401/403/42501 na `/rest/v1/newsletter_subscribers`, `/custom_inquiries` a `/rpc/public_*`).

**Návrat:** `db/migrations/20261109100000_zprisneni_prav_rollback.sql`. Vrátí práva, obě politiky a `search_path` ze záloh. Data se nemění.
Kdy vrátit: formulář nebo veřejné RPC vrací 401/403, nebo druhá aplikace hlásí chybu oprávnění.

## 2) Kód: Cloudflare funkce, `_headers` a SRI (merge větve do `main`)

| Změna | Dopad na uživatele | Riziko | Návrat |
|---|---|---|---|
| `reserve_ai` před AI (`advisor`, `marketing`, `web-ai`, `accountant` PRO+, AI v `digest`) | Nad limitem dostane uživatel 429 s českou hláškou z DB („Denní limit AI firmy…“, „Zkuste AI znovu za minutu“). Starší stránky ukážou obecnou chybu. | **Limit platformy je 100 AI volání denně celkem** a sdílí ho i druhá aplikace, pokud `reserve_ai` volá. Při reálném provozu může být nízký. Zvýšení je změna `private.reserve_ai_core` (samostatné rozhodnutí). | Revert commitu. |
| `/api/chat` s limitem v DB | 200 odpovědí denně pro celý web, 20 za hodinu na návštěvníka. Nad limitem 429. | Bez `SUPABASE_SERVICE_KEY` chat nefunguje (503). Limit `all` sdílí s `help-chat` druhé aplikace. | Revert nebo nastavení klíče. |
| `/api/digest` jen na vlastní e-mail | Pole „e-mail“ u zkušebního přehledu se ignoruje, přehled přijde na e-mail přihlášeného (aplikace ho zobrazí v hlášce). | Žádné. | Revert. |
| Generické chyby e-mailu (`subscribe`, `invite`, `digest`) | Návštěvník nevidí detail. Detail je v logu Cloudflare. | Žádné. | Revert. |
| `_headers` (CSP, `X-Frame-Options`, HSTS…) | Žádná viditelná změna. Stránku nejde vložit do cizího rámu. | CSP by mohla zablokovat zdroj, který lokální test nepokryl (např. nový externí obrázek přes `http:`). Lokálně: 0 porušení CSP na 20 obrazovkách. HSTS (1 rok) je prakticky nevratné pro HTTP, web už ale běží jen na HTTPS. | Smazat nebo upravit `_headers` a nasadit. Prohlížeč pak hned používá novou hlavičku, kromě HSTS. |
| SRI pro supabase-js | Žádná. | Kdyby jsDelivr změnil soubor, prohlížeč skript zablokuje a přihlášení nefunguje. Ověřeno: soubor je bajtově shodný s balíčkem na npm. | Revert, nebo odstranit `integrity`. |

**Staré otevřené stránky a PWA:** `sw.js` je network-first a `_headers` mu nastavuje `Cache-Control: no-cache`. Po obnovení stránky se načte nová verze.
Staré stránky volají stejné endpointy, přechodné určení firmy bez `cid` (`legacyResolve`) zůstává.

**Pořadí:** (a) nastavit `SUPABASE_SERVICE_KEY` v Cloudflare, (b) migrace DB (1) s kontrolou, (c) merge kódu (2), počkat na nasazení Cloudflare Pages a ověřit:
- `curl -sI https://vexaronet.com/` obsahuje `content-security-policy` a `x-frame-options: DENY`.
- Přihlášení funguje (SRI).
- Jeden dotaz na AI CEO vrátí odpověď a v `private.ai_requests` přibude řádek (čtení).
- Veřejný chat odpoví.
- Formulář novinek uloží přihlášku.

Části (b) a (c) jsou na sobě nezávislé a jdou vracet samostatně.
