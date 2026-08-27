/// One content kind's read boundary for the unified library aggregation.
///
/// Each source wraps an EXISTING repository (analysis, practice history,
/// song, setlist) — `library_v2` never opens its own storage (§5.4, §0.0/B3).
/// A source that fails to load reports [LibrarySourceLoad.unavailable]
/// instead of throwing, so one broken source cannot take the rest of the
/// unified list down (§5.1).
library;

import 'library_item.dart';

/// The result of loading one [LibraryItemSource].
final class LibrarySourceLoad {
  const LibrarySourceLoad.success(this.items)
    : unavailable = false,
      failureReasonCode = null;

  const LibrarySourceLoad.unavailable(this.failureReasonCode)
    : items = const [],
      unavailable = true;

  final List<LibraryItem> items;
  final bool unavailable;
  final String? failureReasonCode;
}

/// Read boundary implemented once per [LibraryItemType].
abstract interface class LibraryItemSource {
  LibraryItemType get type;

  Future<LibrarySourceLoad> load();
}
