/// Public live-detection contract for other features (SDD Ch2 §10.4).
///
/// NOTE: the Live DSP/ML engine (`engine/dsp/`, `engine/ml/`) is deliberately
/// NOT exported. Analyze still imports those files directly and is carried on
/// the architecture-guard allowlist, because SDD Ch2 §10.3 defers the shared
/// audio/DSP boundary to a later round — publishing them here would declare a
/// stable contract for code that is about to move to `core/`.
library;

/// The chord-timeline label-stability gate above the pipeline's own chord
/// decision (E14-R12, ADR 0518).
export 'engine/recognition_stabilizer.dart';

/// The strum-engine seam (real/mock) Learn drives during a lesson.
export 'engine/strum_engine.dart';

/// The single output tap a shadow/A-B consumer hooks into the live path
/// (E14-R28 companion delivery for E14-R23, ADR 0545 D6) — interface plus its
/// no-op null object, so a consumer never has to reach into `engine/dsp/`.
export 'engine/recognition_shadow_observer.dart';

/// The frame the Practice observation gateway adapts (E02-R08).
export 'model/live_frame.dart';

/// The hard-negative sound-category taxonomy captured negative material is
/// labelled with (E14-R15, ADR 0521).
export 'domain/evaluation/negative_taxonomy.dart';

/// Which strum model produced a verdict, or why it fell back (E14-R03,
/// ADR 0355) — Flutter-independent telemetry for the Lab and the local
/// accuracy export.
export 'model/recognition_runtime_info.dart';

/// The versioned, Flutter-independent felismerési szerződés — separate
/// chord- and direction-confidence, typed decision states (E14-R04, ADR
/// 0505). `live_pipeline.dart` is not rewired to it yet; this is the
/// contract + the `LiveFrame` compatibility adapter only.
export 'domain/recognition/chord_latch_diagnostics.dart';
export 'domain/recognition/chord_prediction.dart';
export 'domain/recognition/live_frame_adapter.dart';
export 'domain/recognition/recognition_decision.dart';
export 'domain/recognition/recognition_frame.dart';

/// The construction-time recognition regime and the only carrier an
/// expected-chord hint can travel in (E14-R30, ADR 0544) — the Live screen's
/// product modes map onto this, and `PKG-F` needs it to build the right
/// engine per mode.
export 'domain/recognition/recognition_mode.dart';

/// What one device's audio input needs to reach the nominal level (E14-R31,
/// ADR 0552 D4). The CONSUMER side of the audio-setup wizard's seam: the
/// wizard (`features/onboarding/audio_setup`) is the intended producer, the
/// Live preprocessing stage the only consumer. Exported here because the
/// producer lives in another feature and `engine/dsp/` is deliberately not
/// on the barrel.
export 'domain/recognition/device_audio_profile.dart';
export 'domain/recognition/signal_quality_snapshot.dart';
export 'domain/recognition/strum_prediction.dart';

/// Live frame stream + engine lifecycle providers.
export 'providers/live_providers.dart';

/// The ↓/↑ arrow, reused by the Analyze timeline.
export 'widgets/strum_arrow.dart';
