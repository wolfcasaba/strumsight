# Epic 06 — Audio Analysis V1 technikai baseline

**Mérés dátuma:** 2026-08-11. **Parancs:** `flutter test --reporter expanded tool/audio_analysis_baseline.dart`. A mérési környezet Linux `6.17.0-1019-oracle`, aarch64, 4 CPU; a futásidő ezért baseline, nem küszöb. Forrás: `tool/audio_analysis_baseline.dart:24-42`; `uname -srvmo` és `getconf _NPROCESSORS_ONLN` 2026-08-11-i kimenete.

Ez V1-leltár, nem V2-specifikáció. A V2 szerződései: [ADR 0215](../adr/0215-analysis-document-versioning.md), [ADR 0216](../adr/0216-analysis-confidence-calibration-and-abstention.md), [ADR 0217](../adr/0217-analysis-raw-audio-retention.md), [ADR 0218](../adr/0218-analysis-metric-id-and-version-governance.md), [ADR 0219](../adr/0219-analysis-capability-aware-publication.md) és [ADR 0220](../adr/0220-audio-analysis-v2-parallel-rollout-boundary.md).

## V1 működési térkép

| Terület | Mai, hivatkozott V1 állapot |
|---|---|
| Állapotgép | `idle`, `recording`, `analyzing`, `done`, `micDenied`, `micError`; nincs `cancelled`, `degraded`, progress vagy run ID. Forrás: `lib/features/analyze/providers/analyze_providers.dart:21-34`. |
| Felvétel | `ClipRecorder` memóriabeli `List<double>` puffert használ. Forrás: `lib/features/analyze/engine/clip_recorder.dart:9-58`. |
| Eredmény | `AnalyzeResult`: `durationSec`, `bpm`, `chords`, `strums`, `beatsPerBar` (4) és opcionális `diagnostics`; nincs schemaVersion, provenance, per-metrika confidence vagy availability. Forrás: `lib/features/analyze/model/analyze_result.dart:113-136`. |
| Strum/tempo | A `ClipAnalyzer` 2048 mintás chunkokkal hajtja a `LivePipeline`-t; BPM a pozitív intervallumok mediánjából, `30..300` clamp-pel készül. Forrás: `lib/features/analyze/engine/clip_analyzer.dart:113-142,229-240`. |
| Chord | Batch NNLS chroma után Viterbi backtrace épít folytonos akkordszegmenseket. Forrás: `lib/features/analyze/engine/clip_analyzer.dart:145-226`; konstansok: `lib/features/live/engine/dsp/dsp_config.dart:16-17`. |
| CRNN/Lab | A `computeClipAnalysis` main-isolate-on tölti be a strum assetet, `compute`-tal futtat; Lab módban chord CRNN diagnosztikát csatol. Forrás: `lib/features/analyze/providers/analyze_providers.dart:36-120`. |
| Import/lifecycle | WAV-import külön út; a képernyő leválásakor a felvétel törlődik; nem üres eredmény streak- és practice-log bejegyzést ad. Forrás: `lib/features/analyze/providers/analyze_providers.dart:152-250`. |
| Library | `AnalyzedSession` azonosítót, létrehozási időt, címet, `AnalyzeResult`-ot és `customTitle`-t serializál. Forrás: `lib/features/library/model/analyzed_session.dart:8-54`. A repository `ss.library.sessions` és legacy `library_sessions` kulcsot használ, a cap 100. Forrás: `lib/features/library/data/library_repository.dart:14-55`, `lib/core/storage/storage_keys.dart:37-39,145-171`, `lib/core/storage/json_document_store.dart:169-250`. |

## Mért V1 eredmények

A harness három, seed és óra nélküli fixture-t generál: két másodperc digitális csend, öt 0,5 s közű alternáló strum és C–G–Am–F progresszió. Forrás: `tool/audio_analysis_baseline.dart:46-80,96-183`. A modell-overhead a `strum_crnn.bin` közvetlen olvasása és parse-a, `rootBundle` nélkül. Forrás: `tool/audio_analysis_baseline.dart:83-93`; production betöltés: `lib/features/analyze/providers/analyze_providers.dart:81-120`.

| Fixture | Futás A elemzés µs | Futás B elemzés µs | BPM | Strum | Chord-szegmens | Chord idővonal | Model asset byte |
|---|---:|---:|---:|---:|---:|---|---:|
| `silence_2s` | 186344 | 189598 | 0.0 | 0 | 0 | `[]` | 1456371 |
| `strums_120_bpm` | 476446 | 504544 | 120.1853197674418 | 5 | 1 | `Em [0.18575963718820862, 2.6]` | 1456371 |
| `progression_c_g_am_f` | 295281 | 312222 | 74.89809782608695 | 3 | 4 | `C [0.18575963718820862, 0.8359183673469388]`; `G [0.8359183673469388, 1.5789569160997732]`; `Am [1.5789569160997732, 2.414875283446712]`; `F [2.414875283446712, 3.2]` | 1456371 |

| Modell-mérés | Futás A | Futás B |
|---|---:|---:|
| `assets/ml/strum_crnn.bin` read+parse µs | 42439 | 45812 |

A fenti értékek a két tényleges futtatás `MODEL`/`FIXTURE` sorai. A futásidő nem determinisztikus és nem része az összehasonlításnak; a timeline, BPM, event count és asset-byte mezőkből készített UTF-8 JSON mindkét futásban `071925bcc69f53579dddbeb505375ef897760c84efd1f7255db90f4465f1d7b6` SHA-256-t adott. A harness egy futáson belül is két ilyen bájtsorozatot hasonlít össze. Forrás: `tool/audio_analysis_baseline.dart:24-42,233-252`.

