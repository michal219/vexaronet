# Snapshot živé databáze Vexaronetu (2026-11-07)

## Co to je
Dokumentovaný výchozí stav databáze pro práci na AI onboardingu. Pochází přímo ze živého
Supabase projektu `micymdbqgzeckiqyvvkn` (stejný projekt, na který míří `SB_URL` v `build.py`).

| Soubor | Obsah |
|---|---|
| `2026-11-07_jadro_firmy.sql` | Úplné definice objektů pro firmy, členství, předplatné, firemní a fakturační profil, pozvánky a AI limity: tabulky, omezení, indexy, RLS politiky, práva, triggery a těla funkcí. |
| `2026-11-07_manifest.txt` | Seznam 65 záznamů migrací z databáze, otisky md5 všech 193 funkcí a seznam všech 100 tabulek se stavem RLS. |

## Co to NENÍ
- **Není to otestovaná obnovovací migrace.** Obnova z těchto souborů nebyla vyzkoušena
  v oddělené testovací databázi. SQL soubor má na začátku pojistku, která jeho spuštění hned zastaví.
- Není to úplný dump. Těla funkcí mimo jádro onboardingu (např. 14 000 znaků dlouhé
  `private.invoice_action_core`) jsou jen v manifestu jako otisk md5.
- Starý `schema.sql` v kořeni repozitáře (organizations, org_members, ai_actions) **neodpovídá
  živé databázi** a aplikace ho nepoužívá. Ověřeno: tyto tabulky v databázi nejsou.

## Postup získání (2026-11-07)
Pouze čtecí dotazy přes Supabase MCP (`list_tables`, `execute_sql` jen nad systémovým katalogem,
`get_advisors`). Použité zdroje: `pg_class`, `pg_attribute`, `pg_constraint`, `pg_indexes`,
`pg_policies`, `pg_trigger`, `information_schema.role_table_grants`,
`has_schema_privilege`, `has_function_privilege`, `pg_get_functiondef`,
`supabase_migrations.schema_migrations` (jen verze a názvy).
Žádné zákaznické záznamy nebyly čteny. Jediné dotazy nad daty byly agregované počty bez
identifikátorů (kolik uživatelů má kolik členství, počet poboček, počet záznamů migrací).
Nic nebylo změněno.

## Jak snapshot ověřit obnovou (zatím neprovedeno)
1. Založit oddělenou databázi: Supabase branch nebo nový testový projekt. Pozor, branch je
   placený a musí ho schválit vlastník účtu.
2. Odstranit pojistku na začátku SQL souboru a doplnit chybějící závislosti (`customers`, `jobs`,
   `invoices`, `financial_entries`, `reservations`, funkce `log_change`, `enqueue_welcome_mail`
   a další, viz manifest).
3. Spustit a porovnat otisky funkcí s manifestem (`md5(pg_get_functiondef(oid))`).
4. Teprve potom lze soubor označit za obnovovací migraci.

## Jak zjistit, zda se databáze od snapshotu změnila
```sql
select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' fn,
       md5(pg_get_functiondef(p.oid)) h
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('public','private') and p.prokind='f' order by 1;
```
Výsledek porovnejte s oddílem B manifestu.
