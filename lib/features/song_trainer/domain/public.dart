/// Public boundary of the Song Trainer V2 domain layer (E03-R02, ADR 0089
/// §Döntés 1, SDD Ch4 §8.1).
///
/// This barrel is the **only** entry point the rest of the app (Practice
/// Engine adapters, importers, UI) is allowed to import from
/// (`package:strumsight/features/song_trainer/domain/public.dart`). The
/// domain models themselves are intentionally kept inside
/// `lib/features/song_trainer/domain/models/` and re-exported here so the
/// cross-feature surface stays reviewable in a single file.
///
/// The domain is framework-independent: no Flutter, Riverpod, Dio,
/// SharedPreferences, l10n or storage plugin import is allowed below this
/// line. The cross-feature import audit in
/// `test/features/song_trainer/domain/song_document_test.dart` enforces
/// the rule at the round gate (the architecture guard in
/// `tool/check_architecture.dart` does not yet cover `song_trainer/domain`
/// because the pre-flight §0.0 measurement showed it missing from the
/// `_isSharedDomain` allowlist — that file is in another round's scope).
library;

export 'models/backing_audio_track.dart';
export 'models/import_warning.dart';
export 'models/key_map.dart';
export 'models/meter_map.dart';
export 'models/song_asset_reference.dart';
export 'models/song_capability.dart';
export 'models/song_document.dart';
export 'models/song_event.dart';
export 'models/song_id.dart';
export 'models/song_instrument.dart';
export 'models/song_marker.dart';
export 'models/song_metadata.dart';
export 'models/song_note_technique.dart';
export 'models/song_measure.dart';
export 'models/song_section.dart';
export 'models/song_source.dart';
export 'models/song_track.dart';
export 'models/song_validation_report.dart';
export 'models/tempo_map.dart';
export 'services/note_track_analyzer.dart';
export 'services/song_capability_resolver.dart';
export 'services/song_normalizer.dart';
export 'services/song_time_map.dart';
export 'services/song_validator.dart';
