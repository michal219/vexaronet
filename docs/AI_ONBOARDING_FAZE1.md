# AI onboarding – databázový podklad a plán 1. fáze

Stav: **návrh**, 2026-11-07. Zatím nebyl změněn funkční kód, databáze ani nasazení.
Podklad: snapshot `db/snapshot/` (pouze čtení živé DB `micymdbqgzeckiqyvvkn`).
Specifikace onboardingu zatím nebyla dodána. Tento plán připravuje základ, na který se napojí.

Značky: **[OVĚŘENO]** = přečteno přímo z živé DB nebo z kódu repozitáře.
**[PŘEDPOKLAD]** = odvozeno, neověřeno.

---

## 1. Ověřená zjištění

### Firmy a členství
- **[OVĚŘENO]** Firma = `public.companies`. Pobočka (provozovna) = řádek s `parent_company_id`.
  Unikátní index `one_trial_per_owner` povoluje každému vlastníkovi jen jednu hlavní firmu.
- **[OVĚŘENO]** Členství = `public.company_members (company_id, user_id, role, display_name)`.
  Role jsou jen `owner`, `admin`, `employee` (omezení `company_members_role_check`).
  Role `accountant`, `sales`, `viewer` ze starého `schema.sql` neexistují.
- **[OVĚŘENO]** `private.create_company_core` odmítne založit firmu, pokud uživatel nemá
  potvrzený e-mail nebo už je členem jakékoli firmy. Firmu, členství `owner`, `profiles`
  a `subscriptions` vytvoří v jedné transakci.
- **[OVĚŘENO]** Jeden uživatel může být členem více firem: `private.branch_action` kopíruje
  vlastníka a správce do poboček. Dnes v DB není žádná pobočka a každý uživatel má právě jedno
  členství (agregovaný počet, bez identifikátorů). Výběr aktivní firmy je tedy nutné opravit
  dřív, než pobočky začnou existovat.
- **[OVĚŘENO]** Role `authenticated` má na `companies` a `company_members` jen právo SELECT.
  Politika `company_edit` (UPDATE) se proto nikdy neuplatní. Zápis jde jen přes
  SECURITY DEFINER funkce.
- **[OVĚŘENO]** Žádná funkce v DB nemění název, obor ani `workspace_config` firmy. Jediná
  funkce, která firmu upravuje, je `private.workspace_settings`, a ta mění jen zemi a měnu.
  Proto název firmy nejde v aplikaci upravit.
  (Hledáno vzorem `update public.companies set` ve všech funkcích.)

### Předplatné a tarif
- **[OVĚŘENO]** `public.subscriptions`, jeden řádek na firmu (PK `company_id`).
  Tarify: `start`, `accountant`, `pro`, `business`, `enterprise`.
  Stavy: `trial`, `active`, `past_due`, `expired`, `canceled`.
- **[OVĚŘENO]** Trigger `sync_branch_subscription` kopíruje předplatné hlavní firmy na pobočky.
  Autoritativní tarif pro pobočku je tarif hlavní firmy: `private.business_root(cid)`,
  `private.suite_plan(cid)`.
- **[OVĚŘENO]** `private.writable(cid)` povolí zápis při `trial` s budoucím `trial_end`, nebo
  při `active` a zároveň (`paid_until > now()` nebo tarif `start`). **Tarif `pro` nebo `business`
  ve stavu `active` bez `paid_until` tedy zápis neumožní.** To je důležité při ručním
  přepínání tarifů.
- **[OVĚŘENO] Chyba v registraci:** formulář nabízí tarif „AI Účetní“ (`accountant`,
  `build.py:589`). `create_company_for_plan` i `choose_trial_plan` ale přijímají jen
  `start`, `pro`, `business`, `enterprise`. Registrace s tímto tarifem skončí chybou
  „Vyberte platný tarif.“ Ověřeno čtením definic, živě nereprodukováno.
