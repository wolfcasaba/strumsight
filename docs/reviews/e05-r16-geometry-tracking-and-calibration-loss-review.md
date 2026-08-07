# E05-R16 — Review

Brief: `docs/rounds/e05-r16-geometry-tracking-and-calibration-loss.md`
Diff: `git diff 064b071..2889ade` (branch `minimax/e05-r16-geometry-tracking-and-calibration-loss`, workspace `/home/ubuntu/ss-mm-e05-r16`)
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-07
Verdikt (első pass): CHANGES REQUESTED
Verdikt (javító kör 1 után, `8017382`/`6a1c728`): **APPROVED** — ld. „Javító
kör 1 — zárás" szakasz a végén.

## Összegzés

BLOCKER: 1 · MAJOR: 0 · MINOR: 2 · NOTE: 3

A gate a saját, izolált `/tmp/review-e05-r16` klónomban függetlenül újrafuttatva
**6/6 zöld** (`tools/round-gate.sh test/features/vision`), a scope-audit
(`tools/scope-audit.py`) a 9 változott útvonalra **OK** — mindkettő a
handoff önjelentését megerősíti. A BLOCKER azonban **nem a gate-ben látszik**:
mindkét egységteszt-fájl a két új komponenst (`EdgeGeometryTracker`,
`CalibrationLossMachine`) **izoláltan** teszteli, sosem összekötve — a
`calibration_loss_machine_test.dart` egy `observationFor()` helperrel
KÖZVETLENÜL konstruál `GeometryObservation`-t, megkerülve a valódi trackert.
Egy eldobható próbateszttel (lásd lent) a két komponenst ténylegesen
összekötve **a kör §1 „Cél"-jában megfogalmazott biztonsági garancia nem áll
fenn**.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Drift-mátrix (alatt/rajta/fölött → tracking/degraded/lost) | ⚠️ Részleges | A tiszta állapotgép-logika (`CalibrationLossMachine.stateTransition`) helyes és tesztelt (`calibration_loss_machine_test.dart:39-63,328-363`). DE a „rajta"/„fölött" cellák a **szállított egyetlen adapteren (`EdgeGeometryTracker`) keresztül sosem érik el a gépet** — ld. F1 BLOCKER. |
| 2 | Hiszterézis-teszt (17-elemű oszcilláció, ≤2 váltás) | ✅ | `calibration_loss_machine_test.dart:66-85`, manuálisan újraszámolva: minden elem a `(0.06, 0.09)` sávban, 1 váltás. Ez a sáv `< lostDriftBound`, tehát a valódi trackeren át is reprodukálható — nem érinti F1. |
| 3 | Szcenárió-fixture-ök (a/b/c) | ❌ (b), (c) | (a) rendben (drift=0.02, a bound alatt, nem érinti F1). **(b) és (c) a valódi adapteren keresztül NEM a dokumentált viselkedést adja** — ld. F1, empirikusan megmérve. |
| 4 | Feedback-tiltás teszt (`lost` → `notObservable`, 0 negatív insight-hívás) | ⚠️ Részleges | A logika helyes (`feedbackSuppressed` pontosan `_state==lost`-ot tükrözi), DE mivel a valódi trackeren át (b) szcenárió nem éri el a `lost`-ot egyetlen frame alatt, a garancia pont a legveszélyesebb pillanatban (hirtelen nagy elmozdulás UTÁNI első frame-ek) nem érvényesül — ld. F1. |
| 5 | Valódi-sértés próba (bound eltávolítása → (c) PIROS) | ⚠️ Gyenge | A tracker-oldali próba (`geometry_tracker_test.dart:184-210`, `_NoGuardEdgeGeometryTracker`) valódi, párhuzamos-implementációs mutáció — elfogadható. A machine-oldali „próba" (`calibration_loss_machine_test.dart:249-295`) nem mutál semmit, csak megismétli a step-11 állítást kommentárban — ld. N1. |
| 6 | Summary tartalmazza `geometrySource` + `maxDrift` | ✅ | `calibration_loss_machine_test.dart:298-325`, a getterek közvetlenül helyesek, a §0.0 R5 szerinti hatókör-értelmezéssel összhangban. |

## Scope-audit

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-mm-e05-r16 \
    --brief docs/rounds/e05-r16-geometry-tracking-and-calibration-loss.md --base 064b071
