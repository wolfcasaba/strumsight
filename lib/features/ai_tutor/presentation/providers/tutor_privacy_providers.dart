/// Riverpod wiring for the Profile / Privacy / Data presentation layer
/// (E04-R22 §3).
///
/// This file owns three independently editable shapes plus the
/// memory-repository provider that the data screen needs:
///
/// * [tutorConsentControllerProvider] — a [TutorConsent] value object
///   held in memory. The three axes (`modelUseGranted`,
///   `persistentStorageGranted`, `evaluationWithRedactionGranted`) are
///   edited via the model's own grant/revoke copy-methods, so toggling
///   one axis leaves the other two untouched (ADR 0132, falszifikációs
///   cell R22-F1). The controller is intentionally NOT persisted in this
///   round: persistence is a future cross-feature concern (§0.0).
/// * [tutorProfileControllerProvider] — a `StudentProfile` + `GuitarProfile`
///   pair. Mutations go through the model constructors (and therefore
///   their validators); invalid inputs surface as a screen-level error.
/// * [tutorLearningGoalControllerProvider] — a list of `LearningGoal`s
///   with add/remove operations, built on the existing model's
///   `activate()`/`deactivate()` helpers.
/// * [tutorMemoryRepositoryProvider] — the in-feature seam the data
///   screen reads from. Production wires `LocalTutorMemoryRepository`
///   via override; tests inject a `TutorMemoryRepository` fake. Mirrors
///   the existing `tutorConversationRepositoryProvider` pattern (R18).
///
/// The whole layer is widget-testable: tests override the four
/// providers with fakes, and the screens are `ConsumerWidget`s that read
/// only from this layer. No screen reaches into the orchestrator, the
/// gateway or the cloud — §3 tilalom él.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_result.dart';
import '../../domain/models/guitar_profile.dart';
import '../../domain/models/learning_goal.dart';
import '../../domain/models/student_profile.dart';
import '../../domain/models/tutor_consent.dart';
import '../../domain/models/tutor_conversation.dart';
import '../../domain/models/tutor_memory_fact.dart';
import '../../domain/repositories/tutor_conversation_repository.dart';
import '../../domain/repositories/tutor_memory_repository.dart';
import 'tutor_providers.dart';

// ---------------------------------------------------------------------------
// Granular consent (ADR 0132, R03)
// ---------------------------------------------------------------------------

/// Edits a `TutorConsent` value object via the model's own
/// grant/revoke copy-methods. Each setter only mutates the axis it
/// names — the other two are passed through unchanged.
class TutorConsentController extends Notifier<TutorConsent> {
  @override
  TutorConsent build() => const TutorConsent();

  void grantModelUse() => state = state.grantModelUse();
  void revokeModelUse() => state = state.revokeModelUse();

  void grantPersistentStorage() => state = state.grantPersistentStorage();
  void revokePersistentStorage() => state = state.revokePersistentStorage();

  void grantEvaluationWithRedaction() =>
      state = state.grantEvaluationWithRedaction();
  void revokeEvaluationWithRedaction() =>
      state = state.revokeEvaluationWithRedaction();

  /// Set every axis at once — used by tests; the UI never calls it.
  void replace(TutorConsent consent) => state = consent;
}

/// Holder for the granular consent state. Re-read by both the privacy
/// screen and the data screen (for its delete-all scope disclaimer).
final tutorConsentControllerProvider =
    NotifierProvider<TutorConsentController, TutorConsent>(
      TutorConsentController.new,
    );

// ---------------------------------------------------------------------------
// Student + guitar profile (R03)
// ---------------------------------------------------------------------------

/// Owns the in-memory `StudentProfile` and `GuitarProfile` pair.
class TutorProfileController extends Notifier<TutorProfileState> {
  TutorProfileController();

