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
