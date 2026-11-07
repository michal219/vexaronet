# Testovací prostředí pro databázi (bez placeného Supabase branche)

Stav: 2026-11-07. Produkční databáze se při testech nikdy nepoužívá.

## Co už je ověřené a co ne

| Co | Kde | Stav |
|---|---|---|
| Migrace `20261107120000_profil_firmy.sql` se provede (i podruhé) a je čistě přídavná | lokální PostgreSQL 16 | ověřeno |
| Zpětná migrace vrátí databázi do přesně původního stavu | lokální PostgreSQL 16 | ověřeno |
| Oprávnění rolí (majitel, správce, zaměstnanec, cizí firma, `anon`, `service_role`), konflikty, verzování, pobočky, neměnnost, audit, kaskáda při smazání firmy | lokální PostgreSQL 16, 65 kontrol | ověřeno |
| Shoda validace JavaScript ↔ databáze | 122 vektorů | ověřeno |
| Formulář, ukládání, konflikty, výběr firmy | prohlížeč se zamockovaným Supabase (`tests/profile_ui.py`) | ověřeno |
| Funkce `member_role`, `writable`, `business_root` v testu jsou stejné jako v živé DB | shoda md5 se snapshotem | ověřeno |
| Chování na skutečném Supabase: PostgREST (HTTP 409/412/422/403), `auth.uid()` z opravdového JWT, výchozí práva, `pg_jsonschema` | bezplatný testovací projekt | **zatím neověřeno** |
| Aplikace migrace na produkci | – | **neprovedeno, vyžaduje vaše schválení** |

Lokální databáze **není** Supabase. Role, `auth.uid()` a výchozí práva napodobuje `db/test/00_local_supabase_shim.sql`.

## Lokální běh (tam, kde je PostgreSQL)

```bash
tests/db/run_local.sh                                    # běžný uživatel, který smí zakládat databáze
PSQL="runuser -u postgres -- psql" tests/db/run_local.sh # jako root
python3 tests/profile_ui.py                              # UI test (potřebuje playwright + chromium)
node tests/profile_core.test.mjs                         # logika profilu v Node
```

## Bezplatný projekt Supabase: postup krok za krokem

1. Otevřete <https://supabase.com/dashboard> → **New project**.
   - **Pozor na limit:** bezplatná organizace obvykle povoluje jen 2 aktivní projekty a váš účet jich už má 2 (produkce a `gymora-ai`).
     Pokud tlačítko 3. projekt nenabídne, vytvořte pro testování novou **organizaci** (New organization → plán Free) a projekt založte v ní.
     Nepozastavujte ani nemažte existující projekty.
2. Název `vexaronet-test`, region stejný jako produkce (`eu-north-1`), databázové heslo vygenerujte a uložte do správce hesel.
   **Heslo ani klíče nikomu neposílejte.**
3. Po vytvoření (1 až 2 minuty): **Project Settings → API** → opište si adresu `https://<ref>.supabase.co` a **publishable** klíč
   (veřejný; tajný `service_role` klíč nepotřebujete).
4. Připojení pro `psql`: **Connect → Session pooler** → zkopírujte URI, doplňte heslo a uložte do proměnné ve **svém** terminálu:
   ```bash
   export DATABASE_URL='postgresql://postgres.<ref>:<heslo>@<host>:5432/postgres'
   ```
   (`psql` nainstalujete např. `sudo apt install postgresql-client` nebo `brew install libpq`.)
5. Spusťte v tomto pořadí (stub a testy patří **jen** do tohoto prázdného projektu; stub se v databázi s tabulkami aplikace sám zastaví):
   ```bash
   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/test/01_base_stub.sql
   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/20261107120000_profil_firmy.sql
   psql "$DATABASE_URL" -f db/test/10_profile_tests.sql        # SQL testy, na konci se vrací transakce
   ```
   Ve Supabase SQL Editoru lze spustit jen migraci a stub. Testy používají příkazy `psql` (`\gset`) a v editoru nepoběží.
6. Ověření HTTP stavů (PostgREST):
   - V **Authentication → Users → Add user** založte testovacího uživatele (e-mail + heslo, zaškrtněte *Auto Confirm User*).
   - V SQL Editoru spusťte `db/test/20_http_fixture.sql` po změně e-mailu na řádku `v_email`. Vypíše `TEST_COMPANY_ID`.
   - Ve svém terminálu:
     ```bash
     SUPABASE_URL=https://<ref>.supabase.co SUPABASE_ANON_KEY=<publishable klíč> \
     TEST_EMAIL=<e-mail> TEST_PASSWORD=<heslo> TEST_COMPANY_ID=<id z fixture> \
     node tests/db/check_http_status.mjs
     ```
   - Očekávaný výsledek: `VŠE V POŘÁDKU` (zastaralá revize = HTTP 409, jiná verze schématu = 412, neplatná data = 422, cizí firma = 403).
7. Úklid: `db/test/21_http_cleanup.sql`, nebo projekt celý smažte.

**Pokud chcete, abych testy spustil já:** po založení projektu mi napište jeho ID (`<ref>`, není to tajemství). Přes Supabase konektor
mohu v tomto projektu spustit stub a migraci (příkazy `apply_migration`/`execute_sql`) a ověřit výsledek dotazy do katalogu.
Produkční projekt `micymdbqgzeckiqyvvkn` při tom nikdy nepoužiji. SQL testy a HTTP skript musíte kvůli `psql` a heslu spustit vy.

## Nasazení na produkci (až po schválení, mimo tuto fázi)

1. Záloha (ve Supabase: Database → Backups, případně `pg_dump` jen schémat `public` a `private`).
2. Migrace `db/migrations/20261107120000_profil_firmy.sql` v SQL Editoru produkčního projektu (je v transakci, jen přidává objekty).
3. Ověření dotazem: existují funkce `public.profile_*` a tabulky `private.company_profile_*`.
4. Až potom nasazení `index.html` (aplikace při chybějících funkcích zobrazí upozornění místo pádu).
5. Zpět: `db/migrations/20261107120000_profil_firmy_rollback.sql` (smaže i uložené profily, proto nejdřív záloha).
