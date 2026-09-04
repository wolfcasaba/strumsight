import 'dart:convert';

import 'lab_task.dart';

/// Schema version for the [LabCapturePackage] envelope (ADR 0358 D5).
const int labCapturePackageSchemaVersion = 1;

/// Thrown by [LabCapturePackage.fromJson] when `schemaVersion` is missing or
/// not [labCapturePackageSchemaVersion]. Reading an unknown version is a
/// typed failure, never a silent "assume latest" default (ADR 0054 pattern,
/// carried one level down by ADR 0358 D5).
final class LabCapturePackageSchemaVersionException implements Exception {
  const LabCapturePackageSchemaVersionException(this.foundVersion);

  final Object? foundVersion;

  @override
  String toString() =>
      'LabCapturePackageSchemaVersionException: expected schemaVersion '
      '$labCapturePackageSchemaVersion, found $foundVersion';
}

/// Device facts a Lab package may carry — deliberately closed to a handful
/// of non-identifying fields (ADR 0358 D2). No email, account token,
/// precise location, IMEI, advertising id, username or absolute file path.
final class LabDeviceMetadata {
  const LabDeviceMetadata({
    required this.modelName,
    required this.osVersion,
    required this.sampleRate,
    required this.channelCount,
    required this.appVersion,
  });

  final String modelName;
  final String osVersion;
  final int sampleRate;
  final int channelCount;
  final String appVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'modelName': modelName,
    'osVersion': osVersion,
    'sampleRate': sampleRate,
    'channelCount': channelCount,
    'appVersion': appVersion,
  };

  factory LabDeviceMetadata.fromJson(Map<String, Object?> json) =>
      LabDeviceMetadata(
        modelName: json['modelName']! as String,
        osVersion: json['osVersion']! as String,
        sampleRate: (json['sampleRate']! as num).toInt(),
        channelCount: (json['channelCount']! as num).toInt(),
        appVersion: json['appVersion']! as String,
      );
}

/// One marked span inside the captured recording, tying a stretch of audio
/// back to the [LabTask] the user was asked to play.
final class LabCaptureEvent {
  const LabCaptureEvent({
    required this.taskId,
    required this.family,
    required this.startSeconds,
    required this.endSeconds,
  });

  final String taskId;
  final LabTaskFamily family;
  final double startSeconds;
  final double endSeconds;

  Map<String, Object?> toJson() => <String, Object?>{
    'taskId': taskId,
    'family': family.name,
    'startSeconds': startSeconds,
    'endSeconds': endSeconds,
  };

  factory LabCaptureEvent.fromJson(Map<String, Object?> json) =>
      LabCaptureEvent(
        taskId: json['taskId']! as String,
        family: LabTaskFamily.values.byName(json['family']! as String),
        startSeconds: (json['startSeconds']! as num).toDouble(),
        endSeconds: (json['endSeconds']! as num).toDouble(),
      );
}

/// The deterministic, identifier-free record of one Lab capture session
/// (ADR 0358). Carries no raw audio itself — the WAV bytes are written
/// alongside it by `LabPackageWriter`, keyed by [packageId].
final class LabCapturePackage {
  const LabCapturePackage({
    required this.packageId,
    required this.capturedAt,
    required this.consentVersion,
    required this.device,
    required this.events,
  });

  final String packageId;

  /// When the capture happened. Supplied by the caller, never read from a
  /// clock inside this model or its writer (ADR 0358 D3) — that is what
  /// keeps two packages built from the same input byte-identical.
  final DateTime capturedAt;

  /// Which [LabConsentGranted.consentVersion] applied to this capture.
  final String consentVersion;

  final LabDeviceMetadata device;
  final List<LabCaptureEvent> events;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': labCapturePackageSchemaVersion,
    'packageId': packageId,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'consentVersion': consentVersion,
    'device': device.toJson(),
    'events': [for (final event in events) event.toJson()],
  };

  factory LabCapturePackage.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != labCapturePackageSchemaVersion) {
      throw LabCapturePackageSchemaVersionException(schemaVersion);
    }
    final rawEvents = json['events']! as List<Object?>;
    return LabCapturePackage(
      packageId: json['packageId']! as String,
      capturedAt: DateTime.parse(json['capturedAt']! as String),
      consentVersion: json['consentVersion']! as String,
      device: LabDeviceMetadata.fromJson(
        Map<String, Object?>.from(json['device']! as Map),
      ),
      events: [
        for (final event in rawEvents)
          LabCaptureEvent.fromJson(Map<String, Object?>.from(event! as Map)),
      ],
    );
  }

  /// The canonical serialization of this package: object keys sorted at
  /// every level (ADR 0358 D3), so the same content always renders to the
  /// same bytes no matter what order it was assembled in.
  String toCanonicalJson() => canonicalJsonEncode(toJson());
}

/// Encodes [value] (a tree of `Map`/`List`/`String`/`num`/`bool`/`null`) to
/// JSON with every map's keys sorted, recursively. Two structurally-equal
/// values always encode to the same string regardless of the key order
/// they were built in — the determinism ADR 0358 D3 requires.
String canonicalJsonEncode(Object? value) {
  final buffer = StringBuffer();
  _writeCanonical(buffer, value);
  return buffer.toString();
}

void _writeCanonical(StringBuffer buffer, Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key as String).toList()..sort();
    buffer.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) buffer.write(',');
      buffer.write(jsonEncode(keys[i]));
      buffer.write(':');
      _writeCanonical(buffer, value[keys[i]]);
    }
    buffer.write('}');
  } else if (value is List) {
    buffer.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) buffer.write(',');
      _writeCanonical(buffer, value[i]);
    }
    buffer.write(']');
  } else {
    buffer.write(jsonEncode(value));
  }
}
