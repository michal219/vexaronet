# AI tým: architektura, nasazení a provoz

Stav 2026-11-11. **Vše je ve větvi `claude/happy-bell-5266nk`, nic z toho není nasazené.** Placené AI běhy jsou v produkci vypnuté.
Projekt není Next.js: je to statický web (`build.py` → `index.html`), Cloudflare Pages Functions (`functions/api`) a Supabase.

## Jak to funguje
1. **Zadání:** člověk (vlastník nebo správce) zadá úlohu v rozhraní AI tým, nebo ji založí plán, který člověk schválil. Úlohy jsou v `private.ai_jobs`.
2. **Provedení (server):** `/api/ai-worker` nebo `/api/ai-cron` úlohu převezme se zámkem na 3 minuty, dostane kontext spočítaný databází z dat té firmy, rezervuje peníze, zavolá AI s pevným stropem výstupu, uloží výsledek a vypořádá skutečnou spotřebu.
3. **Návrhy místo změn:** AI data nemění. Změny vrací jako návrhy akcí (`private.ai_actions`), které databáze znovu zkontroluje (např. že zákazník patří firmě).
4. **Schválení:** akci provede až `ai_action_decide` pod přihlášeným člověkem a jen pro přesně ten obsah, který viděl (otisk). `service_role` tuto funkci spustit nesmí.

| Vrstva | Soubor |
|---|---|
| Databáze | `db/migrations/20261115100000_ai_tym.sql` (+ rollback) |
| Katalog úloh a jádro | `src/ai_worker_core.js` (32 úloh; test hlídá shodu s `private.ai_kinds`) |
| Endpointy | `functions/api/ai-worker.js` (úlohy, chat), `functions/api/ai-cron.js` (plány na pozadí), `functions/api/accountant.js` (vytěžení dokladu → evidence) |
| Rozhraní | `src/ai_team_ui.js`, `src/bank_csv.js` |

## Typy akcí, které AI smí navrhnout
úkol, koncept příspěvku, poznámka k zákazníkovi, finanční záznam, koncept nabídky, text webu (titulek, podtitulek, O nás), popis produktu, měřitelný cíl, pravidelný plán.
U textu webu a popisu produktu se při schválení uloží původní znění. Nic se neodesílá zákazníkům a nic se nepublikuje na sociální sítě.

## Limity nákladů (vynucuje databáze)
- **Firma za měsíc:** stávající limit; nově strop podle tarifu (PRO 2 USD, BUSINESS 10 USD, ENTERPRISE 50 USD).
- **Uživatel za měsíc:** volitelný (`autopilot_set_limits`).
- **Jedna operace:** výchozí 0,01 USD, lze snížit.
- Kontroly běží uvnitř zámku firmy, takže souběžné požadavky limit nepřekročí. Po vyčerpání se další placené operace odmítnou před voláním AI.

## Běh na pozadí
- Plán (`private.ai_schedules`) schvaluje člověk; běží na jeho účet. Když schvalovatel přestane být vlastníkem nebo správcem, úloha se nespustí.
- Jedna úloha na plán a den, nejvýše 3 pokusy s odstupem, zámek proti dvojímu provedení, tlačítko „Zastavit všechny plány“.
- Výsledky běhů na pozadí jsou zase jen návrhy ke schválení.

### Zapnutí plánovače v produkci (samostatný krok, vyžaduje souhlas)
1. V Cloudflare přidat tajemství `AI_CRON_SECRET` (náhodný řetězec, aspoň 24 znaků) a znovu nasadit.
2. Stejnou hodnotu uložit do Supabase Vault jako `ai_cron_secret` (v SQL editoru, ne do chatu).
3. Naplánovat:
```sql
select cron.schedule('vexaronet-ai-cron', '*/15 * * * *', $$
  select net.http_post(url := 'https://vexaronet.com/api/ai-cron',
    headers := jsonb_build_object('content-type', 'application/json', 'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'ai_cron_secret')),
    body := '{}'::jsonb) $$);
```
Vypnutí: `select cron.unschedule('vexaronet-ai-cron');`

