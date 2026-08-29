// Common benchmark-record schema (ADR 0474, E12-R14).
//
// This file is the single source of truth for the JSON shape both
// `docs/performance/baseline.json` and `tool/compare_benchmarks.py` speak.
// Only `dart:convert` + `dart:core` are used (no package dependency): the
// round's allowed-files list does not include `pubspec.yaml`, and a new
// dependency would fail `flutter pub get` outside this file's control.
import 'dart:convert';

/// Schema version this file's parser understands. A record whose own
/// `schemaVersion` does not match is rejected rather than guessed at.
const int kBenchmarkRecordSchemaVersion = 1;

/// The four value classes a benchmark number can belong to (ADR 0474 D3).
/// Only `measured` values are ever compared for regression; the other three
/// document a number that is not a device measurement, so mixing them into
/// a regression comparison would fabricate a measurement that never
/// happened.
const List<String> kBenchmarkRecordKinds = <String>[
  'measured',
  'upperBound',
  'derivedContract',
  'target',
];

/// The two directions a metric's "better" can point (ADR 0474 D7). There is
/// deliberately no default: a record without one is malformed.
const List<String> kBenchmarkRecordDirections = <String>[
  'lowerIsBetter',
  'higherIsBetter',
];

/// The closed device dictionary (ADR 0474 D2): the four physical devices
/// from the Round 13 device matrix (`docs/testing/device-matrix.yaml`) plus
/// `ci_host` for measurements taken on the machine running the test suite
/// rather than on a physical phone. Inventing a new device id is forbidden;
/// an unrecognised value is a parse failure, not a silent new entry.
const List<String> kBenchmarkRecordDeviceIds = <String>[
  'pixel_6a',
  'pixel_7',
  'samsung_galaxy_a54',
  'xiaomi_redmi_note_12',
  'ci_host',
];

/// Thrown when a JSON map does not satisfy the benchmark-record contract.
/// A missing or invalid field is always a parse failure — this schema has
/// no optional metadata and no defaulted device or direction (ADR 0474 D1,
/// D2, D7).
class BenchmarkRecordFormatException implements Exception {
  BenchmarkRecordFormatException(this.message);

  final String message;

  @override
  String toString() => 'BenchmarkRecordFormatException: $message';
}

/// One benchmark measurement, upper bound, derived contract or target
/// (ADR 0474 D3), always carrying build and device metadata (D1) and a
/// repository-relative source reference (D4).
class BenchmarkRecord {
  const BenchmarkRecord({
    required this.schemaVersion,
    required this.metric,
    required this.value,
    required this.unit,
    required this.sampleCount,
    required this.kind,
    required this.direction,
    required this.source,
    required this.buildSha,
    required this.deviceId,
    required this.timestamp,
  });

  /// Parses and validates a single record. Throws
  /// [BenchmarkRecordFormatException] naming the first invalid or missing
  /// field — there is no partially-valid record.
  factory BenchmarkRecord.fromJson(Map<String, Object?> json) {
    String requireNonEmptyString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw BenchmarkRecordFormatException(
          'missing or empty required field "$key"',
        );
      }
      return value;
    }

    int requireInt(String key) {
      final value = json[key];
      if (value is! int) {
        throw BenchmarkRecordFormatException(
          'missing or non-integer required field "$key"',
        );
      }
      return value;
    }

    double requireNumber(String key) {
      final value = json[key];
      if (value is! num) {
        throw BenchmarkRecordFormatException(
          'missing or non-numeric required field "$key"',
        );
      }
      return value.toDouble();
    }

    final schemaVersion = requireInt('schemaVersion');
    if (schemaVersion != kBenchmarkRecordSchemaVersion) {
      throw BenchmarkRecordFormatException(
        'unsupported schemaVersion $schemaVersion (this parser understands '
        '$kBenchmarkRecordSchemaVersion)',
      );
    }

    final kind = requireNonEmptyString('kind');
    if (!kBenchmarkRecordKinds.contains(kind)) {
      throw BenchmarkRecordFormatException(
        'unknown kind "$kind" (expected one of $kBenchmarkRecordKinds)',
      );
    }

    final direction = requireNonEmptyString('direction');
    if (!kBenchmarkRecordDirections.contains(direction)) {
      throw BenchmarkRecordFormatException(
        'unknown direction "$direction" (expected one of '
        '$kBenchmarkRecordDirections)',
      );
    }

    final deviceId = requireNonEmptyString('deviceId');
    if (!kBenchmarkRecordDeviceIds.contains(deviceId)) {
      throw BenchmarkRecordFormatException(
        'unknown deviceId "$deviceId" (expected one of '
        '$kBenchmarkRecordDeviceIds)',
      );
    }

    final source = requireNonEmptyString('source');
    if (source.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source)) {
      throw BenchmarkRecordFormatException(
        'source must be a repository-relative path, got absolute path '
        '"$source"',
      );
    }

    return BenchmarkRecord(
      schemaVersion: schemaVersion,
      metric: requireNonEmptyString('metric'),
      value: requireNumber('value'),
      unit: requireNonEmptyString('unit'),
      sampleCount: requireInt('sampleCount'),
      kind: kind,
      direction: direction,
      source: source,
      buildSha: requireNonEmptyString('buildSha'),
      deviceId: deviceId,
      timestamp: requireNonEmptyString('timestamp'),
    );
  }

  final int schemaVersion;
  final String metric;
  final double value;
  final String unit;
  final int sampleCount;
  final String kind;
  final String direction;
  final String source;
  final String buildSha;
  final String deviceId;
  final String timestamp;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'metric': metric,
    'value': value,
    'unit': unit,
    'sampleCount': sampleCount,
    'kind': kind,
    'direction': direction,
    'source': source,
    'buildSha': buildSha,
    'deviceId': deviceId,
    'timestamp': timestamp,
  };
}

/// Parses a `{"records": [...]}` document into [BenchmarkRecord]s. Throws
/// [BenchmarkRecordFormatException] on the first invalid record — a
/// benchmark record set is valid as a whole or not parsed at all.
List<BenchmarkRecord> parseBenchmarkRecords(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, Object?>) {
    throw BenchmarkRecordFormatException(
      'top-level benchmark-record document must be a JSON object',
    );
  }
  final records = decoded['records'];
  if (records is! List) {
    throw BenchmarkRecordFormatException(
      'benchmark-record document is missing the "records" array',
    );
  }
  return records
      .map((Object? record) {
        if (record is! Map<String, Object?>) {
          throw BenchmarkRecordFormatException(
            'each entry in the "records" array must be a JSON object, got '
            '${record.runtimeType}',
          );
        }
        return BenchmarkRecord.fromJson(record);
      })
      .toList(growable: false);
}