**Peak memória: NEM MÉRT** (ok: a dart:developer/ProcessInfo itt nem adott reprodukálható processz-peak értéket; a harness csak explicit Stopwatch- és fájlméret-mérést végez). Forrás: `tool/audio_analysis_baseline.dart:53-93`.

## Feature és teszt inventory

Az Analyze production-fa **14 fájl, 2168 sor**; az Analyze tesztfa **15 fájl**, a Library tesztfa **4 fájl**, a property tesztfa **20 fájl**. Forrás: a HEAD-en futtatott `wc -l lib/features/analyze/**/*.dart lib/features/analyze/*.dart test/features/analyze/*.dart test/features/library/*.dart test/property/*.dart` és `rg --files` 2026-08-11-i kimenete.

| Production fájl | Sorok | Hivatkozott szerep |
|---|---:|---|
| `engine/chroma_denoise.dart` | 88 | Temporális chroma-denoise. Forrás: `lib/features/analyze/engine/chroma_denoise.dart:22-88`. |
| `engine/clip_analyzer.dart` | 241 | V1 DSP pipeline. Forrás: `lib/features/analyze/engine/clip_analyzer.dart:60-240`. |
| `engine/clip_recorder.dart` | 58 | In-memory recorder. Forrás: `lib/features/analyze/engine/clip_recorder.dart:9-58`. |
| `engine/hpss.dart` | 226 | HPSS segéd. Forrás: `lib/features/analyze/engine/hpss.dart:26-226`. |
| `engine/ml_chord_decoder.dart` | 250 | Lab chord-CRNN decoder. Forrás: `lib/features/analyze/engine/ml_chord_decoder.dart:34-250`. |
| `engine/wav_decoder.dart` | 2 | Core WAV-decoder re-export. Forrás: `lib/features/analyze/engine/wav_decoder.dart:1-2`. |
| `model/analyze_result.dart` | 198 | Eredmény- és timeline-modell. Forrás: `lib/features/analyze/model/analyze_result.dart:1-198`. |
| `model/analysis_vision_reference.dart` | 21 | Analyze–Vision evidence link. Forrás: `lib/features/analyze/model/analysis_vision_reference.dart:1-21`. |
| `providers/analyze_providers.dart` | 256 | Controller és model wiring. Forrás: `lib/features/analyze/providers/analyze_providers.dart:1-256`. |
| `providers/analysis_vision_adapter.dart` | 81 | Idő-leképezés. Forrás: `lib/features/analyze/providers/analysis_vision_adapter.dart:1-81`. |
| `screens/analyze_screen.dart` | 432 | Analyze képernyő. Forrás: `lib/features/analyze/screens/analyze_screen.dart:1-432`. |
| `widgets/analyze_skeleton.dart` | 127 | Skeleton. Forrás: `lib/features/analyze/widgets/analyze_skeleton.dart:1-127`. |
| `widgets/timeline_view.dart` | 170 | Timeline widget. Forrás: `lib/features/analyze/widgets/timeline_view.dart:1-170`. |
| `public.dart` | 18 | Publikus feature-határ. Forrás: `lib/features/analyze/public.dart:1-18`. |

| Tesztcsoport | Fájlok és sorok |
|---|---|
| Analyze (15) | `analysis_vision_adapter_test.dart` (111), `analyze_import_test.dart` (55), `analyze_screen_test.dart` (34), `batch_chord_timeline_test.dart` (61), `cancel_during_start_test.dart` (214), `cancel_on_leave_test.dart` (92), `chroma_denoise_test.dart` (139), `clip_analyzer_ml_test.dart` (147), `clip_analyzer_test.dart` (143), `hpss_test.dart` (163), `mic_error_parity_test.dart` (71), `ml_chord_wiring_test.dart` (146), `recorder_hardening_test.dart` (89), `timeline_view_test.dart` (53), `wav_decoder_test.dart` (139). Forrás: `test/features/analyze/*.dart:1-214`. |
| Library (4) | `library_cap_test.dart` (44), `library_test.dart` (108), `rename_capo_title_test.dart` (128), `session_rename_test.dart` (112). Forrás: `test/features/library/*.dart:1-128`. |
| Property (20) | `camera_transform_property_test.dart`, `chord_change_property_test.dart`, `chord_timeline_property_test.dart`, `clock_mapping_property_test.dart`, `crnn_ab_property_test.dart`, `dsp_property_test.dart`, `free_practice_property_test.dart`, `hand_track_property_test.dart`, `homography_property_test.dart`, `practice_engine_property_test.dart`, `practice_event_matcher_property_test.dart`, `practice_observation_property_test.dart`, `practice_scorer_property_test.dart`, `practice_session_controller_property_test.dart`, `practice_session_property_test.dart`, `song_normalizer_property_test.dart`, `song_progress_property_test.dart`, `song_time_map_property_test.dart`, `speed_builder_property_test.dart`, `superflux_property_test.dart`. Forrás: `test/property/*.dart:1-631`. |

## Cross-feature dependency map

Az allowlist 12 Analyze → Live bejegyzést tartalmaz és csak szűkülhet. Forrás: `tool/check_architecture.dart:3-22`.

1. `clip_analyzer.dart` → `chord_dictionary.dart`, `dsp_config.dart`, `live_pipeline.dart`, `nnls_chroma.dart`, `strum_direction_classifier.dart`, `viterbi_chord_decoder.dart`.
2. `ml_chord_decoder.dart` → `cqt_extractor.dart`, `viterbi_chord_decoder.dart`, `chord_crnn.dart`.
3. `analyze_providers.dart` → `chord_crnn.dart`, `crnn_strum_net.dart`, `strum_crnn.dart`.
