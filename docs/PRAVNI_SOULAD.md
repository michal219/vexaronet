# Právní soulad a soukromí: audit a opravy

Stav k 10. 11. 2026. Implementace je ve větvi `claude/happy-bell-5266nk` a **není nasazená**. Přehled nasazení je v `docs/NASAZENI_PRAVNI_SOULAD.md`.

**Tento dokument není právní posudek a web tím není „právně certifikovaný“.** Formulace zadání jsem bral jako záměr, ne jako potvrzený výklad.
Místa, která má posoudit právník, jsou označená **⚖ k právnímu posouzení**. Předpisy jsem ověřil z oficiálních zdrojů (EUR-Lex, e-Sbírka, ČOI, ÚOOÚ, MPO) k uvedenému datu.
Kde jsem znění ověřil jen přes neoficiální přepis (zakonyprolidi.cz, kurzy.cz), je to výslovně uvedené.

## Oficiální zdroje

| Předpis | Ustanovení | Zdroj | Ověřeno |
|---|---|---|---|
| Nařízení (EU) 2016/679 (GDPR) | čl. 6, čl. 7 odst. 3 (odvolání stejně snadné jako udělení), čl. 8 (souhlas dítěte, 16 let, členský stát může snížit až na 13) | [EUR-Lex 32016R0679](https://eur-lex.europa.eu/legal-content/CS/TXT/?uri=CELEX:32016R0679) | doslovné znění čl. 7 odst. 3 a čl. 8 |
| Zákon č. 110/2019 Sb., o zpracování osobních údajů | § 7: dítě může udělit souhlas u služeb informační společnosti od 15 let | [e-Sbírka](https://e-sbirka.gov.cz/sb/2019/110), [ÚOOÚ – základní příručka](https://uoou.gov.cz/verejnost/zakladni-prirucka-k-ochrane-udaju) | věková hranice 15 let (ÚOOÚ a text zákona přes přepis) |
| Zákon č. 89/2012 Sb., občanský zákoník | § 30 (zletilost 18 let), § 31 (nezletilý jedná jen v rozsahu přiměřeném věku), § 35 (od 15 let závislá práce) | [e-Sbírka](https://e-sbirka.gov.cz/sb/2012/89) | § 31 přes přepis (kurzy.cz, beck-online), § 30 částečně; **§ 35 neověřen doslovně** |
| Zákon č. 89/2012 Sb. | § 1826a (ve znění zák. č. 374/2022 Sb.): tlačítko „Objednávka zavazující k platbě“, údaje podle § 1820 odst. 1 písm. a), e), o), p) těsně před objednávkou | [e-Sbírka 374/2022](https://e-sbirka.gov.cz/sb/2022/374), [ČOI](https://coi.gov.cz/faq/1-na-co-pamatovat-v-prubehu-objednavky-2/) | doslovné znění |
| Zákon č. 127/2005 Sb., o elektronických komunikacích | § 89 odst. 3: předchozí prokazatelný souhlas s ukládáním a přístupem v zařízení; výjimka pro technicky nezbytné a výslovně vyžádanou službu | [e-Sbírka](https://e-sbirka.gov.cz/sb/2005/127) | doslovné znění (přepis) |
| Zákon č. 480/2004 Sb., o některých službách informační společnosti | § 7: obchodní sdělení e-mailem jen se souhlasem nebo vlastním zákazníkům, označené, s totožností odesílatele a adresou pro odmítnutí v každé zprávě | [e-Sbírka](https://e-sbirka.gov.cz/sb/2004/480) | doslovné znění (přepis) |
| Nařízení (EU) 2022/2065 (DSA) | čl. 3 písm. g) bod iii) a písm. i), čl. 11, 12, 14, 15 odst. 2, 16, 17, 18, 19 | [EUR-Lex 32022R2065](https://eur-lex.europa.eu/legal-content/CS/TXT/?uri=CELEX:32022R2065) | doslovné znění (oficiální text Úř. věst.) |
| Provedení DSA v ČR | návrh zákona o digitální ekonomice (koordinátorem digitálních služeb má být ČTÚ) | [MPO](https://mpo.gov.cz/cz/rozcestnik/pro-media/tiskove-zpravy/bezpecnejsi-on-line-prostredi--vlada-schvalila-navrh-zakona-o-digitalni-ekonomice--290645/) | podle monitoringu je stále ve Sněmovně (poslední změna 14. 10. 2026), DSA platí přímo; **ověřit k datu nasazení** |

---

## 1. Věk při registraci

**Použitelnost.** Je potřeba rozlišit tři různé věci:

- **Souhlas se zpracováním (čl. 8 GDPR, § 7 zák. 110/2019 Sb., 15 let).** Hranice platí jen tam, kde je právním základem souhlas a služba se nabízí přímo dítěti. Provoz účtu a aplikace stojí na plnění smlouvy (čl. 6 odst. 1 písm. b), ne na souhlasu, takže se na registraci nevztahuje. Dopadá na odběr novinek, který je založený na souhlasu, a na volitelnou analytiku a nahrávání.
- **Způsobilost uzavřít placenou smlouvu.** Nezletilý jedná jen v rozsahu přiměřeném svému věku (§ 31 obč. zák.). Placené předplatné podnikatelského softwaru, založení firmy a role vlastníka mezi taková jednání nepatří. Zletilost nastává v 18 letech (§ 30).
- **Podmínky používání.** Pozvaný zaměstnanec používá účet pro práci u zaměstnavatele. Od 15 let s ukončenou povinnou školní docházkou se nezletilý může zavázat k závislé práci (§ 35 obč. zák., neověřeno doslovně).

**Nálezy.** Registrace se na věk vůbec neptala. Odběr novinek byl založený na souhlasu a také bez kontroly věku.

**Opravy** (`build.py`, `authForm` a formulář novinek):

- Registrace firmy a účtu s předplatným vyžaduje potvrzení „je mi 18 let nebo více“.
- Pozvaný zaměstnanec potvrzuje „alespoň 15 let a ukončená povinná školní docházka“.
- Odběr novinek vyžaduje potvrzení „alespoň 15 let“.
- Mladším 15 let službu nenabízíme. Formulář vysvětlí, jak postupovat: osoba ve věku 15–17 let se dostane k účtu přes pozvánku zaměstnavatele.
- **Souhlas rodiče nepotřebujeme,** protože nezletilým nenabízíme nic, k čemu by byl nutný. Zaškrtnutí dítětem tedy nikde nenahrazuje souhlas rodiče.
- **Minimalizace:** ukládá se jen kategorie (`age_group: '18+' | '15+'`) a čas potvrzení v metadatech účtu. Žádné datum narození ani doklad.
- Úprava obchodních podmínek (bod 3a) a zásad ochrany osobních údajů.

**Ověření.** `tests/legal_ui.py` kontroluje, že:
- bez potvrzení věku se účet nezaloží a zobrazí se vysvětlení;
- u pozvaného účtu je hranice 15+;
- do `signUp` jde jen kategorie, bez data narození;
- u novinek se bez potvrzení 15+ nic neodešle.

**Omezení.** Jde o prohlášení uživatele, ne ověření (žádné doklady, na přání zadání). Kontrola probíhá v prohlížeči a v metadatech. Databáze ji nevynucuje: registraci zajišťuje Supabase Auth a funkce druhé aplikace, jejichž změna by ovlivnila i ji.
Stávající účty kategorii nemají.

**⚖ k právnímu posouzení:**
- zda je v pořádku, aby osoba 15–17 let bez souhlasu zákonného zástupce přijala podmínky pro bezplatný pozvaný účet;
- zda má mít odběr novinek hranici 15 let (podle čl. 8), nebo 18 let (B2B obsah).

## 2. Fonty

**Použitelnost.** Žádný předpis přímo nezakazuje Google Fonts. Načtení z cizího serveru ale předá IP adresu návštěvníka třetí straně (Google) bez právního základu a bez informace (čl. 5 a 6 GDPR, případně předání do třetí země). Riziko je známé ze soudní praxe v EU. Lokální hostování ho odstraní.

**Nálezy.** Při načtení webu šly požadavky na `fonts.googleapis.com`, `fonts.gstatic.com` (Manrope, Sora) a `cdn.jsdelivr.net` (knihovna supabase-js).

**Opravy:**
- Fonty Manrope a Sora jsou v `assets/fonts/` jako variabilní woff2 (latin a latin-ext) z npm balíčků `@fontsource-variable/manrope` a `@fontsource-variable/sora` 5.3.0.
- **Licence: SIL Open Font License 1.1**, texty jsou přiložené (`assets/fonts/OFL-*.txt`). OFL dovoluje redistribuci a vkládání do webu.
- Knihovna supabase-js 2.45.4 je hostovaná v `assets/vendor/` (licence MIT) se stejným kontrolním součtem SRI. Ověřil jsem dřív, že je bajtově shodná s npm.
- CSP v `_headers` už nepovoluje Google Fonts ani jsDelivr.

**Ověření.** `tests/legal_ui.py` zachytí **všechny** síťové požadavky při načtení. Na cizí server nejde žádný, fonty a knihovna přicházejí z vlastního serveru a nadpis se skutečně vykreslí lokální Sorou.

## 3. Cookies, analytika a nahrávání relací

**Použitelnost.** § 89 odst. 3 zák. 127/2005 Sb. vyžaduje předchozí souhlas pro vše, co není technicky nezbytné nebo výslovně vyžádané. Čl. 7 odst. 3 GDPR říká, že odvolání musí být stejně snadné jako udělení.

**Nálezy:**
- Web **nemá žádnou analytiku ani nahrávání relací** (ověřeno prohledáním kódu a síťového provozu).
- Úložiště prohlížeče používá jen pro nezbytné věci (přihlášení, režim zobrazení, historie chatu v kartě). Na ty se souhlas nevyžaduje.
- Chyběl ale mechanismus, který by případné nepovinné služby bezpečně spouštěl až po souhlasu.

**Opravy** (`src/consent.js`):
- **Správa souhlasu:**
  - lišta s rovnocennými tlačítky „Odmítnout vše“ a „Přijmout vše“ na první úrovni;
  - „Nastavení soukromí“ v patičce pro pozdější změnu nebo odvolání;
  - po odvolání se sběr hned zastaví a neodeslaná data se zahodí.
- **Bez souhlasu se nic nenačte:** skript nahrávání se ani nestáhne.
- **Volitelná analytika:** jen cesta stránky bez parametrů, šířka okna a doména odkazu. Bez cookies a bez identifikátoru.
- **Volitelné nahrávání relací** (rrweb 2.2.1, MIT, hostované lokálně se SRI) je maskované ve dvou vrstvách:
  - **nastavení rrweb:** všechny vstupy maskované (i hesla, e-maily a telefony), všechny texty nahrazené hvězdičkami a události vstupů ignorované;
  - **blokované celé části:** přihlášená aplikace (`#vxapp`), všechny dialogy a formuláře, AI chat, odkazy `mailto:` a `tel:`, iframe, video a canvas;
  - **vlastní čištění před odesláním:** adresy bez parametrů a fragmentu a textové atributy (`alt`, `aria-label`, `title`, `content`, `data-*`, `value`) nahrazené hvězdičkami. Důvod: rrweb sám převádí relativní odkazy na plné adresy s parametry stránky a atributy nemaskuje. Na to přišel síťový test.
- **V produkci je vše vypnuté** (`OPTIONAL_CFG` bez cílového endpointu). Lišta se proto nezobrazí a nastavení soukromí uvádí, že nic nepovinného se nepoužívá.
- Zapnutí je rozhodnutí provozovatele: cíl pro data, doba uchování, aktualizace zásad a informace o cookies.
- Texty informace o cookies jsou aktualizované.

**Ověření (skutečné síťové požadavky).** `tests/legal_ui.py` běží s testovacím cílem na stejném serveru a zachytává těla požadavků:
- **před souhlasem** 0 požadavků a skript nahrávání se nestáhl;
- **po odmítnutí** 0 požadavků za 5 s aktivity (psaní, posouvání), totéž po obnovení stránky;
- tlačítka „Odmítnout“ a „Přijmout“ mají stejnou velikost i barvu;
- **po souhlasu** analytika pošle jen `/` bez parametrů a nahrávání skutečně odesílá (snímek stránky a průběžné události, přes 240 kB);
- **v odeslaných datech chybí** zadaný e-mail, jméno, název firmy, heslo a zpráva chatu, texty stránky, alt a aria-label i parametry adresy;
- **po odvolání** 0 nových požadavků za 6 s aktivity a odvolání je uložené.

**⚖ / rozhodnutí:** zda nepovinné služby vůbec zapínat. Pokud ano: cíl a zpracovatel, doba uchování, posouzení dopadu (u nahrávání relací doporučuji DPIA) a doplnění zásad.

## 4. Marketingové e-maily

**Použitelnost.** § 7 zák. 480/2004 Sb. stanoví podmínky pro obchodní sdělení e-mailem:
- souhlas, nebo výjimka pro vlastní zákazníky a obdobné produkty;
- zřetelné označení jako obchodní sdělení;
- uvedená totožnost odesílatele;
- platná adresa pro odmítnutí v každé zprávě.

Odvolání souhlasu musí být snadné (čl. 7 odst. 3 GDPR).

**Rozlišení zpráv:**

| Zpráva | Typ | Kde |
|---|---|---|
| Novinky Vexaronet (`newsletter_subscribers`) | **marketing** (souhlas) | tento repozitář |
| Potvrzení registrace, obnova hesla, pozvánka do týmu, potvrzení rezervace, ranní přehled | transakční nebo služební | Supabase Auth, `/api/invite`, `/api/book`, `/api/digest` |
| Kampaně firem jejich zákazníkům (`suite_campaigns`), péče o zákazníky (recenze a návrat) | marketing firem (souhlas) | druhá aplikace nad stejnou DB (edge funkce mimo repozitář) |
| Připomínka rezervace (`customer_care_mail`, `reminder`) | transakční | druhá aplikace |

**Nálezy:**
- Pro Novinky Vexaronet existovalo jen přihlášení. Neexistovalo **žádné odhlášení** ani řízené odesílání.
- Text formuláře přitom sliboval „odhlásit se můžete kdykoli“.
- U toků druhé aplikace jsem **jen čtením** ověřil, že souhlas a odvolání kontrolují až v okamžiku odeslání (`care_mail_allowed`, `suite_mail` s podmínkou `withdrawn_at is null`) a že odkaz na odvolání nese neprůhledný token, ne e-mail. Tam jsem problém nenašel.

**Opravy** (migrace `20261110100000_marketing_odhlaseni.sql`, `functions/api/unsubscribe.js`, `functions/api/newsletter.js`, stránka `/odhlasit/`):
- **Token:** náhodný, cca 244 bitů, jeden na zprávu a příjemce. V DB je jen jeho SHA-256 a v URL ani v odpovědi není e-mail ani ID.
- **Odhlášení bez přihlášení:**
  - stránka `/odhlasit/?t=…` s tlačítkem, token hned zmizí z adresního řádku;
  - odhlášení jedním klikem z pošty podle RFC 8058 (`List-Unsubscribe` a `List-Unsubscribe-Post`);
  - požadavek GET nic nemění, takže ho nespustí náhledy odkazů v poště.
- **Vynucení při každém odeslání** (v DB, ne v prohlížeči):
  1. výběr dávky jen ze souhlasů, které nejsou na seznamu odhlášených;
  2. kontrola těsně před každou zprávou (`marketing_send_allowed`);
  3. zápis výsledku.

  Naplánované zprávy se kontrolují až v okamžiku odeslání, ne při naplánování. Odhlášení platí pro adresu (bez ohledu na velikost písmen), takže ho neobejde ani nová přihláška.
- **Každá zpráva obsahuje:** označení „Obchodní sdělení“, totožnost odesílatele, kontakt, důvod zasílání a odkaz na odhlášení. **Bez `OPERATOR_NAME` a `OPERATOR_ADDRESS` se nic neodešle** (údaje nevymýšlím).
- **Naplánovat** zprávu smí jen správce platformy. Odesílá plánovač se sdíleným tajemstvím.
- Zásady ochrany osobních údajů jsou doplněné o odhlášení a evidenci odhlášených.

**Ověření (skutečné odhlášení):**
- `tests/db/run_legal_local.sh` má 43 kontrol pod rolemi anon, authenticated a service_role.
- `tests/legal_e2e.test.mjs` pouští **skutečné endpointy proti skutečné PostgreSQL**:
  - zpráva jde jen adresátům se souhlasem a je správně označená;
  - GET odkazu nic nezmění, POST jedním klikem odhlásí;
  - **dříve naplánovaná zpráva** odhlášené adrese nepřijde;
  - nová přihláška stejné adresy odhlášení neobejde;
  - bez údajů odesílatele se nic neodešle.
- `tests/legal_ui.py` ověřuje stránku `/odhlasit/`.

**⚖ / rozhodnutí:**
- údaje odesílatele (jméno nebo firma a adresa);
- zda odesílat jen se souhlasem (doporučeno), nebo i stávajícím zákazníkům podle § 7 odst. 3;
- evidence znění souhlasu: `newsletter_subscribers` ukládá jen `consent=true` bez verze textu. Doporučuji doplnit verzi a znění.

## 5. Placené objednávky

**Komu a co prodáváme.**
- **Předplatné Vexaronetu** se prodává podnikatelům a firmám (B2B). Platby **nejsou spuštěné**. Placený tarif je dnes **žádost** (`plan_requests`) a tarif nastavuje ručně provozovatel. Registrace s placeným tarifem znamená 30 dní zkušební doby bez karty, pak účet automaticky přejde na START zdarma, nic se neúčtuje.
- **E-shopy firem** (`?s=slug`) prodávají spotřebitelům. Prodávajícím je firma, Vexaronet poskytuje technickou službu. Tlačítko odeslání objednávky zakládá povinnost zaplatit převodem.

**Použitelnost § 1826a obč. zák.** Ustanovení platí pro **spotřebitele**. Na B2B předplatné se přímo nevztahuje (OSVČ jednající při podnikání není spotřebitel), dnes navíc vůbec nevzniká povinnost platit. Na **e-shopy firem** se vztahuje: povinnost má podnikatel-prodávající a naše šablona ji musí umožnit.

**Nálezy:**
- E-shop měl tlačítko „Odeslat objednávku: X Kč (platba převodem)“. Nevyhovuje výslovnému požadavku § 1826a odst. 2.
- Dále vyžadoval zaškrtnutí „Souhlasím s předáním údajů prodejci“. Zpracování nutné k vyřízení objednávky je plněním smlouvy, ne souhlasem, a nepravý souhlas je zavádějící.
- Žádost o tarif měla tlačítko „Pokračovat“ bez období, obnovování a ukončení.

**Opravy:**
- **E-shop:** tlačítko **„Objednávka zavazující k platbě“**. Těsně nad ním je zboží, doprava, celkem k úhradě, prodejce, kontakt a věta, že se zavazujete zaplatit. „Souhlas“ jsem nahradil informací o plnění smlouvy. Jde o jednorázovou koupi, takže doba trvání a obnovování se nevztahují.
- **Žádost o tarif:** tlačítko **„Odeslat nezávaznou žádost“** (u START „Přejít na START (zdarma)“). U každého tarifu je vidět cena bez DPH, měsíční období a 30 dní zdarma. Výslovně tam stojí, že se nic neúčtuje ani automaticky neobnovuje, že před zahájením účtování pošleme podmínky k výslovnému potvrzení a že tarif lze kdykoli ukončit přechodem na START.

**Ověření.** `tests/legal_ui.py` prochází skutečný průchod košíkem až k poslednímu tlačítku (text tlačítka, souhrn ceny a prodejce, žádné povinné „souhlas“ políčko) i dialog tarifu (text tlačítka, cena, období, obnovování, ukončení).

**⚖ k právnímu posouzení:**
- Až se spustí platby předplatného, zavést skutečný objednávkový krok s „Objednávka zavazující k platbě“ a údaji podle § 1820/1826a. Rozhodnout, zda se služba nabízí i spotřebitelům.
- Povinnosti prodávajících na e-shopech: poučení o odstoupení, údaje podle § 1820. Od 19. 6. 2026 také funkce pro odstoupení podle směrnice (EU) 2023/2673 (*v této práci neověřeno*).

## 6. DSA (nařízení o digitálních službách)

**Použitelnost:**
- Vexaronet ukládá a na žádost firem veřejně zpřístupňuje jejich obsah: weby (`?w=`), e-shopy (`?s=`), rezervační stránky (`?r=`) a veřejné profily. To je **hostingová služba** (čl. 3 písm. g) bod iii). Platí čl. 11, 12, 14, 16, 17 a 18.
- Zda jde zároveň o **online platformu** (čl. 3 písm. i, veřejné šíření na žádost příjemce) **⚖ k právnímu posouzení.** Pro mikro a malé podniky ale oddíl 3 (online platformy) neplatí (čl. 19 odst. 1) a zprávy o transparentnosti také ne (čl. 15 odst. 2).
- Interní data firem (CRM, faktury), která se nezveřejňují, jsou ukládání, ale ne veřejné šíření.

**Nálezy:** neexistovala kontaktní místa ani mechanismus oznamování. Podmínky neobsahovaly informace o moderování obsahu (čl. 14).

**Opravy:**
- **Kontaktní místa** (čl. 11 a 12): stránka `/dsa/`. Jako kontakt jsem použil **již zveřejněnou** adresu info@vexaronet.com, jazyky čeština a angličtina. Uvádím, že odpovídá člověk. Identifikace provozovatele zůstává „zatím nedoplněna“ (nevymýšlím ji).
- **Formulář** `/nahlasit/` (čl. 16 odst. 1 a 2) obsahuje:
  - přesné URL (až 10);
  - upřesnění místa na stránce;
  - druh nezákonnosti;
  - podložené vysvětlení (nejméně 30 znaků);
  - jméno a e-mail;
  - prohlášení o dobré víře.

  U obsahu sexuálního zneužívání dětí jsou jméno a e-mail nepovinné (čl. 16 odst. 2 písm. c). Odkaz „Nahlásit obsah“ s předvyplněnou adresou je na každém zveřejněném webu, obchodě i rezervační stránce a v patičce.
- **Zpracování** (`/api/dsa-notice` a migrace `20261110110000_dsa_oznameni.sql`):
  - povinné údaje kontroluje server i databáze;
  - referenční číslo;
  - **potvrzení přijetí e-mailem** (čl. 16 odst. 4);
  - otisk IP jen proti zahlcení (10 oznámení za hodinu na adresu, 500 za den);
  - data jsou přístupná jen přes serverovou funkci a správci platformy.
- **Evidence:** `private.dsa_events` zaznamenává přijetí, potvrzení, posouzení, rozhodnutí a vyrozumění.
  - **Technická ochrana:** trigger odmítne každý `UPDATE` a `DELETE` řádků, a to i od vlastníka tabulky. Oznámení (`dsa_notices`) nejde smazat, dokud na ně odkazuje evidence.
  - Nejde o absolutní nesmazatelnost: správce databáze může trigger vypnout. Je to ochrana proti nechtěné nebo tiché změně, ne retenční pravidlo.
  - **Doba uchování není stanovená.** Nemám ověřeno, že by nějaký předpis vyžadoval uchovávat oznámení trvale nebo po konkrétní dobu, a proto to netvrdím.
  - Lhůtu musí určit provozovatel (ideálně s právníkem) s ohledem na GDPR (omezení uložení), na možné spory a dozor a na povinnosti podle DSA, které na provozovatele skutečně dopadají (bod 3 níže).
  - Postup výmazu po uplynutí lhůty je potřeba doplnit, až bude lhůta rozhodnutá (viz bod 9).
- **Rozhodnutí** (čl. 16 odst. 5 a 6, čl. 17):
  - přijímá ho člověk, správce platformy (`private.platform_admins`), v Nastavení aplikace nebo přes `/api/dsa-admin`;
  - povinné odůvodnění a právní nebo smluvní důvod;
  - rozhodnutí nejde přepsat;
  - oznamovatel dostane vyrozumění s možnostmi nápravy;
  - firma, jejíhož obsahu se omezení týká, dostane **odůvodnění podle čl. 17 odst. 3**: co, na základě čeho, proč, bez automatizace a jaké má možnosti nápravy.
- **Nic se neodstraňuje automaticky.** Ani oznámení, ani zápis rozhodnutí obsah nemění. Omezení provede správce ručně.
- **Obchodní podmínky, bod 9** (čl. 14): co je zakázáno, jak nahlásit, jak rozhodujeme (člověk, bez automatického moderování), odůvodnění a náprava. Trestné činy ohrožující život oznamujeme policii (čl. 18).

**Ověření:**
- **Databáze:** `tests/db/run_legal_local.sh` kontroluje povinné údaje, anonymní oznámení zneužívání dětí, URL, ochranu proti zahlcení, přístup jen pro správce, povinné odůvodnění, nepřepsatelnost, neměnnou evidenci a to, že se nic neodstraní automaticky.
- **End-to-end:** `tests/legal_e2e.test.mjs` ověřuje skutečné endpointy proti skutečné DB: potvrzení přijetí, odmítnutí neúplných oznámení, 429 při zahlcení, odepření běžnému uživateli a obě vyrozumění po rozhodnutí s úplnou evidencí.
- **Prohlížeč:** `tests/legal_ui.py` ověřuje předvyplnění, kontrolu povinných polí, zobrazení referenčního čísla a odkaz na veřejném obchodě.

**⚖ / rozhodnutí:**
- potvrdit info@vexaronet.com jako jednotné kontaktní místo pro orgány i uživatele, případně určit jinou adresu;
- doplnit identifikaci provozovatele;
- potvrdit status mikro nebo malého podniku;
- posoudit, zda jde o online platformu;
- postup podle čl. 18 (kdo a jak kontaktuje Policii ČR);
- určit, kdo bude správcem platformy (záznam v `private.platform_admins`).

---

## Co zůstává (souhrn rozhodnutí)

| # | Rozhodnutí nebo informace od provozovatele | Blokuje |
|---|---|---|
| 1 | **Identifikace provozovatele** (jméno nebo firma, IČO, adresa): do obchodních podmínek, zásad, `/dsa/` a do `OPERATOR_NAME` a `OPERATOR_ADDRESS` | odesílání novinek, úplnost DSA stránky |
| 2 | Potvrdit **info@vexaronet.com** jako kontaktní místo DSA (nebo jinou adresu `DSA_CONTACT_EMAIL`) a jazyky | – |
| 3 | Status mikro nebo malého podniku, posouzení „online platformy“ | rozsah povinností DSA |
| 4 | Věková pravidla (18+ vlastník, 15+ pozvaný zaměstnanec, 15+ novinky) | ⚖ |
| 5 | Zapnout nepovinnou analytiku nebo nahrávání? (dnes vypnuto) | – |
| 6 | Platby předplatného: objednávkový krok podle § 1826a a podmínky obnovování a ukončení | před spuštěním plateb |
| 7 | Evidence znění souhlasu u novinek (verze textu) | doporučeno |
| 8 | Kód edge funkcí druhé aplikace (mimo repozitář) jsem posoudil jen podle databázových funkcí | – |
| 9 | **Doba uchování oznámení DSA a jejich evidence** a postup výmazu po jejím uplynutí. Zákonná povinnost trvalého uchování ověřená není. Doplnit i do zásad ochrany osobních údajů | úplnost zásad, GDPR |
