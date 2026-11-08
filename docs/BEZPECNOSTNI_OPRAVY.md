# Bezpečnostní opravy z auditu: návrh, dopady, ověření

Stav: **aplikováno na produkci 2026-11-07** (migrace `security_hardening_least_privilege`, ověřeno smoke testem 93).
Aktuální přehled všech nálezů a další opravy: `docs/SECURITY_STATUS.md`.
Migrace: `db/migrations/20261108100000_bezpecnostni_opravy.sql` (+ `_rollback.sql`). Test: `tests/db/run_security_local.sh`.

## Co bylo ověřeno v živé databázi (jen čtení katalogu)

| Nález | Zjištění |
|---|---|
| RLS vypnuté na 4 tabulkách v `private` | Vlastník `postgres`, žádná práva pro `anon` ani `authenticated`. Přes API tedy nedostupné; RLS je druhá pojistka. Tabulky používají jen funkce `SECURITY DEFINER` vlastněné `postgres` (`claim_push_core`, `finish_push_core`, `platform_admin_core`, `platform_feedback_core`, `reserve_ai_core`). |
| Široká práva `anon` na `ai_usage`, `company_invites`, `plan_requests` | `anon` má `arwdDxtm` (vše vč. TRUNCATE). RLS je zapnuté a všechny politiky jsou jen pro `authenticated` (SELECT/INSERT), takže `anon` skrz API nic nepřečte ani nezapíše. `TRUNCATE` přes API nelze. Zbytečně široké. Funkce, které tabulky používají (`invite_member`, `cancel_invite`, `accept_company_invites`), jsou `SECURITY DEFINER`. |
| `clock_in`, `clock_out`, `shop_cancel_order` spustitelné pro `anon` | Mají `EXECUTE` pro **PUBLIC**, `anon`, `authenticated`, `service_role`. Těla jsem přečetl: nepřihlášeného odmítnou (kontrola `auth.uid()` / členství), nic nezmění. `shop_cancel_order` ale před kontrolou oprávnění zamyká řádek objednávky a rozlišuje hlášky „nenalezena“ a „nemáte oprávnění“, takže anon může zjišťovat, zda objednávka existuje. Volá je jen přihlášená aplikace (`build.py` řádky 1152, 1153, 1311). |

## Co migrace mění (jen práva a RLS na 10 objektech)

- **A)** `ENABLE ROW LEVEL SECURITY` na 4 tabulkách v `private`. Bez politik.
- **B)** `anon` bez práv na tři veřejné tabulky. `authenticated` si ponechá jen to, co používá aplikace: `ai_usage` SELECT+INSERT, `company_invites` SELECT, `plan_requests` SELECT+INSERT. Odebírá se UPDATE, DELETE, TRUNCATE, REFERENCES a TRIGGER (RLS UPDATE a DELETE stejně nepovoluje, protože pro ně není politika).
- **C)** `EXECUTE` pro `PUBLIC` a `anon` pryč u tří funkcí. Odebrat jen `anon` by nestačilo (zdědil by ho z `PUBLIC`).

## Dopady (ověřeno testem `run_security_local.sh`, 25 kontrol)

Test staví kopii výchozího stavu přesně podle ACL a politik z živé DB, pak migraci provede.

| Obava | Výsledek |
|---|---|
| Rozbije RLS funkce, které čtou a píšou do tabulek v `private`? | Ne. Funkce `SECURITY DEFINER` vlastněná `postgres` dál čte i zapisuje do všech čtyř (RLS vlastníka neomezuje, `FORCE` se nepoužívá). |
| Rozbije se AI Účetní, pozvánky, žádosti o tarif? | Ne. Člen firmy dál zapíše `ai_usage` a `plan_requests` a vidí je; do cizí firmy zapsat nejde; zaměstnanec dál nevidí pozvánky. |
| Rozbije se docházka a rušení e-shop objednávek? | Ne. Přihlášený člen dál zapíše příchod, cizí člen dostane stejnou hlášku jako dřív (logika funkcí se nemění). |
| Rozbije se veřejný e-shop a rezervace? | Ne. Záměrně veřejné funkce (`public_shop`, `public_shop_order`, `public_site`, `public_book`, `public_booking_info`, `public_slots`) se nemění. |
| Změní se cokoli dalšího? | Ne. Otisk všech ostatních tabulek, práv, funkcí (včetně těl) a politik je před i po shodný. |
| Jde to vrátit? | Ano. Po rollbacku jsou práva a RLS všech 10 objektů shodná s původními. |
| Je migrace opakovatelná? | Ano (spuštěná dvakrát). Při chybějícím objektu skončí chybou a transakce se vrátí. |

**Co test neřeší:** běží v lokální PostgreSQL, ne na Supabase. Jiná aplikace nad stejnou databází, pokud existuje, by mohla
používat `anon` na těchto tabulkách nebo funkcích (např. přes `service_role` by se nic nezměnilo, přes `anon` ano).
Před aplikací proto na produkci spusťte kontrolní dotaz níže a v testovacím projektu opravy vyzkoušejte.

## Ověřovací dotaz pro produkci (jen čtení, před aplikací)

```sql
-- očekávaný výsledek před opravou: 4 tabulky bez RLS; anon má TRUNCATE; PUBLIC má EXECUTE na všech třech funkcích
select (select count(*) from pg_class where oid in ('private.platform_admins'::regclass,'private.ai_requests'::regclass,
        'private.feedback_mail_delivery'::regclass,'private.push_deliveries'::regclass) and not relrowsecurity) as tabulky_bez_rls,
       has_table_privilege('anon','public.ai_usage','truncate') as anon_truncate,
       (select count(*) from pg_proc p, aclexplode(p.proacl) a where a.grantee = 0 and p.oid in
          ('public.clock_in(uuid,uuid)'::regprocedure,'public.clock_out(uuid,uuid)'::regprocedure,'public.shop_cancel_order(uuid)'::regprocedure)) as public_execute;
```

## Zbývající položky z auditu

| Položka | Rozhodnutí |
|---|---|
| Ochrana proti uniklým heslům | Nelze přes SQL. Zapnout v Supabase: Authentication → Policies (u bezplatného plánu může být nedostupné). Dělá majitel projektu. |
| Rozdílné limity týmu (`invite_member` vs. trigger `enforce_team_capacity`) | **Vyhodnoceno, neopravuji.** Platí přísnější z obou, a to `invite_member` (START 1, PRO 3, BUSINESS 10), které odpovídá textům v aplikaci. Trigger je volnější záloha (START 2, PRO 10, BUSINESS bez limitu). Není to bezpečnostní riziko, jen nejednotnost. Sjednocení je údržba. |
| `reserve_ai` (100 požadavků denně pro celou platformu) | Neměním. Autopilot má vlastní limit a s `reserve_ai` se nepotkává (viz `docs/AUTOPILOT.md`). |
| Funkce AI endpointů bez určení firmy a role | Řešeno v kódu, viz `docs/AUTOPILOT.md`, oddíl Bezpečnost AI endpointů. |