## AI Účetnictví
- **Doklady:** vytěžení z PDF nebo fotky (stávající `/api/accountant`) se nově uloží do evidence ke kontrole. Soubor se neukládá, jen jeho SHA-256 otisk.
- **Duplicity:** stejný soubor, nebo stejný dodavatel + číslo + částka.
- **Schválení člověkem:** přijatý doklad vytvoří výdaj; vystavená faktura se jen sváže s existující (žádný druhý příjem). Opravy člověka se ukládají vedle původního návrhu AI.
- **Režim:** daňová evidence / účetnictví / paušální daň, plátce DPH. Podle něj AI navrhuje zařazení nebo předkontace, vždy jako návrh k ověření.
- **Přehled DPH a export CSV:** orientační, s upozorněním, že nejde o přiznání.
- **Banka:** nahrání výpisu CSV a párování na faktury používá stávající produkční funkci `bank_reconciliation` (přesná shoda VS, částky a měny; úhradu potvrzuje člověk). Aplikace netvrdí, že čte banku sama.

### Open Banking (neimplementováno, vyžaduje rozhodnutí a účet u poskytovatele)
- Ověřeno z dokumentace Enable Banking: po registraci sandboxové aplikace je k dispozici „Mock ASPSP“ a sandboxy některých bank; pokrývá přes 2 700 bank ve 30 evropských zemích. **Neověřeno:** zda registrace a produkce vyžadují firmu (IČO) a které české banky jsou dostupné.
- GoCardless Bank Account Data: stav nových registrací se nepodařilo ověřit (stránka vyžaduje přihlášení).
- Návrh napojení: poskytovatel → serverová funkce se souhlasem majitele účtu → tabulka transakcí → stejné párování a stejné potvrzení člověkem jako u CSV. Tokeny souhlasu jen na serveru (Vault), nikdy v prohlížeči.
- Další krok je na vlastníkovi: vybrat poskytovatele a založit vývojářský účet.

## Bezpečnost
- Všechny nové tabulky jsou v `private`, mají RLS a nejsou přes API přímo dostupné; přístup jen funkcemi s kontrolou role a firmy.
- Kontext pro AI skládá databáze jen z dat dané firmy (test ověřuje, že data jiné firmy v zadání nejsou).
- Ochrana proti podvržení pokynů: data a text uživatele jsou v zadání označené jako údaje; typy akcí jsou omezené podle úlohy; každou akci kontroluje DB a schvaluje člověk.
- **Osobní údaje:** do AI (Google Gemini) jdou názvy zákazníků, obchodních případů a částky, ne e-maily ani telefony. Před veřejným provozem je to potřeba uvést v zásadách a mít se zpracovatelem smlouvu.

## Testy
| Test | Výsledek |
|---|---|
| `tests/db/run_ai_tym_local.sh` | 71 kontrol pod rolemi, přesný rollback |
| `tests/ai_worker_e2e.test.mjs` | 16/16 (skutečné endpointy proti skutečné PostgreSQL, simulovaná jen AI) |
| `tests/ai_team_ui.py` | 38 kontrol v prohlížeči včetně mobilu |
| `tests/bank_csv.test.mjs` | 5/5 |
| Regrese | `ai_marketing_e2e` 14, `ai_endpoints` 73, `key_headers`, `run_autopilot_local` 71 a 16 UI testů |

`smoke`, `fakt` a `faktury_qr` selhávají stejně jako na produkční verzi (zastaralé testy, chybějící cv2); touto prací se nezměnily.

## Nasazení (až po souhlasu)
1. Migrace `20261115100000_ai_tym` (mění `autopilot_reserve_core` na obálku se stejným chováním; ostatní jsou nové objekty). Před ní migrace `20261114100000_registrace_limit`, pokud ji chcete.
2. Sloučení větve do `main` (web a funkce). Bez zapnutých placených běhů AI tým vrací „Placené AI běhy nejsou zapnuté“ a nic neúčtuje.
3. Volitelně plánovač (viz výše).
Návrat: revert merge a `20261115100000_ai_tym_rollback.sql` (smaže úlohy, akce, chat, plány, cíle a evidenci dokladů; před tím exportovat `private.ai_*` a `private.acc_*`).
