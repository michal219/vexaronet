# Vexaronet – nasazení úvodní stránky
Soubory: index.html, 404.html, robots.txt, sitemap.xml, netlify.toml, netlify/functions/chat.mjs.
1. Nahraj složku na GitHub a na Netlify zvol Import from Git (build příkaz prázdný, publish složka ".").
2. Netlify, Environment variables: GEMINI_API_KEY (klíč z Google AI Studia, nikdy ho neposílej do chatu). Volitelně GEMINI_MODEL.
3. Deploy znovu, aby se proměnná načetla.
4. Formulář early access: Netlify, Forms, zapni e-mailové notifikace.
5. Doména vexaronet.com přidej v Domain management.
Bez klíče chat napíše, že není dostupný.

## Supabase (přihlášení a registrace)
- V index.html jsou nahoře v JS konstanty SB_URL a SB_KEY (veřejný publishable klíč, smí být ve webu). Tajný klíč (sb_secret / service_role) NIKDY nevkládej do webu.
- V Supabase: Authentication, URL Configuration, do "Site URL" a "Redirect URLs" přidej https://vexaronet.com (a adresu z Netlify), jinak odkaz z potvrzovacího e-mailu povede jinam.
- Hodnoty tarifů (PLAN_VALUE) musí odpovídat tomu, co přijímá funkce create_company_for_plan.

## Ranní přehled do e-mailu a pobočky
1. V Supabase SQL editoru spusťte `schema_prehled_pobocky.sql` (tabulky locations a digest_settings, sloupec location_id).
2. V Cloudflare Pages (Settings → Variables and Secrets) přidejte: `DIGEST_SECRET` (libovolné dlouhé heslo), `SUPABASE_SERVICE_KEY` (service_role klíč z Supabase, Project Settings → API; tajný, nikam jinam). `RESEND_API_KEY` a volitelně `GEMINI_API_KEY` už máte.
3. V Supabase zapněte rozšíření pg_cron a pg_net (Database → Extensions) a spusťte `cron.schedule` z konce souboru schema_prehled_pobocky.sql s vaším DIGEST_SECRET.
4. V aplikaci na Přehledu: Dnes ve firmě → Zapnout ranní e-mail → Poslat zkušební.

## Docházka zaměstnanců (online / offline) a odpracované hodiny
1. V Supabase SQL Editoru spusťte celý soubor `schema_dochazka.sql` (jednou). Vytvoří tabulku `time_entries`, funkce `clock_in` a `clock_out` a dovolí členům firmy přidávat a upravovat zákazníky, zakázky a úkoly (mazat nemohou).
2. Majitel nebo správce vyznačí směny v Kalendáři (jméno nebo e-mail zaměstnance musí odpovídat jeho účtu).
3. Zaměstnanec po přihlášení vidí na Přehledu kartu **Moje docházka**: při příchodu na směnu klikne na **Přijít na směnu (online)**, při odchodu na **Odejít (offline)**. Čas bere server, ne telefon.
4. Majitel vidí v části **Zaměstnanci** kdo je online, odpracované hodiny za tento měsíc i celkem a poslední záznamy. Zapomenutou směnu ukončí tlačítkem **Ukončit**.
5. Zaměstnanec může přidávat zákazníky a zakázky. Faktury, finance a AI CEO nevidí.

## Poptávky na systém na míru
Poptávka se ukládá do samostatné tabulky `custom_inquiries` (soubor `schema_poptavky.sql`, spustit jednou v Supabase SQL Editoru) a nezávisí na odběru novinek. Majiteli přijde e-mail „Poptávka: systém na míru“ (potřebuje `RESEND_API_KEY` a `NOTIFY_EMAIL` v Cloudflare). Pokud selže uložení i e-mail, formulář zobrazí chybu a zákazník uvidí e-mail info@vexaronet.com.
