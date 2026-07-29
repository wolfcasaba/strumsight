/// The shared musical domain: the value objects more than one feature needs.
///
/// Everything exported here is **pure Dart** — no Flutter, Riverpod, Dio,
/// storage plugin, widget or l10n dependency (SDD Ch2 §10.1, enforced by
/// `tool/check_architecture.dart`). Import this barrel for the common case,
/// or a single file when you only need one type.
library;

export 'chord.dart';
export 'chord_event.dart';
export 'guitar_strings.dart';
export 'strum.dart';
export 'tuning.dart';
