/// Public surface of the privacy-safe telemetry contract (ADR 0484), plus
/// the opt-in beta consent, upload gate and recognition-aggregate event
/// added by SDD Ch14 Kör 41 (ADR 0542).
library;

export 'field_session_tag.dart';
export 'recognition_telemetry_event.dart';
export 'telemetry_consent.dart';
export 'telemetry_event.dart';
export 'telemetry_redactor.dart';
export 'telemetry_sink.dart';
export 'telemetry_upload_gate.dart';
