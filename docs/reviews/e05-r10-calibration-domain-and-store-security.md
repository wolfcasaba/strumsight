# E05-R10 — Security/Privacy Review

Round: E05-R10 (camera + guitar calibration domain & versioned store)
Diff reviewed: `539d346..HEAD` (pre-fix tip `c0701db` — F1/F2 general-review
fixes landed afterward and do not touch the files below)
Risk header: `risk = "high"` → mandatory standalone security pass
Reviewer: security-reviewer agent (Claude Sonnet 5) · Dátum: 2026-08-07
**Verdikt: FAIL** — 2 MAJOR nyitva (merge-blokkoló), 0 BLOCKER/CRITICAL

## Javító kör 2 (Codex) — MAJOR-1 termékkód-fixje helyes, DE egy sokkal
   szélesebb, ÚJ MAJOR-t fedett fel az újra-ellenőrzés

Motor: Codex (a §2 motor-eszkaláció szerint — MiniMax már elhasználta az
egy javító körét F1/F2-re). Commit `0bc37c9`, 2 fájl (a codec + a teszt).
A production-fix (`_readOrientation` megosztott helper, explicit
`switch`-tag a `CameraRotation.fromDegrees` hívás ELŐTT, mindkét hívási
helyen — aktuális séma ÉS legacy migráció) **helyes** — saját kézzel,
külön ellenőrizve (lásd lent).

**Első próbálkozásra a Codex-worktree `blocked`-ot jelzett** — a saját
gate-futása analyze-on pirosra váltott. Kimérve: NEM kódhiba, hanem a friss
`git clone`-nal létrehozott munkapéldányban elmaradt
`tools/prepare-flutter-generated.sh` (a hiányzó generált `lib/l10n/`
gitignore-olt fájlok miatti, dokumentált klón-csapda, `docs/LESSONS.md`
L48/L59, konkrét precedens: HANDOFF E04-R16 „nem H6"). Az orchestrátor
saját mulasztása (a munkapéldányt nem prepelte dispatch előtt) — a script
lefuttatása után a gate ZÖLD, a `blocked` jelzés ezzel feloldva, NEM H6.

**Az újra-ellenőrzés (saját kézzel, mutáció-kill próbával) viszont egy
SOKKAL nagyobb, addig rejtett problémát fedett fel.** A `_readOrientation`
fixet ideiglenesen visszaállítva az eredeti (hibás) alakra, a TELJES
`vision_calibration_repository_test.dart` — beleértve a Codex ÚJ,
kifejezetten erre a hibára írt celláját — **mind a 19 teszttel változatlanul
zöld maradt**. Ok (közvetlen diagnosztikával igazolva, lásd MAJOR-2): az új
teszt (és rajta kívül még NÉGY meglévő, a MiniMax eredeti köréből származó
teszt) a `data` objektumon belül NEM ad meg explicit `schemaVersion` mezőt,
ezért a codec `_readShapeVersion` „hiányzó mező → legacy(0)" ága miatt a
teszt bemenete a **legacy** migrációs útvonalra fut, nem az **aktuális
séma** dekódolójára — így a teszt egy KORÁBBI, a szándékolttól teljesen
független ellenőrzésen bukik el (lásd MAJOR-2 részletei).

### MAJOR-2 — ÖT hand-constructed teszt (a „current schema" dekódoló
    korrupció-/sértés-teszjei) a legacy migrációs ágra fut, nem oda, amit
    állítanak

- **Fájl:** `test/features/vision/data/vision_calibration_repository_test.dart`,
  öt cella: „hibás típus — a camera mező nem objektum" (~348), Codex ÚJ
  „érvénytelen orientation" cellája (~380), „degenerált polygon" (~414),
  „a pixel-coordinate field bypasses validation" (~552), „a numeric field
  with a string value is rejected" (~591). Gyökér-mechanizmus:
  `lib/features/vision/data/persistence/vision_calibration_codec.dart:109-119`
  (`_readShapeVersion`: `if (raw == null) return legacySchemaVersion;`).
