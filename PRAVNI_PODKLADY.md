# Podklady pro právní kontrolu (stav k 1. 11. 2026)

Dokumenty na webu (`/podminky/`, `/ochrana-udaju/`, `/cookies/`) jsou **návrh pro beta verzi, ne schválené znění**. Označení „návrh" v textech zůstává, dokud je nezkontroluje odborník.

## A. Ověřené skutečnosti (z kódu a konfigurace projektu)
- **Hosting a servery:** Cloudflare Pages (statický web a serverové funkce v `functions/api/`). Doména vexaronet.com.
- **Databáze, přihlášení, úložiště souborů:** Supabase, projekt v regionu eu-north-1 (Stockholm). Bucket `site-images` má veřejné čtení (obrázky na webech firem), zápis jen vlastník nebo správce firmy.
- **AI:** serverové funkce (`accountant`, `advisor`, `chat`, `digest`, `marketing`, `web-ai`) volají Google Gemini API (`generativelanguage.googleapis.com`). Odesílá se dotaz a data potřebná k odpovědi, u AI Účetní i nahraný doklad. Klíč je jen na serveru.
- **E-maily:** Resend (novinky, poptávky, ranní přehled). Odesílání závisí na nastavených serverových klíčích, jejich nastavení jsem neověřoval.
- **Cookies a úložiště prohlížeče:** žádné analytické ani reklamní cookies. V prohlížeči se ukládá volba světlého/tmavého režimu, historie AI asistenta v rámci karty a přihlášení (Supabase).
- **Export dat:** CSV z reportů a seznamů (zákazníci, faktury, příjmy a výdaje).
- **Zrušení účtu a smazání dat:** v aplikaci **není samoobslužné**, řeší se e-mailem na info@vexaronet.com. Texty nic jiného neslibují.
- **Platby:** nejsou spuštěné, nic se neúčtuje.
- **Limity tarifu START** (50 zákazníků, 10 zakázek, 10 faktur měsíčně) hlídá jen aplikace v prohlížeči, ne server.
- **Automatické mazání dat podle lhůt:** v databázi **není implementované** (žádné retenční úlohy).

## B. Chybí a musí rozhodnout provozovatel
1. **Identita provozovatele:** jméno nebo firma, IČO, adresa sídla/bydliště. Podle sdělení zakladatele zatím IČO neexistuje. Bez toho nelze podmínky ani zásady dokončit a nelze přijímat platby.
2. **Retenční lhůty:** jak dlouho se uchovávají údaje o účtu, data zákazníků, AI dotazy, zálohy po zrušení účtu. Dnes se nic automaticky nemaže.
3. **Postup zrušení a smazání:** lhůta vyřízení, co se maže a co se musí uchovat (např. doklady podle zákona), případné samoobslužné mazání (nutné vyvinout).
4. **Role správce a zpracovatele:** potvrdit, že zákazníci a zaměstnanci firem jsou údaje, u nichž je správcem firma a Vexaronet zpracovatelem. Vyžaduje **zpracovatelskou smlouvu** pro uživatele služby.
5. **Odpovědnost, reklamace, ukončení smlouvy, cena po spuštění plateb:** znění určí právník.

## C. Vyžaduje odbornou kontrolu nebo podklady třetích stran
1. **Předávání údajů mimo EHP:** Google (Gemini), Cloudflare, Resend mohou zpracovávat data i mimo EHP. Je potřeba dohledat jejich aktuální podmínky zpracování (DPA), případné standardní smluvní doložky a zvolenou lokaci zpracování. Neověřoval jsem je a nic o nich netvrdím.
2. **Zda se vstupy z AI používají k trénování modelu u konkrétní verze API a placeného tarifu:** nutno ověřit u poskytovatele.
3. **Bezpečnostní opatření:** v textech jsou záměrně jen ověřené věci (klíče jen na serveru, přístup dle firmy v databázi). Žádné tvrzení o certifikacích, šifrování nebo zálohách se nesmí přidat bez důkazu.
4. **Faktury a účetnictví:** formulace, že nenahrazuje účetního, a odpovědnost za správnost dokladů.
5. **Spotřebitelská část e-shopu** (informace před uzavřením smlouvy, odstoupení, reklamace): týká se firem, které e-shop provozují. Provozovatel Vexaronet by měl posoudit, zda a jaké vzory poskytne.
6. **Souhlas s novinkami (obchodní sdělení):** posouzení podle zákona o některých službách informační společnosti.

## D. Co je hotové v textech
- Jedna skutečná stránka pro každý dokument se správným titulkem a hlavním nadpisem, čitelná na mobilu, dostupná bez přihlášení.
- Odkazy z registrace, newsletteru, poptávky a patičky vedou na správné dokumenty.
