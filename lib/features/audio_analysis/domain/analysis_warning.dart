enum AnalysisWarningKind { inputQuality, capability, processing, migration }

enum AnalysisWarningSeverity { info, warning, error }

/// Stable warning data; presentation resolves [messageKey] in the UI layer.
final class AnalysisWarning {
  AnalysisWarning({
    required this.kind,
    required this.severity,
    required this.messageKey,
    Map<String, String> messageArgs = const <String, String>{},
  }) : messageArgs = Map<String, String>.unmodifiable(messageArgs) {
    if (messageKey.trim().isEmpty) {
      throw ArgumentError.value(messageKey, 'messageKey');
    }
  }

  final AnalysisWarningKind kind;
  final AnalysisWarningSeverity severity;
  final String messageKey;
  final Map<String, String> messageArgs;
}
