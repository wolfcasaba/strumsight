/// Community challenge result submission controller
/// (E09-R22, ADR 0417, brief §5.3).
///
/// The controller is the **only** place where the caller's
/// ``submitResult`` flow lands. It is a Riverpod ``AsyncNotifier`` so the
/// UI can reactively re-render on every state transition — the Kör 20
/// ``NotificationController`` and Kör 21 ``ChallengeController``
/// precedent.
///
/// **Local session success is INDEPENDENT of community upload (§A7 /
/// §5.3).** A Practice / Song-session that lands locally with a
/// ``metricValue`` triggers a SEPARATE ``submitResult`` round-trip in
/// the background; the pending-verification state lives here, in the
/// application layer — the local ``CommunityChallengeParticipantState``
/// (the Kör 5 domain entity) does NOT extend with a verification-mező.
/// A network failure on the community POST MUST NOT delete the local
/// session success — the user would think they lost their practice.
///
/// **No silent no-op (L309).** Every repository call has a try/catch;
/// the controller never swallows a ``StorageException`` or a
/// ``NetworkFailure`` — each one flips the state to a label the UI can
/// show, while KEEPING the local-session success intact.
///
/// **Replay-safe (D2).** The controller passes the SAME
/// ``sourceEventId`` to the repository for retry; the server is the
/// idempotency surface.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/logging/logger_provider.dart';
import '../../data/repositories/challenge_repository_impl.dart';
import '../../domain/repositories/challenge_repository.dart';
import '../../domain/value_objects/content_id.dart';

/// The set of states the controller publishes.
///
/// ``idle`` — no submission in flight, no pending verification.
/// ``uploading`` — the HTTP round-trip is in flight; the UI may show
/// a "uploading" indicator.
/// ``pending`` — the HTTP round-trip succeeded; the server-computed
/// ``verification_state`` is unknown at this layer (the repository
/// returns ``Future<void>``); a SEPARATE poll or refresh is the
/// future round's surface. For Kör 22 the pending state is
/// acknowledged locally: a future refresh of the participant state
/// (the next ``fetchMyParticipation``) will surface the verified
/// decision.
///
/// ``localOnly`` — the community upload FAILED (network / backend
/// error); the LOCAL practice-session success is intact. The UI
/// shows the local success WITHOUT the pending badge; the next
/// retry path is offered. This is the §A7 invariant.
///
/// ``synced`` — terminal: the server confirmed the verified decision
/// (the controller's view of the world — the actual proof is the
/// next participant-state fetch).
enum ChallengeResultSubmissionState {
  idle,
  uploading,
  pending,
  localOnly,
  synced,
}

/// The per-(challenge, source-event) submission state the UI reads.
class ChallengeResultState {
  const ChallengeResultState({
    required this.submission,
    required this.lastError,
    required this.isUploading,
  });

  const ChallengeResultState.initial()
    : submission = ChallengeResultSubmissionState.idle,
      lastError = null,
      isUploading = false;

  final ChallengeResultSubmissionState submission;
  final AppFailure? lastError;

  /// Convenience flag — ``True`` while the HTTP round-trip is
  /// in flight. The UI can use this for a banner.
  final bool isUploading;

  ChallengeResultState copyWith({
    ChallengeResultSubmissionState? submission,
    Object? lastError = _sentinel,
    bool? isUploading,
  }) {
    return ChallengeResultState(
      submission: submission ?? this.submission,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as AppFailure?,
      isUploading: isUploading ?? this.isUploading,
    );
  }
}

const Object _sentinel = Object();

/// Provider for the [CommunityChallengeRepository]. The production
/// wiring lands in ``challenge_repository_impl.dart`` (the Kör 5 +
/// Kör 22 surface).
final communityChallengeResultRepositoryProvider =
    Provider<CommunityChallengeRepository>(
      (ref) => throw UnimplementedError(
        'communityChallengeResultRepositoryProvider must be overridden via '
        'the production wiring (challenge_repository_impl.dart) or via a '
        'recording fake in tests.',
      ),
    );

