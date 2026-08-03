/// Stable failures produced by the shared import resource policy.
abstract final class ImportLimitFailureCode {
  static const String sourceBytesExceeded = 'songImport.limit.sourceBytes';
  static const String eventCountExceeded = 'songImport.limit.eventCount';
  static const String workspaceBytesExceeded =
      'songImport.limit.workspaceBytes';
  static const String wallTimeExceeded = 'songImport.limit.wallTime';
}

/// Bounded resource budget shared by every song importer.
final class ImportLimits {
  const ImportLimits({
    this.maxSourceBytes = 1_048_576,
    this.maxEventCount = 100_000,
    this.maxWorkspaceBytes = 8_388_608,
    this.maxWallTime = const Duration(seconds: 30),
  }) : assert(maxSourceBytes > 0),
       assert(maxEventCount > 0),
       assert(maxWorkspaceBytes > 0);

  final int maxSourceBytes;
  final int maxEventCount;
  final int maxWorkspaceBytes;
  final Duration maxWallTime;
}
