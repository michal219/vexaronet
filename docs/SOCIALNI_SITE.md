# Propojení sociálních sítí (Facebook, Instagram)

Stav k 2026-11-12: kód, databázová migrace a testy jsou hotové. **V produkci funkce neběží**, dokud provozovatel
neudělá kroky v části „Co je potřeba k zapnutí“. Do té doby web poctivě hlásí „zatím není nastavené / nasazené“.

Ověřeno proti dokumentaci Meta dne 2026-11-12 (Graph API v27.0):
- publikace na Instagram: <https://developers.facebook.com/documentation/instagram-platform/content-publishing>
- publikace na stránku Facebooku: <https://developers.facebook.com/docs/pages-api/posts>

## Co je podporované

| Síť | Stav | Poznámka |
|-|-|-|
| Facebook – stránka | podporováno | textový příspěvek na stránku, kde má uživatel právo tvořit obsah (`CREATE_CONTENT`) |
| Instagram – profesionální účet | podporováno | vždy s obrázkem (veřejná adresa https, JPEG); účet musí být propojený se stránkou Facebooku |
| Instagram – osobní účet | nelze | rozhraní Meta publikaci na osobní účty neumožňuje |
| TikTok, YouTube | nepodporováno | jen video; vyžadují vlastní schválení aplikace u poskytovatele |
| Meta Ads, Google Ads | nepodporováno | Vexaronet nezná výdaje ani výsledky kampaní |
| LinkedIn | nepodporováno | firemní stránky vyžadují schválený přístup (Community Management API) |

Zatím se **nenačítají statistiky** (dosah, prokliky). Výsledky se dál zadávají ručně v záložce Analýza.
Nahrávání obrázků do Vexaronetu není – pro Instagram se zadává adresa obrázku, který už je veřejně na internetu.

## Jak to funguje

1. Vlastník nebo správce (tarif PRO a vyšší) klikne v **AI Marketing → Integrace** na „Propojit Facebook a Instagram“.
2. `POST /api/social {op:'begin'}` ověří roli, uloží do databáze otisk náhodného stavu a vrátí adresu přihlášení u Meta.
   Stejný stav dostane prohlížeč v cookie (`HttpOnly; Secure; SameSite=Lax`, 10 minut).
3. Uživatel se přihlásí u Meta a sám vybere stránky. Meta ho vrátí na `GET /api/social?code=…&state=…`.
4. Server ověří, že stav sedí s cookie (propojení dokončuje stejný prohlížeč, který ho zahájil), vymění kód za token,
   načte stránky a navázané účty Instagramu a tokeny stránek uloží **zašifrované** (`social_oauth_finish`).
5. Ve schváleném příspěvku (náhled v kalendáři) se objeví „Zveřejnit na propojený účet“. Po potvrzení:
   `social_publish_begin` (tokenem uživatele: role, otisk schválení, účet firmy, jednou na účet) → volání Meta →
   `social_publish_finish` (zápis výsledku a odkazu do evidence příspěvku).

### Požadovaná oprávnění
`pages_show_list`, `pages_read_engagement`, `pages_manage_posts`, `instagram_basic`, `instagram_content_publish`.
Vexaronet je používá jen ke zveřejnění příspěvku. Nečte zprávy, komentáře ani statistiky.

## Bezpečnostní vlastnosti (ověřené testy)

- Token je v databázi jen zašifrovaný (AES-256-GCM); klíč `SOCIAL_TOKEN_KEY` je pouze v prostředí Cloudflare.
  Šifra je vázaná na konkrétní účet. Klient token nikdy nedostane (`social_state` ho nevrací).
- Tabulky `private.social_*` nejsou přístupné rolím `anon` ani `authenticated`; jen přes funkce.
- Publikaci zahajuje jen člověk (vlastník/správce). Servisní role může dokončit pouze publikaci, kterou člověk zahájil;
  schválení obejít nemůže.
