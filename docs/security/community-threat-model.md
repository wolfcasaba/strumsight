# StrumSight — Epic 9 (Community) threat model

- **Chapter:** 10 — Epic 9 (Community Platform), Kör 1 (E09-R01)
- **Dátum:** 2026-08-22
- **Szerző:** Claude Sonnet 5 (orchestrátor pre-flight), implementer MiniMax M3 (dokumentum-test)
- **Státusz:** **mérő** — a nyolc kategória mindegyike a Kör-2+ implementáció
  kötelező biztonsági referenciája
- **Forrás:** `docs/rounds/e09-r01-community-baseline-and-feature-flags.md`
  §5 + §8, ADR 0395; kapcsolódik: ADR 0220 (Epic 6 audio-analysis-v2
  kill switch), ADR 0247 (ön-törlő share tempfile)
- **Hatály:** a teljes 32 körös Epic 9 (post, komment, follow, club, async
  challenge, leaderboard) — NEM terjed ki az ADR 0395 §5.1 által kizárt
  magas kockázatú felületekre (live audio jam, video chat, privát chat,
  typing indicator, állandó online presence)

> A brief §5.1 rögzíti: az első verzió **aszinkron, poszt/komment/follow
> alapú**; az élő, privát és típus-indikátoros felületek külön threat
> modelt igényelnek, és nem kerülnek be az Epic 9-be. Ez a dokumentum
> kizárólag az aszinkron felületeket tárgyalja.

## 0. Összegzés

| Kategória | Elsődleges fenyegetés | Elsődleges védelem | Feature-flag gate |
|---|---|---|---|
| 1. Identity | fiók-átvétel, e-mail spoofing | UUID publikus ID, FastAPI JWT, opcionális account layer | `accountEnabled` (meglévő) |
| 2. IDOR | jogosulatlan olvasás/írás más user artifact-ján | minden endpoint authorizáció + ownership ellenőrzés, server-enforced | `communityWritesEnabled` |
| 3. Audience bypass | privát poszt nyilvánossá válik | `visibility` enum + szerver-oldali audience-resolver, kliens-cache soha | `communityWritesEnabled` |
| 4. Block bypass | blokkolt user tartalom-blokkolás kijátszása | blokk-szerver-oldali szűrés a feed-összeállításban, kliens-oldali szűrés NEM elég | `communityWritesEnabled` |
| 5. Spam | tömeges poszt/követés, flooding | rate-limit (bejelentkezett userenkénti token-bucket + IP kiegészítés), challenge captcha | `communityWritesEnabled` |
| 6. Media upload | rosszindulatú kép (exif GPS, polyglot JPEG), DoS nagy fájllal | MIME + magic-byte validáció, szerver-oldali átkódolás, méretkorlát, exif törlés | `communityMediaEnabled` |
| 7. Challenge replay | challenge replay-támadás (azonos audio újrajátszása) | session-bound nonce + szerver-oldali feature-hash összehasonlítás, time-bound token | `communityEnabled` |
| 8. Moderation abuse | report-spam, önkényes takarítás | report-rate-limit, moderator audit-log, takarítás csak belső queue-ból | `communityWritesEnabled` |

A nyolc kategória MIND megtalálható ebben a dokumentumban, KIVÉTEL
NÉLKÜL — ez a §6.1 mérce-mátrix A3 sorának fedője (review: a threat
model kihagyja a media upload vagy a challenge replay kockázatot → A3
piros).

## 1. Identity

### 1.1 Fenyegetések

- **A1.1.1 — fiók-átvétel jelszó-visszaállítással.** A regisztráció
  e-mail+password, és a fiókhoz tartozó poszt/follow/club azonosító
  UUID. Ha a jelszó-visszaállítási flow nem rate-limited vagy a
  visszaállító token nem kellően entrópiás, egy támadó átveheti a
  fiókot, és azon keresztül moderálhatatlan tartalmat posztolhat.
