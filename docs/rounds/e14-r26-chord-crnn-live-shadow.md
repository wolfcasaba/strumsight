# E14-R26 — A szállított Chord CRNN élő shadow bekötése (ADR 0549)

- **Kör:** E14-R26 · **Csomag:** PKG-E · **ADR:** 0549
- **Ág:** `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK → lokális gate nem futtatható; a
  mérce a session végi `full-gate.yml` + `build-apk.yml`.

## 1. Cél

A `chord_crnn.bin` a fán van, de a Live úton **nem fut**. A kör második
akkord-véleményként köti be — kizárólag az R23 shadow-bufferbe —, tipizált
integritás-kapuval, és a produkciós NNLS+Viterbi címkével összevetve egy zárt,
gyök/minőség szerinti egyezési mátrixban.

## 2. Mért állapot (a kör előtt)

- Egyetlen betöltő: `analyze_providers.dart`
  (`rootBundle.load('assets/ml/chord_crnn.bin')` → `ml_chord_decoder.dart`).
  A Live izolátum csak a strum-súlyokat kapja
  (`real_strum_engine.dart::_liveCrnnWeights`).
- A manifest bejegyzés **létezik**, és a deklarált sha256
  `8f7596d45784fecd472be3bda141599e77a690edc8d526b85a9929532709fc74`
  **egyezik** az asset tényleges hash-ével (python, 2026-09-09) → a
  manifestbe **nem kellett** új sort írni.
- `assets/ml/model_manifest.json` nincs a `pubspec.yaml` asset-listáján, tehát
  futásidőben nem olvasható.
- `CqtExtractor` (100×144, hop 2048 @ 22,05 kHz) és `ChordCrnn` (25 osztály)
  megvan és paritás-tesztelt.

## 3. Scope

**Benne:** `engine/ml/chord_crnn_shadow_runner.dart` (aktiválás +
integritás + klip- és streaming-illesztő); `ChordShadowObserver` + a
gyök/minőség mátrix; a `RecognitionRuntimeInfo` akkord-mezői
(`chordModelId`/`chordModelVersion`/`chordModelSha256`/`chordFallbackReason`);
a Lab panel akkord-sora.

**Kívül:** `real_strum_engine.dart` (PKG-A — nem módosult, lásd ADR 0549 D5);
`pubspec.yaml`; `cqt_extractor.dart` (nem kapott streaming API-t);
`evaluation/**` (PKG-B); DSP-küszöbök.

## 4. Érintett fájlok

**Új (lib):** `engine/ml/chord_crnn_shadow_runner.dart`,
`data/shadow/chord_shadow_candidate.dart`
**Módosított (lib):** `data/shadow/recognition_shadow_observers.dart`,
`model/recognition_runtime_info.dart`, `providers/live_lab_provider.dart`,
`widgets/live_lab_panel.dart`
**Új (test):** `test/features/live/ml/chord_crnn_shadow_runner_test.dart`
**Változatlan:** `assets/ml/model_manifest.json` (a bejegyzés helyes volt)
**Docs:** `docs/adr/0549-*.md`, ez a brief, `docs/rag/chunks/018-*.md`

## 5. Kapuk

Változatlan ADR 0052 zöld kapu.

## 6. Acceptance

| # | Kritérium | Státusz |
|---|---|---|
| 1 | Asset-paritás: kód-konstans == manifest sha256 == a lemezen lévő bájtok | **PINNED-BY-TEST** — `code constant == manifest sha256 == the bytes on disk` |
| 2 | Élő wiring: a CRNN keretenként ad címkét a shadow-megfigyelőnek | **PINNED-BY-TEST** — `an OPEN chord gate does call it, once per emitted frame` |
| 3 | Shadow OFF → nulla költség (parse sem történik) | **PINNED-BY-TEST** |
| 4 | Hibás/csonka/hamis hash-ű asset → tipizált `FallbackReason`, nem néma no-op | **PINNED-BY-TEST** — 5 cella |
| 5 | `RecognitionRuntimeInfo` a chord-mezőkkel, fail-closed JSON-visszaolvasással | **PINNED-BY-TEST** |
| 6 | A kimenet KIZÁRÓLAG a shadow-bufferbe megy | **PINNED-BY-TEST** (bit-azonossági cella az R23-ban) |
| 7 | N.C. kezelés és a gyök/minőség mátrix | **PINNED-BY-TEST** — `a constant candidate against silence lands in the N.C. row` |
| 8 | Latency/memória riport eszközön | **NEEDS-MEASUREMENT** |
| 9 | NNLS↔CRNN↔ground-truth időben illesztett egyezés valós korpuszon | **NEEDS-MEASUREMENT** (R27 bemenete) |
| 10 | A streaming ablak és a folytonos CQT eltérése | **NEEDS-MEASUREMENT** — ADR 0549 D4 kimondja |

## 7. Verifikáció

Nem futtatható lokálisan. Semmilyen sikeres verifikáció nincs állítva.

## 8. Kockázatok

1. A streaming illesztő párnázási/állapot-újraindítási hibája **nem mért**.
   A Lab út ezért a determinisztikus `runClip`-et használja.
2. A `windowFrames = 100` teljes ablak újrafuttatása hoponként CPU-drága; ez
   shadow-only és `emitEveryFrames`-szel ritkítva, de eszközön nem mértük.
3. A hash-konstans elsodródhatna a modell cseréjekor — pontosan ezért van rá
   háromoldalú teszt.

## 9. Rollback

`recognitionChordShadowModeEnabled` vagy `chordModelRolloutStage` bármelyike
`off` → a sáv nem fut, és semmit nem tölt be.

## 10. Handoff

- PKG-A: az izolátumbeli élő bekötés patchje (chord-súlyok + visszaút) a
  PKG-E jelentés §5-ben; alkalmazása külön döntés.
- PKG-B: a `ChordShadowAggregate` konfúziós cellái közvetlenül az R27
  három-utas riport bemenete.
