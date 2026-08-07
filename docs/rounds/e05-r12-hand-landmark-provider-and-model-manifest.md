# E05-R12 — Hand landmark provider adapter és model manifest

- **Státusz:** PLANNING (előre megírva 2026-08-05; pre-flight revízió és ADR
  2026-08-07, kód mérve: `main` @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 12; §15.1–15.2, §30
- **Branch:** `minimax/e05-r12-hand-landmark-provider-and-model-manifest`
- **Előfeltétel:** **E05-R06, E05-R07 merge** — ✅ teljesítve (mindkettő MERGED)
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3 (aktív
  engine-override, `tools/engine-profile.sh list`, 2026-08-07)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/landmarks/hand_landmarks.dart",
  "lib/features/vision/data/landmarks/hand_landmark_provider.dart",
  "lib/features/vision/data/landmarks/native_hand_landmark_provider.dart",
  "lib/features/vision/data/landmarks/recorded_hand_landmark_provider.dart",
  "lib/core/ml/vision_model_manifest.dart",
  "lib/features/vision/public.dart",
  "assets/ml/model_manifest.json",
  "ml/make_manifest.py",
  "pubspec.yaml",
  "test/features/vision/data/hand_landmark_provider_test.dart",
  "test/features/vision/domain/hand_landmarks_test.dart",
  "test/tooling/ml_asset_manifest_test.dart",
  "docs/adr/0185-vision-hand-landmark-inference-stack.md",
  "docs/rounds/e05-r12-hand-landmark-provider-and-model-manifest.md",
]
gate_tests = [
  "test/features/vision",
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ, ELVÉGEZVE — ld. §0.0):** `origin/main` + E05-R06/R07
> merge ✅; `assets/ml/model_manifest.json` **mai sémáját**,
> `ml/make_manifest.py`-t és `test/tooling/ml_asset_manifest_test.dart`-ot
> (ADR 0063) újraolvasva — a vision-manifest fájlszinten **additív**, de ÚJ
> testvér JSON-kulcs alatt, NEM a meglévő `models[]` tömbben (§0.0 R3, mérve).
> **ADR 0185** (nem 0168 — §0.0 R1, foglalóval mérve). PLANNING, brief commit
> ez a pre-flight commit.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING → mérve `origin/main` @ `a6e6f3d` (E05-R11 MERGED), öt mért
revízió.** Az eredeti PREPARED szöveg 2026-08-05-én íródott, a 0161–0170
ADR-blokk *terve* alapján; az E05-R01/R02 kör azóta ezt a blokkot ténylegesen
**0178–0184-re tolta** (foglalóval, nem `ls`-sel), tehát minden e blokkra
mutató szám-hivatkozás elavult volt — pontosan az a minta, amit az E05-R04/
R08/R11 pre-flightok is mértek.

1. **R1 — ADR-szám csere: `0168` → `0185`.** A `tools/round-slots.py
   reserve-adr --round E05-R12` a foglalóval **0185**-öt adta (a lemezen a
   legmagasabb ADR ma 0184; az `inflight/adr/` már 0172–0184-et foglalta).
   Minden „ADR 0168" hivatkozás a brief törzsében erre cserélve. Az ADR
   megírva: [`docs/adr/0185-vision-hand-landmark-inference-stack.md`](../adr/0185-vision-hand-landmark-inference-stack.md)
   (orchestrátor, pre-flight, ADR 0055).