/// The community challenge result submission state machine.
///
/// The controller publishes its state under
/// ``communityChallengeSubmissionControllerProvider``. The screen
/// reads the ``submission`` flag to drive the UI; ``isUploading``
/// toggles the indicator; ``lastError`` is the Kör 5-style failure
/// that the UI can render (the §A7 "Community-upload failed" banner,
/// which keeps the local-session success visible).
class ChallengeResultController extends AsyncNotifier<ChallengeResultState> {
  CommunityChallengeRepository get _repo =>
      ref.read(communityChallengeResultRepositoryProvider);

  AppLogger get _logger => ref.read(appLoggerProvider);

  @override
  Future<ChallengeResultState> build() async {
    return const ChallengeResultState.initial();
  }

  /// Submit a verified challenge result.
  ///
  /// The local-session success is the caller's responsibility —
  /// the controller does NOT persist it. The §A7 invariant means a
  /// failed HTTP call MUST NOT delete the local-success; the
  /// controller ends in the ``localOnly`` state, where the UI keeps
  /// the local result visible.
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async {
    final current = state.value ?? const ChallengeResultState.initial();
    if (current.isUploading) return;
    state = AsyncData(
      current.copyWith(
        submission: ChallengeResultSubmissionState.uploading,
        isUploading: true,
        lastError: null,
      ),
    );
    try {
      await _repo.submitResult(
        challengeId: challengeId,
        metricValue: metricValue,
        sourceEventId: sourceEventId,
        idempotencyKey: idempotencyKey,
      );
      // §A7 — the server's decision is FUTURE-work to read (a
      // follow-up fetchMyParticipation round-trip). The Kör 22
      // surface commits the verified receipt; the controller
      // marks ``pending`` and the UI shows the local session
      // success WITH a "pending verification" badge.
      _logger.info(
        'community.challenges.submitResult.success',
        fields: {
          'challengeId': challengeId.value,
          'sourceEventId': sourceEventId,
        },
      );
      state = AsyncData(
        current.copyWith(
          submission: ChallengeResultSubmissionState.pending,
          isUploading: false,
        ),
      );
    } on AppFailure catch (failure) {
      // §A7 — the local session success is NOT touched; the UI
      // shows ``localOnly`` with the original metric.
      _logger.warning(
        'community.challenges.submitResult.failure',
        fields: {
          'challengeId': challengeId.value,
          'sourceEventId': sourceEventId,
        },
      );
      state = AsyncData(
        current.copyWith(
          submission: ChallengeResultSubmissionState.localOnly,
          isUploading: false,
          lastError: failure,
        ),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.challenges.submitResult.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'challengeId': challengeId.value,
          'sourceEventId': sourceEventId,
        },
      );
      state = AsyncData(
        current.copyWith(
          submission: ChallengeResultSubmissionState.localOnly,
          isUploading: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Mark the submission as ``synced`` after a follow-up
  /// ``fetchMyParticipation`` confirms the server's verified
  /// decision. Called by the screen after the participant-state
  /// refresh resolves to ``verified`` (the next round's reader).
  void markSynced() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(submission: ChallengeResultSubmissionState.synced),
    );
  }

  /// Drop the last error (the user dismissed the banner).
  void clearError() {
    final current = state.value;
    if (current == null || current.lastError == null) return;
    state = AsyncData(current.copyWith(lastError: null));
  }
}

/// Provider for the [ChallengeResultController]. The screen reads
/// this directly; the repository dependency is pulled from
/// [communityChallengeResultRepositoryProvider].
final communityChallengeSubmissionControllerProvider =
    AsyncNotifierProvider.autoDispose<
      ChallengeResultController,
      ChallengeResultState
    >(ChallengeResultController.new);

/// Re-exports the production repository wiring provider (the
/// Kör 22 extension of ``challenge_repository_impl.dart``). The
/// controller test overrides THIS provider with a recording fake
/// while leaving the production ``communityChallengeRepository
/// Provider`` (the Kör 21 ``challenge_controller`` dependency)
/// intact — the two are different Riverpod scopes (the
/// result-submission flow is a separate concern from the
/// invite-lifecycle read shape).
final challengeResultRepositoryProvider =
    Provider<CommunityChallengeRepository>(
      (ref) => ref.watch(communityChallengeApiClientProvider) == null
          ? const DisabledCommunityChallengeRepository()
          : HttpCommunityChallengeRepository(
              ref.watch(communityChallengeApiClientProvider)!,
            ),
    );
