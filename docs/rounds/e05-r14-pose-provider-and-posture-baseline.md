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
| `test/features/vision/data/pose_privacy_audit_test.dart` | ÚJ | a kör kulcsbizonyítéka (5 teszt): a pinnelt audit-felszín mellett a nyers allow-lista pozitív, pontos 9 kulcsos snapshotját és a nyers név ↔ retained ID 1:1 megfelelést is ellenőrzi |
| `test/features/vision/data/pose_landmark_provider_test.dart` | ÚJ | mapping / cadence / kikapcsolás / fail-closed (16 teszt) |
| `test/features/vision/domain/posture_baseline_test.dart` | ÚJ | 3×3 baseline-mátrix + reset/interrupt + drift (19 teszt) |
| `test/tooling/ml_asset_manifest_test.dart` | meglévő | `hasLength(1)`→`hasLength(2)` + per-bejegyzés séma-ellenőrzés; három ÚJ cella (hand+pose együtt tiszta; pose örökölt hand-séma → piros; regisztrálatlan `model_id` → piros). A hat meglévő hand-mutáció-cella szövegében egyetlen karakter sem változott |

### 10.2 Acceptance — hol méri melyik teszt

| §6 pont | Mérő teszt |
|---|---|
| Mapping-teszt | `pose_landmark_provider_test.dart` → „every retained ID is queryable and face points are dropped"; `pose_privacy_audit_test.dart` → „PoseLandmarkId enum contains exactly the 9 retained points", „the raw-name allow-list maps onto retained IDs only" (pinnelt pozitív nyerskulcs-snapshot + 1:1 hossz-assertion) |
| Privacy-audit teszt | `pose_privacy_audit_test.dart` → „audit map key set matches the pinned snapshot" (pinnelt top-level + per-pont kulcsok) és „face landmarks … never reach the domain object, its serialized form, or its log form" (tiltott alszavak: eye/nose/mouth/ear/face/lip a JSON-ban ÉS a `toString()`-ben; a teszt külön ellenőrzi, hogy a fixture tényleg adott arc-pontot, tehát nem üresen zöld) |
| Valódi-sértés próba | Elvégezve — ld. §10.4 |
| Baseline-mátrix | `posture_baseline_test.dart` → 9 generált cella (quality 0.6/0.7/0.8 × duration 2s/3s/4s), baseline csak a 4 „rajta vagy fölötte" cellában; a többiben `baseline == null` ÉS `observe(...).state == notObservable` |
| Cadence-teszt | `pose_landmark_provider_test.dart` → „12 frames at 1:6 delegate exactly 2", „12 frames at 1:3 delegate exactly 4", „changing the ratio takes effect on the very next call" (a `before + 1` assert a MÉRŐ állítás az „azonnal érvényesül"-re), „skipped frames return the last accepted pose" |
| Kikapcsolás-teszt | `pose_landmark_provider_test.dart` → „disabled flag → no pose provider is instantiated at all" (a `built` számláló 0 marad, tehát a delegált sem épül fel), „the disabled pose gate leaves the hand pipeline untouched" |
| Manifest-teszt | `ml_asset_manifest_test.dart` → „shipping manifest vision_models entries are well-formed" (2 bejegyzés, mindkettő `deferred`, saját sémával, a két séma KÜLÖNBÖZŐ) + a három új mutáció-cella |

### 10.3 Futtatott parancsok, tényleges kimenettel

