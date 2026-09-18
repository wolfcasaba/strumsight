/// Stable failures produced by the shared import resource policy.
abstract final class ImportLimitFailureCode {
  static const String sourceBytesExceeded = 'songImport.limit.sourceBytes';
  static const String eventCountExceeded = 'songImport.limit.eventCount';
  static const String midiTrackCountExceeded =
      'songImport.limit.midiTrackCount';
  static const String workspaceBytesExceeded =
      'songImport.limit.workspaceBytes';
  static const String wallTimeExceeded = 'songImport.limit.wallTime';
  static const String archiveEntryCountExceeded =
      'songImport.limit.archiveEntryCount';
  static const String extractedBytesExceeded =
      'songImport.limit.extractedBytes';
}

/// Ceiling for an AUDIO import (K3).
///
/// Deliberately NOT [ImportLimits.maxSourceBytes]: that 1 MiB budget sizes a
/// notation file, and raising it would widen the sheet-import attack surface
/// for no reason. A compressed recording is three orders of magnitude larger,
/// so the audio path carries its own profile — the same 32 MiB the editor's
/// backing-attach flow already enforces (K1).
const int maxAudioImportSourceBytes = 32 * 1024 * 1024;

/// Bounded resource budget shared by every song importer.
final class ImportLimits {
  const ImportLimits({
    this.maxSourceBytes = 1_048_576,
    this.maxEventCount = 100_000,
    this.maxMidiTrackCount = 128,
    this.maxWorkspaceBytes = 8_388_608,
    this.maxArchiveEntryCount = 128,
    this.maxExtractedBytes = 8_388_608,
    this.maxWallTime = const Duration(seconds: 30),
  }) : assert(maxSourceBytes > 0),
       assert(maxEventCount > 0),
       assert(maxMidiTrackCount > 0),
       assert(maxWorkspaceBytes > 0),
       assert(maxArchiveEntryCount > 0),
       assert(maxExtractedBytes > 0);

  final int maxSourceBytes;
  final int maxEventCount;
  final int maxMidiTrackCount;
  final int maxWorkspaceBytes;
  final int maxArchiveEntryCount;
  final int maxExtractedBytes;
  final Duration maxWallTime;
}