- **A1.1.2 — e-mail spoofing a regisztrációban.** Az opcionális account
  layer (`accountEnabled`) biztosítja a bejelentkezést, de a fastAPI
  service semmit nem tud a felhasználó e-mailjének valódiságáról; ha
  egy támadóé a MailHog/MailPit tévesen levelet elfogad, az
  account-azonosító duplikálódhat.
- **A1.1.3 — UUID vs belső bigint.** A belső `users.id` bigint ÉS az
  e-mail cím soha nem hagyhatja el a szervert válaszban — kizárólag az
  UUID publikus ID.

### 1.2 Védelmi intézkedések

- **A1.2.1 — UUID-only public ID.** A `users_public_id` mező egy külön
  UUIDv4 oszlop, sosem a belső bigint. A response shape-ekhez csak ez
  az oszlop csatlakozik. A bevezető ADR 0395 §5.2 ezt szavatolja.
- **A1.2.2 — FastAPI + JWT.** `HS256` 14 napos lejárattal (meglévő
  `Settings`); a JWT subject mezője a publikus UUID, sosem az e-mail.
  A `lib/core/api/api_config.dart` `Authorization` headert kezel, a
  token a `flutter_secure_storage`-ban (ADR 0052 mért igazság —
  pinned v10).
- **A1.2.3 — jelszó-visszaállítás csak későbbi körben.** A E09-R01 NEM
 ír jelszó-visszaállítást; ha ez később jön, akkor rate-limit
  (5/óra/IP), 24 órás lejárat a reset tokenen, és egyszer-használatos
  token. A E09-R01 csak a feature-flaget és a baseline-t rögzíti.
- **A1.2.4 — e-mail-ellenőrzés MA nincs.** A jelenlegi account layer
  a `register_limiter`-t használja (conftest.py fixture); a teljes
  e-mail-ellenőrzés a E09-R10+ körök dolga. A threat model ezt
  **kifejezetten rögzíti**, hogy későbbi review-k ne higgyék
  késznek.

### 1.3 Kapcsolódó feature-flag

- `accountEnabled` (meglévő) — az account layer teljes kikapcsolása,
  így a Community IDENTITÁS-alapú védelme is áll, de maga a bejelent-
  kezés is letiltott; a Community CI build így a meglévő account
  rétegre hagyatkozik.
- `communityEnabled` — a teljes Community felület KI az Epic 9
  utolsó köréig (production default).

## 2. IDOR (Insecure Direct Object Reference)

### 2.1 Fenyegetések

- **A2.1.1 — poszt olvasása ID-jával.** `/posts/{id}` endpoint — ha
  a szerver nem ellenőrzi, hogy a poszt `visibility == public` VAGY a
  poszt szerzője a hívó, akkor privát poszt is kikerül.
- **A2.1.2 — poszt szerkesztése/törlése ID-jával.** `/posts/{id}/edit`
  és `/posts/{id}/delete` — IDOR itt azonnali account takeover-hez
  vezet, mert a támadó bármely user bármely posztját törölheti.
- **A2.1.3 — moderáló akció kikerülése.** Ha egy `mod_action`
  endpoint nem kéri le a hívó role-ját a JWT-ből, akkor bármely
  bejelentkezett user moderálhat.

### 2.2 Védelmi intézkedések

- **A2.2.1 — minden író endpoint kötelezően ellenőrzi az ownership-et.**
  A `Depends(get_current_user_uuid)` dependency a route handler-en,
  és a service rétegben ismételt ellenőrzés (defence in depth).
- **A2.2.2 — kliensoldali `if (post.authorId == me)` NEM elég.**
  Kizárólag a szerver dönt. A kliens csupán UI affordance.
- **A2.2.3 — a role-claim a JWT-ben.** A szerver a tokenből veszi a
  role-t; a kliens `role` mezője kizárólag UI-elrejtésre szolgál,
  soha nem authority.
- **A2.2.4 — UUID a path-ban, bigint soha.** Az IDOR veszélye a
  kiszámítható bigint ID-val a legnagyobb (1, 2, 3, … sorolgatás);
  a UUID124 bit entrópiája brute-force ellen véd.

