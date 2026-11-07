# Úkoly, které musí být vyřešené nebo ověřeně vyhodnocené před ostrým provozem

Stav: 2026-11-07. Evidováno, **neřešeno**. Nic z toho profil firmy neblokuje (je to samostatná práce), ale AI onboarding
se před ostrým provozem nesmí zapnout, dokud nejsou položky označené „blokuje provoz“ uzavřené.

## Ú1. Registrace s tarifem „AI Účetní“ selže (blokuje provoz)

- **Příčina [OVĚŘENO čtením kódu a definic funkcí]:** formulář nabízí tarif `accountant` (`build.py`, konstanta `PLAN_OPTS`).
  Funkce `private.create_company_for_plan` i `private.choose_trial_plan` přijímají jen `start`, `pro`, `business`, `enterprise`
  a jinak vyhodí „Vyberte platný tarif.“ Uživatel s tímto tarifem si po potvrzení e-mailu nevytvoří firmu.
  Živě jsem to nezkoušel (vyžadovalo by to zakládat účet v produkci).
- **Varianta A (jen aplikace):** tarif z registrace odebrat, zůstane v „Změnit tarif“ (žádost o ruční nastavení).
- **Varianta B (databáze):** povolit `accountant` v obou funkcích. Změní se existující logika na produkci a musí se promyslet
  navazující věci: `reserve_ai_core` AI pro tento tarif nepovoluje, `invite_member` pro něj počítá 2 uživatele, `enforce_team_capacity` jiný limit.
- **Kdo rozhodne:** vlastník produktu. Doporučuji A, pokud „AI Účetní“ ještě nemá smysluplnou nabídku v DB.
- **Uzavřeno, když:** nový účet s každým nabízeným tarifem projde registrací a vznikne firma s předplatným (test na testovacím projektu).

## Ú2. Bezpečnostní nálezy z auditu (blokují provoz, dokud nejsou vyřešené nebo vyhodnocené)

**Aktualizace 2026-11-09:** a, b, d jsou **aplikované na produkci** (2026-11-07). Úplný a aktuální přehled všech nálezů, včetně nových
(AI limity, přehled e-mailem, CSP, zálohy, edge funkce mimo repozitář), je v `docs/SECURITY_STATUS.md`; tabulka níže je historická.

**Aktualizace 2026-11-08:** nálezy a, b, d mají připravenou migraci `db/migrations/20261108100000_bezpecnostni_opravy.sql` s ověřenými dopady (`docs/BEZPECNOSTNI_OPRAVY.md`), nález e je vyhodnocen jako neopravovaný, nález c je nastavení v dashboardu.
Nic z toho není aplikované na produkci. Před aplikací je nutný váš souhlas a zkouška na testovacím projektu.

| # | Nález [OVĚŘENO v živé DB] | Dopad | Návrh | Rizika změny |
|---|---|---|---|---|
| a | RLS vypnuté na `private.platform_admins`, `private.ai_requests`, `private.feedback_mail_delivery`, `private.push_deliveries` | `anon` nemá přístup ke schématu `private`, `authenticated` nemá práva na první dvě tabulky; pro zbylé dvě dotaz nevrátil žádné oprávnění. Přes API tedy nedostupné, chybí druhá pojistka. | `ALTER TABLE private.<tabulka> ENABLE ROW LEVEL SECURITY;` pro čtyři tabulky | Funkce typu `SECURITY DEFINER` (vlastník `postgres`) RLS obcházejí, servisní role také. Před nasazením ověřit na kopii. |
| b | `anon` má všechna práva (i `DELETE`, `UPDATE`, `TRUNCATE`) na `public.ai_usage`, `public.company_invites`, `public.plan_requests` | DML omezuje RLS, `TRUNCATE` přes API nejde. Přesto zbytečně široké. | `REVOKE ALL ON public.ai_usage, public.company_invites, public.plan_requests FROM anon;` a z `authenticated` odebrat `TRUNCATE, REFERENCES, TRIGGER` | Ověřit, že tyto tabulky nepoužívá nepřihlášený kód. |
| c | Ochrana proti uniklým heslům (HaveIBeenPwned) je v Supabase Auth vypnutá | Uživatelé mohou použít uniklé heslo | Zapnout v dashboardu: Authentication → Policies (u bezplatného plánu nemusí být dostupné) | Žádné, jen přísnější hesla |
| d | `anon` smí spouštět `SECURITY DEFINER` funkce `clock_in`, `clock_out`, `shop_cancel_order` | Mohou to být zamýšlené veřejné funkce, nebo ne | **Nejdřív přečíst těla funkcí.** Nečetl jsem je. [NEOVĚŘENO] | Změna by mohla rozbít veřejný e-shop a docházku |
| e | Limity týmu jsou na dvou místech a liší se (`invite_member` vs. trigger `enforce_team_capacity`) | Neurčité chování při pozvání | Sjednotit na jedno místo | Změna existující logiky |
| f | `reserve_ai` limituje 100 AI požadavků denně na celou platformu | Provozní strop pro AI; nesouvisí s bezpečností | Rozhodnout o limitu, než se AI onboarding zapne (viz `docs/ai-onboarding-faze1-technicke-body.md`, bod 6) | Změna globálního AI limitu (jiná aplikace může používat stejnou databázi) |

## Ú3. Další otevřené věci (neblokují)

- ~~Zjistit, zda nad touto databází běží ještě jiná aplikace~~ **Ověřeno 2026-11-09:** ano, 13 Supabase edge funkcí jiné aplikace (viz `docs/SECURITY_STATUS.md`, B-7).
- Pořídit úplný zálohovatelný dump schématu a ověřit obnovu v testovacím projektu (snapshot v `db/snapshot/` je zatím jen dokumentace).
- Zdokumentovat, jak se spouštějí existující cron úlohy (adresy, tajemství) před implementací workeru AI.
- Pět starších testů selhává už před touto prací: `smoke`, `fakt`, `legal`, `demo_btn` a `faktury_qr` (chybí modul `cv2`). Nesouvisí se změnami profilu.
