/// Pure-data reader for the legacy `Song` / `Setlist` JSON shape
/// (E03-R06, ADR 0116 §0.0, SDD §25.5).
///
/// The reader is the single boundary between the on-disk legacy bytes (a
/// JSON map under `StorageKeys.songs` / `StorageKeys.setlists`) and the
/// adapter. It deliberately **does not import** the legacy presentation
/// model (`lib/features/songs/model/song.dart`) — the migration adapter
/// must remain independent of the legacy feature so a future legacy
/// deletion cannot break the migration path (§5 kötött döntés 1).
///
/// The decoded shape is a tiny, immutable value-object tree:
///   [LegacySongRecord]   — id, name, chords, pattern, bpm, beatsPerBar,
///                          canonicalSha256
///   [LegacySetlistRecord] — id, name, songIds
///
/// The reader mirrors the legacy `Song.fromJson` semantics for the keys
/// it cares about, so the parity tests under `test/fixtures/song_trainer/
/// legacy/` continue to round-trip through the adapter with the same
/// values they locked in E03-R01.
library;
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

import '../../../../core/music/strum.dart';

/// Stable exception thrown by the legacy reader when the input JSON is
/// structurally invalid (missing required keys, wrong type, out-of-range
/// value). Carries a machine-readable code so a future migration runner
/// can branch on the failure without parsing messages.
class LegacySongReaderException implements Exception {
  LegacySongReaderException._(this.code, {this.field});

  /// One of [LegacySongReaderErrorCode]'s constants.
  final String code;

  /// The field that failed when the failure is scoped to one.
  final String? field;

  @override
  String toString() =>
      'LegacySongReaderException($code${field == null ? '' : ', field: $field'})';
}

/// Stable machine-readable codes emitted by [LegacySongReader].
abstract final class LegacySongReaderErrorCode {
  static const String songNotAnObject = 'legacyReader.song.notAnObject';
  static const String songIdMissing = 'legacyReader.song.id.missing';
  static const String songIdEmpty = 'legacyReader.song.id.empty';
  static const String songIdTooLong = 'legacyReader.song.id.tooLong';
  static const String songNameMissing = 'legacyReader.song.name.missing';
  static const String songPatMissing = 'legacyReader.song.pat.missing';
  static const String songPatInvalidSlot = 'legacyReader.song.pat.invalidSlot';
  static const String songPatTooLong = 'legacyReader.song.pat.tooLong';
  static const String songChordsMissing = 'legacyReader.song.chords.missing';
  static const String songChordEmpty = 'legacyReader.song.chord.empty';
  static const String songChordTooLong = 'legacyReader.song.chord.tooLong';
  static const String songChordsTooLong = 'legacyReader.song.chords.tooLong';
  static const String songBpmMissing = 'legacyReader.song.bpm.missing';
  static const String songBpmInvalid = 'legacyReader.song.bpm.invalid';
  static const String songBpbInvalid = 'legacyReader.song.bpb.invalid';

  static const String setlistNotAnObject = 'legacyReader.setlist.notAnObject';
  static const String setlistIdMissing = 'legacyReader.setlist.id.missing';
  static const String setlistIdEmpty = 'legacyReader.setlist.id.empty';
  static const String setlistIdTooLong = 'legacyReader.setlist.id.tooLong';
  static const String setlistNameMissing = 'legacyReader.setlist.name.missing';
  static const String setlistSongsMissing =
      'legacyReader.setlist.songs.missing';
  static const String setlistSongIdEmpty =
      'legacyReader.setlist.songs.entryEmpty';
  static const String setlistSongsTooLong =
      'legacyReader.setlist.songs.tooLong';
}

/// Documented upper bound on the number of bars a legacy song may carry.
/// Mirrors the `maxSongBars` constant in the legacy presentation model so
/// the adapter and the legacy reader reject the same records.
const int legacyMaxSongBars = 512;

/// Documented upper bound on the number of entries a legacy setlist may
/// carry. Mirrors `maxSetlistEntries` in the legacy presentation model.
const int legacyMaxSetlistEntries = 500;

/// Documented upper bound on the pattern slot count. The legacy
/// `Song.fromJson` accepts any length and then trims / pads to
/// `beatsPerBar * 2` — the reader preserves that behaviour on the read
/// side and lets the adapter decide whether to surface a
/// [LegacyMigrationCode.patternLengthFitted] note.
const int legacyMaxPatternSlots = legacyMaxSongBars * 2;

/// Documented upper bound on a legacy chord label length.
const int legacyMaxChordLabelLength = 32;

/// Documented upper bound on a legacy song id length.
const int legacyMaxSongIdLength = 128;

/// Documented upper bound on a legacy setlist id length.
const int legacyMaxSetlistIdLength = 128;

/// Documented BPM bounds. Mirrors the legacy `Song.fromJson` contract
/// (1..400 inclusive).
const int legacyMinBpm = 1;
const int legacyMaxBpm = 400;