### 2.3 Kapcsolódó feature-flag

- `communityEnabled` — minden IDOR-veszélyes endpoint a flag mögött.
- `communityWritesEnabled` — az írás (szerkesztés/törlés) külön
  kapu, így olvasás research-üzemmódban lehetséges, írás kikapcsolva.

## 3. Audience bypass

### 3.1 Fenyegetések

- **A3.1.1 — privát poszt `visibility: public` címkével.** A kliens
  küldi a `visibility` mezőt, de ha a szerver nem normalizálja a
  felhasználó valódi klub-tagságához / block-listájához, akkor egy
  privát poszt `public` jelöléssel kikerül.
- **A3.1.2 — csak-klub poszt kikerül a klub feedjén kívülre.** A
  club-only posztot kizárólag a klub tagjai láthatják; ha a feed-
  resolver nem szűr, a poszt kikerül a globális feedbe.
- **A3.1.3 — `friends-only` poszt nyilvános listában.** A barát-
  körön kívüli user láthatja, ha a resolver a kliensre bízza.

### 3.2 Védelmi intézkedések

- **A3.2.1 — `visibility` enum a szerver validálja.** A lehetséges
  értékek halmaza zárt: `public`, `friends`, `club`, `private`.
  A szerver a `private`-ot és a `club`-ot kliens-bypass ellen is
  védi (a kliens nem tud `public`-ra upgrade-olni).
- **A3.2.2 — feed-resolver szerver-oldali.** A `get_feed(user,
  scope)` endpoint kiszolgáláskor ellenőrzi a hívó minden poszt
  authorjával fennálló kapcsolatát (club tagság, follow status,
  block státusz). A kliens kizárólag a saját feedjét rendereli.
- **A3.2.3 — kliens-cache NEM authority.** A `KeyValueStore`-ban
  cache-elt poszt-lista kizárólag UI-hint, soha nem ellenőrzés.
- **A3.2.4 — audit log a `visibility` változásra.** Ha egy poszt
  `private`-ból `public`-ba kerül, a szerver ezt az esemény-
  naplóba írja a review-zhatóság kedvéért.

### 3.3 Kapcsolódó feature-flag

- `communityClubsEnabled` — a club-scope-ú posztok KIZÁRÓLAG ezen
  flag mellett léteznek; klub nélkül nincs ilyen láthatóság.
- `communityWritesEnabled` — a `visibility` módosítás és a feed
  összeállítás a writes-flag alatt áll.

## 4. Block bypass

### 4.1 Fenyegetések

- **A4.1.1 — blokkolt user új accounttal.** A leggyakoribb bypass:
  a támadó új accountot regisztrál, és arról ír a célszemélynek.
  A blokk-user-listája NEM terjed ki az új accountra, hacsak a
  rendszer nem azonosítja a user-t eszköz/IP ujjlenyomat alapján
  — de ez privacy-kockázatot hoz.
- **A4.1.2 — blokk-szűrés kliens-oldalra bízva.** Ha a feed a
  kliensen szűri a blokk-user posztjait, a támadó közvetlen API
  hívásból kiolvashatja azokat.
- **A4.1.3 — komment-válasz lánc.** A támadó kommentál egy nyilvános
  posztot, amire a célszemély kommentel — a célszemély értesítést
  kap, holott blokkolva van a támadó.

### 4.2 Védelmi intézkedések

- **A4.2.1 — szerver-oldali feed-szűrés.** A feed-resolver a blokk-
  listát szerver-oldalon alkalmazza, és a blokkolt felek posztjait
  NEM szolgáltatja ki (még közvetlen ID-lookup esetén sem, ha a
  poszt nem `public+not-blocked-viewer`).
- **A4.2.2 — komment-értesítés szűrése.** Ha A blokkolta B-t, és B
  kommentel A posztjához, A nem kap értesítést.
