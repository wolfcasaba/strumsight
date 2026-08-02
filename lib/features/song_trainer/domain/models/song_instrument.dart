import '../../../../core/music/tuning.dart';

/// Stable exception thrown by [SongInstrument] validation.
class SongInstrumentValidationException implements Exception {
  SongInstrumentValidationException._(this.code);

  /// One of [SongInstrumentValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'SongInstrumentValidationException($code)';
}

/// Stable machine-readable codes emitted by [SongInstrument] validation.
abstract final class SongInstrumentValidationCode {
  static const String nameEmpty = 'songInstrument.name.empty';
  static const String nameTooLong = 'songInstrument.name.tooLong';
}

/// Documented upper bound on a song-instrument display name. Generous next
/// to any realistic instrument label; rejects obvious garbage.
const int maxSongInstrumentNameLength = 64;

/// Immutable description of the instrument a [SongTrack] is played on
/// (ADR 0113 §Döntés 2 — the canonical tuning contract lives in core, the
/// Song Trainer domain never redefines a tuning value object).
///
/// The instrument name is the only strictly required field — the optional
/// [tuning] reference is meaningful for fretted instruments (guitar,
/// bass, ukulele, …) and intentionally `null` for percussion, vocals or
/// non-pitched tracks.
final class SongInstrument {
  SongInstrument({required String name, this.tuning})
    : name = _normalizeName(name);

  /// Trimmed, non-empty instrument display name (e.g. "Guitar", "Bass",
  /// "Vocals"). Persisted as-is by the codec.
  final String name;

  /// Optional canonical [Tuning] for fretted instruments. `null` for
  /// percussion / vocals / any non-fretted instrument.
  final Tuning? tuning;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongInstrument && other.name == name && other.tuning == tuning;

  @override
  int get hashCode => Object.hash(name, tuning);

  static String _normalizeName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw SongInstrumentValidationException._(
        SongInstrumentValidationCode.nameEmpty,
      );
    }
    if (trimmed.length > maxSongInstrumentNameLength) {
      throw SongInstrumentValidationException._(
        SongInstrumentValidationCode.nameTooLong,
      );
    }
    return trimmed;
  }
}
