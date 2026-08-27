/// The unified library's item-type union (SDD Ch13 UI-40/UI-41).
///
/// The directory aggregates four kinds of user content — practice history,
/// saved analyses, songs and setlists — behind one type-safe model so the
/// list/detail screens never blind-cast `extra` the way a stringly-typed
/// route would. [CorruptLibraryItem] represents a whole SOURCE the
/// aggregation could not read (e.g. a corrupt on-disk index) without letting
/// that source's failure take the rest of the library down (§5.1).
library;

/// The four content kinds the unified library aggregates (§0.0/B1, §2).
enum LibraryItemType { practice, analysis, song, setlist }

/// Per-item cloud-sync state (mirrors the account layer's optional settings
/// sync, CLAUDE.md — detection itself is always local-only). [offline] means
/// the item's local copy is fully usable while its cloud counterpart is
/// unreachable; [conflict] means the local and cloud copies disagree and the
/// user must choose (§5.6).
enum LibrarySyncStatus { synced, pending, conflict, offline }

/// Base type every unified-library row and detail screen switches on.
///
/// Sealed so a `switch` over [LibraryItem] is exhaustive at compile time —
/// the type-safe routing acceptance (A1) rests on the compiler refusing to
/// let a new variant silently fall through to the wrong screen content.
sealed class LibraryItem {
  const LibraryItem({required this.id, required this.type});

  final String id;
  final LibraryItemType type;
}

/// A whole source (one [LibraryItemType]) that failed to load — e.g. a
/// corrupt on-disk index. Carries no content beyond the fact that it broke;
/// the aggregation keeps every OTHER source's items visible alongside this
/// placeholder (§5.1, A2).
final class CorruptLibraryItem extends LibraryItem {
  const CorruptLibraryItem({
    required super.id,
    required super.type,
    required this.reasonCode,
  });

  /// Stable machine-readable failure code from the owning repository
  /// (e.g. `SongRepositoryErrorCode.corruptIndex`), surfaced so the UI can
  /// localise without depending on the data-layer exception type.
  final String reasonCode;
}

/// A saved analysis session (the V2 `AnalysisRepository` document/summary).
final class AnalysisLibraryItem extends LibraryItem {
  const AnalysisLibraryItem({
    required super.id,
    required this.title,
    required this.createdAt,
    required this.syncStatus,
    required this.hasRawAudio,
    required this.hasResult,
  }) : super(type: LibraryItemType.analysis);

  final String title;
  final DateTime createdAt;
  final LibrarySyncStatus syncStatus;

  /// Whether the retained raw capture is still present (§5.5). Production
  /// analyses never retain raw audio today ([AudioRetentionPolicy.
  /// defaultPolicy]), so this is `false` for every real item until a future
  /// round wires audio retention — the field exists so the delete-scope UI
  /// and the resilience contract (A6) are already correct when it does.
  final bool hasRawAudio;

  /// Whether the computed analysis result is still readable.
  final bool hasResult;
}

/// A finished practice session (read-only in this round — `library_v2`
/// does not offer per-entry deletion for practice history; see §0.0/B3).
final class PracticeLibraryItem extends LibraryItem {
  const PracticeLibraryItem({
    required super.id,
    required this.title,
    required this.createdAt,
    required this.syncStatus,
  }) : super(type: LibraryItemType.practice);

  final String title;
  final DateTime createdAt;
  final LibrarySyncStatus syncStatus;
}

/// A stored song document (read-only in this round).
final class SongLibraryItem extends LibraryItem {
  const SongLibraryItem({
    required super.id,
    required this.title,
    required this.artist,
    required this.updatedAt,
    required this.syncStatus,
  }) : super(type: LibraryItemType.song);

  final String title;
  final String? artist;
  final DateTime updatedAt;
  final LibrarySyncStatus syncStatus;
}

/// A saved setlist (read-only in this round).
final class SetlistLibraryItem extends LibraryItem {
  const SetlistLibraryItem({
    required super.id,
    required this.title,
    required this.songCount,
    required this.updatedAt,
    required this.syncStatus,
  }) : super(type: LibraryItemType.setlist);

  final String title;
  final int songCount;
  final DateTime updatedAt;
  final LibrarySyncStatus syncStatus;
}