```

═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 1106 files (0 changed) in 4.30 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  camera 0.11.4 (0.12.0+2 available)
  camera_android_camerax 0.6.30 (0.7.4+4 available)
  camera_avfoundation 0.9.23+2 (0.10.2 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  go_router 17.3.0 (17.4.0 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
43 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...
No issues found! (ran in 4.3s)

    → [2] analyze: ZÖLD

═══ [3] test test/features/vision
    $ /home/ubuntu/flutter/bin/flutter test test/features/vision

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  camera 0.11.4 (0.12.0+2 available)
  camera_android_camerax 0.6.30 (0.7.4+4 available)
  camera_avfoundation 0.9.23+2 (0.10.2 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  go_router 17.3.0 (17.4.0 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
43 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart
00:00 +0: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: HandTrackAssigner — ID stability on a continuous noisy trajectory one physical hand keeps ONE stable track ID across all frames
00:00 +1: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: HandTrackAssigner — occlusion matrix (under / at / over shortGap) gap of 2 frames (< shortGapFrames=3) → SAME track ID
00:00 +2: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: HandTrackAssigner — occlusion matrix (under / at / over shortGap) gap of 3 frames (= shortGapFrames) → SAME track ID
00:00 +3: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: HandTrackAssigner — occlusion matrix (under / at / over shortGap) gap of 5 frames (> shortGapFrames=3) → trackLost + NEW ID
00:00 +4: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: HandTrackAssigner — crossing hands, ID and role stay stable two physical hands crossing → track IDs and roles do not swap
00:00 +5: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: HandTrackAssigner — mirror / left-handed parity (4-cell matrix) leftHanded × {back, front} all 4 cells keep roles consistent
00:00 +6: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: Fix round — F1 BLOCKER: jump-rejection recovers from a sustained shift persistent relocation without occlusion converges to the new position
00:00 +7: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: Fix round — F1 BLOCKER: jump-rejection recovers from a sustained shift relocation after a short occlusion keeps the same track ID and converges to the new position
00:00 +8: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: Fix round — F2 MAJOR: TrackContinuity latency + jitter are real continuous noisy trajectory → maxJitterNormalized > 0
00:00 +9: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: Fix round — F2 MAJOR: TrackContinuity latency + jitter are real many frames → totalProcessingDuration > Duration.zero
00:00 +10: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: Fix round — F2 MAJOR: TrackContinuity latency + jitter are real trackLost event increments tracksLost and tracksObserved
00:00 +11: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_track_assigner_test.dart: Fix round — F3 MINOR: smoothed visibility follows raw confidence sustained low visibility lowers the smoothed visibility
00:00 +12: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/calibration_validity_test.dart: CalibrationValidity — happy path returns null when stored and runtime match (valid calibration)
00:00 +13: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/calibration_validity_test.dart: Validity-mátrix — öt cella, mind külön cell 1 — camera device changed → cameraDeviceChanged
00:00 +14: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/calibration_validity_test.dart: Validity-mátrix — öt cella, mind külön cell 2 — orientation changed → orientationChanged
00:00 +15: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/calibration_validity_test.dart: Validity-mátrix — öt cella, mind külön cell 3 — zoom changed beyond tolerance → zoomChangedBeyondTolerance
00:00 +16: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/calibration_validity_test.dart: Validity-mátrix — öt cella, mind külön cell 4 — timestamp expired → timestampExpired
00:00 +17: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/calibration_validity_test.dart: Validity-mátrix — öt cella, mind külön cell 5 — degenerate geometry → degenerateGeometry
00:00 +18: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/calibration_validity_test.dart: Validity-mátrix — öt cella, mind külön a zoom change WITHIN tolerance is still valid
00:00 +19: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/calibration_validity_test.dart: Validity-mátrix — öt cella, mind külön priority order: camera device beats every later trigger
00:00 +20: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/calibration_validity_test.dart: CalibrationInvalidationReason enum a dokumentált öt érték mind jelen van, és nem lett bővítve
00:00 +21: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: baseline matrix — quality × visible duration quality below threshold × duration below minimum → no baseline
00:00 +22: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: baseline matrix — quality × visible duration quality below threshold × duration at minimum → no baseline
00:00 +23: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: baseline matrix — quality × visible duration quality below threshold × duration above minimum → no baseline
00:00 +24: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: baseline matrix — quality × visible duration quality at threshold × duration below minimum → no baseline
00:00 +25: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: baseline matrix — quality × visible duration quality at threshold × duration at minimum → baseline
00:00 +26: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: baseline matrix — quality × visible duration quality at threshold × duration above minimum → baseline
00:00 +27: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: baseline matrix — quality × visible duration quality above threshold × duration below minimum → no baseline
00:00 +28: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: baseline matrix — quality × visible duration quality above threshold × duration at minimum → baseline
00:00 +29: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: baseline matrix — quality × visible duration quality above threshold × duration above minimum → baseline
00:00 +30: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: a non-good categorical quality state blocks the baseline
00:00 +31: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: notObservable quality state blocks the baseline
00:00 +32: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: an interrupted window is discarded, not partially reused
00:00 +33: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: a pose without the required landmarks never feeds the baseline
00:00 +34: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: low-visibility landmarks are treated as absent
00:00 +35: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: raw posture observation baseline averages the accepted window and records its span
00:00 +36: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: raw posture observation an unchanged pose drifts by zero
00:00 +37: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: raw posture observation a shifted pose drifts by the span-normalized offset
00:00 +38: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: raw posture observation a notObservable pose yields a notObservable observation
00:00 +39: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/posture_baseline_test.dart: raw posture observation reset removes the baseline
00:01 +40: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_landmarks_test.dart: HandLandmarkId — 21 stable StrumSight IDs enumerates exactly 21 landmarks in the canonical topology
00:01 +41: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_landmarks_test.dart: HandLandmarkId — 21 stable StrumSight IDs each finger contributes exactly four joints
00:01 +42: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_landmarks_test.dart: HandObservation — domain-level landmark access byId returns the stored point for every present landmark
00:01 +43: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_landmarks_test.dart: HandObservation — domain-level landmark access byId returns null for absent landmarks (no provider-index leakage)
00:01 +44: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_landmarks_test.dart: HandObservation — domain-level landmark access count reflects exactly the populated landmarks
00:01 +45: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_landmarks_test.dart: HandLandmarkPoint — value guards rejects NaN coordinates
00:01 +46: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_landmarks_test.dart: HandLandmarkPoint — value guards rejects out-of-range visibility
00:01 +47: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_landmarks_test.dart: HandLandmarkResult — observability encoding notObservable when zero hands are detected
00:01 +48: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/hand_landmarks_test.dart: HandLandmarkResult — observability encoding one hand observation is distinct from two
00:01 +49: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/vision_quality_summary_test.dart: VisionQualitySummary chooses exactly one cue using the required complete priority order
00:01 +50: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/vision_quality_summary_test.dart: VisionQualitySummary resolves same-severity lighting failures deterministically
00:01 +51: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/vision_quality_summary_test.dart: VisionQualitySummary uses each later cue only when every earlier concern is good
00:01 +52: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/vision_quality_summary_test.dart: VisionQualitySummary prioritizes each cue over every lower-priority concern
00:01 +53: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/vision_quality_summary_test.dart: VisionQualitySummary does not turn unavailable evidence into technical feedback
00:02 +54: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/landmark_smoothing_test.dart: LandmarkSmoothingFilter — picking profile on a fast strum peak-to-peak amplitude preservation ≥ 90% of the raw input
00:02 +55: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/landmark_smoothing_test.dart: LandmarkSmoothingFilter — fretting profile on a noisy trajectory high-frequency noise reduction ≥ 60% (documented floor)
00:02 +56: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/landmark_smoothing_test.dart: LandmarkSmoothingFilter — jump-rejection matrix fast strum passes the velocity check (no rejection)
00:02 +57: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/landmark_smoothing_test.dart: LandmarkSmoothingFilter — jump-rejection matrix single-frame teleport IS rejected, then the next frame recovers
00:02 +58: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/frame_quality_assessor_test.dart: FrameQualityAssessor assesses the synthetic dark, clipped, blurred and sharp fixtures
00:02 +59: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/frame_quality_assessor_test.dart: FrameQualityAssessor uses all three luminance and clipping threshold cells
00:02 +60: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/frame_quality_assessor_test.dart: FrameQualityAssessor uses all three sharpness, motion and coverage threshold cells
00:02 +61: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/frame_quality_assessor_test.dart: FrameQualityAssessor returns notObservable with finite measurements for degenerate input
00:02 +62: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/frame_quality_assessor_test.dart: FrameQualityAssessor returns notObservable with finite measurements for a constant frame
00:02 +63: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/frame_quality_assessor_test.dart: FrameQualityAssessor partial ROI is a separate frame-quality concern
00:02 +64: /home/ubuntu/ss-codex-e05-r14/test/features/vision/domain/frame_quality_assessor_test.dart: FrameQualityAssessor does not compare motion across an unobservable frame
00:04 +65: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/guitar_calibration_screen_test.dart: drag on the nut handle moves the controller normalized state
00:05 +66: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/guitar_calibration_screen_test.dart: mirror parity: dragging right increases normalised x
00:06 +67: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/guitar_calibration_screen_test.dart: f2: clanp visibility — dragging outside the frame thickens the handle border
00:06 +68: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/guitar_calibration_screen_test.dart: f3: front-camera mirror — dragging right decreases normalised x
00:06 +69: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +70: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +71: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +72: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +73: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +74: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +75: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +76: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +77: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +78: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +79: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +80: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +81: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel granted shows the continue state
00:07 +82: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel denied shows the explicit request action
00:07 +83: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel permanently denied sends the user to Settings
00:07 +84: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel restricted sends the user to Settings
00:07 +85: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: camera permission panel unavailable explains the state without a request action
00:07 +86: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: each setup profile renders its own frame guide
00:08 +87: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: skip reaches audio-only continuation from every wizard step
00:08 +88: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: skip reaches audio-only continuation from every wizard step
00:08 +89: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: skip reaches audio-only continuation from every wizard step
00:08 +90: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: skip reaches audio-only continuation from every wizard step
00:08 +91: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: skip reaches audio-only continuation from every wizard step
00:08 +92: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: skip reaches audio-only continuation from every wizard step
00:09 +93: /home/ubuntu/ss-codex-e05-r14/test/features/vision/presentation/vision_setup_screen_test.dart: Vision route is absent while either setup flag is disabled
00:09 +94: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: round-trip a freshly written profile reads back as the same value
00:09 +95: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: round-trip the serialized JSON is bit-stable across two encodes
00:09 +96: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: round-trip the bundle key order is deterministic (hand-pinned)
00:09 +97: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: migration matrix — four cells, four separate tests cell v0 — absent document returns null, not a fabricated profile
00:09 +98: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: migration matrix — four cells, four separate tests cell vN — a freshly written document decodes to current schema
00:09 +99: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: migration matrix — four cells, four separate tests cell vN-1 — an older-shape document is migrated to current shape
00:09 +100: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: migration matrix — four cells, four separate tests cell vN+1 — a future-version document is NOT misread, returns null
00:09 +101: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: migration matrix — four cells, four separate tests cell vN+1b — inner shape version ahead of codec (envelope OK) is NOT misread, returns null
00:09 +102: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: idempotence writing the same profile+guitar twice yields identical JSON
00:09 +103: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: idempotence a migrated document survives a second read identically
00:09 +104: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: corruption tolerance — record-level quarantine csonka JSON — az egész dokumentum karanténba kerül, read null
00:09 +105: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: corruption tolerance — record-level quarantine hibás típus — a camera mező nem objektum → record karantén
00:09 +106: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: corruption tolerance — record-level quarantine érvénytelen orientation — tartományon belüli érték → record karantén
00:09 +107: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: corruption tolerance — record-level quarantine degenerált polygon — a neckPolygon < 3 csúcs → record karantén
00:09 +108: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: privacy snapshot a serialized profile only contains the expected key set (any level)
00:09 +109: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: privacy snapshot the privacy snapshot set is hand-pinned — adding a key fails
00:09 +110: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: real-violation probe a pixel-coordinate field bypasses validation → codec rejects
00:09 +111: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: real-violation probe a numeric field with a string value is rejected (poison prevention)
00:09 +112: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/vision_calibration_repository_test.dart: JsonRecordException thrown by the codec for unparseable input the codec itself surfaces JsonRecordException on missing fields
00:09 +113: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: RecordedPoseLandmarkProvider — 9-point mapping every retained ID is queryable and face points are dropped
00:09 +114: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: RecordedPoseLandmarkProvider — 9-point mapping an empty payload is notObservable, not a failure
00:09 +115: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: RecordedPoseLandmarkProvider — 9-point mapping the failure fixture surfaces AppResult.failure
00:09 +116: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: CadenceLimitedPoseLandmarkProvider — cadence ratio 12 frames at 1:6 delegate exactly 2 pose inferences
00:09 +117: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: CadenceLimitedPoseLandmarkProvider — cadence ratio 12 frames at 1:3 delegate exactly 4 pose inferences
00:09 +118: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: CadenceLimitedPoseLandmarkProvider — cadence ratio the default cadence is a fraction of the hand rate
00:09 +119: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: CadenceLimitedPoseLandmarkProvider — cadence ratio changing the ratio takes effect on the very next call
00:09 +120: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: CadenceLimitedPoseLandmarkProvider — cadence ratio skipped frames return the last accepted pose, never a failure
00:09 +121: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: CadenceLimitedPoseLandmarkProvider — cadence ratio a cadence below 1 is rejected
00:09 +122: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: createPoseLandmarkProvider — feature-flag gate disabled flag → no pose provider is instantiated at all
00:09 +123: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: createPoseLandmarkProvider — feature-flag gate enabled flag → a cadence-limited provider is returned
00:09 +124: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: createPoseLandmarkProvider — feature-flag gate the disabled pose gate leaves the hand pipeline untouched
00:09 +125: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: NativePoseLandmarkProvider — fail-closed deferred manifest entry → initialize fails (capability unavailable)
00:09 +126: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: NativePoseLandmarkProvider — fail-closed dirty manifest → initialize fails
00:09 +127: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: NativePoseLandmarkProvider — fail-closed hand output_schema on the pose entry → initialize fails
00:09 +128: /home/ubuntu/ss-codex-e05-r14/test/features/vision/data/pose_landmark_provider_test.dart: NativePoseLandmarkProvider — fail-closed infer without a successful initialize fails
00:10 +129: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/vision_setup_controller_test.dart: VisionSetupController left-handed preference changes the recommendation but not selection
00:10 +130: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/vision_setup_controller_test.dart: VisionSetupController persists exactly the profile and camera preference keys
00:10 +131: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/vision_setup_controller_test.dart: VisionSetupController permission request happens only from the explicit action
00:10 +132: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/vision_setup_controller_test.dart: VisionSetupController camera preference switch closes its lease before opening another
00:10 +133: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/vision_setup_controller_test.dart: VisionSetupController skip never constructs or starts a camera capture
00:10 +134: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R4 helpers computeQualityScore is monotonic in the neck-margin term
00:10 +135: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R4 helpers isGeometryDegenerate flags short neck
00:10 +136: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R4 helpers isGeometryDegenerate flags collinear polygon
00:10 +137: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R4 helpers isGeometryDegenerate accepts a degenerate sub-minimum area AND polygon is also collinear
00:10 +138: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R4 helpers isGeometryDegenerate accepts a healthy neck rectangle
00:10 +139: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R4 helpers neckPolygonArea is zero for collinear input
00:10 +140: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R4 helpers neckPolygonIsCollinear detects three collinear points
00:10 +141: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R5 Save gate (self-comparison) live context overrides loaded profile ⇒ entryEvaluationReason set
00:10 +142: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R5 Save gate (self-comparison) matches the live context ⇒ entryEvaluationReason is null
00:10 +143: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R5 Save gate (self-comparison) moving anchors to a degenerate config blocks Save
00:10 +144: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R5 Save gate (self-comparison) f1: collinear polygon with healthy nut↔bridge distance blocks Save
00:10 +145: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R5 Save gate (self-comparison) f1: zero-area polygon (3 vertices pulled to a point) blocks Save
00:10 +146: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R5 Save gate (self-comparison) healthy anchor spread keeps Save enabled
00:11 +147: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R5 Save gate (self-comparison) saveIfValid persists the draft and clears entry evaluation
00:11 +148: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R5 Save gate (self-comparison) saveIfValid blocks when the draft is degenerate
00:11 +149: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — R5 Save gate (self-comparison) resetDraft reverts a fresh draft to the initial seed
00:11 +150: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationRuntimeContextProvider — F3 storage wiring reads the saved camera preference from the keyValueStore
00:11 +151: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationRuntimeContextProvider — F3 storage wiring reads the saved setup profile from the keyValueStore
00:11 +152: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationRuntimeContextProvider — F3 storage wiring falls back to back camera + balanced profile when no key set
00:11 +153: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationRuntimeContextProvider — F3 storage wiring saveIfValid persists the saved camera + setup profile, not the hardcoded one
00:11 +154: /home/ubuntu/ss-codex-e05-r14/test/features/vision/application/guitar_calibration_controller_test.dart: GuitarCalibrationController — repo write failure writeFailed surfaces when the underlying store rejects
00:11 +155: All tests passed!

    → [3] test test/features/vision: ZÖLD

═══ [4] test test/tooling
    $ /home/ubuntu/flutter/bin/flutter test test/tooling

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  camera 0.11.4 (0.12.0+2 available)
  camera_android_camerax 0.6.30 (0.7.4+4 available)
  camera_avfoundation 0.9.23+2 (0.10.2 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  go_router 17.3.0 (17.4.0 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
43 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e05-r14/test/tooling/route_literal_guard_test.dart
00:00 +0: /home/ubuntu/ss-codex-e05-r14/test/tooling/route_literal_guard_test.dart: navigation calls use the central AppRoutes catalogue
00:00 +1: /home/ubuntu/ss-codex-e05-r14/test/tooling/dio_factory_guard_test.dart: production Dio instances are created only by DioFactory
00:01 +2: /home/ubuntu/ss-codex-e05-r14/test/tooling/ml_asset_manifest_test.dart: SHA-256 implementation matches standard vectors
00:01 +3: /home/ubuntu/ss-codex-e05-r14/test/tooling/ml_asset_manifest_test.dart: shipping manifest covers four valid declared ML binaries
00:01 +4: /home/ubuntu/ss-codex-e05-r14/test/tooling/ml_asset_manifest_test.dart: shipping manifest covers four valid declared ML binaries
00:01 +5: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags provider token literals by their own prefix
00:01 +6: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags provider token literals by their own prefix
00:01 +7: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags provider token literals by their own prefix
00:01 +8: /home/ubuntu/ss-codex-e05-r14/test/tooling/ml_asset_manifest_test.dart: VisionModelManifest — manifest-guard mutations missing checksum → init failure
00:01 +9: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags a private key block and a JSON Web Token
00:01 +10: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags a private key block and a JSON Web Token
00:01 +11: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags a private key block and a JSON Web Token
00:01 +12: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags a private key block and a JSON Web Token
00:01 +13: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags a private key block and a JSON Web Token
00:01 +14: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags a private key block and a JSON Web Token
00:01 +15: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags a private key block and a JSON Web Token
00:01 +16: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags a private key block and a JSON Web Token
00:01 +17: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags a private key block and a JSON Web Token
00:01 +18: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: flags a credential assigned a long literal
00:01 +19: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: accepts placeholders, env-var names and interpolation
00:01 +20: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: honours the inline allow marker for a proven fixture
00:01 +21: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: honours the file-level allow marker for a redaction test
00:01 +22: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: the file-level marker does not leak to other files
00:01 +23: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: ignores untracked and gitignored trees
00:01 +24: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: never puts the matched value into the report
00:01 +25: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: fails loudly when Git cannot enumerate the tree
00:01 +26: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_secrets_test.dart: the measured R14 prod-config fixtures need — and get — a marker
00:02 +27: /home/ubuntu/ss-codex-e05-r14/test/tooling/preferences_plugin_import_guard_test.dart: only the storage layer imports shared_preferences
00:02 +28: /home/ubuntu/ss-codex-e05-r14/test/tooling/preferences_plugin_import_guard_test.dart: every migrated feature is off the plugin
00:02 +29: /home/ubuntu/ss-codex-e05-r14/test/tooling/diagnostics_storage_separation_test.dart: no diagnostics file touches the key-value storage layer
00:02 +30: /home/ubuntu/ss-codex-e05-r14/test/tooling/diagnostics_storage_separation_test.dart: no persisted key is a diagnostics/audio payload
00:02 +31: /home/ubuntu/ss-codex-e05-r14/test/tooling/diagnostics_storage_separation_test.dart: the upload payload keeps its own, much larger bound
00:02 +32: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_assets_test.dart: accepts existing declared Flutter assets and fonts
00:02 +33: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_assets_test.dart: reports every missing declared asset and font
00:03 +34: /home/ubuntu/ss-codex-e05-r14/test/tooling/check_assets_test.dart: rejects only empty declared ML binaries
00:04 +35: /home/ubuntu/ss-codex-e05-r14/test/tooling/legacy_identifier_guard_test.dart: no production file carries a legacy music_theory identifier
00:04 +36: /home/ubuntu/ss-codex-e05-r14/test/tooling/legacy_identifier_guard_test.dart: no production file carries a legacy music_theory identifier
00:04 +37: /home/ubuntu/ss-codex-e05-r14/test/tooling/legacy_identifier_guard_test.dart: no production file carries a legacy music_theory identifier
00:04 +38: /home/ubuntu/ss-codex-e05-r14/test/tooling/legacy_identifier_guard_test.dart: no production file carries a legacy music_theory identifier
00:04 +39: /home/ubuntu/ss-codex-e05-r14/test/tooling/legacy_identifier_guard_test.dart: no production file carries a legacy music_theory identifier
00:04 +40: /home/ubuntu/ss-codex-e05-r14/test/tooling/legacy_identifier_guard_test.dart: no production file carries a legacy music_theory identifier
00:04 +41: /home/ubuntu/ss-codex-e05-r14/test/tooling/legacy_identifier_guard_test.dart: no production file carries a legacy music_theory identifier
00:04 +42: /home/ubuntu/ss-codex-e05-r14/test/tooling/legacy_identifier_guard_test.dart: pubspec is the single source of the client version
00:04 +43: All tests passed!

    → [4] test test/tooling: ZÖLD

═══ [5] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [5] architecture: ZÖLD

═══ [6] secrets
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_secrets.dart

Running build hooks...Running build hooks...Secret scan OK (1932 file(s) scanned, 0 finding(s)).

    → [6] secrets: ZÖLD

═══ [7] l10n
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_l10n_parity.dart

Running build hooks...Running build hooks...L10n parity OK (en → hu, 964 message(s)).

    → [7] l10n: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/vision                                  zöld
    test test/tooling                                          zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

A fenti a javító kör 2 friss, teljes és csonkítatlan gate-kimenete; a gate a brief §7 szerinti alakban futott — nincs `&&` lánc, nincs `| tail`, nincs `| head`.
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

### 10.4b Security MAJOR-1 valódi-sértés próba (javító kör 2)

Az eredeti név-heurisztika megkerülésére ideiglenesen `'chin':
PoseLandmarkId.neckReference` bejegyzést tettem a
`poseLandmarkIdByRawName` allow-listára, majd:

```
$ flutter test test/features/vision/data/pose_privacy_audit_test.dart
00:00 +1 -1: the raw-name allow-list maps onto retained IDs only [E]
Expected: Set:[..., 'neck']
  Actual: Set:[..., 'neck', 'chin']
Which: larger than expected
the raw-name allow-list must match the approved snapshot
00:00 +4 -1: Some tests failed.
```

A kizárólag a most hozzáadott pozitív nyerskulcs-snapshot assertion bukott el,
így a tiltott alszavakat megkerülő alias is megbízhatóan piros. A vizsgálat
után a célfájlt `git checkout --
lib/features/vision/domain/landmarks/pose_landmarks.dart` paranccsal
visszaállítottam; csak ez a szándékosan ideiglenes, előtte `git diff`-fel
ellenőrzött saját módosítás került eldobásra.

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
- **Security MINOR-2 follow-up:** `PostureObservation.state` ma nyers drift
  összehasonlítás után is `good`; a `needsImprovement`-hez szükséges
  minőségi/drift küszöb vagy az állapotmező szemantikája nincs ebben a körben
  meghatározva (ADR 0186 Döntés 5 az ítéletet E05-R20-ra hagyja). Ezért nem
  vezettem be találgatott policy-t ebben a teszt-szigorító javításban.

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
