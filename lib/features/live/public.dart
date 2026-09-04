/// Public live-detection contract for other features (SDD Ch2 §10.4).
///
/// NOTE: the Live DSP/ML engine (`engine/dsp/`, `engine/ml/`) is deliberately
/// NOT exported. Analyze still imports those files directly and is carried on
/// the architecture-guard allowlist, because SDD Ch2 §10.3 defers the shared
/// audio/DSP boundary to a later round — publishing them here would declare a
/// stable contract for code that is about to move to `core/`.
library;

/// The strum-engine seam (real/mock) Learn drives during a lesson.
export 'engine/strum_engine.dart';

/// The frame the Practice observation gateway adapts (E02-R08).
export 'model/live_frame.dart';

/// Which strum model produced a verdict, or why it fell back (E14-R03,
/// ADR 0355) — Flutter-independent telemetry for the Lab and the local
/// accuracy export.
export 'model/recognition_runtime_info.dart';

/// Live frame stream + engine lifecycle providers.
export 'providers/live_providers.dart';

/// The ↓/↑ arrow, reused by the Analyze timeline.
export 'widgets/strum_arrow.dart';