- **[OVĚŘENO]** Limity týmu jsou na dvou místech a liší se:
  - `public.invite_member`: start 1, accountant 2, pro 3, business 10,
  - trigger `private.enforce_team_capacity`: start 2, pro 10, ostatní 50, business a enterprise bez limitu.

### Firemní profil
- **[OVĚŘENO]** Fakturační údaje dodavatele jsou v `public.user_business_profiles`. Navzdory
  názvu je primárním klíčem `company_id`, profil je tedy už **společný pro firmu**.
  - Číst je smí jen `owner` a `admin`.
  - Zapisovat jde jen přes `public.invoice_action(cid, 'profile', doc)`: role owner/admin,
    `writable`, přísná validace (povinný název, sídlo, údaj o registraci, platné IČO,
    IBAN a e-mail).
  - **Neúplné údaje z onboardingu tam proto uložit nejdou.**
- **[OVĚŘENO]** `companies.workspace_config` má přísné JSON schéma. Povolené klíče jsou jen
  `industries` (pole oborů, nejvýše 10) a `hiddenModules` (výčet 22 modulů);
  `additionalProperties: false`. Pro výběr oborů a modulů je to připravené místo, odpovědi
  z onboardingu se sem ale nevejdou.
- **[OVĚŘENO]** Existuje `public.public_profiles` (veřejný profil: popis, služby, město,
  kontakty, otevírací doba). Zveřejnit ho jde jen v tarifu Pro a vyšším. Vyžaduje unikátní `slug`.
- **[OVĚŘENO]** Aplikace v repozitáři dnes ukládá obor (`ui_industry`), zvolené funkce
  (`features`) a příznak `onboarded` do metadat **jednoho uživatele** (`auth.updateUser`,
  `build.py:670`, `:2247`, `:2249`), nikoli k firmě. `workspace_config` vůbec nepoužívá.

### AI
- **[OVĚŘENO]** V DB už existuje serverová kontrola nároku a limitů:
  `public.reserve_ai(cid)` → `private.reserve_ai_core`. Ověří členství, `writable(cid)` a tarif
  hlavní firmy (pro, business, enterprise). Pak atomicky hlídá limity: 100 požadavků za den na
  celou platformu, 300 za měsíc a 20 za den na firmu, 3 za minutu na uživatele.
  Záznamy ukládá do `private.ai_requests`.
- **[OVĚŘENO]** Cloudflare funkce z repozitáře `reserve_ai` nevolají. Limity drží jen v paměti
  jedné instance (`limited()` v každém souboru), takže je každá nová instance vynuluje.
- **[OVĚŘENO]** `advisor.js`, `web-ai.js` a `marketing.js` čtou `subscriptions?...&limit=1`
  **bez určení firmy**. Frontend jim `cid` neposílá (`build.py:1703`, `:1747`, `:1800`, `:2169`).
  Role uživatele se nekontroluje, takže i `employee` může AI CEO zavolat přímo.
  `accountant.js` firmu filtruje správně, nepočítá ale s tarifem hlavní firmy u poboček.
- **[OVĚŘENO]** Frontend vybírá firmu dotazem `company_members ... limit(1)` bez řazení
  (`ensureCompany`, `build.py:620`). Při více členstvích je výsledek náhodný.

### Rozdíl mezi repozitářem a databází
- **[OVĚŘENO]** DB obsahuje 65 záznamů migrací (poslední `crm_deals_quotes_notes`,
  2. 11. 2026). V repozitáři žádné nejsou.
- **[OVĚŘENO]** Commit `4001a25` uvádí „schema_crm.sql (neaplikována)“, ale tabulky
  `deals`, `quotes` a `client_notes` i záznam migrace v DB **jsou**.
- **[OVĚŘENO]** DB obsahuje backend funkcí, které aplikace v repozitáři vůbec nevolá:
  `ai_workspace`, `ai_proposals`, `suite_*`, `business_web_*`, `bank_reconciliation`,
  `booking_settings`, `public_profiles`, `user_preferences`, `workspace_settings` a další.
