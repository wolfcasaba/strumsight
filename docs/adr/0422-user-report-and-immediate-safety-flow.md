# ADR 0422 — Felhasználói report és azonnali safety flow

- **Státusz:** Elfogadva (E09-R26 pre-flight, 2026-08-24)
- **Kör:** E09-R26 — Felhasználói report és azonnali safety flow
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 26 (a 32 kör közül a huszonhatodik)
- **Kontext-ADR-ek:** [0402](0402-block-mute-and-safety-relationships.md)
  (Kör 8 — `safety_relationships_screen.dart`, block/mute idempotency-at-retry
  minta, DELETE-query-param konvenció), [0398](0398-profile-privacy-audience-policy-and-access-control.md)
  (Kör 4 — plain-`String` allowlist-mező konvenció, ADR 0398 §1),
  [0414](0414-notification-inbox-and-push-abstraction.md) (Kör 20 —
  `dedup_key` UNIQUE-per-recipient minta, amit ez a kör a report-táblára
  másol).
- **Sorszám-jegyzet:** a pipeline-prompt E09-R26 sorára előre kiosztott
  `0414` MÁR FOGLALT — ez a Kör 20 (Notification inbox és push abstraction,
  PR #? — `docs/adr/0414-notification-inbox-and-push-abstraction.md`, merge-elve)
  száma. A `tools/round-slots.py reserve-adr --round E09-R26` friss számot
  adott (`0422`).

## Kontextus

**Mért 2026-08-24-én, a pre-flightban (a brief §0.0-ja hordozza a teljes
tényellenőrzést):**

1. `docs/adr/0414-notification-inbox-and-push-abstraction.md` és
   `backend/app/community/models/notification.py` docstringje (`"E09-R20,
   ADR 0414"`) igazolja: 0414 egy MÁR ELFOGADOTT, merge-elt ADR száma —
   újrafelhasználása egy másik kör döntéseire ADR 0087 §2 H1-hez hasonló
   kockázatot nyitna (két divergens szöveg ugyanazon a fájlnéven). A helyes
   szám 0422 (lásd fent).
2. `grep -rn "class.*Category\|Enum" backend/app/community/models/*.py` → 0
   találat. A projektben NINCS előre álló, kategorikus enum-minta a
   moderation/report tartalomra — a legközelebbi analóg
   `backend/app/community/models/reaction.py` `kind` mezője: sima `String`
   oszlop + modul-szintű `frozenset` allowlist + service-rétegbeli
   validáció (ADR 0398 §1 projekt-szintű konvenció). A report `category`
   mezője ugyanezt a mintát követi (D4).
3. `grep -rn "class CommunityPost\|class CommunityComment" -A5 ... deleted`
   → mindkét tartalom-modell `deleted_at` (nullable `DateTime`) soft-delete
   tombstone-t visz (D7 uniform-404 minta), NEM egy `status` enumot. A
   report-tábla "törölt target" kezelésének (A4) erre az ELÉRHETŐ mezőre
   kell épülnie, nem egy nem létező `status="deleted"` értékre (D5).
4. `grep -rn "RateLimiter" backend/app/community/services/challenge_invite_service.py`
   → a Kör 21 mintája **authentikált** endpointon a hívó BELSŐ
   (`inviter_profile_id`) azonosítóján kulcsol, NEM az IP-n. Ezzel szemben
   `handles.py::_client_key` (Kör 3, authentikáció ELŐTTI availability
   endpoint) a socket-peer IP-t használja, dokumentált indoklással: *"E09-R03
   review F1, 60/60 requests bypassed the 30/min limit by rotating the
   [X-Forwarded-For] header"* — az IP/header-alapú kulcs authentikált
   endpointon spoofolható/megkerülhető felület, ha nem a szerver-oldali
   identitásra épül. A report endpoint authentikált (`CurrentUser`), tehát a
   Kör 21 mintáját követi, nem a Kör 3-ét (D6).
5. `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "reporter
   identity never leaks..."` → **L431** (E09-R11): egy megosztott,
   OLVASÁSI láthatóság-helper újrahasználása ÍRÁSI/válasz-szűrési kapuként
   IDOR-t nyitott — a válasz-identitást "a SORBÓL told fel, ne a hívóból".
   **L414** (E09-R03): egy 282/282-zöld suite mellett is élt MAJOR
   biztonsági hiba, amit csak egy a jelentett teszt-készlettől FÜGGETLEN
   mutation-próba fogott meg. Mindkettő közvetlenül a brief §6.1
   valódi-sértés próbáját indokolja (D3) — az A1 cellát nem elég egy
   pozitív teszttel lefedni, a mutation-próba KÖTELEZŐ.
6. `grep -n "\"report\|selfHarm\|self_harm\|crisis" lib/l10n/app_en.arb
   lib/l10n/app_hu.arb` → 0 találat. A brief §5.3 ("CSAK jóváhagyott safety
   copy") egy MA NEM LÉTEZŐ, előre jóváhagyott copy-készletre hivatkozik —
   nincs mit "meglévőből" felhasználni. Az `allowed_paths` emiatt sem
   tartalmazta az ARB fájlokat, holott a CLAUDE.md kötelezi: *"every
   user-facing string goes through ARB → AppLocalizations"* — enélkül az
   implementer vagy hardkódolt szöveget írna (konvenció-sértés), vagy
   STOP-olna egy valódi, a kör saját scope-jából fakadó akadályon (D1/D7).

## Döntés

### D1 — ARB FORRÁS-fragmentum felvétele az `allowed_paths`-ra (szűk, indokolt bővítés)

**Javítva (§0.0b, az implementer STOP jelzése után, 2026-08-24 15:45):** az
eredeti D1 tévesen `lib/l10n/app_{en,hu}.arb`-ot (a szegmentált l10n
architektúra GENERÁLT kimenete, `tool/gen_l10n_segments.dart --write`
állítja elő) vette fel — a helyes, forrás-igazságú útvonal
`lib/l10n/features/community_en.arb` / `community_hu.arb` (a Kör 8 safety-
kulcsok is ide kerültek, `docs/rounds/e09-r08-...` 607. sor). Ez a pár
bekerül az `allowed_paths`-ba (brief §0.0/§0.0b revízió). Indoklás: a report
bottom sheet lokalizált kategória-címkéket és a §5.3 self-harm safety
copy-t visz — az ARB az EGYETLEN szankcionált útvonal felhasználó-néző
szöveghez (CLAUDE.md), és a szegmentált architektúrában a FORRÁS mindig a
`features/*.arb`, sosem az aggregált `app_{en,hu}.arb` (amit a gate saját
`gen_l10n_segments`/`check_l10n_parity` lépése regenerál és őriz — a
regenerálás következtében változó `app_{en,hu}.arb` NEM scope-sértés, még
akkor sem, ha nincs az `allowed_paths`-on, a Kör 8 dokumentált precedense
szerint). A generált `lib/l10n/app_localizations*.dart` gitignore-olt,
szintén nem kerül az `allowed_paths`-ra. Ez ugyanaz a minta, mint az ADR
0402 D5 "szűk kivétel a domain tilos zónán" — a fájl nincs kifejezetten
felsorolva, de a kör explicit szükséglete miatt, dokumentáltan bekerül, és
ettől kezdve NEM esik a H3 (tilos zóna) alá (ADR 0087 §2, a pipeline-prompt
4. szakasza).

### D2 — A reportoló-identitás perzisztencia- és válasz-határa

`community_reports.reporter_profile_id` (FK `community_profiles.id`,
CASCADE) az EGYETLEN hely, ahol a reportoló azonosítója tárolódik. A kör
ebben a fordulóban **egyetlen** publikus válasz-sémát ad
(`ReportOut` — a `POST /community/reports` válasza, KIZÁRÓLAG a
reportolónak, saját maga jelenti be a saját reportját, tehát nincs
identitás-szivárgás abban, hogy ismeri a saját akcióját). A kör NEM épít
target-néző vagy moderation-queue-olvasó felületet (az Kör 27 dolga) — a
brief §6.1 valódi-sértés próbája ezért a service-rétegben él: a
`report_service.py` bármely, Kör 27 által majd újrahasznosítható belső
lekérdezése (pl. a dedup-lookup vagy egy jövőbeli `list_reports_for_target`
csonk) `reporter_profile_id`-t NEM tehet olyan Pydantic sémába vagy
dict-alakba, amit egy target-néző endpoint valaha visszaadhatna. A próba
konkrét formája (§6.1): vedd fel a `reporter_id`-t egy — a service által
ehhez a fordulóhoz készített — moderation-jelzés sémájába, és mérd, hogy az
A1 cella PIROSRA vált.

**NEM elfogadható gyengítés:** egy "átláthatósági" mező bármely, a
target vagy egy jövőbeli moderátor felé szánt válaszban — ADR 0087 §2
H1/H2 nélkül sem vezethető be utólag anélkül, hogy ez az ADR ne
módosulna elébb.

### D3 — A §6.1 valódi-sértés próba KÖTELEZŐ, önmagában nem elég a pozitív teszt

L414 mérése szerint egy teljesen zöld suite mellett is élhet egy MAJOR
biztonsági rés — a brief §6.1 próbáját (add hozzá `reporter_id`-t a
moderation-jelzés sémájához → A1 PIROS → állítsd vissza) az implementer
KÖTELEZŐEN futtatja és a §10 handoffban dokumentálja a pontos
visszaállítási diffet, a review pedig FÜGGETLENÜL, saját kézzel
megismétli (ugyanaz a minta, mint az E09-R03 review saját mutation-próbája,
L414).

### D4 — `category` mező: sima `String` + modul-szintű allowlist (ADR 0398 §1 minta)

Nincs DB-szintű enum/CHECK — a `CommunityReaction.kind` mintáját követi
(`reaction.py`): egy `REPORT_CATEGORY_ALLOWLIST: frozenset[str]` a
`report.py` modellben, a service-réteg validálja. Kezdő kategória-készlet
(a brief nem sorolja fel, ez a kör dönti el, lokalizációs kulcsokkal
1:1 megfeleltetve):

- `spam`
- `harassment_or_bullying`
- `hate_speech`
- `misinformation`
- `self_harm_concern` — kizárólag a §5.3 jóváhagyott copy-val (D7)
- `copyright_or_privacy` — a brief §3 "minimalizált extra metadata mező"-je
  ehhez a kategóriához kötött (`detail` mező, opcionális, max hosszra
  korlátozva)
- `other`

Egy ismeretlen kategória-string a service-rétegben elutasított (A5) —
mintaazonos a `reaction_service.py::InvalidReactionKind`-dal (a hibaosztály
neve az implementer választása, ugyanaz a minta).

### D5 — "Törölt target" kezelése: `deleted_at IS NOT NULL`, a report ELFOGADOTT marad

A2/A4: a report submit NEM 404-el, ha a target `deleted_at` nem NULL — a
reportoló nem feltétlenül tudja, hogy időközben törölték, és a moderation
(Kör 27) számára a történeti rekord (mit jelentettek, mikor) attól még
értékes. A service ellenőrzi a target létezését (a `target_type` szerinti
tábla `public_id` lookupja), de a soft-delete állapot nem blokkoló — a
válasz-sémában NINCS külön "target already removed" jelzés (a brief §3
"kontrolláltan kezelt" megfogalmazása ezt engedi, nem ír elő egyedi
hibakódot). Egy teljesen ISMERETLEN (soha nem létezett) `target_id` viszont
elutasított — ez a kettő közötti határvonalat a `test_report_service.py`
külön cellával fedi (A4 mérce-mátrix).

### D6 — Rate limit: authentikált hívó BELSŐ profil-id-jén kulcsol, NEM IP-n

`RateLimiter` (a meglévő `backend/app/ratelimit.py` primitív) —
`reports.py` router a `challenge_invite_service.py`/`_invite_limiter`
mintáját követi: a kulcs a JWT-ből feloldott hívó BELSŐ
(`reporter_profile_id`) azonosítója, NEM `request.client.host` és NEM egy
kliens-küldött header. Indoklás: a `handles.py::_client_key` IP-alapú
mintája kifejezetten egy AUTHENTIKÁCIÓ ELŐTTI endpointra való (nincs
hívó-identitás); a report endpoint authentikált, tehát a Kör 21
(`challenge_invite_service.py`) analóg, authentikált-endpoint mintáját
kell követnie — az IP-kulcs itt gyengébb védelem lenne (megosztott
NAT/proxy mögötti felhasználók ugyanazt a vödröt osztanák, egy elszánt
visszaélő pedig IP-t válthatna anélkül, hogy az azonosítója változna). A
pontos budget (érték/ablak) az implementer választása — a brief nem ad
numerikus küszöböt, tehát nincs S3-cellahármas kötelezettség.

### D7 — Self-harm safety copy: EBBEN a körben születő, EGYETLEN fix string-pár

Mivel nincs előre jóváhagyott copy-készlet a repóban (Kontextus 6. pont),
ez a kör hozza létre az ELSŐ, kanonikus `self_harm_concern` szöveget — EN +
HU ARB kulcs (pl. `reportSelfHarmSafetyMessage`), NEM kategóriánként vagy
call-site-onként variált szöveg. A tartalom generikus, nem diagnosztikus,
nem ad módszer-részletet, és egy általános krízisvonal-jellegű
útmutatásra szorítkozik (a pontos szöveget az implementer fogalmazza, a
review a §5.3 invariánst — "nincs ad-hoc variáció" — a forráskódban
egyetlen string-referencia meglétével ellenőrzi, nem tartalmi
jogi/szakmai lektorálással, ami e kör keretein kívül esik). Egy jövőbeli
kör lecserélheti erre a kulcsra hivatkozva, jogi/szakmai jóváhagyás
birtokában — ez az ADR nem zárja le a szöveg VÉGLEGESSÉGÉT, csak az
EGYETLEN-forrás szerkezetet.

### D8 — `dedup_key`: az ADR 0414 (Kör 20, notification inbox) mintája, nem új idempotency-key body-mező

A2 ("ugyanazon target/category ismételt submit idempotens") a
`notification.py` A7 dedup-key mintáját másolja (`docs/adr/0414-...`,
`dedup_key` nullable String, `UNIQUE(reporter_profile_id, dedup_key)`), NEM
a block/mute-stílusú kliens-küldött `idempotency_key` body-mezőt. A
`dedup_key` szerver-oldalon számított, determinisztikus érték
(`f"{target_type}:{target_public_id}:{category}"` vagy ezzel ekvivalens),
tehát a kliensnek nem kell semmilyen tokent generálnia/megőriznie — egy
retry (hálózati hiba utáni újraküldés) ugyanarra a target/category párra
automatikusan ugyanazt a `dedup_key`-t számolja, a DB UNIQUE elutasítja a
duplikátumot, a service `IntegrityError`-t elkapva a MEGLÉVŐ sort adja
vissza (a `reaction_service.py`/`block_service.py` idempotency-at-retry
mintája). Nincs "kontrolláltan összevont" (merge) ág — az egyszerűbb,
meglévő precedenssel konzisztens "idempotens no-op" a választott
szemantika.

### `**Kockázat = high, indoklás:**`

A `risk = "high"` besorolás nem egy `high_risk_path_fragments` kulcsszóra
illeszkedő `allowed_paths` elemből fakad (a brief-lint S7 ezt jelezte),
hanem magából a funkcionális tartalomból: a kör egy PII-jellegű,
retaliation-kockázatú azonosítót (reporter identity) kezel, ÉS egy
self-harm safety-copy routingot épít — mindkettő a `security-reviewer`
subagent kötelező bevonását indokolja (AGENTS.md §15 risk=high sor), a
kockázat forrása a DOMAIN (safety/PII), nem egy fájlnév-minta.

## Elutasított alternatívák

- **Kliens-küldött `idempotency_key` body-mező (block/mute mintája).**
  Elvetve (D8): a report submit determinisztikus természetes kulccsal
  (target+category+reporter) rendelkezik — nincs olyan több-lépéses
  tranzakció (mint a block DELETE+UPDATE párja), amihez egy opak kliens-
  token többletvédelmet adna; a szerver-oldali `dedup_key` egyszerűbb és a
  Kör 20 notification precedensével konzisztens.
- **DB-szintű enum a `category`-hoz.** Elvetve (D4): a projekt-szintű
  minta (ADR 0398 §1) a plain-`String` + service-allowlist, ami migráció
  nélkül bővíthető — egy DB enum minden új kategóriához sémaváltozást
  igényelne.
- **A törölt target-re irányuló report elutasítása (404).** Elvetve (D5):
  a moderation történeti értéke (mit jelentettek, mielőtt törölték) nagyobb,
  mint a "tiszta" 404 válasz — és a reportoló időzítés-függő 404-je zavaró
  UX lenne egy biztonsági funkciónál.
- **IP-alapú rate-limit kulcs (a `handles.py` mintája).** Elvetve (D6): az
  endpoint authentikált, a Kör 21 belső-id mintája erősebb védelmet ad
  (lásd Kontextus 4. pont).

## Következmények

- `lib/l10n/app_en.arb` / `app_hu.arb` mostantól a kör `allowed_paths`
  listáján — a brief §0.0 revíziója ezt commitolja a dispatch előtt.
- A `community_reports` tábla `dedup_key` mezője ugyanazt a mintát viszi
  tovább, mint a `community_notifications` (ADR 0414/Kör 20) — egy jövőbeli
  kör, amely új dedup-igényű táblát ad, ezt a párost követheti minta
  gyanánt.
- A self-harm safety copy EGY kulcsra redukált (D7) — egy jövőbeli,
  jogi/szakmai lektorálást hozó kör a string TARTALMÁT cserélheti, a
  SZERKEZETET (egyetlen forrás) nem kell újratárgyalnia.
- A Kör 27 (moderation-queue feldolgozás) brief-jének a D2 belső
  reprezentációra kell épülnie (nem újraírnia a dedup-lookupot), és saját
  válasz-sémáiban ugyanazt az A1-határt kell tartania.

## A visszavonás feltétele

Felülvizsgálandó, ha a Kör 27 azt találja, hogy a D2 belső reprezentáció
nem elég a moderation-queue UI-hoz (pl. súlyozott prioritás vagy
csoportosítás szükséges) — ekkor a Kör 27 brief-je bővítheti a
`report_service.py`-t, az A1 határ változatlanul tartásával. Szintén
felülvizsgálandó, ha egy jogi/szakmai lektorálás a D7 self-harm szöveget
lecseréli — ekkor csak az ARB-érték módosul, ez az ADR nem.
