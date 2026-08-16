/// Application boundary for a revisioned exercise-catalog snapshot.
library;

import '../../domain/model/practice_catalog_snapshot.dart';

/// Supplies exactly the catalog snapshot a generation run will record.
///
/// Implementations own live catalog access. Consumers receive candidates and
/// both revisions together, so they cannot accidentally persist only one
/// provenance dimension.
abstract interface class PracticeCatalogReader {
  PracticeCatalogSnapshot read();
}
