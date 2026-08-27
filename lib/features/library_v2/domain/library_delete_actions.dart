/// The unified library's ONLY delete entry point (§5.4).
///
/// `library_v2` never mutates storage directly — every scope resolves to an
/// existing use case. The A5 machine-checked contract (§0.0/B3, see
/// `test/features/library_v2/delete_confirmation_test.dart`) forbids this
/// feature's tree from referencing any raw storage primitive; this file (and
/// its real implementation in `data/analysis_library_delete_actions.dart`)
/// is the boundary that keeps that true.
library;

import '../../../core/foundation/app_result.dart';
import 'library_delete_scope.dart';

abstract interface class LibraryDeleteActions {
  Future<AppResult<void>> delete(String id, LibraryDeleteScope scope);
}
