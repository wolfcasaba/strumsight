import 'package:flutter/foundation.dart';

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

  factory AnalyzedSession.fromJson(Map<String, dynamic> j) => AnalyzedSession(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        title: j['title'] as String,
        result: AnalyzeResult.fromJson(j['result'] as Map<String, dynamic>),
        customTitle: j['customTitle'] as bool? ?? false,
      );
}