- **A4.2.3 — fingerprint-alapú azonosítás NEM bevezetve.** Az
  új-account bypass-t a jelenlegi account layer NEM kezeli; ez
  a feature-flag alapú védelem korlátja, és a threat model
  kifejezetten nyilván tartja. Ha a későbbi körök eszköz-
  ujjlenyomatot vezetnek be, azt külön ADR-vel kell fedni.
- **A4.2.4 — user oldaláról reverse-engineering.** A blokkolt user
  profil-oldala csak a saját feedjén jelenik meg, másokéban nem —
  ez a felfedezhetőséget csökkenti.

### 4.3 Kapcsolódó feature-flag

- `communityEnabled` — teljes Community KI; a blokk-szűrés MA
  feltételesen nem releváns, de a terv a későbbi körök számára
  rögzített.
- A flag-ek `communityWritesEnabled` és `communityClubsEnabled`
  bekapcsolásakor a blokk-szűrés szerver-oldali implementációja a
  Kör 2+ kötelező része.

## 5. Spam

### 5.1 Fenyegetések

- **A5.1.1 — tömeges poszt.** Szkript 100 posztot küld másodpercen-
  ként — a feedet elárasztja, a moderálás lehetetlenné válik.
- **A5.1.2 — tömeges follow.** Egy user 10000 másikat követ egy
  perc alatt — a notification rendszer túlterhelődik.
- **A5.1.3 — komment-spam.** Egy posztra 500 komment egymás után —
  a célszemély értesítési listája tele.
- **A5.1.4 — challenge-spam.** Aszinkron challenge-ek tömeges
  küldése — a címzett storage kvóta megtelik.

### 5.2 Védelmi intézkedések

- **A5.2.1 — rate-limit token-bucket, userenként.** A meglévő
  `register_limiter` / `login_limiter` mintájára; a POST endpointok
  saját limitert kapnak. A limit értéke feature-flag-elhető a
  Kör 8-ban a valós forgalmi adatok alapján.
- **A5.2.2 — challenge captcha nincs a jelenlegi tervben.** A
  aszinkron challenge-ek nem captcha-kötelesek, de a rate-limit
  ellensúlyozza. Ha a Kör 20+ tájékán kiderül, hogy ez nem elég,
  a Kör 22+ bevezethet proof-of-work-öt.
- **A5.2.3 — IP-alapú kiegészítő limit.** A userenkénti limit
  felett egy IP-alapú limit is fut a Sybil-támadások ellen.
- **A5.2.4 — moderation queue.** A flag-elt content (report-ok,
  kulcsszó-egyezés) emberi moderátorhoz kerül, mielőtt láthatóvá
  válna.

### 5.3 Kapcsolódó feature-flag

- `communityWritesEnabled` — a rate-limit csak írás mellett aktív,
  olvasás nyitva maradhat research-üzemmódban.

## 6. Media upload

### 6.1 Fenyegetések

- **A6.1.1 — exif GPS leak.** A feltöltött fotó megőrzi a koordinátá-
  kat — privacy-incidens.
- **A6.1.2 — polyglot JPEG.** A fájl neve `.jpg`, de a tartalom
  egy HTML+JavaScript polyglot, ami XSS-t okoz a feedben.
- **A6.1.3 — DoS nagy fájllal.** Egy 100 MB-os fotó azonnal megtölti
  a szerver storage-ot és lassítja a CDN-t.
- **A6.1.4 — gyermek-visszaélés tartalom.** A platform nem enged
  ilyen tartalmat; ez a fenyegetés nem technikai, hanem jogi/
  reputációs, de a threat model kifejezetten rögzíti, mert a
  moderation policy NEM csak a fenyegetést oldja meg, hanem a
  gyors eltávolítást is.

### 6.2 Védelmi intézkedések

- **A6.2.1 — MIME + magic-byte validáció.** A feltöltött fájl MIME
  típusát a szerver a magic-bytek alapján ellenőrzi, és a
  deklarált típust eldobja, ha nem egyezik.
- **A6.2.2 — exif törlés.** A szerver a feltöltött képet szerver-
  oldalon újra-kódolja, ami az exif-ot kiszedi.
