# Vexaronet – architektura (návrh pro etapy 2 až 8)

Stav: hotová je jen etapa 1 (úvodní stránka). Vše níže je plán, nic z toho zatím neběží.

## Technologie
- Úvodní stránka: statický HTML/CSS/JS (jeden soubor), hostovaný na Netlify.
- Aplikace (od etapy 2): Next.js + TypeScript + Tailwind + Framer Motion, Supabase (PostgreSQL, Auth, Storage).
- AI: serverové funkce volají AI poskytovatele, API klíč je jen v proměnných prostředí na serveru, nikdy v prohlížeči.
- Platby předplatného: Stripe nebo GoPay (vyžaduje účet a právní ověření).

## Oddělení dat firem
Každá tabulka má `org_id`. Přístup řídí Row Level Security podle členství v `org_members` a role (`owner, admin, accountant, sales, employee, viewer`). Schéma: `schema.sql` (ověřeno, že se v PostgreSQL 16 vytvoří bez chyby; RLS politiky nejsou prakticky otestované s reálnými uživateli).

## AI a schvalování
AI nikdy nevykoná důležitou akci sama. Navrhne ji do tabulky `ai_actions` (stav `pending`), uživatel s rolí owner/admin ji schválí a teprve potom ji provede server. Každá akce se eviduje.

## Registrace a zkušební období
Po registraci server vytvoří firmu, členství vlastníka a předplatné se zkušebním obdobím 30 dní. Ceny tarifů jsou v tabulce `plan_prices` a mají se upravovat v administraci. PRO = 699 Kč měsíčně, ostatní se doplní.

## Etapy
1. Úvodní stránka a design (hotový návrh)
2. Registrace, přihlášení, databáze
3. Dashboard, CRM, zakázky, kalendář
4. Finance a fakturace (nutná kontrola účetním; legislativa ČR/SK/EU)
5. AI centrum a automatizace
6. Weby a e-shopy (platební a dopravní služby, domény)
7. Marketing a analytika
8. Předplatné, zabezpečení, testování

## Co vyžaduje externí službu nebo právní ověření
AI (API klíč), e-maily, platby, doprava, domény, účetní a daňová pravidla zemí EU, GDPR dokumenty, obchodní podmínky.