/// Documented beats-per-bar bounds. Mirrors the legacy `Song.fromJson`
/// default and the upper guard.
const int legacyMinBeatsPerBar = 1;
const int legacyMaxBeatsPerBar = 16;

/// Immutable, decoded form of a legacy `Song` JSON record.
///
/// Mirrors the legacy `Song` value object without importing it — the
/// reader is the only path that crosses the feature boundary, so this
/// record is the canonical input to the adapter.
@immutable
final class LegacySongRecord {
  /// Stable record constructor. The raw pattern is preserved as-is (the
  /// adapter decides whether to fit / report).
  const LegacySongRecord({
    required this.id,
    required this.name,
    required this.chords,
    required this.pattern,
    required this.bpm,
    required this.beatsPerBar,
    required this.canonicalSha256,
  });

  /// Stable, locally-unique song identifier (legacy key `id`).
  final String id;

  /// User-authored song name. Empty strings are accepted (a song the user
  /// never named is still the user's song).
  final String name;

  /// Chord label per bar, in play order. The reader rejects empty entries
  /// — they would render as a blank cell on the legacy side.
  final List<String> chords;

  /// Raw eighth-note strum pattern (length may differ from
  /// `beatsPerBar * 2` — the adapter surfaces the discrepancy).
  final List<StrumDirection?> pattern;

  /// Tempo in beats per minute.
  final int bpm;

  /// Beats per bar (the legacy default is 4 for records saved before the
  /// 3/4 meter was introduced).
  final int beatsPerBar;

  /// Lower-case hex SHA-256 of the canonical-form JSON of this record.
  /// Two records that decode to equal [LegacySongRecord]s (id, name,
  /// chords, pattern, bpm, beatsPerBar all equal) hash to the same
  /// digest. The adapter carries it onto the produced document's
  /// [SongSource.sha256] field.
  final String canonicalSha256;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacySongRecord &&
          other.id == id &&
          other.name == name &&
          _listEquals(other.chords, chords) &&
          _listEquals(other.pattern, pattern) &&
          other.bpm == bpm &&
          other.beatsPerBar == beatsPerBar &&
          other.canonicalSha256 == canonicalSha256;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(chords),
    Object.hashAll(pattern),
    bpm,
    beatsPerBar,
    canonicalSha256,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

/// Immutable, decoded form of a legacy `Setlist` JSON record.
@immutable
final class LegacySetlistRecord {
  const LegacySetlistRecord({
    required this.id,
    required this.name,
    required this.songIds,
  });

  /// Stable, locally-unique setlist identifier (legacy key `id`).
  final String id;

  /// User-authored setlist name. Empty strings are accepted.
  final String name;

  /// Song references in play order (the adapter treats duplicates as a
  /// fidelity note, not an error).
  final List<String> songIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacySetlistRecord &&
          other.id == id &&
          other.name == name &&
          _listEquals(other.songIds, songIds);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(songIds));

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

/// Pure, side-effect-free decoder for legacy Song / Setlist JSON maps
/// (E03-R06, ADR 0116 §0.0, SDD §25.5).
///
/// The reader never imports a presentation layer and never opens a
/// storage handle — it accepts an already-parsed JSON map and returns
/// either a [LegacySongRecord] or a [LegacySetlistRecord] (or a typed
/// exception). The codec-side use case (round-tripping a stored legacy
/// document) threads the raw bytes through `jsonDecode` first and then
/// calls this class.
final class LegacySongReader {
  /// Stable constructor — the reader carries no state.
  const LegacySongReader();

