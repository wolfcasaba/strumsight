/// Public clip-analysis contract for other features (SDD Ch2 §10.4).
///
/// Consumers must import this boundary instead of Analyze internals; the
/// analyzer/recorder/DSP wiring behind it is free to change.
library;

/// The analysed clip itself — timeline, chords, strums, ML diagnostics.
/// Library, Songs, Learn, Share and Diagnostics all persist or render it.
export 'model/analyze_result.dart';

/// Run/record/cancel an analysis (Live's Lab panel drives it too).
export 'providers/analyze_providers.dart';

/// The chord/strum timeline widget, reused by the saved-session detail screen.
export 'widgets/timeline_view.dart';

/// ML-vs-DSP comparison used by the Lab diagnostics panel.
export 'engine/ml_chord_decoder.dart';