- Zveřejní se přesně schválený text. Po úpravě textu je nutné nové schválení.
- Jeden příspěvek jde na jeden účet nejvýš jednou. Dvojklik ani opakování požadavku nic znovu nezveřejní.
- Když síť neodpoví včas, výsledek se označí „nejasný“ a **neopakuje se automaticky**. Uživatel se podívá na síť a potvrdí,
  zda příspěvek vyšel.
- Token se posílá Meta v hlavičce, ne v adrese; k volání se přikládá `appsecret_proof`.
- Odpojení smaže token z databáze okamžitě.

Co testy **neověřují**: skutečné chování Meta (testy používají simulaci). První propojení skutečného účtu je potřeba
vyzkoušet ručně. Toto není bezpečnostní certifikace.

## Co je potřeba k zapnutí (provozovatel)

### 1. Aplikace u Meta (externí účet – dělá vlastník)
1. Na <https://developers.facebook.com/apps> vytvořit aplikaci typu **Business**.
2. Přidat produkt **Facebook Login for Business**; do „Valid OAuth Redirect URIs“ zadat přesně
   `https://vexaronet.com/api/social`.
3. V nastavení aplikace vyplnit adresu zásad ochrany údajů (`https://vexaronet.com/ochrana-udaju/`) a způsob
   smazání údajů uživatele (Meta to vyžaduje).
4. Dokud aplikace neprojde kontrolou Meta (**App Review**) a ověřením firmy (**Business Verification**), funguje jen
   pro lidi s rolí v aplikaci (správce, vývojář, tester). To stačí pro vlastní pilot. Pro ostatní firmy je kontrola
   Meta nutná pro každé z pěti oprávnění výše; její délku ani výsledek nelze zaručit.

### 2. Tajné hodnoty v Cloudflare Pages (Production) – nikdy je neposílat do chatu
| Proměnná | Hodnota |
|-|-|
| `META_APP_ID` | App ID z přehledu aplikace (číslo; není tajné) |
| `META_APP_SECRET` | App Secret (typ **Secret**) |
| `SOCIAL_TOKEN_KEY` | náhodný řetězec aspoň 32 znaků (typ **Secret**), např. výstup `openssl rand -base64 48` |

`SUPABASE_SERVICE_KEY` už nastavený je. Po uložení je nutné nové nasazení (nový commit do `main`).
Změna `SOCIAL_TOKEN_KEY` zneplatní všechna uložená propojení (účty je pak nutné propojit znovu).

### 3. Databáze
Aplikovat `db/migrations/20261116100000_social_ucty.sql` (nezávisí na dosud neaplikovaných migracích
`registrace_limit` a `ai_tym`). Návrat: `…_social_ucty_rollback.sql` – smaže uložené tokeny a evidenci publikací na
sítě; záznam o zveřejnění u příspěvků zůstane.

### 4. První zkouška
Přihlásit se jako vlastník nebo správce firmy, propojit vlastní stránku, schválit krátký příspěvek a zveřejnit ho.
Zkontrolovat ho na síti a případně tam smazat.

## Otevřené body
- **Zásady ochrany údajů:** po zapnutí je potřeba doplnit, že při propojení se údaje (text příspěvku, adresa obrázku)
  předávají společnosti Meta a že se ukládá přístupový token. Text musí schválit provozovatel; zde není doplněn.
- **Zrušení oprávnění u Meta:** odpojení ve Vexaronetu maže token, ale oprávnění aplikace ruší uživatel ve svém účtu
  Facebook (Nastavení → Firemní integrace). Automatické zrušení přes API není implementováno.
- **Smazání zveřejněného příspěvku** z Vexaronetu není; maže se přímo na síti.
- **Plánované zveřejnění** (v určený čas bez kliknutí) není; vyžadovalo by plánovač a samostatné schválení.

## Testy
- `PSQL="runuser -u postgres -- psql" node tests/social_e2e.test.mjs` – 19 kontrol, skutečný endpoint proti skutečné
  PostgreSQL včetně návratu migrace; simulovaná jen Meta.
- `python3 tests/social_ui.py` – rozhraní (Integrace, zveřejnění, nejasný výsledek, odpojení, ukázka).
