import 'package:strumsight/features/song_trainer/public.dart';

import '../tutor_context_snapshot.dart';

/// Explicit degradation while Song Trainer exposes no scoring result publicly.
final class SongTrainerContextAdapter {
  const SongTrainerContextAdapter();

  /// Compile-time marker that this adapter depends on the public boundary only.
  Type get publicBoundaryContract => SongLibraryScreen;

  TutorContextField adapt() => TutorContextField.unavailable(
    key: TutorContextFieldKey.songTrainer,
    provenance: ContextProvenance(
      sourceFeature: ContextSourceFeature.songTrainer,
      schemaVersion: 'songTrainer.unavailable.v1',
    ),
  );
}
