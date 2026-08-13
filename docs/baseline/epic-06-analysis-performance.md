# Epic 06 — Analysis cache és performance baseline

**Mérés dátuma:** 2026-08-13. **Parancs:** `flutter test --reporter expanded tool/audio_analysis_benchmark.dart`. Környezet: Linux `6.17.0-1019-oracle`, aarch64, 4 CPU. Az idők gép- és terhelésfüggő baseline-ok, nem merge-küszöbök.

Az R28 benchmark a meglévő V1 három fixture-ét futtatja újra változatlanul (`silence_2s`, `strums_120_bpm`, `progression_c_g_am_f`), és a V2 cache-infrastruktúrát külön méri. Konkrét V2 stage-lista még nincs: `analysisV2RunnerProvider` fail-closed, ezért a V2-cancel késleltetés még nem mérhető. Ez nem nullának értendő, hanem explicit `not available` állapot.

## Futás kimenete

```
CACHE {"missMicroseconds":30589,"hitMicroseconds":5317,"entryCount":1,"totalPayloadBytes":4,"cancelLatencyMicroseconds":null,"cancelMeasurement":"not available: V2 runner is not composed"}
MODEL {"asset":"assets/ml/strum_crnn.bin","bytes":1456371,"readAndParseMicroseconds":43578}
FIXTURE {"name":"silence_2s","analysisMicroseconds":190721,"durationSec":2.0,"bpm":0.0,"strumCount":0,"chordSegmentCount":0,"chordTimeline":[],"modelAssetBytes":1456371}
FIXTURE {"name":"strums_120_bpm","analysisMicroseconds":496777,"durationSec":2.6,"bpm":120.1853197674418,"strumCount":5,"chordSegmentCount":1,"chordTimeline":[{"label":"Em","startSec":0.18575963718820862,"endSec":2.6}],"modelAssetBytes":1456371}
FIXTURE {"name":"progression_c_g_am_f","analysisMicroseconds":308328,"durationSec":3.2,"bpm":74.89809782608695,"strumCount":3,"chordSegmentCount":4,"chordTimeline":[{"label":"C","startSec":0.18575963718820862,"endSec":0.8359183673469388},{"label":"G","startSec":0.8359183673469388,"endSec":1.5789569160997732},{"label":"Am","startSec":1.5789569160997732,"endSec":2.414875283446712},{"label":"F","startSec":2.414875283446712,"endSec":3.2}],"modelAssetBytes":1456371}
DETERMINISM_SHA256 071925bcc69f53579dddbeb505375ef897760c84efd1f7255db90f4465f1d7b6
```

## Értelmezés

- A két egymást követő V1 futásnak a harnessen belül azonos event/chord/BPM JSON-bájtokat kell adnia; a fenti SHA-256 ennek a determinisztikus eredménynek a bizonyítéka.
- A cache-hit (`5 317 µs`) kisebb volt a cache-missnél (`30 589 µs`) ezen a futáson, de ez nem teljes V2 pipeline teljesítményígéret.
- A model read+parse 43 578 µs; a `ModelByteCache` egységtesztje külön bizonyítja, hogy egy futás három stage-hívója ezt egyetlen read+parse-ra coalesceli.
- A `Float32List`/`TransferableTypedData` átállás nem történt meg. Bevezetéséhez külön körben mért paritás és mérhető gyorsulás szükséges az ADR 0248 szerint.
