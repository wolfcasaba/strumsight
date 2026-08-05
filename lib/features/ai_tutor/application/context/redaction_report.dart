import 'package:meta/meta.dart';

import 'tutor_context_snapshot.dart';

/// Why a candidate context field was deliberately excluded.
enum ContextOmissionReason {
  purposeNotAllowed,
  missingVersion,
  rawAudio,
  absolutePath,
  credential,
  importedLyrics,
  contextBudget,
}

/// Audit entry for one excluded context field or nested value.
@immutable
final class ContextOmission {
  const ContextOmission({required this.path, required this.reason});

  final String path;
  final ContextOmissionReason reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'reason': reason.name,
  };
}

/// Immutable record of privacy redactions and minimum-context omissions.
@immutable
final class RedactionReport {
  RedactionReport(Iterable<ContextOmission> entries)
    : entries = List<ContextOmission>.unmodifiable(entries);

  factory RedactionReport.empty() => RedactionReport(const <ContextOmission>[]);

  final List<ContextOmission> entries;

  RedactionReport plus(Iterable<ContextOmission> additional) =>
      RedactionReport(<ContextOmission>[...entries, ...additional]);

  Map<String, Object?> toJson() => <String, Object?>{
    'entries': <Object?>[for (final entry in entries) entry.toJson()],
  };
}

/// The safe context field and audit record produced by [ContextRedactor].
@immutable
final class RedactedContextField {
  const RedactedContextField({required this.field, required this.report});

  final TutorContextField field;
  final RedactionReport report;
}

/// Deny-by-default privacy filter for structured context values.
final class ContextRedactor {
  const ContextRedactor();

  RedactedContextField redact(TutorContextField field) {
    if (field.availability == ContextFieldAvailability.unavailable) {
      return RedactedContextField(
        field: field,
        report: RedactionReport.empty(),
      );
    }

    final omissions = <ContextOmission>[];
    final values = _redactMap(field.values, field.key.name, omissions);
    return RedactedContextField(
      field: TutorContextField.available(
        key: field.key,
        values: values,
        provenance: field.provenance,
      ),
      report: RedactionReport(omissions),
    );
  }

  Map<String, Object?> _redactMap(
    Map<String, Object?> source,
    String path,
    List<ContextOmission> omissions,
  ) {
    final retained = <String, Object?>{};
    for (final entry in source.entries) {
      final entryPath = '$path.${entry.key}';
      final reason = _reasonForKey(entry.key);
      if (reason != null) {
        omissions.add(ContextOmission(path: entryPath, reason: reason));
        continue;
      }
      final value = _redactValue(entry.value, entryPath, omissions);
      if (value != null) retained[entry.key] = value;
    }
    return retained;
  }

  Object? _redactValue(
    Object? value,
    String path,
    List<ContextOmission> omissions,
  ) {
    if (value is String && _isAbsolutePath(value)) {
      omissions.add(
        ContextOmission(path: path, reason: ContextOmissionReason.absolutePath),
      );
      return null;
    }
    if (value is List<Object?>) {
      return <Object?>[
        for (var index = 0; index < value.length; index++)
          ?_redactValue(value[index], '$path[$index]', omissions),
      ];
    }
    if (value is Map<String, Object?>) {
      return _redactMap(value, path, omissions);
    }
    return value;
  }

  ContextOmissionReason? _reasonForKey(String key) {
    final normalized = key.toLowerCase();
    if (normalized.contains('pcm') ||
        normalized.contains('sample') ||
        normalized.contains('rawaudio') ||
        normalized.contains('waveform')) {
      return ContextOmissionReason.rawAudio;
    }
    if (normalized.contains('lyrics') || normalized.contains('lyric')) {
      return ContextOmissionReason.importedLyrics;
    }
    if (normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('password') ||
        normalized.contains('credential') ||
        normalized.contains('authorization') ||
        normalized.contains('apikey')) {
      return ContextOmissionReason.credential;
    }
    return null;
  }

  bool _isAbsolutePath(String value) =>
      value.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
}
