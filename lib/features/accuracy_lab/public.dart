/// Public surface of the `accuracy_lab` feature. Hand-written — this
/// feature has no `public/` fragment directory, so the generated-barrel
/// freshness guard does not apply to it (ADR 0358 §0.0.1 R6).
library;

export 'data/lab_package_writer.dart';
export 'domain/lab_capture_package.dart';
export 'domain/lab_consent.dart';
export 'domain/lab_task.dart';
