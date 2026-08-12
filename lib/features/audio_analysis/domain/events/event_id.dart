/// Builds stable identifiers for audio-analysis timeline events.
final class EventId {
  const EventId._();

  /// The fixed, persisted type literal for an onset event.
  static const String onsetType = 'onset';

  /// The fixed, persisted type literal for a strum event.
  static const String strumType = 'strum';

  /// Returns `<runId>:onset:<sampleIndex>`.
  static String onset({required String runId, required int sampleIndex}) =>
      _build(runId: runId, type: onsetType, sampleIndex: sampleIndex);

  /// Returns `<runId>:strum:<sampleIndex>`.
  static String strum({required String runId, required int sampleIndex}) =>
      _build(runId: runId, type: strumType, sampleIndex: sampleIndex);

  static String _build({
    required String runId,
    required String type,
    required int sampleIndex,
  }) {
    if (runId.trim().isEmpty) throw ArgumentError.value(runId, 'runId');
    if (sampleIndex < 0) {
      throw ArgumentError.value(sampleIndex, 'sampleIndex');
    }
    return '$runId:$type:$sampleIndex';
  }
}