- **[PŘEDPOKLAD]** Nad stejnou DB může běžet (nebo běžel) jiný frontend. Pokud ano, změny
  `companies`, `workspace_config` nebo AI limitů ho mohou ovlivnit. **Potřebuji potvrzení.**
- **[PŘEDPOKLAD]** Část tabulek (`company_invites`, `ai_usage`, `shifts`, `sites`, `shop_*`…)
  vznikla ručně v SQL Editoru ze souborů `schema_*.sql` a nemá záznam v historii migrací.

### Bezpečnostní nálezy (mimo rozsah 1. fáze, k rozhodnutí)
1. RLS je vypnuté na `private.platform_admins`, `private.ai_requests`,
   `private.feedback_mail_delivery`, `private.push_deliveries`.
   - **[OVĚŘENO]** Role `anon` nemá přístup ke schématu `private`.
   - **[OVĚŘENO]** `anon` ani `authenticated` nemají práva na první dvě tabulky; pro zbylé dvě
     dotaz na práva nevrátil nic.
   - Přes API tedy dostupné nejsou. Doporučuji RLS přesto zapnout, jako druhou pojistku.
2. **[OVĚŘENO]** `anon` má plná práva (vč. DELETE, UPDATE, TRUNCATE) na `public.ai_usage`,
   `public.company_invites` a `public.plan_requests`. DML omezuje RLS; TRUNCATE přes API
   provést nejde. Doporučuji práva `anon` odebrat.
3. **[OVĚŘENO]** Ochrana proti uniklým heslům (HaveIBeenPwned) je v Supabase Auth vypnutá.
4. **[OVĚŘENO]** `anon` smí spouštět SECURITY DEFINER funkce `clock_in`, `clock_out`
   a `shop_cancel_order`.
   - **[PŘEDPOKLAD]** Uvnitř kontrolují `auth.uid()` (verze v repozitáři ano).
     Živá těla jsem kvůli rozsahu nečetl.

---

## 2. Návrh napojení onboardingu (bez paralelních tabulek)

Princip: firma zůstává v `companies` a členství v `company_members`. `organizations` ani
`org_members` nevznikají. Firemní data se ukládají k `company_id`, ne do metadat uživatele.
Zápis jde přes SECURITY DEFINER funkce ve stejném vzoru jako zbytek DB
(veřejná obálka v `public`, jádro v `private`, `search_path = ''`).

| Údaj | Kam | Proč |
|---|---|---|
| Název firmy, hlavní obor | `companies.name`, `companies.industry` | Už existuje, sdílí celá firma. Chybí jen funkce pro změnu. |
| Obory a skryté moduly | `companies.workspace_config` (`industries`, `hiddenModules`) | Existující a validované místo. Nahradí `features` a `ui_industry` v metadatech. |
| Země, měna | `public.workspace_settings` (existující) | Už má kontroly (měna jen u hlavní firmy, nelze změnit při existujících datech). |
| Fakturační údaje (úplné) | `user_business_profiles` přes `invoice_action(cid,'profile',…)` | Využije existující validaci. Žádný druhý zdroj pravdy. |
| Rozpracované odpovědi, neúplný profil, stav průvodce | **nová** `public.company_onboarding` | Nikam jinam se bezpečně nevejde. |

