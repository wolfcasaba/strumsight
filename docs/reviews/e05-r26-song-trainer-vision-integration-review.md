# E05-R26 — Review

Brief: [`docs/rounds/e05-r26-song-trainer-vision-integration.md`](../rounds/e05-r26-song-trainer-vision-integration.md) (§0.0 pre-flight revízió, 2026-08-08)
ADR: [`docs/adr/0193-song-trainer-vision-integration-contract.md`](../adr/0193-song-trainer-vision-integration-contract.md)
Diff: `git diff origin/main...codex/e05-r26-song-trainer-vision-integration` (`7c474fa`…`d5698e0`, javító kör #1 után)
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-08 (frissítve javító kör #1 után)
Verdikt: **APPROVED** (0 nyitott BLOCKER/MAJOR/MINOR — F1 zárva a javító kör #1-ben)

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 (**zárva**) · NOTE: 3 (nyitva, follow-up)

Független gate-újrafuttatás izolált `/tmp/review-e05-r26` klónban (`git clone
--branch codex/e05-r26-song-trainer-vision-integration`, HEAD `5308958`
ellenőrizve): **mind a 7 gate-lépés zöld** (format, analyze, `test
test/features/song_trainer` — 471 teszt, `test test/features/vision` — 338
teszt, architecture, secrets, l10n); a végső „MINDEN GATE ZÖLD" jelzés
jelen van, PIROS lépés nulla — a folyamat háttérben futott (nohup+wait-loop),
ezért az architecture/secrets/l10n lépéseket **külön, közvetlenül is
lefuttattam** (`ARCH_EXIT:0`, `SECRETS_EXIT:0`, l10n `EXIT:0`) valódi, saját
kézzel elkapott kilépési kóddal. Scope-audit: 13/13 fájl pontosan a
(pre-flightban bővített) `allowed_paths`-on belül, nulla kívüli változás.
Saját kézzel **három** valódi-sértés próbát futtattam (2 kért + 1 saját
kezdeményezésű), mindegyik PIROSRA fordult, majd visszaállítás után tisztán
zöld maradt a working tree.

A legérdemibb megállapítás (F1, MINOR) egy **saját, futtatott próbateszttel
felfedezett** tranzitív típus-szivárgás a szűk barrelben — ezt egy dedikált
security-review (risk="high" kötelező, ld. lent) **függetlenül, ugyanazt a
tényt** már megtalálta és NOTE-ra minősítette; a saját elemzésem ugyanazt a
tényt erősíti meg, a súlyosságot dokumentum-pontossági/karbantarthatósági
szempontból egy fokkal szigorúbban (MINOR) ítélem meg, biztonsági kockázatot
én sem találtam.

## Acceptance criteria (brief §6, 8 tétel a pre-flight-bővítés után)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | **Transport-timing parity fixture** — esemény-idővonal + pontozás bitre azonos vision ON/OFF, tolerancia nélkül | ✅ | `test/features/song_trainer/performance/transport_timing_parity_test.dart:17-31` — `expect(withVision.transportTimeline, audioOnly.transportTimeline)` + `expect(withVision.scoringResult, audioOnly.scoringResult)`, epsilon/tolerancia sehol. Saját mérés: `git diff --stat 33b958e..5308958 -- lib/features/song_trainer/application/trainer/ lib/features/song_trainer/domain/models/loop_config.dart` → **üres kimenet** (nulla módosítás a transport/loop-config fájlokban). |
| 2 | **Loop-aggregáció** — N iteráció → egy összegzés/iteráció, hiányzó quality jelölve, nem eldobva | ✅ | `test/features/song_trainer/data/song_vision_adapter_test.dart:13-53` — 2 loop (`good`+`notObservable`), `summary.loops` hossza 2, a `notObservable` loop `quality` mezője megmarad (nem törlődik a listából). Harmadik teszt (82-115. sor): `audioOnly`/`visionDisabled` esetén is `hasLength(1)` — a loop megmarad, csak `quality=notObservable`-re áll. |
| 3 | **Thermal-fake mátrix** (normál/meleg/forró) — 2. cadence-t csökkent, 3. audio-only, egyik sem szakítja meg a dalt | ✅ | `transport_timing_parity_test.dart:33-69` — mindhárom cellára (`0`/`reducedCadenceThermalLoad`/`audioOnlyThermalLoad`) `expect(transport.state.phase, SongTransportPhase.playing)`, `expect(transport.state.backingStatus, BackingPlaybackStatus.playing)`, **plusz** `expect(player.pauseCalls, 0)` — a lejátszás-állapot explicit assertálva, nem csak hiba hiánya. |
| 4 | **Cadence-teszt** — determinisztikus, a határok mindkét oldala külön cella | ✅ | `test/features/vision/application/vision_cadence_policy_test.dart:8-27` — 6 külön cella: `0,39→full`, `40,79→reduced`, `80,100→audioOnly` (mindkét küszöb — 40 és 80 — mindkét oldala lefedve). Determinizmus külön tesztelve (40-45. sor: azonos bemenet → azonos kimenet, `==` összehasonlítással). |
| 5 | **Posture-küszöb** — alatt/rajta/fölött, „alatt" cellában hívásszámláló 0 | ✅ | `song_vision_adapter_test.dart:55-80` — 29s/30s/31s (`contract.minimumPostureSectionDuration=30s`). `postureCalls==1` összesen, és mivel `loops[2]` (31s, „fölött") az egyetlen nem-null `postureDrift`, a másik két cella (29s, 30s) matematikailag 0 hívást adott. **Forráskód-szinten is megerősítve**: `song_vision_adapter.dart:50-54` a `postureDriftFor(loop)` hívást egy ternary jobb ágába teszi (`condition ? postureDriftFor(loop) : null`), Dart short-circuit szemantika miatt a hívás fizikailag nem történik meg, ha a szakasz nem szigorúan hosszabb a minimumnál (`>`, nem `>=` — „fölött", nem „rajta vagy fölött", helyesen). |
| 6 | **Architektúra-őr zöld, allowlist nem bővült; l10n paritás zöld** | ✅ | Saját, közvetlen futtatás izolált klónban: `dart run tool/check_architecture.dart` → `Architecture dependencies OK (12 allowlisted deviation(s))`, EXIT 0. Ugyanez plain `origin/main`-en (külön klón, `/tmp/review-e05-r26-main-check`) → **szintén pontosan 12** — az allowlist változatlan. `git diff origin/main -- tool/check_architecture.dart` → 0 sor, a fájl bájtra érintetlen. `dart run tool/ci/check_l10n_parity.dart` → `L10n parity OK (en → hu, 1002 message(s))`, EXIT 0. |
| 7 | **Valódi-sértés próba** — cadence policy megkerülése (fix magas cadence) → thermal-mátrix „forró" cellája PIROS → visszaállítás | ✅ | **Saját reprodukció** (nem csak az implementer állítása): `vision_cadence_policy.dart` `audioOnlyThermalLoad` ágát `if (false && thermalLoad.value >= audioOnlyThermalLoad)`-ra rontva → `vision_cadence_policy_test.dart` 2 cellája (`80`, `100`) ÉS `transport_timing_parity_test.dart` „normal, warm and hot…" tesztje PIROSRA fordult (`Expected: VisionCadence.audioOnly, Actual: VisionCadence.reduced`); revert után `git diff --stat` üres. |
| 8 | **(pre-flight bővítés) Vision-barrel-boundary őr** — 2 cella + valódi-sértés próba | ✅ (ld. F1 is) | **Saját reprodukció**: `export '../geometry/guitar_region.dart';` ideiglenes hozzáadása a szűk barrelhez → `vision_integration_barrel_boundary_test.dart` első cellája PIROSRA fordult (`Integration barrel must not export ../geometry/guitar_region.dart.`); revert után zöld. A 9 direkt export célja mind a nem-tiltott könyvtárakban él (`domain/integration/`, `application/`, `domain/metrics/`, `domain/quality/`, `domain/`) — ADR 0193 Döntés 5 tiltólistája ellen ellenőrizve, direkt export szinten megfelel. **De** ld. F1: az egyik re-exportált fájl (`posture_metrics.dart`) tranzitívan egy tiltott típust (`PoseLandmarkId`) is elérhetővé tesz — ezt a guard (és a szó szerinti brief-kritérium, ami csak a barrel SAJÁT export-sorait nézi) nem fogja el, de a kritérium betűje szerint (a barrel export-sorai nem céloznak tiltott könyvtárat) teljesül. |

## Scope-audit

```
git diff --name-only origin/main...codex/e05-r26-song-trainer-vision-integration
```

13 fájl, mind az (pre-flightban 12→15 elemre bővített) `allowed_paths`-on
belül — **0 kívüli fájl**:

- `docs/adr/0193-song-trainer-vision-integration-contract.md` (ÚJ)
- `docs/rounds/e05-r26-song-trainer-vision-integration.md`
- `lib/features/song_trainer/data/vision/song_vision_adapter.dart` (ÚJ)
- `lib/features/song_trainer/domain/models/song_vision_summary.dart` (ÚJ)
- `lib/features/vision/application/vision_cadence_policy.dart` (ÚJ)
- `lib/features/vision/domain/integration/public.dart` (ÚJ)
- `lib/features/vision/domain/integration/vision_song_contract.dart` (ÚJ)
- `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`
- `test/features/song_trainer/data/song_vision_adapter_test.dart` (ÚJ)
- `test/features/song_trainer/performance/transport_timing_parity_test.dart` (ÚJ)
- `test/features/vision/application/vision_cadence_policy_test.dart` (ÚJ)
- `test/features/vision/domain/integration/vision_integration_barrel_boundary_test.dart` (ÚJ)

`lib/features/song_trainer/public.dart` és `lib/features/vision/public.dart`
engedélyezve voltak, de **nem lettek módosítva** (0-diff) — ez pontosan
egyezik az ADR 0193 saját mérésével („egyik sem szükséges ténylegesen ebben
a körben"). A `.codex-round-status` `scope_audit_changed=12` az
implementer-only diffre (`33b958e..5308958`, kizárva az ADR-fájlt, ami a
pre-flight commitban jött) vonatkozik — ez a szám egyezik, ha az ADR-fájlt
levonjuk a fenti 13-ból; nincs ellentmondás.

**Tiltott zóna ellenőrizve, tiszta:** `lib/core/audio/` — nincs találat a
diffben; `lib/features/practice/` — nincs találat; `tool/check_architecture.dart` —
0-diff (fent); DSP-fájl — nincs.

## Architektúra + termékhatárok (AGENTS.md §5/§6)

- **Cross-feature import fegyelem:** a `song_trainer` új fájljai kizárólag
  `vision/domain/integration/public.dart`-ot importálják, sosem a wide
  `vision/public.dart`-ot — ellenőrizve grep-pel ÉS a gépi
  `vision_integration_barrel_boundary_test.dart` (b) cellájával, ÉS saját
  reprodukcióval (F1/AC8).
- **Erőforrás-lifecycle:** N/A — `VisionCadencePolicy.decide()` és
  `SongVisionAdapter.aggregate()` mindketten tiszta, szinkron függvények;
  egyik új fájlban sincs `StreamSubscription`/`Timer`/isolate/mic/camera/
  wakelock — nincs mit felszabadítani, nincs lifecycle-kockázat.
- **Nincs raw media / landmark / geometry / koordináta expozíció az ÚJ
  song_trainer fájlokban** — grep 0 találat `Camera|Landmark|Normalized|
  dart:io|MethodChannel` mintákra a 2 új song_trainer produkciós fájlban.
- **Nincs hálózat/persistence/permission/secret felület** — grep 0 találat
  `http|Dio|SharedPreferences|dart:io|File\(|permission_handler|print\(|
  token|secret|password|apiKey` mintákra a route 5 új production fájlban;
  `pubspec.yaml`/`pubspec.lock`/`android/`/`ios/` diffje üres (`native_gate
  = false` indokolt). `dart run tool/ci/check_secrets.dart` → `Secret scan OK
  (2042 file(s) scanned, 0 finding(s))`.
- **Nincs confidence-túlállítás** — az új `songVisionLoopQualityUnavailable`
  szöveg („Visual quality was unavailable… Audio scoring is unchanged")
  hiányt jelez, nem állít bizonyosságot; ez összhangban van §5 #5-tel.

## Megállapítások

### F1 — MINOR — A szűk barrel tranzitívan elérhetővé tesz egy tiltott `domain/landmarks/` típust a `posture_metrics.dart` blanket exportján át

- **Fájl:** `lib/features/vision/domain/integration/public.dart:1-4` (doc-comment: „This deliberately excludes landmark, geometry, provider and presentation types") és `:12` (`export '../metrics/posture_metrics.dart';`, nincs `show` korlátozás); `lib/features/vision/domain/metrics/posture_metrics.dart:38` (`import '../landmarks/pose_landmarks.dart';`), `:132` (`final Set<PoseLandmarkId> requiredPoseLandmarkIds;`), `:156` (`postureMetricDefinitions` publikus top-level katalógus-konstans).
- **Probléma:** `PoseLandmarkId` az ADR 0193 Döntés 5 saját, tételes tiltólistáján szerepel (`domain/landmarks/` alá eső enum). A szűk barrel `export`-sorai közvetlenül soha nem célozzák a `domain/landmarks/` könyvtárat (ezt a `vision_integration_barrel_boundary_test.dart` helyesen ellenőrzi és zöldre hozza), **de** az egyik re-exportált fájl (`posture_metrics.dart`) blanket exporttal (nincs `show` kulcsszó) kerül a barrelbe, és ANNAK publikus felülete (`PostureMetricDefinition.requiredPoseLandmarkIds`, illetve maga a `postureMetricDefinitions` lista) `PoseLandmarkId` értékeket hordoz. Saját, futtatott próbateszttel igazoltam (ld. lent), hogy egy fájl, ami KIZÁRÓLAG a szűk barrelt importálja — sosem `pose_landmarks.dart`-ot —, ki tudja olvasni a valódi landmark-neveket (`leftShoulder`, `rightShoulder`, …) a `.name` getteren át. A barrel doc-commentjének „deliberately excludes landmark… types" állítása ezért **nem teljesen pontos**.
- **Saját reprodukció (mérve, nem csak olvasva):** ideiglenes teszt-fájl
  (`test/features/vision/domain/integration/_reviewer_probe_barrel_leak_test.dart`,
  törölve a mérés után), ami KIZÁRÓLAG
  `package:strumsight/features/vision/domain/integration/public.dart`-ot
  importálja:
  ```dart
  final def = postureMetricDefinitions.first;
  final names = def.requiredPoseLandmarkIds.map((l) => l.name).toList();
  ```
  Futtatva: `flutter test` → **PASS**, kimenet
  `LEAK-PROBE requiredPoseLandmarkIds names: [leftShoulder, rightShoulder]` —
  vagyis a tiltott enum ÉRTÉKEI (nem a típusneve) ténylegesen kiolvashatók a
  szűk barrelen keresztül, `pose_landmarks.dart` közvetlen importja nélkül.
  A többi 8 re-exportált fájlt (`vision_practice_contract.dart`,
  `vision_song_contract.dart`, `vision_cadence_policy.dart`,
  `metric_definition.dart`, `picking_metrics.dart`, `vision_frame_quality.dart`,
  `vision_session_result.dart` és tranzitívan `calibration_loss_machine.dart`/
  `insight_code.dart`/`vision_evidence.dart`/`vision_quality_summary.dart`)
  végigolvastam — ez az EGYETLEN tranzitív rés (pl. `VisionSessionResult.
  calibrationState` típusa `CalibrationLossState`, ami önmagában zárt enum,
  nem hordoz geometria-típust, annak ellenére, hogy a deklaráló fájl
  `calibration_loss_machine.dart` importál `domain/geometry/`-t).
- **Hatás:** Ebben a körben **nem kihasznált** — a 4 új song_trainer/vision
  produkciós fájl egyike sem hivatkozik `postureMetricDefinitions`-re vagy
  `PostureMetricDefinition`-re (grep-pel megerősítve). A kiszivárgó adat egy
  **statikus, fordítás-idejű, session-független katalógus** (landmark-NÉV
  enum, nem koordináta/frame/pixel) — nem AGENTS §5 termékhatár-sértés (nincs
  nyers kamera-frame, nincs per-session adat). Ugyanez az elérhetőség MA IS
  fennáll a wide `vision/public.dart`-on át (változatlan, nem ebben a körben
  keletkezett).
- **Keresztellenőrzés:** a dedikált security-review
  ([`docs/reviews/e05-r26-song-trainer-vision-integration-security.md`](e05-r26-song-trainer-vision-integration-security.md),
  NOTE-1) **függetlenül, ugyanezt a tényt** azonosította („reachable-graph
  deep read"), és biztonsági szempontból NOTE-ra minősítette — érvelésük
  (statikus katalógus, session-független, nem koordináta-adat, gyengébb mint
  az előzmény E05-R25 MINOR-1) helytálló, és **egyetértek** azzal, hogy ez
  NEM privacy/security kockázat. Ebben a jelentésben mégis **MINOR**-ként
  tartom nyilván (nem NOTE-ként), mert (a) a barrel doc-commentje ma
  ténylegesen pontatlan állítást tesz, (b) a kör saját, kifejezetten erre a
  garanciára írt gépi őre (AC8) a teljes állítást nem fedi le, és (c) a fix
  olcsó és a jelen `allowed_paths`-on belüli.
- **Javasolt irány (NEM kész patch):** `show` kombinátor hozzáadása a barrel
  export-soraihoz, a ténylegesen fogyasztott szimbólumokra szűkítve (ma
  egyik song_trainer fájl sem használ `PostureCapability`-n kívül semmit a
  `posture_metrics.dart`-ból, és még azt sem — a `vision_practice_contract.dart`
  szimmetria-célból importálja). Rendszerszintű alternatíva (már ADR 0193
  „Elutasított alternatívák" + `docs/LESSONS.md` L190 által egy jövőbeli
  dedikált architektúra-körre halasztva): a boundary-teszt kiterjesztése a
  tranzitív mező-típus-gráfra, nem csak a barrel saját export-sorira.
- **Ellenőrzés:** a fenti probe-teszt (jelen jelentésben dokumentálva,
  törölve) újra futtatható a `show`-javítás UTÁN — akkor `postureMetricDefinitions`
  többé nem lesz elérhető a szűk barrelen át, a próba analyzer-hibával
  bukna (`postureMetricDefinitions` undefined).
- **Státusz:** **CLOSED — javítva a javító kör #1-ben (`d5698e0`,
  2026-08-08).** A fix pontosan a javasolt irány: `export '../metrics/
  posture_metrics.dart' show PostureCapability;` — a `PostureMetricDefinition`/
  `postureMetricDefinitions` (a tranzitív `PoseLandmarkId`-forrás) többé nem
  érhető el a szűk barrelen át. **Saját, független verifikáció** (nem csak az
  implementer állítása): friss `/tmp/review-e05-r26-fix1` klón a fixer-commit
  SHA-ján; a review saját próbateszt-mintáját (F1 fenti kódrészlete)
  reprodukáltam `_verify_probe_test.dart` néven (IGNORE-kommentár NÉLKÜL,
  mert egy első próbálkozásom véletlenül elnyomta volna a hibát) —
  `flutter analyze` eredmény: `error • Undefined name
  'postureMetricDefinitions' … • undefined_identifier` — a leak megerősítve
  zárva. Teljes gate újra lefuttatva ugyanebben a friss klónban: mind a 7
  lépés ZÖLD (`test test/features/vision` **533** teszt — ez a hiteles szám;
  a fenti gate-bizonyíték szakasz „338"-as említése ennek a jelentésnek egy
  korábbi, pontatlan önmérése volt, a verdiktet nem érintette, mert minden
  lépés akkor is ZÖLD volt).

### F2 — NOTE — Az új ARB-kulcs egyelőre egyetlen widgetből sem hívott

- **Fájl:** `lib/l10n/app_en.arb:1361`, `lib/l10n/app_hu.arb:1284` —
  `songVisionLoopQualityUnavailable`.
- **Megfigyelés:** a brief §3 „Benne" listája említi „a result-UI
  loop-onkénti vision-quality jelzését" mint kör-scope-ot, de egyetlen
  presentation-réteg fájl sincs az `allowed_paths`-on (sem az eredeti, sem a
  pre-flight-bővített listán) a song_trainer oldalon — így az implementer
  NEM köthette be ténylegesen egy result-képernyőbe (scope-on kívüli lett
  volna). A kulcs ma kizárólag a generált `app_localizations*.dart`
  fájlokban létezik, éles widget-hívás nélkül (grep megerősítve).
- **Hatás:** nincs — az l10n-paritás gate kulcsonként, nem hívottság szerint
  ellenőriz; nem build- vagy teszthiba. Pontosan ugyanaz a minta, mint az
  E05-R25 review N1 megállapítása (`practiceVisionDimensionUnavailable`).
- **Javasolt irány:** nem blokkoló; a következő (result-UI-t ténylegesen
  bekötő) kör brief-jébe érdemes felvenni a tényleges widget-fogyasztást, és
  a §3 megfogalmazását pontosítani, hogy csak a domain-modell/string
  előkészítése történt, nem a UI-bekötés.
- **Státusz:** OPEN (nem blokkol, follow-up).

### F3 — NOTE — `VisionMetricState.needsImprovement` nincs külön tesztcellával lefedve az adapterben

- **Fájl:** `lib/features/song_trainer/data/vision/song_vision_adapter.dart:49`
  (`final hasSufficientQuality = loop.quality == VisionMetricState.good;`);
  `test/features/song_trainer/data/song_vision_adapter_test.dart` (mindhárom
  teszt csak `good` és `notObservable` értékeket használ).
- **Megfigyelés:** a harmadik `VisionMetricState` érték
  (`needsImprovement`) ugyanazt a logikai ágat futtatja, mint
  `notObservable` (mindkettő megbukik a `== good` feltételen), és a `quality`
  mező helyesen megőrződik (nincs kód-ág, ami felülírná) — forráskód-olvasással
  megerősítve, hogy a viselkedés helyes. Nincs azonban dedikált teszt-cella,
  ami ezt explicit bizonyítaná.
- **Hatás:** alacsony kockázat — a megosztott branch-et a `notObservable`
  eset már lefedi.
- **Javasolt irány:** egy harmadik `_loop(quality: VisionMetricState.
  needsImprovement)` variáns hozzáadása a meglévő táblázatos tesztekhez egy
  jövőbeli körben.
- **Státusz:** OPEN (nem blokkol, follow-up).

### F4 — NOTE — A posture-küszöb „alatt" cellájának 0-hívás bizonyítéka közös számlálón át indirekt

- **Fájl:** `test/features/song_trainer/data/song_vision_adapter_test.dart:55-80`.
- **Megfigyelés:** a teszt egyetlen megosztott `postureCalls` számlálóval
  méri mindhárom cellát (`below`/`at`/`above`) együtt, és csak az összesített
  `postureCalls==1`-et állítja. A brief §6 explicit „hívásszámláló 0" a
  „alatt" cellára vonatkozik — ez a jelen tesztből csak levezetve (nem
  közvetlenül) igaz: mivel a nem-null `postureDrift` bizonyíthatóan a
  „fölött" loophoz tartozik, a másik két cella együtt 0 hívást adott.
  Forráskód-olvasással (ternary short-circuit, ld. AC5 fent) függetlenül
  megerősítettem, hogy ez helyes és nem véletlen egybeesés.
- **Hatás:** nincs funkcionális kockázat — inkább a teszt olvashatóságát/
  közvetlenségét érintő észrevétel.
- **Javasolt irány:** izolált számláló minden cellához (vagy 3 külön teszt)
  egy jövőbeli finomításban, hogy az AC5 „hívásszámláló 0" állítása
  közvetlenül, cellánként legyen leolvasható.
- **Státusz:** OPEN (nem blokkol, follow-up).

## Gate-bizonyíték (saját kézzel, izolált `/tmp/review-e05-r26` klónban)

```
═══ Gate-összegzés
    format                                                       zöld
    analyze                                                      zöld
    test test/features/song_trainer                              zöld
    test test/features/vision                                    zöld
    architecture                                                 zöld
    secrets                                                       zöld
    l10n                                                          zöld

MINDEN GATE ZÖLD.
```

`test test/features/song_trainer`: `+471 ~1` (`All tests passed!`).
`test test/features/vision`: `+338 ~2` (`All tests passed!`) — a teljes
`test/features/vision/` fa, tehát az E05-R01…R25 vision-tesztek is
újra-validálva, nem csak az ezen körben újak.

A gate-et háttérfolyamatként (nohup+wait-loop) futtattam, ezért a formális
kilépési kód közvetlen elkapása helyett a log tartalmát mértem: a script
kizárólag a 0-kilépési ágon nyomtatja ki a záró „MINDEN GATE ZÖLD…" sort (a
forrás szerint közvetlenül `write_result "pass" 0 "" 0 ""` előtt), és a
teljes 1222 soros logban egyetlen PIROS jelzés sincs. Hogy ne csak erre a
következtetésre támaszkodjak, az `architecture`, `secrets` és `l10n`
lépéseket **közvetlenül, külön is lefuttattam**, közvetlenül elkapott
kilépési kóddal: `ARCH_EXIT:0`, `SECRETS_EXIT:0`, l10n `EXIT:0` — mindhárom
megerősíti a log alapján levont következtetést.

**Reprodukált valódi-sértés próbák** (mindegyik: rontás → PIROS →
`git diff --stat` üres a revert után):

1. Tiltott export (`../geometry/guitar_region.dart`) a szűk barrelbe →
   `vision_integration_barrel_boundary_test.dart` 1. cellája PIROS.
2. Cadence-küszöb megkerülése (`audioOnlyThermalLoad` ág `if (false && …)`) →
   `vision_cadence_policy_test.dart` 2 cellája + `transport_timing_parity_test.dart`
   thermal-tesztje PIROS.
3. (Saját kezdeményezés, F1) Szűk-barrel-only import próba, ami kiolvassa a
   `postureMetricDefinitions`-t → sikeresen lefut, bizonyítva a tranzitív
   elérhetőséget (ld. F1 részletei).

## CI-bizonyíték

- **Full Gate (no APK)** — [run 31266849535](https://github.com/wolfcasaba/strumsight/actions/runs/31266849535),
  **success**, `headSha=5308958df8f0d9db6f0949415dfdaf422fc216c9` (egyezik a
  branch tippel). Jogos gate-választás: `native_gate=false`, nincs
  `pubspec`/`android`/`ios`/`assets` diff → AGENTS.md §12 döntési szabálya
  szerint `full-gate.yml`, nem `build-apk.yml`.
- Property gate: **mindkét** seed lefutott a logban —
  `PROPERTY_SEED=42` (determinisztikus dev-loop) ÉS `PROPERTY_SEED=31266849535`
  (== a run ID, a dokumentált HARD-lépés randomizált seedje) — a teljes
  suite valóban mindkét móddal lefutott, nem csak a determinisztikussal.
- **Router CI** — ugyanazon a SHA-n, **success**.
- PR: [#200](https://github.com/wolfcasaba/strumsight/pull/200), `base=main`,
  `mergeable=MERGEABLE`, törzse pontos és nem tulajdonít nem-futtatott
  evidenciát (a „independent review… in progress" sor korrekt volt e
  jelentés megírásáig).

## Dedikált security-review (risk = "high")

[`docs/reviews/e05-r26-song-trainer-vision-integration-security.md`](e05-r26-song-trainer-vision-integration-security.md)
— **PASS**, 0 CRITICAL/BLOCKER/MAJOR/MINOR, 1 NOTE, saját izolált `/tmp`
klónban futtatott gate-tel és próbákkal, függetlenül ettől a jelentéstől.
A security-review NOTE-1 tétele **ugyanazt a tranzitív `PoseLandmarkId`
elérhetőséget** írja le, mint ez a jelentés F1-je (a kettőt egymástól
függetlenül, két különböző módszerrel találtuk meg — én egy futtatott
probe-teszttel, ők statikus gráf-bejárással) — a tényállás **megerősítve
kétszer**, a súlyosság-értékelés (biztonsági szempontból NOTE, ebben a
jelentésben dokumentum-pontosság/karbantarthatóság szempontból MINOR) a
fent leírtak szerint tér el, de egyik sem blokkoló.

> Megjegyzés: a security-review fájl elején egy orchesztrátori bejegyzés
> rögzíti, hogy a security-reviewer ágens a leletlistát a válaszába ágyazva
> adta vissza a fájl közvetlen megírása helyett — ez folyamat-eltérés, nem a
> tartalom hitelességét érintő probléma; a tartalmat én magam is
> keresztellenőriztem (F1), és megbízhatónak találtam.

## Javító kör #1 (2026-08-08, F1 zárása)

Egyetlen, szűken kiosztott javító kör (`d5698e0`): `lib/features/vision/
domain/integration/public.dart` `posture_metrics.dart` exportja `show
PostureCapability`-ra szűkítve. Saját, független verifikáció fent (F1
„Státusz" sora) — friss `/tmp/review-e05-r26-fix1` klón, a review saját
próbatesztje reprodukálva (most már analyzer-hibával bukik), teljes gate
újrafuttatva, mind a 7 lépés ZÖLD. A javítás nem érintett más fájlt, csak a
brief §10 handoffját (implementer-oldali dokumentáció). Scope-audit a
fixer-commitra is tiszta (`scope_audit=ok`, `scope_audit_changed=2` —
pontosan a barrel-fájl + brief).

## Végső verdikt

**APPROVED, 0 nyitott BLOCKER/MAJOR/MINOR.** Mind a 8 acceptance criterion
saját, futtatott bizonyítékkal teljesült; a scope-audit tökéletes (13/13
implementációs fájl + a javító kör 2 fájlja az engedélyezett listán, 0
kívüli változás); a gate mind a 7 lépése zöld **két külön izolált klónban**
(az eredeti implementáció után ÉS a javító kör után is újrafuttatva); 3
valódi-sértés próbát saját kézzel reprodukáltam az eredeti körben (2 kért +
1 saját kezdeményezésű, ami F1-et feltárta) + 1-et a javító kör után (a
próba most már analyzer-hibával bukik, bizonyítva a zárást). Az egyetlen
MINOR (F1) **zárva**; a 3 NOTE egyike sem érinti a §6 acceptance-et vagy a
mai viselkedést, mindhárom dokumentált follow-up. F1-et egy független,
dedikált security-review is megvizsgálta és biztonsági szempontból
nem-blokkolónak (NOTE) minősítette — a security-review a javító kör előtti
állapotot értékelte, de a NOTE-1 érvelése (statikus, session-független
katalógus, nincs koordináta-adat) a javítással immár tárgytalanná is vált
(a szimbólum többé nem érhető el). CI (az eredeti implementáción): Full Gate
[31266849535](https://github.com/wolfcasaba/strumsight/actions/runs/31266849535)
**success** (mindkét property-seed móddal) + Router CI **success**, mindkettő
az akkori tip `5308958`-on — a javító kör `d5698e0` commitja miatt az
orchestrátor ÚJRA dispatch-eli mindkettőt a pontos merge-előtti tipre
merge előtt (ADR 0086 §2). `tool/check_architecture.dart` bájtra érintetlen,
az allowlist mérete (12) változatlan mind `main`-en, mind a branchen. Mehet
a squash-merge, amint az újra-dispatch-elt CI zöld a `d5698e0` SHA-n.
