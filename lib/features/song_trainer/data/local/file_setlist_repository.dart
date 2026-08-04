import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import '../../domain/models/song_id.dart';
import '../../domain/models/song_setlist.dart';
import '../../domain/models/trainer_range.dart';
import '../../domain/repositories/setlist_repository.dart';
import 'atomic_file_writer.dart';

abstract final class SetlistRepositoryFailureCode {
  static const String read = 'setlistRepository.read';
  static const String write = 'setlistRepository.write';
}

/// File-backed Setlist V2 storage with verified atomic replacement.
final class FileSetlistRepository implements SetlistRepository {
  FileSetlistRepository._(this._file, this._setlists);

  final File _file;
  final Map<String, SongSetlist> _setlists;

  static Future<FileSetlistRepository> openAtDirectory({
    required Directory directory,
  }) async {
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}setlists.json',
    );
    if (!await file.exists()) {
      return FileSetlistRepository._(file, <String, SongSetlist>{});
    }
    final decoded = _decodeSetlists(await file.readAsString());
    return FileSetlistRepository._(file, <String, SongSetlist>{
      for (final setlist in decoded) setlist.id: setlist,
    });
  }

  @override
  Future<AppResult<List<SongSetlist>>> list() async {
    final values = _setlists.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return AppResult<List<SongSetlist>>.success(
      List<SongSetlist>.unmodifiable(values),
    );
  }

  @override
  Future<AppResult<SongSetlist?>> get(String id) async =>
      AppResult<SongSetlist?>.success(_setlists[id]);

  @override
  Future<AppResult<void>> save(SongSetlist setlist) async {
    final next = <String, SongSetlist>{..._setlists, setlist.id: setlist};
    final written = await _write(next);
    if (written.isFailure) return written;
    _setlists
      ..clear()
      ..addAll(next);
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> delete(String id) async {
    if (!_setlists.containsKey(id)) return const AppResult<void>.success(null);
    final next = <String, SongSetlist>{..._setlists}..remove(id);
    final written = await _write(next);
    if (written.isFailure) return written;
    _setlists
      ..clear()
      ..addAll(next);
    return const AppResult<void>.success(null);
  }

  Future<AppResult<void>> _write(Map<String, SongSetlist> next) async {
    try {
      final ordered = next.values.toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': songSetlistSchemaVersion,
            'items': <Object?>[
              for (final setlist in ordered) _encodeSetlist(setlist),
            ],
          }),
        ),
      );
      final outcome = const AtomicFileWriter().write(
        target: _file,
        bytes: bytes,
        verifier: (written) {
          final restored = _decodeSetlists(utf8.decode(written));
          return restored.length == ordered.length &&
              restored.map((setlist) => setlist.id).join('|') ==
                  ordered.map((setlist) => setlist.id).join('|');
        },
      );
      if (!outcome.committed) {
        return AppResult<void>.failure(
          const StorageFailure(code: SetlistRepositoryFailureCode.write),
        );
      }
      return const AppResult<void>.success(null);
    } on Object catch (error, stackTrace) {
      return AppResult<void>.failure(
        StorageFailure(
          code: SetlistRepositoryFailureCode.write,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

List<SongSetlist> _decodeSetlists(String source) {
  final envelope = _map(jsonDecode(source));
  if (_int(envelope['schemaVersion']) != songSetlistSchemaVersion) {
    throw const FormatException('Unsupported Setlist schema.');
  }
  return _list(
    envelope['items'],
  ).map((item) => _decodeSetlist(_map(item))).toList();
}

SongSetlist _decodeSetlist(Map<String, Object?> json) => SongSetlist(
  schemaVersion: _int(json['schemaVersion']),
  id: _string(json['id']),
  name: _string(json['name']),
  notes: json['notes'] as String?,
  createdAt: DateTime.parse(_string(json['createdAt'])).toUtc(),
  updatedAt: DateTime.parse(_string(json['updatedAt'])).toUtc(),
  items: _list(json['items']).map((item) => _decodeItem(_map(item))).toList(),
);

SongSetlistItem _decodeItem(Map<String, Object?> json) => SongSetlistItem(
  id: _string(json['id']),
  songId: SongId(_string(json['songId'])),
  initialAvailability: SetlistItemAvailability.values.byName(
    _string(json['availability']),
  ),
  overrides: _decodeOverrides(_map(json['overrides'])),
);

SetlistItemOverrides _decodeOverrides(Map<String, Object?> json) =>
    SetlistItemOverrides(
      trackId: switch (json['trackId']) {
        String value => SongTrackId(value),
        _ => null,
      },
      range: _decodeRange(_map(json['range'])),
      speedMultiplier: _double(json['speedMultiplier']),
      loopCount: _int(json['loopCount']),
      countInBars: _int(json['countInBars']),
      pauseAfter: Duration(microseconds: _int(json['pauseAfterMicros'])),
      capoOverride: json['capoOverride'] as int?,
      tuningOverrideCode: json['tuningOverrideCode'] as String?,
    );

TrainerRange _decodeRange(Map<String, Object?> json) =>
    switch (_string(json['kind'])) {
      'full' => const FullSongRange(),
      'measure' => MeasureRange(
        start: _int(json['start']),
        endExclusive: _int(json['endExclusive']),
      ),
      'section' => SectionRange(SongSectionId(_string(json['sectionId']))),
      'bookmark' => BookmarkRange(
        songId: SongId(_string(json['songId'])),
        songRevision: _int(json['songRevision']),
        range: _decodeRange(_map(json['range'])),
      ),
      _ => throw const FormatException('Unknown TrainerRange kind.'),
    };

Map<String, Object?> _encodeSetlist(SongSetlist setlist) => <String, Object?>{
  'schemaVersion': setlist.schemaVersion,
  'id': setlist.id,
  'name': setlist.name,
  'notes': setlist.notes,
  'createdAt': setlist.createdAt.toUtc().toIso8601String(),
  'updatedAt': setlist.updatedAt.toUtc().toIso8601String(),
  'items': <Object?>[for (final item in setlist.items) _encodeItem(item)],
};

Map<String, Object?> _encodeItem(SongSetlistItem item) => <String, Object?>{
  'id': item.id,
  'songId': item.songId.value,
  'availability': item.initialAvailability.name,
  'overrides': _encodeOverrides(item.overrides),
};

Map<String, Object?> _encodeOverrides(SetlistItemOverrides overrides) =>
    <String, Object?>{
      'trackId': overrides.trackId?.value,
      'range': _encodeRange(overrides.range),
      'speedMultiplier': overrides.speedMultiplier,
      'loopCount': overrides.loopCount,
      'countInBars': overrides.countInBars,
      'pauseAfterMicros': overrides.pauseAfter.inMicroseconds,
      'capoOverride': overrides.capoOverride,
      'tuningOverrideCode': overrides.tuningOverrideCode,
    };

Map<String, Object?> _encodeRange(TrainerRange range) => switch (range) {
  FullSongRange() => const <String, Object?>{'kind': 'full'},
  MeasureRange(:final start, :final endExclusive) => <String, Object?>{
    'kind': 'measure',
    'start': start,
    'endExclusive': endExclusive,
  },
  SectionRange(:final sectionId) => <String, Object?>{
    'kind': 'section',
    'sectionId': sectionId.value,
  },
  BookmarkRange(:final songId, :final songRevision, :final range) =>
    <String, Object?>{
      'kind': 'bookmark',
      'songId': songId.value,
      'songRevision': songRevision,
      'range': _encodeRange(range),
    },
};

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('Expected object.');
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected list.');
  return List<Object?>.from(value);
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected string.');
  return value;
}

int _int(Object? value) {
  if (value is! num || value is double && value != value.roundToDouble()) {
    throw const FormatException('Expected integer.');
  }
  return value.toInt();
}

double _double(Object? value) {
  if (value is! num) throw const FormatException('Expected number.');
  return value.toDouble();
}
