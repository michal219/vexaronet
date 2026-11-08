# Nasazení AI Marketing Autopilota (připravený krok, NENASAZENO)

Tento dokument popisuje kroky a dopady. Sám o sobě nasazení neautorizuje. Placené AI běhy zůstávají po nasazení **vypnuté**
(`private.autopilot_platform.paid_runs_enabled = false`). Zapnutí je samostatný krok na konci.

## Co se nasazuje

| Část | Soubor | Závislost |
|---|---|---|
| DB | `db/migrations/20261112100000_ai_marketing.sql` (návrat: `…_rollback.sql`) | v produkci už nasazené migrace profilu firmy (20261107120000) a limitů Autopilota (20261108110000); tabulka `public.marketing_posts` |
| Server | `functions/api/ai-marketing.js` (+ `src/ai_guard.js` beze změny rozhraní) | proměnné Cloudflare `GEMINI_API_KEY` a `SUPABASE_SERVICE_KEY` (obě už používají jiné funkce: `advisor.js`, `digest.js`, `chat.js`; před nasazením ověřit, že jsou nastavené i pro produkční prostředí Pages) |
| Web aplikace | `src/ai_marketing_ui.js`, úpravy `src/autopilot_dash.js`, `build.py` (sekce Novinky na webu firmy) → `index.html` | dashboard AI Marketing Autopilota (commit `8d586f0`) je zatím **nenasazený**; nasazuje se spolu s ním |

## Pořadí

1. **DB migrace** (Supabase, `apply_migration`). Je zpětně kompatibilní: současný web ji nevolá. Jediná změna chování existující tabulky je
   trigger `mkt_post_changed` na `public.marketing_posts`. Ten se projeví jen u příspěvků, které mají schválení v `private.mkt_items`, a ty zatím neexistují.
2. **Kontrola po migraci (jen čtení):**
   - existují funkce `mkt_state`, `mkt_results` a `public_site_news`;
   - `anon` smí spouštět jen `public_site_news`;
   - `get_advisors` (security) nehlásí nové položky.
3. **Server a web** (merge větve do `main` → Cloudflare Pages). Bez zapnutých placených běhů vrací `/api/ai-marketing` 403 `paid_runs_disabled` ještě před voláním AI.
   UI to zobrazí jako „Placené AI běhy zatím nejsou zapnuté provozovatelem. Nic se neúčtovalo.“
   - Bez AI funguje: ruční úprava a schválení strategie (pokud existuje), schválení příspěvků na serveru, publikace na web firmy, záznam ručního zveřejnění a výsledky.
   - Strategii bez AI zatím nelze založit od nuly. Vzniká jen návrhem AI, potom ji lze upravovat.
4. **Ověření živého webu (bez zásahu do zákaznických dat):**
   - načte se záložka Strategie;
   - veřejný web firmy bez novinek se zobrazí beze změny.

## Dopady

- **Uživatelé:**
  - Schválení příspěvku v dashboardu jde nově přes `mkt_post_approve`. Server zapíše otisk obsahu a po pozdější úpravě textu příspěvek vrátí do konceptu.
  - Na veřejném webu firmy se objeví sekce **Novinky**, jen pokud firma příspěvek výslovně zveřejní na webu.
- **Náklady:** žádné, dokud nejsou zapnuté placené běhy. Potom nejvýše do měsíčního limitu firmy, který vynucuje DB (`autopilot_reserve`).
- **Data:** nové tabulky `private.mkt_strategies`, `private.mkt_items` a `private.mkt_results`. Klient k nim nemá přímý přístup, jen přes funkce s kontrolou role.

## Návrat

1. Web a server: revert merge v `main` (Cloudflare nasadí předchozí verzi).
2. DB: `db/migrations/20261112100000_ai_marketing_rollback.sql`. Odstraní tabulky AI marketingu včetně uložených strategií a výsledků.
   - Příspěvky v `public.marketing_posts` zůstanou.
   - Před návratem udělat export tří tabulek `private.mkt_*`, pokud v nich už jsou data.
   - Lokálně ověřeno: po rollbacku je katalog shodný s výchozím stavem.

## Zapnutí placených běhů (samostatné rozhodnutí)

1. Ověřit ceník `gemini-3.5-flash-lite` v `private.ai_model_prices` proti oficiálnímu ceníku k datu zapnutí.
2. Vlastník firmy nastaví limit ve Finance & ROI (schváleno 0,25 USD/měsíc).
3. `update private.autopilot_platform set paid_runs_enabled = true;`
4. Odhad ceny jednoho běhu podle stropů endpointu:
   - strategie: nejvýše 8 000 vstupních a 1 800 výstupních tokenů, tj. nejvýše přibližně 0,007 USD;
   - dávka příspěvků: nejvýše 8 000 vstupních a 3 000 výstupních tokenů, tj. nejvýše přibližně 0,01 USD;
   - skutečná spotřeba bývá nižší a účtuje se podle `usageMetadata`.
5. Sledovat `private.autopilot_runs` (stav `failed`, otevřené rezervace) a `private.autopilot_events`.
6. Návrat: `paid_runs_enabled = false`. Běžící rezervace doběhnou, nové se odmítnou.