- **A6.2.3 — méretkorlát (8 MB / kép).** A feltöltés mérete
  szerver-oldalon korlátozott; a CDN közvetlen hozzáférést nem
  kap.
- **A6.2.4 — átkódolás.** A szerver a feltöltött képet `image/webp`-
  be konvertálja, ami kizárja a polyglot támadásokat.
- **A6.2.5 — moderation pipeline.** A feltöltés után a kép
  hash-elt a recognised CSAM-adatbázis ellen (PhotoDNA vagy
  helyi hash-lista — a környezet függvénye), és a moderátor
  5 percen belül átnézi.

### 6.3 Kapcsolódó feature-flag

- `communityMediaEnabled` — KIZÁRÓLAG ez a flag engedi a média-
  feltöltést. A flag nélkül a szöveg-only üzemmód aktív.
- `communityWritesEnabled` — a media upload is egy write művelet,
  tehát mindkettő kell.

## 7. Challenge replay

### 7.1 Fenyegetések

- **A7.1.1 — challenge audio újrajátszása.** A kliens egy
  érvényes challenge hangot újrajátszik egy másik device-ról,
  pontszámot gyűjtve.
- **A7.1.2 — időablak-támadás.** A challenge 24 órás ablakában
  érvényes, de ha a token nem time-bound, a támadó napokkal
  később is beválthatja.
- **A7.1.3 — feature fingerprint másolása.** A challenge szerver a
  hang feature-hash-ét is ellenőrzi — ha a feature-hash a kliens
  által szolgáltatott, a támadó saját hash-t generál.

### 7.2 Védelmi intézkedések

- **A7.2.1 — session-bound nonce.** Minden challenge
  kihirdetéskor kap egy egyedi UUID-t, és a beváltás kizárólag
  ezzel a nonce-szal lehetséges. A nonce csak egyszer használható.
- **A7.2.2 — time-bound token (24 óra).** A nonce-ot a szerver
  a kiadás pillanatában tárolja, és a beváltáskor ellenőrzi,
  hogy az érvényességi ablakon belül van-e.
- **A7.2.3 — szerver-oldali feature-hash.** A hang feature-hash-ét
  a szerver a saját DSP-vel futtatja le (ONNX-vagy TensorFlow
  modell), és az eredményt hasonlítja a kliens által küldött-
  höz — a kliens küldött értéke kizárólag UI-előnézetre szolgál,
  nem a szerver döntésére.
- **A7.2.4 — device fingerprint kötése.** A challenge token
  együtt jár a device fingerprint-tel (cross-device
  felismerhetetlenség). Ez a feature-flag-elt szintig védi a
  rendszert: ha a későbbi körök kikapcsolják, a védelem is
  csökken, és a threat model ezt jelzi.

### 7.3 Kapcsolódó feature-flag

- `communityEnabled` — a challenge rendszer a teljes Community
  flag mögött van.
- `communityWritesEnabled` — a challenge submit (beváltás) írás,
  tehát külön kapu.

## 8. Moderation abuse

### 8.1 Fenyegetések

- **A8.1.1 — report-spam.** A támadó 1000 report-ot küld egy
  poszt ellen — a moderátor queue elárasztódik, és az áldozat
  valódi reportjai is eltűnnek a zajban.
- **A8.1.2 — self-moderationnak álcázott támadás.** A támadó
  egy posztot saját maga ellen jelent, hogy a moderátor
  törölje a konkurens tartalmat.
- **A8.1.3 — moderator-account kompromittálódás.** Ha egy
  moderator jelszava gyenge, egy támadó átveszi a szerepet
  és indokolatlanul töröl.
- **A8.1.4 — shadow-ban eltüntetés.** A támadó egy belső
  flag-et állít be, és a poszt a `remove` flow nélkül tűnik
  el — ezt a review-detektálhatóság kedvéért auditálni kell.

### 8.2 Védelmi intézkedések

- **A8.2.1 — report-rate-limit (10 / user / nap).** A userenkénti
  report-limit a Sybil-támadások és a flood ellen.
