/// The stable identity and start time of one in-memory Vision session.
///
/// This is deliberately an aggregate identity only. It contains neither a
/// camera frame nor a reference to a platform capture object.
extension type VisionSessionId(String value) {
  factory VisionSessionId.create(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Must not be empty.');
    }
    return VisionSessionId(normalized);
  }
}

final class VisionSession {
  VisionSession({required this.id, required DateTime startedAt})
    : startedAt = startedAt.toUtc();

  final VisionSessionId id;
  final DateTime startedAt;
}
