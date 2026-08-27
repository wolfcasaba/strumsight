import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/foundation/app_result.dart';
import '../data/offline_model_source.dart';
import '../model/offline_model.dart';

/// The model manager screen's full observable state (§6.1 three-cell matrix):
/// [active] is the currently activated asset (null before the first
/// successful activation); [previous] is the last-known-working asset a
/// [OfflineModelPhase.activeWithRollback] state can fall back to.
final class OfflineModelUiState {
  const OfflineModelUiState({required this.phase, this.active, this.previous});

  static const initial = OfflineModelUiState(
    phase: OfflineModelPhase.notChecked,
  );

  final OfflineModelPhase phase;
  final OfflineModelAsset? active;
  final OfflineModelAsset? previous;

  OfflineModelUiState _copyWith({
    OfflineModelPhase? phase,
    OfflineModelAsset? active,
    bool clearActive = false,
    OfflineModelAsset? previous,
    bool clearPrevious = false,
  }) => OfflineModelUiState(
    phase: phase ?? this.phase,
    active: clearActive ? null : (active ?? this.active),
    previous: clearPrevious ? null : (previous ?? this.previous),
  );
}

final offlineModelSourceProvider = Provider<OfflineModelSource>(
  (_) => const UnavailableOfflineModelSource(),
);

/// Drives the model manager screen. The verification gate
/// ([verifyOfflineModelAsset]) is the ONLY thing standing between "checked"
/// and "active" — there is no method anywhere on this class that activates
/// without calling it first (A6, ADR 0292 §5.1).
class OfflineModelController extends Notifier<OfflineModelUiState> {
  OfflineModelSource get _source => ref.read(offlineModelSourceProvider);

  @override
  OfflineModelUiState build() => OfflineModelUiState.initial;

  /// The "Check for model" action: fetches a candidate, then runs it through
  /// the same [activate] gate a directly-supplied asset would.
  Future<void> checkAndActivate(String modelId) async {
    state = state._copyWith(phase: OfflineModelPhase.checking);
    final result = await _source.fetchCandidate(modelId);
    switch (result) {
      case Failure():
        state = state._copyWith(phase: OfflineModelPhase.blockedIntegrity);
      case Success(:final value):
        activate(value);
    }
  }

  /// Verifies [candidate]'s checksum for real and only then activates it.
  /// A failed verification leaves [OfflineModelUiState.active] untouched and
  /// moves to [OfflineModelPhase.blockedIntegrity] — no bypass parameter, no
  /// "activate anyway" branch (the §10 real-violation probe proves this cell
  /// goes red the moment such a branch is added).
  void activate(OfflineModelAsset candidate) {
    final verification = verifyOfflineModelAsset(candidate);
    if (!verification.verified) {
      state = state._copyWith(phase: OfflineModelPhase.blockedIntegrity);
      return;
    }
    final previouslyActive = state.active;
    state = OfflineModelUiState(
      phase: previouslyActive == null
          ? OfflineModelPhase.active
          : OfflineModelPhase.activeWithRollback,
      active: candidate,
      previous: previouslyActive,
    );
  }

  /// Falls back to the last-known-working version (the "above threshold"
  /// cell, §6.1). A no-op when there is nothing to roll back to.
  void rollback() {
    final previous = state.previous;
    if (previous == null) return;
    state = OfflineModelUiState(
      phase: OfflineModelPhase.active,
      active: previous,
      previous: null,
    );
  }
}

final offlineModelControllerProvider =
    NotifierProvider<OfflineModelController, OfflineModelUiState>(
      OfflineModelController.new,
    );