  @override
  TutorProfileState build() {
    return TutorProfileState(
      student: StudentProfile(
        experienceLevel: ProfileField<StudentExperienceLevel>(
          StudentExperienceLevel.beginner,
          StudentProfileFieldProvenance.userExplicit,
        ),
        preferredStyles: ProfileField<List<String>>(
          const <String>[],
          StudentProfileFieldProvenance.userExplicit,
        ),
        weeklyPracticeMinutes: ProfileField<int?>(
          null,
          StudentProfileFieldProvenance.userExplicit,
        ),
        explanationLength: ProfileField<TutorExplanationLength>(
          TutorExplanationLength.standard,
          StudentProfileFieldProvenance.userExplicit,
        ),
        feedbackDirectness: ProfileField<TutorFeedbackDirectness>(
          TutorFeedbackDirectness.balanced,
          StudentProfileFieldProvenance.userExplicit,
        ),
        knownTechniques: ProfileField<List<String>>(
          const <String>[],
          StudentProfileFieldProvenance.userExplicit,
        ),
        avoidList: ProfileField<List<String>>(
          const <String>[],
          StudentProfileFieldProvenance.userExplicit,
        ),
        locale: ProfileField<String>(
          'en',
          StudentProfileFieldProvenance.userExplicit,
        ),
      ),
      guitar: GuitarProfile(
        id: 'default',
        name: ProfileField<String>(
          'My guitar',
          StudentProfileFieldProvenance.userExplicit,
        ),
        type: ProfileField<GuitarType>(
          GuitarType.unknown,
          StudentProfileFieldProvenance.userExplicit,
        ),
        tuning: ProfileField<List<String>>(const <String>[
          'E2',
          'A2',
          'D3',
          'G3',
          'B3',
          'E4',
        ], StudentProfileFieldProvenance.userExplicit),
        stringCount: ProfileField<int>(
          6,
          StudentProfileFieldProvenance.userExplicit,
        ),
        capoFret: ProfileField<int>(
          0,
          StudentProfileFieldProvenance.userExplicit,
        ),
        isPrimary: ProfileField<bool>(
          true,
          StudentProfileFieldProvenance.userExplicit,
        ),
      ),
    );
  }

  // -- Student fields ---------------------------------------------------------

  /// Set the weekly practice minutes. The model constructor validates the
  /// range; on out-of-range input the state retains its previous
  /// `student` and the latest `lastValidationCode` is set so the screen
  /// can surface a localized error without catching the exception.
  void setWeeklyMinutes(int? minutes) {
    try {
      final next = StudentProfile(
        experienceLevel: state.student.experienceLevel,
        preferredStyles: state.student.preferredStyles,
        weeklyPracticeMinutes: ProfileField<int?>(
          minutes,
          StudentProfileFieldProvenance.userExplicit,
        ),
        explanationLength: state.student.explanationLength,
        feedbackDirectness: state.student.feedbackDirectness,
        knownTechniques: state.student.knownTechniques,
        avoidList: state.student.avoidList,
        locale: state.student.locale,
      );
      state = state.copyWith(student: next, clearValidationCode: true);
    } on StudentProfileValidationException catch (error) {
      state = state.copyWith(lastValidationCode: error.code);
    }
  }

  /// Clear the most-recent validation code (e.g. after the user fixed
  /// the input). The screen wires this to field focus changes.
  void clearValidation() {
    if (state.lastValidationCode == null) return;
    state = state.copyWith(clearValidationCode: true);
  }

  // -- Guitar fields ----------------------------------------------------------

  /// Update the guitar name. Sets [TutorProfileState.lastValidationCode]
  /// if the trimmed value is empty.
  void setGuitarName(String value) {
    final g = state.guitar;
    try {
      final next = GuitarProfile(
        id: g.id,
        name: ProfileField<String>(
          value,
          StudentProfileFieldProvenance.userExplicit,
        ),
        type: g.type,
        tuning: g.tuning,
        stringCount: g.stringCount,
        capoFret: g.capoFret,
        isPrimary: g.isPrimary,
      );
      state = state.copyWith(guitar: next, clearValidationCode: true);
    } on GuitarProfileValidationException catch (error) {
      state = state.copyWith(lastValidationCode: error.code);
    }
  }
}

