# E05-R14 — Pose landmark provider és posture baseline

- **Státusz:** PLANNING (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`;
  pre-flight revízió és ADR 2026-08-07, kód mérve: `main` @ `c9d9b4d`, E05-R09/
  R12/R13 merge után)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 14; §16, §30
- **Branch:** `minimax/e05-r14-pose-provider-and-posture-baseline`
- **Előfeltétel:** **E05-R09, E05-R12 merge** — ✅ teljesítve (mindkettő MERGED, E05-R13 is azóta)
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3 (kör-táblázat
  szerinti kiosztás, 2026-08-07)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/landmarks/pose_landmarks.dart",
  "lib/features/vision/domain/landmarks/posture_baseline.dart",
  "lib/features/vision/data/landmarks/pose_landmark_provider.dart",
  "lib/features/vision/data/landmarks/native_pose_landmark_provider.dart",
  "lib/features/vision/data/landmarks/recorded_pose_landmark_provider.dart",
  "lib/features/vision/public.dart",
  "assets/ml/model_manifest.json",
  "lib/core/ml/vision_model_manifest.dart",
  "ml/make_manifest.py",
  "test/features/vision/domain/posture_baseline_test.dart",
  "test/features/vision/data/pose_landmark_provider_test.dart",
  "test/features/vision/data/pose_privacy_audit_test.dart",
  "test/tooling/ml_asset_manifest_test.dart",
  "docs/adr/0186-vision-pose-landmark-inference-stack.md",
  "docs/rounds/e05-r14-pose-provider-and-posture-baseline.md",
]
gate_tests = [
  "test/features/vision",
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ, ELVÉGEZVE — ld. §0.0):** `origin/main` + E05-R09/R12
> merge ✅ (E05-R13 is azóta merge-elt); az R12 manifest-sémáját, fail-closed
> init-szabályát és az R09 quality-gate-jét újraolvasva. **ADR 0186** (a
> fejlécben szereplő „0161/0168 bővítése" terv NEM tartható — ld. §0.0 R1).
> PLANNING, ez a pre-flight commit a kör indítása előtt.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING → mérve `origin/main` @ `c9d9b4d` (E05-R13 MERGED), hét mért
revízió.** Az eredeti PREPARED szöveg 2026-08-05-én íródott, mielőtt az
E05-R09/R12/R13 kód létezett volna — pontosan az a minta, amit az E05-R04/R08/
R11/R12 pre-flightok is mértek (`docs/LESSONS.md` L143/L147).

1. **R1 — a fejléc „Nincs ÚJ ADR (0161/0168 bővítése)" terve NEM tartható; ADR
   szükséges, kiosztva `tools/round-slots.py reserve-adr --round E05-R14` ⇒
   `0186`.** A kör három, architekturálisan új felszínt vezet be, összemérhető
   súlyban azzal, amiért az E05-R12 saját ADR-t kapott (0185): (a) egy MÁSODIK,
   párhuzamos landmark-provider-család a saját stabil ID-topológiájával; (b) a
   megosztott manifest-validátor **mérten szükséges** általánosítása (R3); (c) a
   privacy-audit mint a kör kulcsbizonyítéka — ez konkrét, kör-specifikus
   döntés (mely pontok maradnak meg), nem csak az ADR 0178 elvének
   megismétlése. Az [`docs/adr/0186-vision-pose-landmark-inference-stack.md`](../adr/0186-vision-pose-landmark-inference-stack.md)
   megírva (orchestrátor, pre-flight, ADR 0055) — az ADR 0178-at (adatminimalizálás)
   és az ADR 0185-öt (provider/manifest-minta) terjeszti ki, nem ír felül
   egyiket sem.
2. **R2 — stale ADR-hivatkozás: minden „ADR 0161" a briefben `ADR 0178`-ra
   cserélve.** A `docs/LESSONS.md` L147 mért, megerősített leképezése szerint
   (2026-08-06, az E05-R01 tényleges ADR-átszámozásából): a batch-brief-ek
   eredetileg tervezett `0161–0166` blokkja ténylegesen `0178–0183`-ra tolódott;
   `0161→0178` = [`vision-privacy-by-default`](../adr/0178-vision-privacy-by-default.md).
   Ez PONTOSAN az adatminimalizálási elv, amit a brief §5 pont 1 idéz — az ADR
   tartalma (elolvasva) megerősíti: „A kamerakép feldolgozása kizárólag a
   készüléken történik… Raw frame nem kerül hálózatra". A „0168" a fejléc
   eredeti tervében a hetedik/nyolcadik vision-ADR helyőrzője volt, amely
   ténylegesen [`0185`](../adr/0185-vision-hand-landmark-inference-stack.md)-re
   lett (a hand-landmark-inference-stack, ugyanaz a provider/manifest minta,
   amit ez a kör másodszor alkalmaz) — a fejléc erre már **0186**-ra mutat
   (R1), mert ennek a körnek saját ADR-je lett, nem pusztán 0185 bővítése.
3. **R3 — a `assets/ml/model_manifest.json` additív pose-bejegyzése a JELENLEGI
   kód mellett NEM tud átmenni a validátoron; `allowed_paths` három fájllal
   bővült, mérve, nem feltételezve.** Két, egymástól független, kőbe vésett
   egyszeresség:
   - `lib/core/ml/vision_model_manifest.dart:205-211` — `if (outputSchema !=
     handLandmarksOutputSchema)` egyetlen elfogadott sémaértéket ismer; egy
     `pose_landmarker` bejegyzés `strumsight.pose_landmarks.v1` sémával ezen
     azonnal `issues.add(...)`-ot kapna.
   - `test/tooling/ml_asset_manifest_test.dart:106-110` — `hasLength(1)`,
     indoklás a tesztben szó szerint: `"one deferred vision model expected"`.
     Egy második bejegyzés hozzáadása ezt azonnal pirosra vinné, FÜGGETLENÜL
     attól, hogy a validátor elfogadná-e a sémát.
   Mindkettő azért hardkódolt egyre, mert az E05-R12 pre-flightjában csak EGY
   modellcsalád létezett — nem szándékos, örök egy-modelles korlát (a
   validátor-fájl saját kommentje: „a jövőbeli aktiváló kör bővítheti újabb
   modellekkel"). A generátor (`ml/make_manifest.py` `_VISION_MODEL_SPECS`,
   sor 202-217) a shipped JSON **egyetlen forrása** — kézi JSON-szerkesztés a
   generátor megkerülése lenne. **Ezért `allowed_paths` három fájllal bővült:**
   `lib/core/ml/vision_model_manifest.dart`, `ml/make_manifest.py`,
   `test/tooling/ml_asset_manifest_test.dart` — pontosan ugyanaz a három fájl,
   amit az ADR 0185 saját köre, az E05-R12 is `allowed_paths`-on tartott,
   ugyanezért az okért (első vision-manifest-bejegyzés). Ez additív bővítés
   (a §0.0-nak dokumentált mérésből, nem az implementer utólagos kérése) —
   MINDEN meglévő `hand_landmarker`-validáció és a hozzá tartozó hat
   mutáció-teszt bitre változatlanul zöld marad; a pontos elvárt kódalakot
   [ADR 0186 Döntés 2](../adr/0186-vision-pose-landmark-inference-stack.md) írja
   le. Elvetett alternatívák (miért nem elég a fájllistát változatlanul
   hagyni): (a) a pose bejegyzés a MEGLÉVŐ `handLandmarksOutputSchema`
   értékkel — hamis manifest-metaadat, elvetve; (b) a manifest-bejegyzés
   elhagyása ebben a körben — ellentmond a §4/§5.6 saját követelményének és az
   SDD Kör 14 feladatlistájának.
4. **R4 — a `PoseLandmarkId` pontos, 9 tagú halmaza kimondva (ADR 0186 Döntés
   1), nem az implementer választására bízva.** `leftShoulder`/`rightShoulder`,
   `leftElbow`/`rightElbow`, `leftWrist`/`rightWrist`, `leftHip`/`rightHip`,
   `neckReference` (a legfeljebb egy semleges fej/nyak-referenciapont). A
   `left`/`right` a személy FIZIKAI oldalát jelöli (a `Handedness`-konvenció és
   az R07 nem-tükrözött bemenet-garancia szerint), nem kamera-relatív oldalt.
   Szem/orr/száj/fül ID **nem létezik** ebben az enumban — ha a provider ilyet
   ad, a mapping eldobja (§6 mapping-teszt + privacy-audit teszt erre pinnel).
5. **R5 — a bemenet-típusok (`VisionImage`, `HandLandmarkTimestamp`,
   `VisionDeviceTier`) ÚJRAFELHASZNÁLTAK, nem újradefiniáltak.** Mérve:
   `lib/features/vision/data/landmarks/hand_landmark_provider.dart:37-125`
   már definiálja mindhármat, és ez a fájl NINCS ezen a listán (nem is kell —
   csak import, nem módosítás). A `PoseLandmarkProvider.infer()` ugyanazt a
   `VisionImage`-et fogadja, amit a kéz-provider — egy kameraframe táplálhatja
   mindkét pipeline-t. Ne definiálj párhuzamos, majdnem-azonos típusokat.
6. **R6 — posture quality/drift modellek scope-határa (ADR 0186 Döntés 5).**
   A `posture_baseline.dart` a baseline collectort ÉS a nyers posture-quality/
   drift **megfigyelés-modelleket** tartalmazza (SDD Kör 14 feladatlista:
   „Készíts posture quality és drift observation modelleket") — ezek egyszerű,
   ítélet-mentes mértékek (pl. pontonkénti, baseline-hoz viszonyított
   normalizált delta), NEM posture safety policy vagy „jó/rossz testtartás"
   ítélet (az explicit E05-R20 dolga, §3 kizárás). Mindkét irányú hiba
   kockázat: a modellek teljes kihagyása (ellentmond az SDD feladatlistának)
   és a policy-réteg túlépítése (scope-sértés) egyaránt hiba.
7. **R7 — a „kikapcsolás-teszt" egy sima Dart-függvény szintjén mérhető, NEM
   Riverpod-wiring szintjén.** `visionPoseTrackingEnabled`
   (`lib/app/config/feature_flags.dart:24`, default `false` — mérve, létezik)
   egy `FeatureFlags` mező; a tényleges Riverpod-bekötés (mely réteg olvassa a
   flaget és dönt a példányosításról) egy KÉSŐBBI kör dolga (E05-R24, vision
   session controller) — `allowed_paths`-on nincs `application/*provider*.dart`
   fájl, ahogy az E05-R12 hand-oldali köre sem kapott ilyet. A §6
   „kikapcsolás-teszt" tehát egy plain factory-függvény szintjén bizonyítandó
   (pl. `pose_landmark_provider.dart`-ban, a flaget paraméterként kapva) —
   ugyanaz a minta, mint ahogy a `NativeHandLandmarkProvider` sem ismeri a
   `visionHandTrackingEnabled` flaget, csak a manifest-státuszt.

## 1. Cél

**Adatminimalizált** felsőtest-pose pipeline (arcelemzés nélkül), alacsonyabb
cadence-en, és személyes **posture baseline**, amely kizárólag jó setup-quality
és stabil frame mellett készülhet.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R12 kész: manifest-séma checksummal/licenccel, fail-closed init,
  rögzített-kimenetű adapter mint CI-út. A pose ugyanezt a mintát követi.
- Az R09 kész: `VisionFrameQuality` + ablakos summary — ez a baseline kapuja.
- Nincs pose-modell a repóban; a `visionPoseTrackingEnabled` flag OFF (R03).

## 3. Scope

**Benne:** `PoseLandmarks` **szűkített** ponthalmazzal, `PoseLandmarkProvider`
+ production és rögzített adapter, cadence-szabályozás (a kéz-modellnél
ritkábban), visibility gate, `PostureBaseline` collector ablak, posture quality
és drift observation modellek, manifest-bejegyzés, privacy-audit teszt.

**Kívül — TILOS:** posture metrikák és safety policy (R20), fusion (R22),
UI, arcfelismerés bármely formája, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/landmarks/pose_landmarks.dart` | ÚJ | szűkített pose modell |
| `.../domain/landmarks/posture_baseline.dart` | ÚJ | baseline collector |
| `.../data/landmarks/pose_landmark_provider.dart` | ÚJ | interfész |
| `.../data/landmarks/native_pose_landmark_provider.dart` | ÚJ | production adapter |
| `.../data/landmarks/recorded_pose_landmark_provider.dart` | ÚJ | fixture-adapter |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `assets/ml/model_manifest.json` | meglévő | **additív** pose bejegyzés |
| `lib/core/ml/vision_model_manifest.dart` | meglévő | §0.0 R3 — output-schema-ellenőrzés általánosítása egyre-hardkódoltról modell-id-kulcsolt regisztrációra; a `hand_landmarker` ág változatlan |
| `ml/make_manifest.py` | meglévő | §0.0 R3 — `_VISION_MODEL_SPECS` második (pose) tuple-je, a shipped manifest egyetlen forrása |
| `test/tooling/ml_asset_manifest_test.dart` | meglévő | §0.0 R3 — `hasLength(1)`→`hasLength(2)`; a hat meglévő hand-mutáció-cella változatlan marad |
| `docs/adr/0186-vision-pose-landmark-inference-stack.md` | ÚJ | §0.0 R1 — az ADR, amit ez a pre-flight írt |
| `test/features/vision/*` | ÚJ | mapping + baseline + privacy tesztek |
| `docs/rounds/e05-r14-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; audio modellfájlok; `docs/rag`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Adatminimalizálás ([ADR 0178](../adr/0178-vision-privacy-by-default.md), §0.0
   R2 — a fejléc eredeti „ADR 0161" jelölése erre cserélve):** kizárólag váll,
   könyök, csukló, csípő és **legfeljebb egy** semleges fej-referenciapont (pl.
   nyakpont) tárolható. **NEM elfogadható:** szem/orr/száj/fül landmark
   tárolása, logolása vagy továbbadása — akkor sem, ha a modell kiadja. A
   modell kimenetét a mapping **eldobja**, nem a fogyasztó. A pontos, 9 tagú
   `PoseLandmarkId` halmazt (`leftShoulder`/`rightShoulder`,
   `leftElbow`/`rightElbow`, `leftWrist`/`rightWrist`, `leftHip`/`rightHip`,
   `neckReference`) [ADR 0186 Döntés 1](../adr/0186-vision-pose-landmark-inference-stack.md)
   pinneli — ez a kör NEM tervezhet ettől eltérő ID-topológiát.
2. **Nincs arcfelismerés, nincs identitás-jellemző** — sem számított
   embedding, sem arc-crop. **NEM elfogadható** „debug célú" kivétel.
3. **A pose külön leállítható** (`visionPoseTrackingEnabled`, mérve:
   `lib/app/config/feature_flags.dart:24`, default `false`), és a
   kikapcsolása nem befolyásolja a kéz-pipeline-t. §0.0 R7: a gate egy plain
   factory-függvény szintjén mérendő — Riverpod-wiring nincs ezen a listán.
4. **Alacsonyabb cadence:** a pose futási gyakorisága konfigurált, és
   alapértelmezetten a kéz-modell **töredéke**; a cadence a device tier
   szerint tovább csökkenthető (R29). A bemenet-típus (`VisionImage` és
   társai) a kéz-oldali `hand_landmark_provider.dart`-ból **importált**, nem
   újradefiniált (§0.0 R5).
5. **Baseline csak valid körülményből:** jó quality (R09) + stabil frame +
   minimum látható időtartam. **NEM elfogadható:** részleges ablakból számolt
   baseline „hogy legyen valami" — ilyenkor nincs baseline, és a későbbi
   posture-observation `notObservable`. A posture-quality/drift
   megfigyelés-modellek nyers mértékek, NEM safety policy vagy testtartás-
   ítélet (§0.0 R6, ADR 0186 Döntés 5 — az az E05-R20 dolga).
6. **Fail-closed manifest** az R12 szabálya szerint; asset hiányában
   capability `unavailable`, `status = "deferred"` bejegyzéssel. A validátor
   és a generátor általánosítása additív — a meglévő `hand_landmarker` út
   bitre változatlan marad (§0.0 R3, ADR 0186 Döntés 2).

## 6. Acceptance criteria

- [ ] **Mapping-teszt:** a fixture provider-kimenet arc-pontjai a
      `PoseLandmarks`-ban **nem jelennek meg**; a megtartott pontok listája
      pontosan az engedélyezett halmaz.
- [ ] **Privacy-audit teszt (a kör kulcsbizonyítéka):** a `PoseLandmarks`
      szerializált alakja és a logolt mezők egy **rögzített, elvárt
      kulcshalmazzal** egyeznek; új mező csak a snapshot frissítésével kerülhet be.
- [ ] **Valódi-sértés próba (§10):** egy arc-landmark ideiglenes átengedése a
      mappingen → a privacy-audit teszt PIROS → visszaállítás.
- [ ] **Baseline-mátrix:** quality a küszöb **alatt / rajta / fölött** × látható
      időtartam a minimum **alatt / rajta / fölött** — a baseline csak a
      „rajta vagy fölötte" cellákban jön létre; a többiben `notObservable`.
- [ ] **Cadence-teszt:** N kéz-frame-re a pose-hívások száma a konfigurált
      arány szerinti (számmal), és a cadence állítása azonnal érvényesül.
- [ ] **Kikapcsolás-teszt:** `visionPoseTrackingEnabled = false` → a pose
      provider **nem példányosul**, a kéz-pipeline változatlan.
- [ ] **Manifest-teszt (§0.0 R3):** a shipped `assets/ml/model_manifest.json`
      `vision_models` tömbje **két** tiszta bejegyzést tartalmaz
      (`hand_landmarker` + `pose_landmarker`, mindkettő `status = "deferred"`,
      saját `output_schema`-val); a meglévő hat hand-mutáció-cella
      (`test/tooling/ml_asset_manifest_test.dart`) **változatlanul zöld**.

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A mapping egy arc-landmarkot (pl. orr) is átenged | Mapping-teszt + Privacy-audit teszt |
| A privacy-audit snapshot-ba belekerül egy új, nem-jóváhagyott mező | Privacy-audit teszt |
| A jump-rejection mintájára a baseline "gyenge jelből is" épül | Baseline-mátrix (quality alatta × duration bármi cella) |
| A cadence-arány módosítása csak újraindítás után hat | Cadence-teszt |
| A pose provider a flag ellenére példányosul | Kikapcsolás-teszt |
| A pose manifest-bejegyzés a hand `output_schema`-t (`strumsight.hand_landmarks.v1`) örökli | Manifest-teszt |
| A validátor-általánosítás melléktermékként elfogadja a hibás/hiányzó hand-checksumot | a hat meglévő hand-mutáció-cella (`ml_asset_manifest_test.dart`) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/tooling
```

Külön processzek, nincs `&&`/pipe/`tail`. A valós eszközös pose-latency és a
rövid thermal-mérés a device-mátrix **PENDING** sora.

## 8. Implementációs sorrend

1. RED: privacy-audit + mapping + baseline-mátrix.
2. `PoseLandmarks` (szűkített) + mapping.
3. Provider-ek + cadence.
4. Baseline collector + manifest; gate.

## 9. Kockázatok

- **A modell arc-pontokat is ad**; ha a mapping „kényelemből" mindent átenged,
  a privacy-ígéret sérül — a privacy-audit teszt az egyetlen gépi őr.
- **A baseline túl szigorú** lesz, és sosem jön létre valós használatban; ezt
  a device-mátrix PENDING mérése deríti ki, a küszöb konfigurált marad.

**STOP:** arc-landmark tárolása, közös kéz/pose cadence vagy a baseline-kapu
lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** MiniMax M3 · **Branch:** `minimax/e05-r14-pose-provider-and-posture-baseline`

### 10.1 Fájlonkénti összefoglaló

| Fájl | Állapot | Mit tartalmaz |
|---|---|---|
| `lib/features/vision/domain/landmarks/pose_landmarks.dart` | ÚJ | `PoseLandmarkId` (pontosan a §0.0 R4 / ADR 0186 Döntés 1 szerinti 9 tag), `PoseLandmarkPoint`, `PoseObservability`, `PoseLandmarks` (`byId`/`presentIds`/`count`, `toAuditMap()` a pinnelt audit-felszín, `toString()` csak számokat logol), `RawPoseLandmark` + `mapRawPoseLandmarks()` a `poseLandmarkIdByRawName` allow-listával — minden nem allow-listás nyers név (arc-pontok) itt esik ki, mielőtt domain-objektum keletkezne |
| `lib/features/vision/domain/landmarks/posture_baseline.dart` | ÚJ | `PostureBaselineConfig` (duration + sample-count + numerikus quality-küszöb + per-landmark visibility + kötelező ID-k), `PostureBaseline` (átlagpontok, sampleCount, durationUs, shoulderSpan), `PostureBaselineCollector` (gate-bukás → ablak RESET, részleges ablakból nincs baseline), `PostureObservation` — NYERS, vállszélességgel normalizált per-pont drift, `maxDrift`/`meanDrift`, semmilyen ítélet/küszöb/coaching (ADR 0186 Döntés 5) |
| `lib/features/vision/data/landmarks/pose_landmark_provider.dart` | ÚJ | `PoseModelConfig`, `PoseLandmarkProvider` interfész, `defaultPoseCadenceEveryNthFrame = 6`, `CadenceLimitedPoseLandmarkProvider` wrapper (minden N. hívás megy le a delegálthoz; `everyNthFrame` setter azonnal érvényes), `createPoseLandmarkProvider(poseTrackingEnabled:…)` plain factory — kikapcsolt flagnél `null`, a delegált meg sem épül (§0.0 R7). `VisionImage`/`VisionDeviceTier` IMPORTÁLVA a `hand_landmark_provider.dart`-ból (§0.0 R5) |
| `lib/features/vision/data/landmarks/native_pose_landmark_provider.dart` | ÚJ | Fail-closed production adapter a `NativeHandLandmarkProvider` alakját követve: piszkos manifest / hiányzó bejegyzés / hand-séma a pose bejegyzésen / `status = deferred` → `AppResult.failure(mlModelLoad)`; `infer` init nélkül `mlInference` failure |
| `lib/features/vision/data/landmarks/recorded_pose_landmark_provider.dart` | ÚJ | CI-fixture adapter. A nyers payload SZÁNDÉKOSAN tartalmaz 7 arc-pontot (`recordedFaceLandmarkNames`), és a `mapRawPoseLandmarks`-on megy át — így a privacy-szűrő a mérce, nem egy külön teszt-ág. Fixture-ök: `fixtureUpperBody({offsetY})`, `fixtureFaceOnly`, `fixtureNoPose`, `fixtureFailure` |
| `lib/features/vision/public.dart` | meglévő | additív exportok (5 pose-fájl + `poseLandmarksOutputSchema`, `visionModelOutputSchemas`) |
| `lib/core/ml/vision_model_manifest.dart` | meglévő | §0.0 R3 / ADR 0186 Döntés 2: az `outputSchema != handLandmarksOutputSchema` egysoros ellenőrzés helyett `visionModelOutputSchemas` (`model_id → elvárt output_schema`) regisztráció; regisztrálatlan `model_id` elutasítva. A `hand_landmarker` út és a checksum/licenc/asset-ágak érintetlenek |
| `ml/make_manifest.py` | meglévő | `_VISION_MODEL_SPECS` második, additív tuple (`pose_landmarker`, `deferred`, placeholder sha256, saját `strumsight.pose_landmarks.v1` séma, `docs/eval/vision/pose_landmarker.md`) |
| `assets/ml/model_manifest.json` | meglévő | a GENERÁTORRAL újraírva (`python3 ml/make_manifest.py` → „wrote … 4 models, 2 vision models"); a diff tisztán additív: csak a pose bejegyzés 19 sora, a hand bejegyzés és a 4 audio modell bitre változatlan |
| `test/features/vision/data/pose_privacy_audit_test.dart` | ÚJ | a kör kulcsbizonyítéka (5 teszt) |
| `test/features/vision/data/pose_landmark_provider_test.dart` | ÚJ | mapping / cadence / kikapcsolás / fail-closed (16 teszt) |
| `test/features/vision/domain/posture_baseline_test.dart` | ÚJ | 3×3 baseline-mátrix + reset/interrupt + drift (19 teszt) |
| `test/tooling/ml_asset_manifest_test.dart` | meglévő | `hasLength(1)`→`hasLength(2)` + per-bejegyzés séma-ellenőrzés; három ÚJ cella (hand+pose együtt tiszta; pose örökölt hand-séma → piros; regisztrálatlan `model_id` → piros). A hat meglévő hand-mutáció-cella szövegében egyetlen karakter sem változott |

### 10.2 Acceptance — hol méri melyik teszt

| §6 pont | Mérő teszt |
|---|---|
| Mapping-teszt | `pose_landmark_provider_test.dart` → „every retained ID is queryable and face points are dropped"; `pose_privacy_audit_test.dart` → „PoseLandmarkId enum contains exactly the 9 retained points", „the raw-name allow-list maps onto retained IDs only" |
| Privacy-audit teszt | `pose_privacy_audit_test.dart` → „audit map key set matches the pinned snapshot" (pinnelt top-level + per-pont kulcsok) és „face landmarks … never reach the domain object, its serialized form, or its log form" (tiltott alszavak: eye/nose/mouth/ear/face/lip a JSON-ban ÉS a `toString()`-ben; a teszt külön ellenőrzi, hogy a fixture tényleg adott arc-pontot, tehát nem üresen zöld) |
| Valódi-sértés próba | Elvégezve — ld. §10.4 |
| Baseline-mátrix | `posture_baseline_test.dart` → 9 generált cella (quality 0.6/0.7/0.8 × duration 2s/3s/4s), baseline csak a 4 „rajta vagy fölötte" cellában; a többiben `baseline == null` ÉS `observe(...).state == notObservable` |
| Cadence-teszt | `pose_landmark_provider_test.dart` → „12 frames at 1:6 delegate exactly 2", „12 frames at 1:3 delegate exactly 4", „changing the ratio takes effect on the very next call" (a `before + 1` assert a MÉRŐ állítás az „azonnal érvényesül"-re), „skipped frames return the last accepted pose" |
| Kikapcsolás-teszt | `pose_landmark_provider_test.dart` → „disabled flag → no pose provider is instantiated at all" (a `built` számláló 0 marad, tehát a delegált sem épül fel), „the disabled pose gate leaves the hand pipeline untouched" |
| Manifest-teszt | `ml_asset_manifest_test.dart` → „shipping manifest vision_models entries are well-formed" (2 bejegyzés, mindkettő `deferred`, saját sémával, a két séma KÜLÖNBÖZŐ) + a három új mutáció-cella |

### 10.3 Futtatott parancsok, tényleges kimenettel

```
$ python3 ml/make_manifest.py
wrote assets/ml/model_manifest.json (4 models, 2 vision models)

$ tools/round-gate.sh test/features/vision test/tooling
    → [1] format: ZÖLD
    → [2] analyze: ZÖLD
    → [3] test test/features/vision: ZÖLD
    → [4] test test/tooling: ZÖLD
    → [5] architecture: ZÖLD
    → [6] secrets: ZÖLD
    → [7] l10n: ZÖLD
MINDEN GATE ZÖLD.
```

A gate a brief §7 szerinti alakban futott — nincs `&&` lánc, nincs `| tail`,
nincs `| head`; a fenti sorok a csonkítatlan gate-kimenet összegző sorai.

### 10.4 Valódi-sértés próba (§6 harmadik pont)

Ideiglenesen `'nose': PoseLandmarkId.neckReference` bejegyzést tettem a
`poseLandmarkIdByRawName` allow-listára (azaz egy arc-pont átjut a mappingen),
majd:

```
$ ~/flutter/bin/flutter test test/features/vision/data/pose_privacy_audit_test.dart
00:00 +3 -2: Some tests failed.
Failing tests:
  …pose_privacy_audit_test.dart: a face-only payload yields notObservable, not a zero-filled body
  …pose_privacy_audit_test.dart: the raw-name allow-list maps onto retained IDs only
```

Két független cella váltott pirosra (az allow-lista alakja és a viselkedés is),
majd `git checkout lib/features/vision/domain/landmarks/pose_landmarks.dart`
visszaállítás — a fán a próbából semmi nem maradt (`git status` tiszta a fájlra).

### 10.5 Eltérések, döntések és okuk

- **A cadence-arány szemantikája:** „minden N. frame" (fázisszámláló), a
  0-indexű frame-mel kezdve — 12 frame × N=6 → pontosan 2 delegált hívás. Az
  `everyNthFrame` setter a fázist NULLÁZZA, ezért az új arány már a következő
  hívásnál érvényes (a §6.1 „csak újraindítás után hat" hibás implementációt
  pontosan ez a cella fogja meg).
- **Kihagyott frame → az utolsó elfogadott pose**, nem failure és nem
  `notObservable` — a `MonotonicHandLandmarkProvider` mintája (az is az utolsó
  elfogadott eredményt adja vissza eldobott híváskor). Ha még nincs eredmény,
  a kihagyott frame `notObservable`, a saját timestampjével — sosem
  nullákkal töltött álpóz.
- **A baseline-kapu KÉT quality-feltétel:** a kategorikus
  `VisionMetricState.good` (R09) ÉS egy numerikus `minimumQualityScore`. A
  mátrix „küszöb alatt / rajta / fölött" tengelye a numerikus küszöbön mérhető
  (a kategorikus enumnak nincs „rajta" pontja); a kategorikus ág külön két
  cellát kapott (`needsImprovement`, `notObservable`).
- **A drift normalizálása a baseline vállszélességével** történik, hogy a
  mérték kamera-távolságtól független legyen; ha nincs vállpár a baseline-ban,
  a skála 1.0 (nyers normalizált-frame egység). Ez NYERS mérték — küszöb,
  ítélet, cue nincs benne (ADR 0186 Döntés 5, E05-R20 határa).
- **A `NativePoseLandmarkProvider` a `deferred` ág ELŐTT ellenőrzi az
  `output_schema`-t** is: így az aktiváló körben sem tud egy hand-sémájú
  bejegyzés pose-providerként betöltődni.

### 10.6 Nem futtatott ellenőrzések és okuk

- **Teljes `flutter test` suite / property gate / APK:** ADR 0053 szerint
  CI-ban fut, az orchestrátor indítja (a brief §7 kifejezetten tiltja a
  `gh` hívást az implementer oldalán).
- **Valós eszközös pose-latency és thermal mérés:** a brief §7 szerint a
  device-mátrix PENDING sora; ebben a körben nincs futtatható pose-modell
  (deferred asset), tehát nem is mérhető.
- **Backend sáv:** a kör nem ért a `backend/`-hez, a gate backend-sávja ezért
  helyesen nem futott.


## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r14-pose-provider-and-posture-baseline-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.

> **Reviewer figyelem:** ez a kör privacy-kritikus ([ADR 0178](../adr/0178-vision-privacy-by-default.md),
> [ADR 0186](../adr/0186-vision-pose-landmark-inference-stack.md)) — a
> `security-reviewer` ágens bevonása KÖTELEZŐ (adatminimalizálás, logolt
> mezők). Nézze meg külön a §0.0 R3 manifest-validátor-változást is: az
> additív bővítés ne gyengítse a meglévő `hand_landmarker` checksum/licenc-
> ellenőrzést (a hat meglévő mutáció-cella a mérce).
