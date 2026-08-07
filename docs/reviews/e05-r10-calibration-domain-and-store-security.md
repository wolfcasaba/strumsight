# E05-R10 — Security/Privacy Review

Round: E05-R10 (camera + guitar calibration domain & versioned store)
Diff reviewed: `539d346..HEAD` (pre-fix tip `c0701db` — F1/F2 general-review
fixes landed afterward and do not touch the files below)
Risk header: `risk = "high"` → mandatory standalone security pass
Reviewer: security-reviewer agent (Claude Sonnet 5) · Dátum: 2026-08-07
**Verdikt: FAIL** — 1 MAJOR nyitva (merge-blokkoló), 0 BLOCKER/CRITICAL

## Scope

Az 5 új production fájl (`lib/features/vision/domain/calibration/**`,
`lib/features/vision/data/persistence/**`), az additív `public.dart` +
`storage_keys.dart` diff, és a kötött döntések (ADR 0183 no-raw-frame, ADR
0181 normalized-space, §5.1–5.6, acceptance #4/#6/#7).

## Megállapítások

### MAJOR-1 — korrupt `orientation` megszökik a `read()` `on Exception` őrén → crash, nem karantén

- **Fájl:** `lib/features/vision/data/persistence/vision_calibration_repository.dart:63`
  (`} on Exception catch (e) {`) + a védetlen factory-hívások
  `vision_calibration_codec.dart:298` (aktuális séma) és `:155` (legacy
  migráció), amik forrása `lib/core/camera/camera_coordinate_space.dart:260`
  (`CameraRotation.fromDegrees` → `ArgumentError`).
- **Hibaforgatókönyv:** egy perzisztált/kézzel szerkesztett/bit-flip-elt
  rekord, aminek `orientation` mezője `requireInt(min:0, max:359)`-en ÁTMEGY
  (tehát tartományon belüli), de NEM a négy érvényes rotáció-érték egyike
  (pl. `45`, `1`, `359`) → `CameraRotation.fromDegrees(45)` `ArgumentError`-t
  dob. Az `ArgumentError` egy `Error`, **nem** `Exception` — a `read()`
  `on Exception catch`-e ezt NEM kapja el, a hiba kiszáll a hívóig és
  **elszáll a caller**, ahelyett hogy a szándékolt „karantén → `null`, a
  többi adat olvasható marad" útra kerülne.
- **Sértett szabály:** acceptance #4 („csonka JSON / hibás típus / degenerált
  polygon → record karanténba, a többi olvasható marad, SOHA nem crashel")
  és §5.2 fail-safe szándéka.
- **Mérve (reprodukálva, önálló Dart harness a shippelt codec-en):**
  ```
  [orientation=90 (valid)]            decoded OK
  [orientation=45 (tartományon belüli korrupt)] *** ESCAPED on Exception *** ArgumentError → read() DOB, a hívó crashel
  [orientation=1] ... ESCAPED ...   [orientation=359] ... ESCAPED ...
  fromDegrees(45) ArgumentError-t dobott; is Exception? false; is Error? true
  ```
  Azonos módon reprodukálódik `--enable-asserts` (teszt-mód) ÉS
  `--no-enable-asserts` (release) alatt — ez NEM egy assert-stripping
  mellékhatás, mindkét módban elérhető catch-clause típus-eltérés. Egyetlen
  meglévő teszt sem próbál tartományon-belüli-de-érvénytelen orientation-t,
  ezért az acceptance #4 ma zöld, miközben ez a korrupció-osztály crashel.
  Mind az aktuális-séma decode (`:298`), mind a legacy-migráció decode
  (`:155`) érintett.
- **Hatás / miért MAJOR és nem BLOCKER:** ebben a körben semmilyen hívó nem
  köti be a `read()`-et UI-hoz (az R11 fogja) — élesben ma nem
  exploitable/látens. Nincs secret/PII a hibaüzenetben (csak az orientation
  fokérték). Ezért MAJOR, nem §5 termékhatár-BLOCKER.
- **Kötelező javítás:** a codec zárjon FAIL-CLOSED — validálja, hogy
  `orientation ∈ {0,90,180,270}`, és nem-egyező esetben dobjon
  `JsonRecordException(RecordDecodeReason.unknownEnum, field:'orientation')`-t
  (ami `Exception`, tehát a repository elkapja → karantén → `read()==null`),
  a többi mező `requireX` mintáját követve. Vegyél fel egy korrupció-mátrix
  cellát tartományon-belüli-érvénytelen orientation-re.
- **Státusz:** OPEN.

### MINOR-1 — a privacy-snapshot nem száll le a pont-objektum szintjéig; a tiltólista szűk

- **Fájl:** `test/features/vision/data/vision_calibration_repository_test.dart:399-433`.
- **Probléma:** a kulcskészlet-pin a top/`data`/`camera`/`guitar` szinteket
  fedi, de a pont-objektum szintet (`nut`/`bridge`/`neckPolygon` egyes elemei,
  ma `{x,y}`) nem — egy jövőbeli, denylist-en kívüli nevű mező (pl. egy pont
  belsejébe rejtett `d`) mindkét ellenőrzésen átcsúszna. A tiltólista hiányol
  gyakori raw-frame tokeneket: `jpg`, `webp`, `heic/heif`, `bmp`, `gif`,
  `raw`, `frame`, `pixel`, `bytes`, `blob`, `yuv`, `nv21`, `bitmap`,
  `capture`.
- **Nem élő szivárgás ma** — a jelenlegi encoder csak `{x,y}` double-t ír a
  pontokba. Defense-in-depth jövőre nézve.
- **Kötelező javítás:** pin-eld a pont-objektum kulcskészletét is (vagy
  assertáld, hogy minden levél-érték `is num`), és bővítsd a tiltólistát.
- **Státusz:** OPEN.

### NOTE-1 — nem szigorú enum-koercíció csendben defaultol ismeretlen perzisztált értékre

- **Fájl:** `vision_calibration_codec.dart:289-291` (`camera` — ismeretlen
  string → `back`) és `:301-304`/`:158-161` (`setupProfile` — ismeretlen
  érték → `practiceBalanced`).
- **Megfigyelés:** enyhe „csendes félreolvasás" nem-szenzitív framing
  mezőkön — szándékos degradálás, a meglévő `VisionSetupProfile.fromStorage`
  mintáját követve, biztonsági hatása elhanyagolható. Elsődlegesen az
  általános/korrektségi review dolga; itt csak azért jelölve, mert a kör
  saját, kimondott „soha nem olvasódik félre csendben" elve érinti. Nem
  blokkoló.

## Ellenőrzött és PASS-elt pontok (evidenciával)

1. **Nincs raw kép soha perzisztálva (ADR 0183) — PASS.** Az encode-út
   kizárólag skalár/enum/pont mezőket ír; grep a kép/blob/base64/bytes/File
   mintákra csak doc-commentet és egy false-positive-ot ad (`proFile(`).
2. **Pixelkoordináta-kizárás — PASS.** Minden koordináta `requireDouble(min:0,
   max:1)`-en megy át a CODEC határán (nem csak a release-stripped domain
   assert-en) — függetlenül falszifikálva: bound nélkül `1920.0` átmenne,
   bounddal `out_of_range`-t dob.
3. **Nincs secret/PII a logban — PASS.** `JsonRecordException.toString()`
   csak reason+field NEVET ad, sosem értéket; mind a ~13 throw-hely és az
   egyetlen repository log-hívás ellenőrizve.
4. **Storage-kulcs ütközés-mentes — PASS.** `ss.vision.calibration` egyedi,
   `StorageKeys.all`-ban, nincs olvasó/író rajta kívül a `lib/features/vision/**`-en.
5. **Domain framework-független — PASS.** `domain/calibration/**` csak a
   pure-Dart `camera_coordinate_space.dart`-ot és domain-testvéreket importál.
6. **Public boundary — PASS.** additív export, pixel-terű típusok
   (`SensorPoint`/`PreviewPoint`/…) kint maradnak.
7. **Jövőbeli verzió fail-closed (acceptance #7) — PASS.** mind az
   envelope-, mind a codec-szintű jövőbeli verzió karanténba kerül, soha nem
   olvasódik félre.

## Merge-döntés

FAIL — MAJOR-1 nyitva. Javító kör szükséges (MAJOR-1 + MINOR-1, ugyanabban a
körben), utána a security-review frissítve PASS-ra a javító commit SHA-jával.
