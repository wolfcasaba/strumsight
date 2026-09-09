/// Public settings contract for other features (SDD Ch2 §10.4).
///
/// Only the preferences other features actually read are exported; the
/// settings screen and its cloud sync stay internal.
library;

export 'providers/capo_provider.dart';
export 'providers/input_latency_provider.dart';
export 'providers/lab_mode_provider.dart';
export 'providers/left_handed_provider.dart';
// E14-R41/R40 (ADR 0542): the beta-telemetry consent, the upload gate
// and the field-session tag resolver — the diagnostics/Lab capture path
// reaches them through this barrel, never through a deep import.
export 'providers/telemetry_consent_provider.dart';
export 'providers/tuning_reference_provider.dart';
export 'providers/visual_latency_provider.dart';
