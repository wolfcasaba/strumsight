/// The local lifecycle of one microphone recording attempt.
enum RecordingRunStatus { recording, completed, cancelled, maxDurationReached }

/// Immutable metadata for a microphone capture run.
final class RecordingRun {
  const RecordingRun({
    required this.id,
    required this.startedAt,
    required this.sampleRate,
    required this.status,
    required this.sampleCount,
  });

  final String id;
  final DateTime startedAt;
  final int sampleRate;
  final RecordingRunStatus status;
  final int sampleCount;

  RecordingRun copyWith({
    int? sampleRate,
    RecordingRunStatus? status,
    int? sampleCount,
  }) => RecordingRun(
    id: id,
    startedAt: startedAt,
    sampleRate: sampleRate ?? this.sampleRate,
    status: status ?? this.status,
    sampleCount: sampleCount ?? this.sampleCount,
  );
}