  /// Decode a legacy Song JSON map. The input is the raw value the legacy
  /// `KeyValueStore` returns under `StorageKeys.songs`.
  LegacySongRecord readSong(Map<String, dynamic> json) {
    _expectObject(json);

    final idRaw = json['id'];
    if (idRaw is! String) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songIdMissing,
        field: 'id',
      );
    }
    if (idRaw.isEmpty) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songIdEmpty,
        field: 'id',
      );
    }
    if (idRaw.length > legacyMaxSongIdLength) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songIdTooLong,
        field: 'id',
      );
    }
    final id = idRaw;

    final nameRaw = json['name'];
    if (nameRaw is! String) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songNameMissing,
        field: 'name',
      );
    }
    final name = nameRaw;

    final rawPat = json['pat'];
    if (rawPat is! String) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songPatMissing,
        field: 'pat',
      );
    }
    final pattern = <StrumDirection?>[];
    for (var i = 0; i < rawPat.length; i++) {
      pattern.add(_slot(rawPat[i]));
    }
    if (pattern.length > legacyMaxPatternSlots) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songPatTooLong,
        field: 'pat',
      );
    }

    final chordsRaw = json['chords'];
    if (chordsRaw is! List) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songChordsMissing,
        field: 'chords',
      );
    }
    final chords = <String>[];
    for (var i = 0; i < chordsRaw.length; i++) {
      final entry = chordsRaw[i];
      if (entry is! String) {
        throw LegacySongReaderException._(
          LegacySongReaderErrorCode.songChordEmpty,
          field: 'chords[$i]',
        );
      }
      if (entry.isEmpty) {
        throw LegacySongReaderException._(
          LegacySongReaderErrorCode.songChordEmpty,
          field: 'chords[$i]',
        );
      }
      if (entry.length > legacyMaxChordLabelLength) {
        throw LegacySongReaderException._(
          LegacySongReaderErrorCode.songChordTooLong,
          field: 'chords[$i]',
        );
      }
      chords.add(entry);
    }
    if (chords.length > legacyMaxSongBars) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songChordsTooLong,
        field: 'chords',
      );
    }

    final bpmRaw = json['bpm'];
    if (bpmRaw is! int) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songBpmMissing,
        field: 'bpm',
      );
    }
    if (bpmRaw < legacyMinBpm || bpmRaw > legacyMaxBpm) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songBpmInvalid,
        field: 'bpm',
      );
    }

    // `bpb` defaults to 4 to match the legacy reader contract for records
    // saved before the 3/4 meter was introduced (round 116).
    final beatsPerBarRaw = json['bpb'];
    final beatsPerBar = switch (beatsPerBarRaw) {
      null => 4,
      final int value
          when value >= legacyMinBeatsPerBar && value <= legacyMaxBeatsPerBar =>
        value,
      _ => throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songBpbInvalid,
        field: 'bpb',
      ),
    };

    return LegacySongRecord(
      id: id,
      name: name,
      chords: List<String>.unmodifiable(chords),
      pattern: List<StrumDirection?>.unmodifiable(pattern),
      bpm: bpmRaw,
      beatsPerBar: beatsPerBar,
      canonicalSha256: _canonicalSha256(
        id: id,
        name: name,
        chords: chords,
        pattern: pattern,
        bpm: bpmRaw,
        beatsPerBar: beatsPerBar,
      ),
    );
  }

  /// Decode a legacy Setlist JSON map.
  LegacySetlistRecord readSetlist(Map<String, dynamic> json) {
    _expectObject(json);

    final idRaw = json['id'];
    if (idRaw is! String) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.setlistIdMissing,
        field: 'id',
      );
    }
    if (idRaw.isEmpty) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.setlistIdEmpty,
        field: 'id',
      );
    }
    if (idRaw.length > legacyMaxSetlistIdLength) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.setlistIdTooLong,
        field: 'id',
      );
    }
    final id = idRaw;

    final nameRaw = json['name'];
    if (nameRaw is! String) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.setlistNameMissing,
        field: 'name',
      );
    }
    final name = nameRaw;

    final songsRaw = json['songs'];
    if (songsRaw is! List) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.setlistSongsMissing,
        field: 'songs',
      );
    }
    final songIds = <String>[];
    for (var i = 0; i < songsRaw.length; i++) {
      final entry = songsRaw[i];
      if (entry is! String) {
        throw LegacySongReaderException._(
          LegacySongReaderErrorCode.setlistSongIdEmpty,
          field: 'songs[$i]',
        );
      }
      if (entry.isEmpty) {
        throw LegacySongReaderException._(
          LegacySongReaderErrorCode.setlistSongIdEmpty,
          field: 'songs[$i]',
        );
      }
      songIds.add(entry);
    }
    if (songIds.length > legacyMaxSetlistEntries) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.setlistSongsTooLong,
        field: 'songs',
      );
    }

    return LegacySetlistRecord(
      id: id,
      name: name,
      songIds: List<String>.unmodifiable(songIds),
    );
  }

  static void _expectObject(Map<String, dynamic> json) {
    // jsonDecode of an empty input yields `null`, an array literal yields
    // `List`, and a scalar yields the scalar — none of those are objects.
    if (json.isEmpty && (json.keys.isEmpty)) {
      throw LegacySongReaderException._(
        LegacySongReaderErrorCode.songNotAnObject,
      );
    }
  }

  static StrumDirection? _slot(String token) => switch (token) {
    'd' => StrumDirection.down,
    'u' => StrumDirection.up,
    '-' => null,
    _ => throw LegacySongReaderException._(
      LegacySongReaderErrorCode.songPatInvalidSlot,
      field: 'pat',
    ),
  };

  static String _canonicalSha256({
    required String id,
    required String name,
    required List<String> chords,
    required List<StrumDirection?> pattern,
    required int bpm,
    required int beatsPerBar,
  }) {
    final patternStr = pattern.map(_directionToken).join();
    final canonical = <String, dynamic>{
      'id': id,
      'name': name,
      'chords': chords,
      'pat': patternStr,
      'bpm': bpm,
      'bpb': beatsPerBar,
    };
    final bytes = utf8.encode(jsonEncode(canonical));
    return crypto.sha256.convert(bytes).toString();
  }

  static String _directionToken(StrumDirection? direction) =>
      switch (direction) {
        StrumDirection.down => 'd',
        StrumDirection.up => 'u',
        null => '-',
      };
}
