/// Stable, recognised performance techniques attached to a [SongNoteEvent].
///
/// The enum is intentionally small and stays in sync with the SDD §11.4
/// list; techniques outside this set are still preserved on disk via the
/// [SongNoteTechnique.unknown] escape hatch, but the analyzer and
/// capability resolver MUST NOT pretend an unknown technique grants any
/// scoring capability (SDD §11.4, ADR 0113 §Döntés 4).
enum SongNoteTechniqueKind {
  hammerOn('hammer_on'),
  pullOff('pull_off'),
  slideUp('slide_up'),
  slideDown('slide_down'),
  bend('bend'),
  vibrato('vibrato'),
  palmMute('palm_mute'),
  harmonic('harmonic');

  const SongNoteTechniqueKind(this.code);

  /// Stable, lower-snake-case identifier persisted on the wire.
  final String code;
}

/// Documented upper bound on the raw/display length of an unknown
/// technique. Generous next to any realistic third-party code; rejects
/// obvious garbage.
const int maxSongNoteTechniqueRawLength = 128;

/// Immutable technique attached to a note event. The known set is closed
/// and lives in [SongNoteTechniqueKind]; anything else is preserved as a
/// raw code + display text pair so the codec can survive a future
/// technique without losing data (SDD §11.4 + §5 kötött döntés 2).
final class SongNoteTechnique {
  const SongNoteTechnique._({
    required this.kind,
    required this.rawCode,
    required this.displayText,
  });

  /// Construct a recognised technique.
  factory SongNoteTechnique.known(SongNoteTechniqueKind kind) {
    return SongNoteTechnique._(
      kind: kind,
      rawCode: kind.code,
      displayText: kind.code,
    );
  }

  /// Construct an unrecognised technique that the codec / analyser chose
  /// to preserve as data rather than drop. [rawCode] is the stable
  /// machine-readable identifier; [displayText] is what the UI shows.
  factory SongNoteTechnique.unknown({
    required String rawCode,
    required String displayText,
  }) {
    return SongNoteTechnique._(
      kind: null,
      rawCode: _normalizeRaw(rawCode),
      displayText: _normalizeDisplay(displayText),
    );
  }

  /// The recognised kind, or `null` when the technique came from an
  /// unknown raw code. `null` MUST NOT be interpreted as scoring
  /// capability (SDD §11.4 + §5 kötött döntés 2).
  final SongNoteTechniqueKind? kind;

  /// Stable wire identifier. For known techniques this matches [kind.code];
  /// for unknown techniques the importer-supplied code is preserved.
  final String rawCode;

  /// Localisable display label. Defaults to the raw code for known
  /// techniques; preserved verbatim for unknown techniques.
  final String displayText;

  bool get isKnown => kind != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongNoteTechnique &&
          other.kind == kind &&
          other.rawCode == rawCode &&
          other.displayText == displayText;

  @override
  int get hashCode => Object.hash(kind, rawCode, displayText);

  static String _normalizeRaw(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, 'rawCode', 'must not be empty');
    }
    if (trimmed.length > maxSongNoteTechniqueRawLength) {
      throw ArgumentError.value(
        value,
        'rawCode',
        'exceeds maxSongNoteTechniqueRawLength ($maxSongNoteTechniqueRawLength)',
      );
    }
    return trimmed;
  }

  static String _normalizeDisplay(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, 'displayText', 'must not be empty');
    }
    if (trimmed.length > maxSongNoteTechniqueRawLength) {
      throw ArgumentError.value(
        value,
        'displayText',
        'exceeds maxSongNoteTechniqueRawLength ($maxSongNoteTechniqueRawLength)',
      );
    }
    return trimmed;
  }
}