/// Pair of profile models the screen edits together, plus the latest
/// validation failure from the most recent mutation. The screen reads
/// `lastValidationCode` to surface a localized error without having to
/// catch the model's exception itself (the constructor throws).
@immutable
class TutorProfileState {
  const TutorProfileState({
    required this.student,
    required this.guitar,
    this.lastValidationCode,
  });

  final StudentProfile student;
  final GuitarProfile guitar;

  /// One of the `*ValidationCode` constants from the model classes, or
  /// `null` when the last mutation succeeded.
  final String? lastValidationCode;

  TutorProfileState copyWith({
    StudentProfile? student,
    GuitarProfile? guitar,
    String? lastValidationCode,
    bool clearValidationCode = false,
  }) => TutorProfileState(
    student: student ?? this.student,
    guitar: guitar ?? this.guitar,
    lastValidationCode: clearValidationCode
        ? null
        : (lastValidationCode ?? this.lastValidationCode),
  );
}

final tutorProfileControllerProvider =
    NotifierProvider<TutorProfileController, TutorProfileState>(
      TutorProfileController.new,
    );

// ---------------------------------------------------------------------------
// Learning goals (R03)
// ---------------------------------------------------------------------------

/// Mutable list of learning goals. Goals are constructed with `userExplicit`
/// provenance by the screen's add-row, mirroring the rest of the profile
/// surface.
class TutorLearningGoalController extends Notifier<List<LearningGoal>> {
  TutorLearningGoalController();

  @override
  List<LearningGoal> build() => const <LearningGoal>[];

  /// Add a new goal. Replaces any existing goal with the same id.
  void addGoal(LearningGoal goal) {
    final next = <LearningGoal>[
      for (final item in state)
        if (item.id != goal.id) item,
      goal,
    ];
    state = List<LearningGoal>.unmodifiable(next);
  }

  /// Remove a goal by id.
  void removeGoal(String id) {
    state = List<LearningGoal>.unmodifiable(<LearningGoal>[
      for (final item in state)
        if (item.id != id) item,
    ]);
  }

  /// Toggle the active/inactive status of a goal.
  void toggleGoal(String id) {
    state = List<LearningGoal>.unmodifiable(<LearningGoal>[
      for (final item in state)
        if (item.id == id)
          (item.status == LearningGoalStatus.active
              ? item.deactivate()
              : item.activate())
        else
          item,
    ]);
  }
}

final tutorLearningGoalControllerProvider =
    NotifierProvider<TutorLearningGoalController, List<LearningGoal>>(
      TutorLearningGoalController.new,
    );

// ---------------------------------------------------------------------------
// Memory repository (R17) + listing projection
// ---------------------------------------------------------------------------

/// Overridable seam for the memory repository (R17). Tests inject a
/// `TutorMemoryRepository` fake; production wires `LocalTutorMemoryRepository`
/// from the boot layer.
final tutorMemoryRepositoryProvider = Provider<TutorMemoryRepository>((ref) {
  throw UnimplementedError(
    'tutorMemoryRepositoryProvider must be overridden in tests; '
    'production wires it from the boot layer.',
  );
});

/// Current memory-fact list. Driven off
/// [tutorMemoryRepositoryProvider.list()]; reload via `ref.invalidate`.
final tutorMemoryFactsProvider = FutureProvider<List<TutorMemoryFact>>((
  ref,
) async {
  final repo = ref.watch(tutorMemoryRepositoryProvider);
  final result = await repo.list();
  return switch (result) {
    Success<List<TutorMemoryFact>>(:final value) => value,
    Failure<List<TutorMemoryFact>>() => const <TutorMemoryFact>[],
  };
});

// ---------------------------------------------------------------------------
// Conversation listing projection
// ---------------------------------------------------------------------------

/// Paginated conversation list used by the data screen.
final tutorConversationsProvider = FutureProvider<TutorConversationPage>((
  ref,
) async {
  final repo = ref.watch(tutorConversationRepositoryProvider);
  final result = await repo.list();
  return switch (result) {
    Success<TutorConversationPage>(:final value) => value,
    Failure<TutorConversationPage>() => TutorConversationPage(
      items: const <TutorConversation>[],
      offset: 0,
      total: 0,
    ),
  };
});
