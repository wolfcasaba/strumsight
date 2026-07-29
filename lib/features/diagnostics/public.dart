/// Public Lab-diagnostics contract for other features (SDD Ch2 §10.4).
///
/// Everything here is inert unless Lab mode is on — see the Lab-mode gate in
/// Settings. Raw audio never leaves the device without that opt-in.
library;

/// Consent flag, uploader and upload status.
export 'providers/diagnostics_providers.dart';

/// The ML-vs-DSP agreement panel shown under Analyze/Live results.
export 'widgets/diagnostics_panel.dart';