### Navržená tabulka (zatím jen návrh, nespuštěno)
```sql
create table public.company_onboarding (
  company_id    uuid primary key references public.companies(id) on delete cascade,
  status        text not null default 'not_started'
                check (status in ('not_started','in_progress','completed','skipped')),
  current_step  text not null default '' check (length(current_step) <= 60),
  answers       jsonb not null default '{}'::jsonb
                check (jsonb_typeof(answers) = 'object' and pg_column_size(answers) <= 65536),
  profile_draft jsonb not null default '{}'::jsonb
                check (jsonb_typeof(profile_draft) = 'object' and pg_column_size(profile_draft) <= 32768),
  started_at    timestamptz,
  completed_at  timestamptz,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references auth.users(id) on delete set null
);
alter table public.company_onboarding enable row level security;
revoke all on public.company_onboarding from anon, authenticated;
grant select on public.company_onboarding to authenticated;
create policy onboarding_read on public.company_onboarding for select to authenticated
  using (private.member_role(company_id) in ('owner','admin'));
```
Podoba `answers` se upřesní podle specifikace. Validace klíčů bude ve funkci, ne v CHECK,
aby šla měnit bez migrace tabulky.

### Navržené funkce (veřejná obálka → `private` jádro, SECURITY DEFINER)
| Funkce | Kdo | Co dělá |
|---|---|---|
| `my_companies()` | přihlášený | Firmy, kde je uživatel členem: role, hlavní firma, efektivní tarif (z hlavní firmy), stav onboardingu. Podklad pro výběr aktivní firmy. |
| `onboarding_state(cid)` | owner/admin | Stav, krok, odpovědi a rozpracovaný profil. Řádek založí líně, při prvním čtení. |
| `onboarding_save(cid, step, patch)` | owner/admin + `writable` | Uloží průběžné odpovědi (whitelist klíčů, limit velikosti). Zámek `pg_advisory_xact_lock` na firmu. |
| `onboarding_complete(cid, doc)` | owner/admin + `writable` | V jedné transakci: název a obor → `companies`, obory a moduly → `workspace_config`, země a měna → `private.workspace_settings`, fakturační údaje (jen jsou-li úplné) → `private.invoice_action_core(cid,'profile',…)`, stav `completed`. |
| `company_update_basics(cid, doc)` | owner/admin + `writable` | Pozdější úprava názvu a oboru v Nastavení (dnes nemožná). |

---

## 3. Oprava aktivní firmy a tarifu v AI funkcích

### Frontend (`build.py`)
1. `ensureCompany` (`build.py:619`): místo `limit(1)` načíst všechna členství přes `my_companies()`.
   Aktivní firmu vybrat takto:
   - uložená volba `vx_active_company_<uid>` v `localStorage`, ale jen pokud je stále
     mezi členstvími,
   - jinak hlavní firma, kde je uživatel `owner`,
   - jinak nejstarší členství.
2. Při více firmách zobrazit přepínač v hlavičce. Při přepnutí znovu načíst data (`refresh`).
3. Všem AI voláním posílat `cid: APP.cid` (`build.py:1703`, `:1747`, `:1800`, `:2169`).
4. Přestat ukládat firemní údaje do metadat uživatele (`ui_industry`, `features`, `onboarded`).
   Číst je z firmy. Stará metadata použít jen jako jednorázový zdroj pro předvyplnění.

### Server (`functions/api/advisor.js`, `web-ai.js`, `marketing.js`, `accountant.js`)
Společný pomocník, který postupně:
1. Ověří token: `auth/v1/user` → `uid` (jako dnes).
2. Vyžaduje platné `cid` (UUID). Bez něj vrátí `400`.
3. Načte s tokenem uživatele `company_members?company_id=eq.{cid}&user_id=eq.{uid}&select=role`.
   Prázdný výsledek znamená `403`. Role musí být `owner` nebo `admin`, stejně jako v UI (`allowed()`).
4. Najde hlavní firmu (`companies?id=eq.{cid}&select=id,parent_company_id`) a načte její
   `subscriptions`.
5. Efektivní tarif určí stejnou logikou jako DB (`writable` a `booking_plan_allowed`).
   Prošlá zkušební doba se bere jako `start`.
