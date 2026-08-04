import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import '../../domain/models/song_id.dart';
import '../../domain/models/song_practice_record.dart';
import '../../domain/repositories/song_progress_repository.dart';
import 'atomic_file_writer.dart';

abstract final class SongProgressRepositoryFailureCode {
  static const String read = 'songProgressRepository.read';
  static const String write = 'songProgressRepository.write';
}

/// File-backed, upsert-by-record-id Song Trainer progress persistence.
final class FileSongProgressRepository implements SongProgressRepository {
  FileSongProgressRepository._(this._file, this._records);

  final File _file;
  final Map<String, SongPracticeRecord> _records;

  static Future<FileSongProgressRepository> openAtDirectory({
    required Directory directory,
  }) async {
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}song_progress.json',
    );
    if (!await file.exists()) {
      return FileSongProgressRepository._(file, <String, SongPracticeRecord>{});
    }
    final records = _decodeRecords(await file.readAsString());
    return FileSongProgressRepository._(file, <String, SongPracticeRecord>{
      for (final record in records) record.id: record,
    });
  }

  @override
  Future<AppResult<List<SongPracticeRecord>>> load({
    SongId? songId,
    int? revision,
  }) async {
    final values = _records.values.where((record) {
      if (songId != null && record.songId != songId) return false;
      if (revision != null && record.songRevision != revision) return false;
      return true;
    }).toList()..sort((left, right) => left.id.compareTo(right.id));
    return AppResult<List<SongPracticeRecord>>.success(
      List<SongPracticeRecord>.unmodifiable(values),
    );
  }

  @override
  Future<AppResult<void>> save(SongPracticeRecord record) async {
    final next = <String, SongPracticeRecord>{..._records, record.id: record};
    try {
      final ordered = next.values.toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': songPracticeRecordSchemaVersion,
            'items': <Object?>[
              for (final value in ordered) _encodeRecord(value),
            ],
          }),
        ),
      );
      final outcome = const AtomicFileWriter().write(
        target: _file,
        bytes: bytes,
        verifier: (written) =>
            _decodeRecords(utf8.decode(written)).length == ordered.length,
      );
      if (!outcome.committed) {
        return AppResult<void>.failure(
          const StorageFailure(code: SongProgressRepositoryFailureCode.write),
        );
      }
      _records
        ..clear()
        ..addAll(next);
      return const AppResult<void>.success(null);
    } on Object catch (error, stackTrace) {
      return AppResult<void>.failure(
        StorageFailure(
          code: SongProgressRepositoryFailureCode.write,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

List<SongPracticeRecord> _decodeRecords(String source) {
  final envelope = _map(jsonDecode(source));
  if (_int(envelope['schemaVersion']) != songPracticeRecordSchemaVersion) {
    throw const FormatException('Unsupported Song progress schema.');
  }
  return _list(
    envelope['items'],
  ).map((item) => _decodeRecord(_map(item))).toList();
}

SongPracticeRecord _decodeRecord(Map<String, Object?> json) =>
    SongPracticeRecord(
      schemaVersion: _int(json['schemaVersion']),
      id: _string(json['id']),
      songId: SongId(_string(json['songId'])),
      songRevision: _int(json['songRevision']),
      source: SongProgressSource(
        measureId: _string(_map(json['source'])['measureId']),
        eventId: _string(_map(json['source'])['eventId']),
        measureIndex: _int(_map(json['source'])['measureIndex']),
        sectionId: _map(json['source'])['sectionId'] as String?,
      ),
      activeDuration: Duration(
        microseconds: _int(json['activeDurationMicros']),
      ),
      completed: _bool(json['completed']),
      score: _double(json['score']),
      recordedAt: DateTime.parse(_string(json['recordedAt'])).toUtc(),
      playbackOnly: _bool(json['playbackOnly']),
      isArchived: _bool(json['isArchived']),
    );

Map<String, Object?> _encodeRecord(SongPracticeRecord record) =>
    <String, Object?>{
      'schemaVersion': record.schemaVersion,
      'id': record.id,
      'songId': record.songId.value,
      'songRevision': record.songRevision,
      'source': <String, Object?>{
        'measureId': record.source.measureId,
        'eventId': record.source.eventId,
        'measureIndex': record.source.measureIndex,
        'sectionId': record.source.sectionId,
      },
      'activeDurationMicros': record.activeDuration.inMicroseconds,
      'completed': record.completed,
      'score': record.score,
      'recordedAt': record.recordedAt.toUtc().toIso8601String(),
      'playbackOnly': record.playbackOnly,
      'isArchived': record.isArchived,
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

bool _bool(Object? value) {
  if (value is! bool) throw const FormatException('Expected bool.');
  return value;
}
