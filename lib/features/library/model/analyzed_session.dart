import 'package:flutter/foundation.dart';

import '../../../core/foundation/json_validation.dart';
import '../../analyze/model/analyze_result.dart';

/// A saved analysis: the result plus when it was recorded and a title.
@immutable
class AnalyzedSession {
  const AnalyzedSession({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.result,
    this.customTitle = false,
  });

  final String id;
  final DateTime createdAt;
  final String title;
  final AnalyzeResult result;

  /// Whether [title] is a user-chosen name (round 114). Auto-titles are chord
  /// summaries ("C · G") and get capo-transposed for display; a personal name
  /// must render verbatim — "Campfire riff" is not a chord.
  final bool customTitle;

  /// The same session under a new name (round 106 — rename).
  AnalyzedSession withTitle(String newTitle) => AnalyzedSession(
    id: id,
    createdAt: createdAt,
    title: newTitle,
    result: result,
    customTitle: true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'title': title,
    'result': result.toJson(),
    'customTitle': customTitle,
  };

  /// Decode one saved session (Kör 7 §7.1). Throws [JsonRecordException] on a
  /// record the app could not have written — the storage layer skips it and
  /// keeps the rest of the library.
  factory AnalyzedSession.fromJson(Map<String, dynamic> j) => AnalyzedSession(
    id: requireString(j, 'id'),
    createdAt: requireDateTime(j, 'createdAt'),
    // An auto-title of an empty analysis is legitimately blank.
    title: requireString(j, 'title', allowEmpty: true),
    result: AnalyzeResult.fromJson(requireObject(j['result'], field: 'result')),
    customTitle: optionalBool(j, 'customTitle', fallback: false),
  );
}