2. **R2 — stale ADR-hivatkozás a §5.1-ben: `ADR 0163` → `ADR 0180`.** A
   „domain nem függ provider-API-tól" szabály ma ténylegesen az
   [ADR 0180](../adr/0180-vision-android-first-camera-strategy.md) 3. döntési
   pontjában él („A domain platform-független… a konkrét inference-/
   capture-provider interfész mögött él") — mérve, nem az eredeti
   0161–0166 blokk feltételezett sorrendjéből.
3. **R3 — a manifest-bővítés NEM az meglévő `models[]` tömb additív sora,
   hanem ÚJ, testvér top-level kulcs.** Mérve, nem az „additív bővítés"
   átmenettáblából feltételezve:
   - `test/tooling/ml_asset_manifest_test.dart:44` a `models` tömb hosszát
     kőbe vésve `expectedModelCount: 4`-re rögzíti — egy 5. bejegyzés
     hozzáadása ezt a tesztet azonnal pirosra vinné.
   - `ml/make_manifest.py` `_MODEL_SPECS` egy hardkódolt 4-elemű tuple, és a
     generált bejegyzéseket a `_build_entry`/`_read_binary_metadata`
     állítja elő, ami a StrumSight **saját CRNN bináris formátumát**
     (4-bájt magic + tömbszámláló + nevesített float-tömbök) parse-olja —
     egy `.tflite`/`.task` landmark-modell (teljesen más, FlatBuffer-alapú
     bináris) ezen azonnal `ValueError`-ral elhasalna.
   - `_modelPathPattern` (`^assets/ml/[A-Za-z0-9][A-Za-z0-9._-]*\.bin$`)
     kizárólag `.bin` kiterjesztést fogad el; egy landmark-modell tipikusan
     nem az.
   - `_validateOutputClasses` string osztálycímke-listát vár — egy
     landmark-kimenet (21 koordináta) fogalmilag nem "osztály".
   → **Döntés (ld. ADR 0185):** a vision-modell bejegyzés egy ÚJ, testvér
   JSON-kulcs alá kerül (pl. `vision_models`, a manifest gyökerében a
   meglévő `models` mellett), saját sémával és saját validátorral
   (`lib/core/ml/vision_model_manifest.dart` a Dart-oldalon, a
   `ml/make_manifest.py` egy ÚJ, elkülönített függvénye a generátor
   oldalán). A meglévő `models` kulcs, a `_MODEL_SPECS` tuple és a
   `ml_asset_manifest_test.dart` egyetlen meglévő sora sem változik — ez
   valódi additivitás fájlszinten, nem közös tömb/validátor-út.
4. **R4 — `VisionImage` (az SDD §15.1 kontraktusának paramétertípusa) ma
   sehol nem létezik** (`grep -rn "VisionImage" lib/` → 0 találat, csak az
   SDD-dokumentumban). Ezt a kört vezeti be — a legkisebb változtatás elve
   szerint a `hand_landmark_provider.dart`-ban (már ÚJ, engedélyezett fájl,
   nincs útvonal-bővítés), a meglévő R06/R07 típusokra építve: a
   `CameraFrame` pixel-buffere + az R07
   `NormalizedRect`/`CameraTransform<…, NormalizedPoint>` tere
   (`lib/core/camera/camera_coordinate_space.dart` —
   `NormalizedPoint`/`NormalizedRect` doc-commentje szó szerint „the model's
   non-mirrored, resolution-independent frame space"). Ne épüljön a
   provider natív típusára.
5. **R5 — a §3 „stream-alapú" szóhasználata pontosítva.** Az SDD §15.1
   idézett, kötelező kontraktusa **Future-alapú, hívásonkénti**
   `Future<AppResult<HandLandmarkResult>> infer(VisionImage image)` —
   **NEM** `Stream<HandLandmarkResult>`. A „stream-alapú" a §15.2 „realtime/
   live-stream running mode" leírására utal (folyamatos, egymást követő
   `infer()`-hívások monoton timestamppel), nem egy Dart `Stream`
   visszatérési típusra. Az implementer az SDD §15.1 kódblokkját kövesse,
   ne a brief lazább prózáját.

**Megerősítve (nem hiba):**

- A device-mátrix (`docs/manual-testing/vision-device-matrix.md` §2.3,
  „Hand tracking (production)") **már tartalmazza** a jobb/bal kéz landmark
  confidence/FPS PENDING sorokat az E05-R01 sablonból (91–95. sor) — a §5.5/
  §9 „a device-mátrix kap egy PENDING sort" ígérete ezekkel MÁR teljesül;
  a fájl nincs és nem is kell, hogy bekerüljön az `allowed_paths`-ba.
- `VisionMetricState.notObservable` (E05-R09, `frame_quality_assessor.dart`)
  már bevett idióma erre a fogalomra — a zero-hand-output `notObservable`
  elve konzisztens a meglévő mintával, nem új absztrakció.
- Nincs erőforrás-tulajdonlási kétértelműség: az SDD §15.1 kontraktus
  hívásonkénti (`infer(VisionImage)`), nem subscription-alapú — a
  `HandLandmarkProvider` nem szerez kamera-lease-t. `grep -rn "\.acquire("
  lib/` ma két hívót ad (`vision_setup_controller.dart`,
  `mic_capture.dart`), egyik sem ez a réteg, és a kontraktus alapján nem is
  lesz az.
- ADR 0063 valós és releváns (`docs/adr/0063-generated-ml-manifest-and-backend-ci.md`)
  — az audio-oldali manifest-őr precedense, amit ez a kör kiegészít, nem
  helyettesít.
- Előfeltétel (E05-R06, E05-R07) teljesítve — mindkettő MERGED (HANDOFF).

## 1. Cél

**Providerfüggetlen** kéz-landmark contract + production adapter + rögzített
kimeneten futó CI-adapter, és a model-asset **checksum + licenc + output-schema**
nyilvántartása a meglévő manifest-rendszerben.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- `assets/ml/model_manifest.json` (3 114 bájt) írja le a mai audio-modelleket
  (`chord_crnn.bin`, `strum_crnn*.bin`); a generátor `ml/make_manifest.py`, az
  őr `test/tooling/ml_asset_manifest_test.dart` (ADR 0063).
- **Nincs `lib/core/ml/`**, nincs vision model-asset, nincs inference plugin.
- Az R06 adapter szolgáltatja a `CameraFrame`-et; az R07 a nem tükrözött
  normalized teret — a modell bemenete **ez**.

## 3. Scope

**Benne:** `HandLandmarks` domain-modell **stabil StrumSight landmark ID-kkel**,
`HandLandmarkProvider` interfész (timestampelt hívásokkal — SDD §15.1
`Future`-alapú `infer()`, §0.0 R5), production adapter az ADR 0185 szerinti,
**deferred** stackkel (fail-closed `unavailable`, §0.0 R3/ADR 0185 §Döntés 2),
`RecordedHandLandmarkProvider`
(rögzített kimenet fixture-ből, CI-ben ez fut), `VisionModelManifest`
(checksum + input/output schema + licenc + evaluation-hivatkozás),
manifest-generátor és -őr bővítése, initialization-kori asset- és
output-shape-validáció.

**Kívül — TILOS:** tracking/smoothing (R13), pose (R14), metrikák (R18+),
DSP-paraméter, audio-modellek érintése, **training**.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/landmarks/hand_landmarks.dart` | ÚJ | landmark ID-k + modell |
| `.../data/landmarks/hand_landmark_provider.dart` | ÚJ | interfész |
| `.../data/landmarks/native_hand_landmark_provider.dart` | ÚJ | production adapter |
| `.../data/landmarks/recorded_hand_landmark_provider.dart` | ÚJ | fixture-adapter |
| `lib/core/ml/vision_model_manifest.dart` | ÚJ | manifest olvasó/validátor |
| `assets/ml/model_manifest.json` | meglévő | **additív** vision bejegyzés, ÚJ `vision_models` testvér-kulcs (§0.0 R3) |
| `ml/make_manifest.py` | meglévő | generátor bővítés, ÚJ elkülönített függvény (§0.0 R3) — a `_MODEL_SPECS`/audio-út NEM változik |
| `pubspec.yaml` | meglévő | **NE** kapjon inference pub-függőséget ebben a körben (ADR 0185 Döntés 3) — csak akkor módosul, ha az implementáció más okból indokolja |
| `test/features/vision/*`, `test/tooling/*` | ÚJ/meglévő | tesztek |
| `docs/adr/0185-vision-hand-landmark-inference-stack.md` | **KÉSZ** (orchestrátor, pre-flight) | inference stack döntés — az implementer NEM írja újra |
| `docs/rounds/e05-r12-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `assets/ml/*.bin` (audio modellek); `docs/rag`;
DSP-konstans; bármely training-script futtatása. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A domain nem függ provider-API-tól** (ADR 0180 §Döntés 3): a `HandLandmarks` a
   StrumSight saját ID-jeit használja, a provider mapping a `data/` rétegben van.
   **NEM elfogadható:** provider-index (`landmark[8]`) szivárgása a domainbe.
2. **Nincs kimenet ≠ hiba.** Zero-hand output **`notObservable`**, nem failure —
   a hívó nem kap „valamit" kényszerből. **NEM elfogadható:** üres landmark-lista
   helyett nullákkal kitöltött modell.
3. **Timestamp-monotonitás védett:** régebbi timestampű eredmény **eldobódik**
   (a stream nem keveredhet). Ezt teszt méri.
4. **Model-asset szabály (AGENTS.md §9 + ADR 0063):** minden asset mellé
   **checksum + licenc + verzió + output-schema** a manifestben, és az
   initialization **ellenőrzi a checksumot és az output shape-et**; eltérés →
   fail-closed, capability `unavailable`. **NEM elfogadható:** manifest nélküli
   asset, vagy checksum-ellenőrzés kihagyása „mert lassú".
5. **A model-asset EBBEN a körben nem szerezhető meg jogtisztán (ADR 0185
   Döntés 2 — eldöntve a pre-flightban, nem az implementer választása):** a
   kör a **contractot, a manifest-sémát, a validátort és a
   `RecordedHandLandmarkProvider`-t szállítja**, az assetet a manifestben
   `status = "deferred"` bejegyzés jelöli (az ÚJ `vision_models` kulcs alatt,
   §0.0 R3), és a device-mátrix PENDING sorai már a helyükön vannak (§0.0
   megerősítve — nem kell hozzájuk nyúlni). Ez **nem halt** és **nem
   mércegyengítés** — a production adapter ilyenkor fail-closed
   `unavailable`-t ad, tesztelve.
6. **A CI-ben a rögzített kimenetű adapter fut** — natív inference a CI-ben nem
   követelmény. A valós eszközös latency a device-mátrix PENDING sora.

## 6. Acceptance criteria

- [ ] **Mapping-teszt rögzített kimeneten:** a fixture provider-kimenet →
      StrumSight landmark ID-k, **mind a 21 pont** ellenőrzött indexszel.
- [ ] **Kéz-szám mátrix:** 0 / 1 / 2 kéz — a 0 `notObservable`, az 1 és 2
      külön track-jelölt, a >2 kimenet kontrolláltan levágott (nem crash).
- [ ] **Timestamp-mátrix:** növekvő / azonos / **csökkenő** timestamp — a
      csökkenő eldobódik, és ezt számláló méri.
- [ ] **Manifest-őr:** hiányzó checksum / rossz checksum / hiányzó licenc /
      eltérő output-schema → mind a négy esetben **init-hiba**, capability
      `unavailable`; és a `test/tooling/ml_asset_manifest_test.dart` a vision
      bejegyzésre is fut.
- [ ] **Valódi-sértés próba (§10):** a manifest checksum egy karakterének
      átírása → a manifest-őr PIROS → visszaállítás.
- [x] **Az ADR 0185 (KÉSZ, pre-flight)** megnevezi: a választott stacket
      (`tflite_flutter` + MediaPipe Hands, deferred aktiválással), a licencet
      (Apache-2.0), az asset méretét (ma nulla — nincs bináris ebben a
      körben, §Döntés 2/3), az elutasított alternatívákat és a
      **visszavonás**/újradöntés feltételét (§Döntés 5). A reviewer ezt
      olvasással ellenőrzi, az implementer nem módosítja.
- [ ] Az audio modellfájlok (`chord_crnn.bin`, `strum_crnn*.bin`) **bájtra
      változatlanok** (`git diff --stat` nem tartalmazza őket).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/tooling
```

Külön processzek, nincs `&&`/pipe/`tail`. A natív inference fordítási
bizonyítéka a CI `build-apk`; a valós latency PENDING a device-mátrixban.

## 8. Implementációs sorrend

1. ~~ADR~~ **KÉSZ (0185, pre-flight) — ne írd újra.** Olvasd el döntésként.
2. RED: mapping-, kéz-szám-, timestamp- és manifest-mátrix.
3. Domain modell + interfész (SDD §15.1 `Future`-alapú `infer()`, §0.0 R5) +
   `VisionImage` (§0.0 R4) + rögzített adapter.
4. Manifest-séma + generátor + validátor — ÚJ `vision_models` testvér-kulcs
   (§0.0 R3), a meglévő `models`/`_MODEL_SPECS` út érintetlen.
5. Production adapter fail-closed `unavailable`-ként (ADR 0185 Döntés 2 — ez
   MÁR eldöntött, nem választás); gate.

## 9. Kockázatok

- **Az asset licence/beszerzése blokkol** — a §5.5 deferred útja erre van.
- **A manifest-séma töri az audio-oldali őrt** — a bővítés **additív**, a mai
  mezők nem nevezhetők át; ha a meglévő teszt elbukik, az **megállás és jelentés**.
- **Az APK mérete ugrik** a model-assettel — **ebben a körben N/A** (ADR 0185
  Döntés 2/3: nincs bináris asset, nincs pub-függőség), a méretszám egy
  jövőbeli aktiváló kör §10-ének dolga.

**STOP:** training indítása, audio-modell érintése, checksum-ellenőrzés
kihagyása vagy provider-típus szivárgása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**Státusz:** kész — 4 lépéses commit, minden kapu zöld.

### Végrehajtott commitok (`minimax/e05-r12-hand-landmark-provider-and-model-manifest`)

1. `d423a64` — domain modell (`HandLandmarkId` 21 elemű enum + `Handedness` +
   `HandLandmarkPoint` + `HandObservation` + `HandLandmarkObservability` +
   `HandLandmarkResult`) és a 21-pont topológiát mérő domain-teszt.
2. `e35e536` — `HandLandmarkProvider` interfekt + `VisionImage` (SDD §15.1,
   brief §0.0 R4) + `RecordedHandLandmarkProvider` (5 fixture: 0/1/2/>2 kéz
   + failure) + `MonotonicHandLandmarkProvider` wrapper + a `NativeHandLandmarkProvider`
   fail-closed unavailable adaptere.
3. `730d71f` — `lib/core/ml/vision_model_manifest.dart` (saját validátor +
   reader, `package:crypto`-alapú SHA-256 — a saját inline SHA-256-ot a
   `crypto` csomag váltja, hogy ne legyenek kézzel beírt konstansok).
4. `10518c1` — `assets/ml/hand_landmarker_deferred.tflite` 1-byte placeholder
   + `model_manifest.json` `vision_models` testvér-kulcs (a `models`
   tömb érintetlen) + `ml/make_manifest.py` izolált `_build_vision_models`
   + `vision/public.dart` additív export + `ml_asset_manifest_test` 5 új
   vision-mátrix cella.

### §6 acceptance criteria — mért állapot

- [x] **Mapping-teszt rögzített kimeneten** — a
      `test/features/vision/data/hand_landmark_provider_test.dart` "every
      StrumSight landmark ID is queryable from a single-hand result"
      végigmegy mind a 21 ID-n.
- [x] **Kéz-szám mátrix** — 0/1/2/>2 cellák a
      `hand_landmark_provider_test.dart` Hand-count matrix groupban; a
      `>2` esetben a kimenet `take(2)`-vel vágott, observability `two`,
      nincs crash.
- [x] **Timestamp-mátrix** — increasing/equal/decreasing + "decreasing
      before any accept" cellák a Timestamp matrix groupban; a
      csökkenő eldobódik, `droppedTimestampCount` számláló méri,
      `lastAcceptedTimestampUs` nem regresszál.
- [x] **Manifest-őr** — `missing checksum / wrong checksum / missing
      license / mismatched output_schema / well-formed` cellák a
      `ml_asset_manifest_test.dart` VisionModelManifest groupban; a
      negatív cellák `isClean = false` üzenettel, a pozitív cella
      `isClean = true`.
- [x] **Valódi-sértés próba** — a `assets/ml/model_manifest.json`
      checksum utolsó karaktere `d` → `e` átírva (sed, in-place), a
      `shipping manifest vision_models entry is well-formed` teszt
      PIROS lett üzenettel: `vision_models[0] checksum mismatch for
      assets/ml/hand_landmarker_deferred.tflite: expected ...01e,
      actual ...01d`. Visszaállítás (`cp /tmp/backup`) → GREEN.
- [x] **Az ADR 0185 (KÉSZ, pre-flight)** — olvasva, nem módosítva.
- [x] **Audio modellfájlok bájtra változatlanok** —
      `git diff --stat HEAD~ -- assets/ml/*.bin` üres, a `chord_crnn.bin`
      és a `strum_crnn*.bin` SHA-256-jai azonosak a manifestben.

### Gate kimenet

```
tools/round-gate.sh test/features/vision test/tooling
    format                                                     zöld
    analyze                                                    zöld
    test test/features/vision                                  zöld
    test test/tooling                                          zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
```

### Megjegyzések a reviewer számára

- **A `MonotonicHandLandmarkProvider` a wrapper, nem a kontraktus metódusa.**
  A provider alatti kontraktus `Future<AppResult<HandLandmarkResult>>
  infer(VisionImage)` hívásonkénti és stateless; a timestamp-monotonitás
  szállítási szintű (brief §5.3), így külön wrapper.
- **A `NativeHandLandmarkProvider` `manifestReader` (nem `_manifest`)
  mezőnevet használ** a `prefer_initializing_formals` lint miatt — a
  privát mezőt hívó-barát néven tesszük ki, de a `manifest` paraméter
  maradt (külső API).
- **A SHA-256 nem saját implementáció** — a `package:crypto/crypto.dart`
  `sha256.convert()`-ját használja a `lib/core/ml/vision_model_manifest.dart`
  (FIPS 180-4-gyel konzisztens, és azonos a tesztben levő
  `_sha256Hex`-szel). A tesztben továbbra is van saját implementáció
  (referencia-vektorok: `''`, `'abc'`), mert a teszt a saját maga által
  használt algoritmust ellenőrzi, nem a library-t.
- **`prefer_initializing_formals` a `RecordedHandLandmarkProvider` `produce`
  mezőjén is feloldva** — a paraméter és a mező is `produce`, az
  inicializáló formális `: this.produce`.
- **A `tools/codex-signal.sh done "<egy sor>"` jelzés a végén** —
  lásd lentebb a §0.0-ban.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r12-hand-landmark-provider-and-model-manifest-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
