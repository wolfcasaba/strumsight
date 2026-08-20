import 'gamification_storage_schema.dart';

/// Explicit outcome of reading a versioned gamification document.
enum GamificationReadStatus { available, missing, corrupt }

/// A storage-free repository value that distinguishes empty state from bytes
/// that exist but cannot safely be decoded.
final class GamificationRead<T> {
  const GamificationRead.available(this.value)
    : status = GamificationReadStatus.available;

  const GamificationRead.missing()
    : status = GamificationReadStatus.missing,
      value = null;

  const GamificationRead.corrupt()
    : status = GamificationReadStatus.corrupt,
      value = null;

  final GamificationReadStatus status;
  final T? value;
}

/// Diagnostic result of persisting a bounded reward inbox.
final class GamificationInboxWriteReport {
  const GamificationInboxWriteReport({required this.trimmedCount});

  final int trimmedCount;
}

/// Versioned local persistence boundary for gamification feature state.
///
/// The contract exposes only schema DTOs and plain Dart streams, so callers
/// can provide fakes without depending on a storage plugin or adapter.
abstract interface class GamificationRepository {
  GamificationRead<GamificationProfileSnapshot> readProfileSnapshot();

  Future<void> replaceProfileSnapshot(GamificationProfileSnapshot snapshot);

  Stream<GamificationRead<GamificationProfileSnapshot>> watchProfileSnapshots();

  GamificationRead<GamificationCatalogVersion> readCatalogVersion();

  Future<void> replaceCatalogVersion(GamificationCatalogVersion version);

  GamificationRead<List<GamificationInboxItem>> readInbox();

  Future<GamificationInboxWriteReport> replaceInbox(
    List<GamificationInboxItem> items,
  );

  GamificationRead<GamificationMigrationState> readMigrationState();

  Future<void> replaceMigrationState(GamificationMigrationState state);

  Future<void> dispose();
}