6. AI CEO, web a marketing: zavolá `rpc/reserve_ai` s `{cid}`. Ta atomicky ověří nárok i limity
   a zapíše požadavek. Paměťové `limited()` se ponechá jen jako ochrana proti zahlcení.
   Chyby DB se převedou na dnešní kódy (`plan` → 403, limit → 429), takže se frontend nemusí měnit.
7. AI Účetní: `reserve_ai` tarif `accountant` nepovoluje. Zůstane vlastní kontrola
   (tarif hlavní firmy, role owner/admin, počítadlo `ai_usage`).

**[PŘEDPOKLAD k ověření při implementaci]** Kam umístit společný modul, aby ho Cloudflare Pages
nezpřístupnily jako trasu ani jako veřejný soubor (publikuje se celý kořen `.`).

---

## 4. První implementační fáze – kroky

Pořadí je zvolené tak, aby každý krok šel nasadit a vrátit samostatně.

| # | Krok | Soubory / objekty | Hotovo, když |
|---|---|---|---|
| 0 | Testovací databáze | Supabase branch nebo samostatný projekt (schválí vlastník, branch je placený) | Snapshot obnoven a otisky funkcí sedí s manifestem. Teprve pak smí být označen jako obnovovací migrace. |
| 1 | Migrace `company_onboarding` a funkce z oddílu 2 | `db/migrations/<datum>_company_onboarding.sql` + rollback | Testy rolí na testovací DB: owner ✓, admin ✓, employee ✗, cizí uživatel ✗, prošlý trial ✗, pobočka čte tarif hlavní firmy. |
| 2 | Výběr aktivní firmy | `build.py` (`ensureCompany`, `openApp`, `showAccount`) | Smoke test s mockem dvou firem: volba přežije obnovení stránky; po odebrání členství se vybere jiná firma. |
| 3 | AI funkce: `cid`, role, tarif hlavní firmy, `reserve_ai` | `functions/api/advisor.js`, `web-ai.js`, `marketing.js`, `accountant.js`, `build.py` | Testy pro každý endpoint: bez `cid` 400; cizí firma 403; employee 403; start 403; pro trial OK; pobočka bere tarif hlavní firmy; limit 429. |
| 4 | Firemní údaje mimo metadata uživatele | `build.py` (Nastavení: obor, funkce, název firmy) | Změna oboru u jednoho správce je vidět i u druhého. |
| 5 | Kostra onboardingu (stav, uložit, dokončit) bez AI | `build.py` (nahradí `onboard()` na `:955`) | Průvodce jde přerušit a dokončit; po dokončení se znovu nezobrazí nikomu z firmy. |
| 6 | AI část podle specifikace | podle specifikace | – |

Nasazení na produkci až po schválení. Pořadí: migrace (1) → serverové funkce (3) → frontend (2, 4, 5).
Kroky 2 až 4 jsou kompatibilní se současnou DB, i kdyby se krok 1 odložil, pokud se
`my_companies()` nahradí přímým dotazem.

---

## 5. Otázky k rozhodnutí před implementací
1. **Tarif AI Účetní při registraci:** povolit `accountant` v `create_company_for_plan`
   a `choose_trial_plan`, nebo ho z registrace odebrat? Dnes registrace s ním selže.
2. **Limity `reserve_ai`:** 100 požadavků za den na celou platformu je pro provoz velmi málo.
   Mají AI funkce používat tyto limity (upravené), nebo zůstat u vlastních?
3. **Pobočky:** vyplňuje se onboarding jen za hlavní firmu, nebo za každou provozovnu?
4. **Kdo vyplňuje onboarding:** jen `owner`, nebo i `admin`?
5. **Jiný frontend nad stejnou DB:** existuje? Ovlivní, zda smím použít `workspace_config`
   a měnit AI limity.
6. **Testovací DB:** Supabase branch (placený, rychlý) nebo samostatný bezplatný projekt?
7. Bezpečnostní nálezy 1–4: řešit v samostatném kroku před onboardingem, souběžně, nebo později?