Legacy scope audit OK (064b071..2889adee3cdb, 9 changed path(s), 0 generated/ignored)
```

Egy üres, `=` nevű untracked fájl volt a munkapéldányban (feltehetően egy
implementer-oldali shell-parszolási mellékhatás — pl. egy `>=`/`=` körüli
idézőjel-hiányos parancs), amit a kilépő jelzés `dirty_files=2`-je jelzett. A
fájl 0 bájtos, sosem volt commitolva, nem lehetett volna PR-részévé — az
orchestrátor törölte, majd a scope-audit tisztán futott le. Nincs hatása a
diffre. (Megjegyzés a §11 „nem futtatott ellenőrzések" listájához: az
implementernek `ROUND_BRIEF` nélkül a wrapper gépi scope-auditja `skipped`
maradt — ezt az orchestrátor pótolta kézzel, ld. fent.)

## Megállapítások

### F1 — BLOCKER — A tracker elnyeli a nagy driftet, a gép sosem látja: a §1 „biztonságos érvénytelenítés" cél a valódi adapteren át nem teljesül

- **Fájl:** `lib/features/vision/data/guitar/edge_geometry_tracker.dart:95`
  (`if (drift >= lostDriftBound) return null;`) ×
  `lib/features/vision/application/calibration_loss_machine.dart:168-176`
  (`update()` null-ág: `_state` VÁLTOZATLAN marad, amíg
  `_consecutiveLostFrames < noObservationLostThreshold(5)`).
- **Probléma:** Az `EdgeGeometryTracker` a `lostDriftBound`-nál nagyobb-egyenlő
  driftet **`null`-ra konvertálja** ("refuse"), ahelyett hogy a tényleges
  (nagy) drift-értékkel `GeometryObservation`-t adna vissza. A
  `CalibrationLossMachine._nextState` maga HELYESEN implementálja az azonnali
  forward-escalation logikát (`drift > lostDriftBound` → `lost`, MINDEN
  előző állapotból, dokumentálva is: "Forward escalation has priority in
  EVERY branch") — de ez a logika halott kód a valódi integrációban, mert a
  gép sosem kapja meg a nagy drift-értéket: a tracker null-ra cseréli, és a
  `null`-ág egy MÁSIK, lassabb útvonalra (`_consecutiveLostFrames`
  számláló, 5 egymást követő frame) tereli, amit eredetileg a „nincs
  detektált feature" (kamera-glitch, átmeneti detektor-kiesés) esetére
  szántak, NEM a „biztosan rossz geometria" esetére.
- **Hatás (empirikusan mérve, eldobható próbateszttel — ld. lent):**
  - **Szcenárió (b) „nagy elmozdulás":** EGY frame nagy (0.20) drifttel a
    valódi `EdgeGeometryTracker`-en át `null`-t termel; a gép ez UTÁN is
    `tracking` állapotban marad, `feedbackSuppressed=false`,
    `recalibrateRequested=false`. A brief §1 kifejezett célja — „elmozdulás
    esetén biztonságos érvénytelenítés: negatív technikai feedback helyett
    Recalibrate kérés" — EGYETLEN frame alatt nem teljesül; legalább
    `noObservationLostThreshold`(5) egymást követő ilyen frame kell hozzá
    (~0,2 s 25 fps mellett) — eddig a felhasználó a RÉGI, immár rossz
    geometrián kapna gitárspecifikus visszajelzést.
  - **Szcenárió (c) „lassú kumulatív sodródás":** a dokumentált/tesztelt
    „11. lépésnél `lost`" állítás a valódi integráción át **14. lépés**
    (mért, ld. lent) — 3 lépés (~27%) késés, mert a 10-13. lépések driftje
    (0.10-0.13) mind `>= lostDriftBound`, tehát a tracker mind `null`-t ad,
    és csak az 5. egymást követő null (14. lépés) váltja `lost`-ra a gépet.
    Sőt, még a `degraded` állapot elérése is 1 lépéssel később következik be
    (6. lépés, nem 5.) — lebegőpontos eltérés a tracker VALÓDI
    (feature-anchor kivonásból számolt) shiftje és a teszt pinnelt
    konstansai között, amit a bypass-helperes tesztek nem fognak meg.
  - **Drift-mátrix 2/3. cellája** („pontosan rajta" → `degraded`, „fölött" →
    `lost`) a szállított `EdgeGeometryTracker`-en át **elérhetetlen** —
    mindkettő `null`-lá válik a tracker szintjén, tehát a gép sosem
    klasszifikálja őket közvetlenül a valódi pipeline-ban, csak az
    izolált unit teszt hívja őket `stateTransition`/`observationFor` bypass-
    szal.
- **Bizonyíték — eldobható próbateszt** (`/tmp/review-e05-r16/test/features/vision/_review_probe_integration_test.dart`,
  NEM része a diffnek, a review klónban futtatva és eltávolítva):
  ```
  step=5  drift=0.050 trackerNull=false state=tracking   (a teszt szerint: degraded)
  step=6  drift=0.060 trackerNull=false state=degraded
  step=10 drift=0.100 trackerNull=true  state=degraded
  step=11 drift=0.110 trackerNull=true  state=degraded   (a teszt szerint: lost)
  step=14 drift=0.140 trackerNull=true  state=lost
  firstDegradedStep=6 firstLostStep=14   (dokumentált/tesztelt állítás: 5 / 11)

  scenario(b) single-frame: trackerReturnedNull=true
    stateAfterOneFrame=tracking feedbackSuppressed=false
  ```
- **Kötelező javítás (irány, nem kész patch):** `EdgeGeometryTracker.observe()`
  ne konvertálja a nagy driftet `null`-ra. A `null` maradjon fenntartva a
  VALÓDI „nincs evidencia" esetnek (`features.isEmpty` /
  `translations.isEmpty` — a jelenlegi 66. és 82. sor, ezek helyesek és
  változatlanul maradhatnak); nagy drift esetén adjon vissza egy
  `GeometryObservation`-t a TÉNYLEGES drift-értékkel, és hagyja, hogy a
  `CalibrationLossMachine` saját (már helyes, már tesztelt) azonnali
  forward-escalation logikája döntsön. Ezután írj (a meglévő `allowed_paths`-on
  belül, `test/features/vision/**`) legalább egy valódi integrációs tesztet,
  ami `EdgeGeometryTracker.observe()` kimenetét közvetlenül
  `CalibrationLossMachine.update()`-be vezeti a (b) és (c) szcenárióra —
  bypass-helper nélkül —, hogy a jövőben ez a réteg-szakadás ne tudjon zöld
  gate mellett visszatérni.
- **Ellenőrzés:** az új integrációs teszt PIROS a jelenlegi kódon, ZÖLD a
  javítás után; a fenti eldobható próba (vagy ekvivalens) megismételve
  `firstLostStep=11`-et és `stateAfterOneFrame=lost`-ot kell adjon.
- **Státusz:** FIXED (`8017382`) — a null-refusal ág törölve
  `edge_geometry_tracker.dart`-ban, ÚJ valódi integrációs teszt
  (`test/features/vision/application/calibration_loss_machine_integration_test.dart`,
  orchestrátor-addendummal felvéve az `allowed_paths`-ra, §0.0 R7).
  Függetlenül újra-ellenőrizve friss `/tmp/review-e05-r16-fix1` klónban: az
  ÚJ integrációs teszt mind a 4 esetben zöld, ÉS egy saját, a fixtől
  független eldobható próbateszttel megismételve: `trackerReturnedNull=false,
  stateAfterOneFrame=lost, feedbackSuppressed=true` — a BLOCKER ténylegesen
  zárva, nem csak a diff alapján feltételezve.

### F2 — MINOR — A `GeometryConfidence` validációja csak `assert` — release buildben nem fut, a doc-comment saját magának mond ellent

- **Fájl:** `lib/features/vision/domain/geometry/geometry_confidence.dart:67-75`
  (a konstruktor `assert(confidence.isFinite && …)` / `assert(drift.isFinite && …)`),
  fogyasztva: `lib/features/vision/application/calibration_loss_machine.dart:168-191`.
- **Probléma** (dedikált `security-reviewer` subagent lelete, MINOR-1,
  függetlenül megerősítve): Dart `assert` **release módban nem fut** — a
  fájl saját doc-commentje (2-25. sor: "Construction validates inputs so a
  corrupt tracker can never feed the loss machine a NaN/Infinity drift") és
  a hozzá tartozó teszt neve
  (`test/features/vision/domain/geometry_tracker_test.dart:64`,
  `'rejects non-finite inputs (silent-garbage prohibition)'`) egy védelmet
  állítanak, ami **csak debug/test módban létezik**. Ez pontosan az a
  doc-comment-fegyelem sértés, amit a projekt szabálya tilt (a state
  állítás nem bizonyított a TÉNYLEGES (release) futásban). A minta, amit
  KÖVETNI kellett volna, már a repóban van:
  `lib/features/vision/domain/geometry/guitar_landmark_mapper.dart:234-256`
  explicit `if (!(x.isFinite && …)) return null`-t használ, NEM
  konstruktor-assertet.
- **Hatás:** egy jövőbeli (R17) `GeometryTracker` adapter, ami NaN/Infinity
  driftet ad át, a release APK-ban CSENDBEN felépít egy
  `GeometryConfidence`-t; `isLost` (`drift > lostDriftBound`) `NaN > 0.10`
  esetén `false`, tehát a gép **`tracking`/`feedbackSuppressed=false`**
  állapotot jelentene garbage geometria fölött — a security-reviewer
  reprodukálta `--no-enable-asserts` alatt. `_maxDrift` ráadásul
  **véglegesen NaN-ra fagy** (`math.max(x, NaN) == NaN`), egy későbbi tiszta
  frame sem törli. Ugyanez a hiányzó véges-őr fedezi az anchor-oldali
  degenerálódást is (security NOTE-1: egy NaN anchor-koordináta a
  `.clamp(0.0, 1.0)`-on át csendben `1.0`-ra esik).
- **Miért nem BLOCKER:** a szállított `EdgeGeometryTracker` maga NEM tudja
  előidézni (a `_nearestAnchor` min-keresése kihagyja a nem véges
  feature/anchor pontokat, tehát `observe()` `null`-t ad — reprodukálva a
  security review saját NaN/Inf próbáival), és a kör hatókörében nincs másik
  konzumens. A hézag a KONTRAKT-határon latens, nem élő útvonalon.
- **Kötelező javítás:** a `GeometryConfidence` konstruktorban az `assert`-eket
  cseréld VALÓDI, minden build-módban futó ellenőrzésre (pl. feltétel nélküli
  `throw ArgumentError(...)`, a `guitar_landmark_mapper` fail-loud
  filozófiáját követve — nem kell feltétlenül nullable factory, mivel a
  `GeometryObservation.confidence` jelenleg nem-nullable mezőként várja).
  Ha a mechanizmus változik (assert → throw), a hozzá tartozó tesztet
  (`geometry_tracker_test.dart:64-77`) is igazítsd — a `throwsA(isA<AssertionError>())`
  helyett a TÉNYLEGES (nem debug-only) hibatípust ellenőrizze.
- **Ellenőrzés:** a teszt `flutter test --no-enable-asserts` (vagy
  ekvivalens release-szimuláció) alatt is bizonyítsa a védelmet, ne csak
  debug módban.
- **Státusz:** FIXED (`8017382`) — az `assert`-ek feltétel nélküli
  `throw ArgumentError(...)`-ra cserélve, a hozzá tartozó teszt
  `throwsA(isA<ArgumentError>())`-ra igazítva. Megjegyzés: `flutter test`
  nem támogat `--no-enable-asserts` kapcsolót (az `flutter run`/`build`
  opció, nem `test`) — de ez nem szükséges a bizonyításhoz, mert a javítás
  szerkezetileg `assert`-mentes: egy feltétel nélküli `throw` minden
  build-módban lefut, ez nyelvi tény, nem futásidőben mérendő. A meglévő
  gate-teszt (`throwsA(isA<ArgumentError>())`) elégséges bizonyíték.

### F3 — MINOR (follow-up, NEM ebben a körben) — `FrameObservation.detectedFeatures` felső korlát nélküli

- **Fájl:** `lib/features/vision/domain/geometry/geometry_tracker.dart:36-43`
  → `edge_geometry_tracker.dart:77-99` (O(n log n) a feature-számban, nincs
  isolate-határ).
- **Lelet forrása:** dedikált `security-reviewer` subagent, MINOR-2, mérve
  (n=1k→14ms … 4M→14s szinkron a hívó száson). A jelen körben nincs éles
  feed (csak teszt-fixture-ök, kis listák) — a security-reviewer saját
  szavaival "materially milder than the E05-R13 cubic case" és kifejezetten
  az R17 automatikus detektorra vonatkozó, e körben ki NEM váltható kockázat.
- **Kötelező javítás:** NEM ebben a körben — a §3 "Kívül — TILOS: automatikus
  gitárdetektor modell (R17)" hatókör-határ miatt egy új invariáns
  (felső korlát a feature-listára) bevezetése ide tartozna, amikor a
  tényleges detektor megépül. Dokumentálva itt, hogy az R17 brief-je
  pre-flightban vegye figyelembe.
- **Státusz:** OPEN (follow-up, nem blokkoló, nem ebben a körben esedékes)

### N1 — NOTE — A machine-oldali „valódi-sértés próba" nem mutál kódot

- **Fájl:** `test/features/vision/application/calibration_loss_machine_test.dart:249-295`
- **Probléma:** A teszt neve és a brief §6 utolsó előtti cellája
  „drift-bound eltávolítása → PIROS → visszaállítás"-t ír elő, de a teszt
  ténylegesen NEM távolít el semmit — csak megismétli „a bound megléte
  mellett a step-11-nél `lost`" állítást, kommentben leírva, mi történne
  elméletileg a bound nélkül. Ez tautológikus: sosem tudna pirosra váltani,
  mert nincs benne mutáció. (A tracker-oldali `_NoGuardEdgeGeometryTracker`
  párhuzamos-implementációs próba viszont valódi és elfogadható.) Ha F1
  javítása során ez a teszt úgyis átíródik (a bypass helper helyett valódi
  integrációra), érdemes itt egy tényleges ideiglenes küszöb-mutációt
  (pl. `recoveryDriftBound` átmeneti feltételes felülírása egy test-only
  branch-csel) vagy legalább egy közvetlen `stateTransition`-hívást tenni,
  ami a küszöböt paraméterként kapná és bizonyíthatóan pirosra váltana egy
  laza értékkel.
- **Hatás:** Gyenge bizonyító erő — a teszt nem védi meg ténylegesen a
  jövőbeli küszöb-lazítás ellen, csak dokumentálja a szándékot.
- **Független megerősítés:** a dedikált `security-reviewer` subagent
  ugyanerre a fájlra, ugyanerre a következtetésre jutott (saját NOTE-2),
  tőlem függetlenül — két különböző review-szög ugyanazt a gyengeséget
  találta.
- **Kötelező javítás:** nem kötelező ebben a körben; follow-up javasolt, ha
  F1 miatt ez a teszt-fájl úgyis módosul.
- **Ellenőrzés:** —
- **Státusz:** OPEN (nem blokkoló)

### N2 — NOTE — Doc-comment elgépelés és pontatlan állapot-leírás

- **Fájl:** `lib/features/vision/domain/geometry/geometry_tracker.dart:3`
  („FAME-TO-FRAME" → „FRAME-TO-FRAME" elgépelés) és
  `lib/features/vision/application/calibration_loss_machine.dart:210-213`
  (a `_nextState` fejléc-kommentje csak „degraded → lost"-ot említ a
  `drift > lostDriftBound` ágnál, holott a kód ELSŐ ága ezt MINDEN
  `previous`-ra alkalmazza, `tracking`-ből és `lost`-ból is közvetlenül
  `lost`-ba ugorhat egy nagy drifttel — a kommentár emiatt hiányos, nem
  hibás).
- **Hatás:** Kozmetikai / dokumentáció-pontossági, nem viselkedésbeli.
- **Kötelező javítás:** apró szövegjavítás, ha F1 miatt ez a fájl úgyis
  módosul; önmagában nem éri meg külön kört.
- **Státusz:** OPEN (nem blokkoló)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (handoff) | Ellenőrizve (saját /tmp klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test test/features/vision | zöld | ✅ zöld (196 teszt, „All tests passed!") |
| architecture | zöld | ✅ zöld (12 allowlistelt eltérés — egyik sem az új fájlokra, ellenőrizve `tool/check_architecture.dart` grep-pel) |
| secrets | (nem jelentve a handoffban) | ✅ zöld |
| l10n | (nem jelentve a handoffban) | ✅ zöld |
| CI (teljes suite + property + APK) | — | Merge előtt az orchestrátor dispatch-eli |

A gate ténylegesen zöld — a BLOCKER egy VISELKEDÉSI hézag, amit egyik gate
sem mér (a review skill alapelve: „a zöld gate nem bizonyíték").

## Architektúra + termékhatárok

Import-lista ellenőrizve mind a 4 új production fájlra: nincs `dart:ui`,
nincs `package:flutter` import a domain/application rétegben, a
`core/camera` importja a helyes irányban (feature → core). Nincs hálózati
hívás, storage-írás, mic/camera-plugin hívás, secret. Lifecycle-erőforrás
nincs a diffben (pure Dart, nincs `StreamSubscription`/isolate/timer).

## Biztonsági/adatvédelmi review (risk=high)

Dedikált `security-reviewer` subagent futott (2026-08-07, `/tmp` scratchpad
reprodukcióval, `--no-enable-asserts` release-szimulációval és
`--enable-asserts` debug-móddal is lefuttatva). **Verdikt: PASS** — 0
CRITICAL/BLOCKER/MAJOR. Grep-pel megerősítve: a diff nem tartalmaz logolást,
IO-t, hálózatot, `Dio`/HTTP-t, perzisztencia-írást, auth-ot, AI-provider
hívást, engedélykérést, új függőséget vagy asset-et — a szokásos
privacy/network/consent/prompt-injection/import-lánc N/A ebben a diffben. A
két MINOR lelet (F2, F3 fent) és a NOTE-2 (= N1 fent, függetlenül
megerősítve) a fenti megállapítások közé olvasztva. Egy további negatív
(informális) megfigyelés:

### N3 — NOTE — Nincs érzékeny-adat szivárgás (ellenőrizve, negatív)

A négy új production fájlban nincs `print`/log/IO. Az egyetlen kiadott
string-ek: `adapterId = 'edge_geometry_tracker.v1'` és numerikus
`toString()`-ok (`geometry_confidence.dart:107-110`) — nincs fájlrendszer-
útvonal, secret, token vagy belső state. A `public.dart` diffje 4 additív
export. Nincs valódi kulcs egyetlen fixture-ben sem.

## Javító kör 1 — zárás (2026-08-07)

MiniMax M3 ugyanabban a munkapéldányban (`/home/ubuntu/ss-mm-e05-r16`),
ugyanazon a branchen javított, `.pipeline/fix-prompt-E05-R16-1.md`
findings-listával. Eredmény: `status=done`, két commit
(`8017382` kód, `6a1c728` orchestrátor `allowed_paths`-addendum §0.0 R7).

- **F1 BLOCKER → FIXED.** A tracker null-refusal ága törölve; a
  `CalibrationLossMachine` saját forward-escalation logikája most élő a
  valódi integrációban. ÚJ integrációs teszt-fájl
  (`calibration_loss_machine_integration_test.dart`) köti össze a két
  komponenst bypass nélkül — ez zárja a review fő megállapítását (hogy
  korábban EGYETLEN teszt sem tette ezt).
- **F2 MINOR → FIXED.** `assert` → feltétel nélküli `throw ArgumentError`.
- **F3, N1, N2** — státuszuk változatlan (follow-up / nem blokkoló), a
  javító kör mellékhatásaként N1 ténylegesen javult is (a tautologikus
  machine-oldali próba törölve, az új valódi integrációs teszt vette át a
  szerepét) — de ezt nem kértem kötelezően, bónusz.
- **Scope:** a javító kör diffje ELSŐ scope-audit-futáson egy listán
  kívüli fájlt talált (`calibration_loss_machine_integration_test.dart`) —
  ez az orchestrátor saját fix-prompt-jának belső ellentmondása volt (a
  §1 kért egy új tesztet, a §4 nem vette fel a listára), NEM implementer
  scope-túllépés. Orvosolva egy dokumentált §0.0 R7 addendummal
  (ADR 0087 §2 — a kör saját, még nem merge-elt artefaktumát érintő
  döntés). Scope-audit a bővített listával **OK** (5 changed path).
- **Független újra-ellenőrzés** (friss `/tmp/review-e05-r16-fix1` klón,
  NEM a `ss-mm-e05-r16` implementer-munkapéldány): `tools/round-gate.sh
  test/features/vision` **6/6 ZÖLD**; az ÚJ integrációs teszt-fájl
  önmagában futtatva mind a 4 esetben zöld; egy a fixtől független,
  eldobható próbateszttel (nem a MiniMax-é) megismételve a scenario (b)
  eset: `trackerReturnedNull=false, stateAfterOneFrame=lost,
  feedbackSuppressed=true` — a BLOCKER zárása MÉRVE, nem a diff
  elolvasásából feltételezve.

## Merge-döntés

**Merge ENGEDÉLYEZETT** — 0 nyitott BLOCKER/MAJOR. F3 dokumentált follow-up
(R17 pre-flight), N1/N2 nem blokkolók. Hátravan: CI-dispatch (teljes suite +
randomizált property + a `tools/round-ci-plan.py` szerinti terv) és az
exact-SHA zöld kapu a merge SHA-ján (ADR 0052/0086 §2).