- **Probléma:** mind az öt teszt `jsonEncode({'schemaVersion': <envelope>,
  'data': {'camera': {...beágyazott objektum...}, 'guitar': {...}}})` alakú
  bemenetet ad, de a **belső** `data` objektumnak NINCS saját
  `'schemaVersion'` kulcsa. A codec ezt a hiányzó mezőt `legacySchemaVersion
  (0)`-ként értelmezi, tehát `_migrateFromLegacy` fut, ami a `_legacyCamera`
  helperen keresztül **lapos, string-alapú** mezőket vár (`legacy['camera']`
  egy STRING-nek kell lennie). Mivel mind az öt teszt `data.camera`-ja egy
  **beágyazott objektum** (a szándékolt „aktuális séma" alak), a
  `_readLegacyString(legacy, 'camera')` `raw is! String` ága azonnal
  `JsonRecordException(not_a_string, field: 'camera')`-t dob — **mielőtt**
  a teszt által állítólag célzott ellenőrzés (a camera-objektum típusa az
  AKTUÁLIS sémában, az orientation-fehérlista, a polygon-hosszkorlát, a
  pixelkoordináta-tartomány, a numerikus-mező-típus) egyáltalán lefutna.
  Az egyetlen kivétel a „hibás típus" teszt, ahol `data.camera` szándékosan
  egy STRING (`'not-an-object'`) — ott a `_readLegacyString` átmegy, de a
  KÖVETKEZŐ lépés (`legacy['orientation']`, ami nincs a lapos tesztadatban)
  bukik `JsonRecordException(missing, field:'orientation')`-nel.
- **Mérve (közvetlen diagnosztika, önálló Dart-harness a shippelt codec-en
  `decodeFromMap`-et közvetlenül hívva):**
  ```
  HIBAS_TIPUS_THROWS: JsonRecordException -- JsonRecordException(missing, field: orientation)
  ORIENTATION_THROWS: JsonRecordException -- JsonRecordException(not_a_string, field: camera)
  ORIENTATION_WITH_VERSION_THROWS: JsonRecordException -- JsonRecordException(unknown_enum, field: orientation)
  ```
  A harmadik sor ugyanaz a bemenet, DE explicit belső
  `'schemaVersion': VisionCalibrationCodec.currentSchemaVersion`-nel — ez
  adja a VALÓBAN szándékolt `unknown_enum`/`orientation` hibát, bizonyítva,
  hogy a `_readOrientation` fix helyes, CSAK a teszt nem éri el.
- **Hatás:** az acceptance #4 (korrupció-tolerancia) és #7 (valódi-sértés
  próba) **az aktuális (nem-legacy) séma dekódolójára NINCS bizonyítva** —
  ez a séma az, amit az app 99%-ban ténylegesen használ (a legacy út
  egyszeri migráció). Konkrétan: a `_decodeGuitar`/`_decodeProfile`
  (aktuális séma) SAJÁT `requireDouble(min:0,max:1)` hívásait, a
  `cameraRaw is! Map` ellenőrzést és a polygon-hossz-korlátot **egyetlen
  teszt sem méri** — ha ezeket egy jövőbeli refaktor meggyengíti (pl. csak
  a `_legacyGuitar`-ban marad meg a bound-check), a teljes shippelt suite
  zöld maradna. Ez pontosan az a mintázat, amit ADR 0181/0183 kizárni
  próbál, MOST géppel nem bizonyítva a fő (nem-legacy) útra.
- **Kötelező javítás:** mind az öt hand-constructed teszt `data` mezőjébe
  vegyél fel egy explicit `'schemaVersion':
  VisionCalibrationCodec.currentSchemaVersion` kulcsot, hogy ténylegesen az
  aktuális-séma dekódolót (`_decodeBundle`/`_decodeProfile`/`_decodeGuitar`)
  érjék el, majd ellenőrizd, hogy mindegyik a SAJÁT állított okára bukik
  (nem egy máshonnan jövő, véletlen `JsonRecordException`-re) — a pontos
  `reason`/`field` párra `expect` a `logger.events` mellé, ahol ésszerű.
- **Státusz:** OPEN.

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

FAIL — MAJOR-1 termékkód-szinten FIXED (`0bc37c9`, saját kézzel
függetlenül igazolva), de a hozzá tartozó teszt nem bizonyít, és emellett
MAJOR-2 (öt teszt legacy-ágra tévedése) nyitva. Harmadik javító kör
szükséges (Codex folytatja ugyanabban a munkapéldányban, `0bc37c9`-ről) —
mind az öt érintett tesztet a fenti MAJOR-2 leírás szerint kell javítani,
beleértve MAJOR-1 saját regressziós celláját is. Utána a security-review
frissítve PASS-ra a végső javító commit SHA-jával.