- **A8.2.2 — distinct-report-limit (3 különböző user).** Csak
  három vagy több független user reportja után kerül a poszt
  auto-moderációra — a self-report kiszűrése.
- **A8.2.3 — moderator audit-log.** Minden `mod_action` azonnal
  egy audit-log-ba kerül, és a logot senki (még a főmoderátor
  sem) törölheti a retention-windowon belül.
- **A8.2.4 — két-faktoros auth a moderátoroknál.** A moderátor
  accountok kötelező 2FA-t kapnak a Kör 10-ben, amikor az
  account layer képessé válik rá.
- **A8.2.5 — takeover-detektálás.** Ha egy moderátor szokatlan
  IP-ről / földrajzi helyről lép be, a rendszer automatikusan
  sandbox-ba helyezi a fiókot és ellenőrző emailt küld.
- **A8.2.6 — nyilvános moderation-nyilatkozat.** A törölt poszt
  nyilvános helyen (a poszt szerzőjének privacy-tisztelettel)
  értesítést kap — ezáltal a moderation transzparens.

### 8.3 Kapcsolódó feature-flag

- `communityWritesEnabled` — a report-ok küldése és a moderáció
  a writes alatt van.
- A Kör 10-ben bevezetendő `moderationQueueEnabled` flag jelzi,
  hogy a belső moderációs queue elérhető-e.

## 9. A nyolc kategórián kívüli, de idevágó megfontolások

### 9.1 Privacy (GDPR / COPPA / App Store)

- A Community user adatai (poszt, komment, follow, club) személyes
  adatok. A threat model a védelmi intézkedéseket rögzíti, a teljes
  privacy impact assessment a Kör 12+ dolga (külön doksi).
- A COPPA (13 év alatti) és a magyar / EU jogrend a Kör 14+ review
  témája.

### 9.2 Audit és forensics

- Minden moderation akció, user-deletion és adat-export azonnali
  audit-log-ba kerül. A logot a user maga NEM törölheti, de a
  retention-window után igen (Kör 16+).

### 9.3 A flag-k alapállapotának védelme

- A `community_*_enabled` flag-ek production defaultja `False`.
- A flutter oldalon a `bool.fromEnvironment('STRUMSIGHT_COMMUNITY_*')`
  formában olvasható, `defaultValue` NÉLKÜL — így a flag hiánya =
  `False`. A backend oldalon a `Settings.community_*_enabled` mező
  defaultja szintén `False`, és a `_default_lab_flags_for_environment`
  validator NEM nyúl hozzá (a Community NEM env-aware, mert a
  dev-safe default itt a `False`, nem a `True`).

### 9.4 Tesztelhetőség és a mérce-mátrix

- A §6.1 mérce-mátrix harmadik sora kimondja: "a threat model
  kihagyja a media upload vagy a challenge replay kockázatot → A3
  cella piros". Ez a nyolc kategória (1–8) mindegyikének explicit
  jelenlétét és az adatvédelmi audit-szempontokkal való
  összhangját a review-nak KÖTELEZŐ ellenőriznie.

## 10. Kapcsolódó dokumentumok

- `docs/rounds/e09-r01-community-baseline-and-feature-flags.md` — a
  kör briefje; a fenti lista a §5 / §8-ból származik.
- ADR 0395 — a Community flag család pontos definíciója (a Claude
  írja, e körhöz).
- ADR 0220 — Epic 6 audio-analysis-v2 kill switch, a Community
  flag-ek MECHANIZMUS-szintű előzménye.
- ADR 0247 — self-deleting share tempfile, a Kör 10 share-artifact
  alapja.
- `docs/sdd/epic-08-completion-report.md` — a megelőző epic záró
  jelentése, a Community adat-modell kiindulópontja.

---

> **Ezen threat model változásai a későbbi körökben** (a Kör 2+
>  minden újabb fenyegetési osztály felfedezésekor) — a dokumentum
>  frissítése a feature-vel együtt, a commit message-ben explicit
>  hivatkozással a módosított szakaszra.
