/// Riverpod wiring for the Profile / Privacy / Data presentation layer
/// (E04-R22 §3).
///
/// This file owns three independently editable shapes plus the
/// memory-repository provider that the data screen needs:
///
/// * [tutorConsentControllerProvider] — a [TutorConsent] value object.
///   The three axes (`modelUseGranted`, `persistentStorageGranted`,
///   `evaluationWithRedactionGranted`) are edited via the model's own
///   grant/revoke copy-methods, so toggling one axis leaves the other two
///   untouched (ADR 0132, falszifikációs cell R22-F1).
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
/// **The first three are PERSISTED** (E-R29a, 2026-09-08 re-audit MAJOR
/// M8). Before this round they were in-memory only, so a student who
/// granted model use and filled in their profile lost both on the next app
/// start, with no explanation — while the conversation and memory
/// repositories next to them were already durable. They now follow the
/// app's [PersistedPreference] convention (the same one `themeMode` and
/// `locale` use): the value is read back synchronously in `build()` — the
/// store is opened before the first frame — and written on every mutation.
///
/// The wire format is the ALREADY-EXISTING [TutorProfileCodec] (R22): a
/// versioned envelope per document, so an unreadable or future-versioned
/// value degrades to the fail-closed default (no consent, a fresh profile,
/// no goals) instead of taking the app down. Revoking model use writes the
/// revocation, so a revoked consent can never be resurrected by a restart.
///
/// The whole layer is widget-testable: tests override the four
/// providers with fakes, and the screens are `ConsumerWidget`s that read
/// only from this layer. No screen reaches into the orchestrator, the
/// gateway or the cloud — §3 tilalom él.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_result.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../../../core/storage/persisted_preference.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../data/local/tutor_profile_codec.dart';
import '../../data/repositories/local_tutor_memory_repository.dart';
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
///
/// Every mutation — a grant AND a revocation — is written through, so the
/// student's decision survives a restart in both directions.
class TutorConsentController extends Notifier<TutorConsent>
    with PersistedPreference<TutorConsent> {
  @override
  TutorConsent build() {
    const codec = TutorProfileCodec();
    final stored = preferences.readString(StorageKeys.tutorConsent);
    return _decodeOrNull(stored, codec.decodeTutorConsent) ??
        const TutorConsent();
  }

  void grantModelUse() => _write(state.grantModelUse());
  void revokeModelUse() => _write(state.revokeModelUse());

  void grantPersistentStorage() => _write(state.grantPersistentStorage());
  void revokePersistentStorage() => _write(state.revokePersistentStorage());

  void grantEvaluationWithRedaction() =>
      _write(state.grantEvaluationWithRedaction());
  void revokeEvaluationWithRedaction() =>
      _write(state.revokeEvaluationWithRedaction());

  /// Set every axis at once — used by tests; the UI never calls it.
  void replace(TutorConsent consent) => _write(consent);

  void _write(TutorConsent next) {
    state = next;
    const codec = TutorProfileCodec();
    final document = _encode(codec.encodeTutorConsent(next));
    unawaited(
      persist(
        StorageKeys.tutorConsent,
        (store) => store.writeString(StorageKeys.tutorConsent, document),
      ),
    );
  }
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

/// Owns the persisted `StudentProfile` and `GuitarProfile` pair.
///
/// `lastValidationCode` is deliberately NOT persisted: it describes the most
/// recent edit, not the student's data.
class TutorProfileController extends Notifier<TutorProfileState>
    with PersistedPreference<TutorProfileState> {
  TutorProfileController();

  @override
  TutorProfileState build() {
    const codec = TutorProfileCodec();
    final defaults = _defaultTutorProfileState();
    final student = _decodeOrNull(
      preferences.readString(StorageKeys.tutorStudentProfile),
      codec.decodeStudentProfile,
    );
    final guitar = _decodeOrNull(
      preferences.readString(StorageKeys.tutorGuitarProfile),
      codec.decodeGuitarProfile,
    );
    return TutorProfileState(
      student: student ?? defaults.student,
      guitar: guitar ?? defaults.guitar,
    );
  }

  void _writeStudent(StudentProfile student) {
    const codec = TutorProfileCodec();
    final document = _encode(codec.encodeStudentProfile(student));
    unawaited(
      persist(
        StorageKeys.tutorStudentProfile,
        (store) => store.writeString(StorageKeys.tutorStudentProfile, document),
      ),
    );
  }

  void _writeGuitar(GuitarProfile guitar) {
    const codec = TutorProfileCodec();
    final document = _encode(codec.encodeGuitarProfile(guitar));
    unawaited(
      persist(
        StorageKeys.tutorGuitarProfile,
        (store) => store.writeString(StorageKeys.tutorGuitarProfile, document),
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
      _writeStudent(next);
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
      _writeGuitar(next);
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
class TutorLearningGoalController extends Notifier<List<LearningGoal>>
    with PersistedPreference<List<LearningGoal>> {
  TutorLearningGoalController();

  @override
  List<LearningGoal> build() {
    const codec = TutorProfileCodec();
    final stored = preferences.readStringList(StorageKeys.tutorLearningGoals);
    if (stored == null) return const <LearningGoal>[];
    final restored = <LearningGoal>[];
    for (final document in stored) {
      final goal = _decodeOrNull(document, codec.decodeLearningGoal);
      // One unreadable goal drops only itself — the rest of the list is
      // still the student's data and must not be thrown away with it.
      if (goal != null) restored.add(goal);
    }
    return List<LearningGoal>.unmodifiable(restored);
  }

  /// Add a new goal. Replaces any existing goal with the same id.
  void addGoal(LearningGoal goal) {
    final next = <LearningGoal>[
      for (final item in state)
        if (item.id != goal.id) item,
      goal,
    ];
    _write(next);
  }

  /// Remove a goal by id.
  void removeGoal(String id) {
    _write(<LearningGoal>[
      for (final item in state)
        if (item.id != id) item,
    ]);
  }

  /// Toggle the active/inactive status of a goal.
  void toggleGoal(String id) {
    _write(<LearningGoal>[
      for (final item in state)
        if (item.id == id)
          (item.status == LearningGoalStatus.active
              ? item.deactivate()
              : item.activate())
        else
          item,
    ]);
  }

  void _write(List<LearningGoal> next) {
    state = List<LearningGoal>.unmodifiable(next);
    const codec = TutorProfileCodec();
    final documents = <String>[
      for (final goal in next) _encode(codec.encodeLearningGoal(goal)),
    ];
    unawaited(
      persist(
        StorageKeys.tutorLearningGoals,
        (store) =>
            store.writeStringList(StorageKeys.tutorLearningGoals, documents),
      ),
    );
  }
}

final tutorLearningGoalControllerProvider =
    NotifierProvider<TutorLearningGoalController, List<LearningGoal>>(
      TutorLearningGoalController.new,
    );

// ---------------------------------------------------------------------------
// Persistence helpers (E-R29a) — one encode/decode pair shared by the three
// controllers above, so the fail-closed rule is written down once.
// ---------------------------------------------------------------------------

/// The stored form of one [TutorProfileCodec] envelope.
///
/// The codec speaks canonical UTF-8 bytes; [KeyValueStore] stores strings,
/// so the bytes are decoded back to the very text the codec encoded.
String _encode(List<int> bytes) => utf8.decode(bytes);

/// Decodes one stored document, or null when there is nothing readable.
///
/// Fail-closed by construction: an absent key, a value written by a codec
/// version this build cannot read, and a corrupt payload all collapse to
/// null, and the caller substitutes its own default. The unreadable bytes
/// stay on disk — nothing is destroyed by the fallback (the same rule
/// [KeyValueStore] states for a type-mismatched read).
T? _decodeOrNull<T>(String? stored, T Function(List<int> bytes) decode) {
  if (stored == null || stored.isEmpty) return null;
  try {
    return decode(utf8.encode(stored));
  } on TutorProfileCodecException {
    return null;
  } on FormatException {
    return null;
  }
}

/// The profile pair a student who has never edited anything starts from.
TutorProfileState _defaultTutorProfileState() => TutorProfileState(
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
    capoFret: ProfileField<int>(0, StudentProfileFieldProvenance.userExplicit),
    isPrimary: ProfileField<bool>(
      true,
      StudentProfileFieldProvenance.userExplicit,
    ),
  ),
);

// ---------------------------------------------------------------------------
// Memory repository (R17) + listing projection
// ---------------------------------------------------------------------------

/// Overridable seam for the memory repository (R17). Tests inject a
/// `TutorMemoryRepository` fake; production wires `LocalTutorMemoryRepository`
/// from the boot layer.
TutorMemoryRepository createProductionTutorMemoryRepository({
  required KeyValueStore keyValueStore,
}) => LocalTutorMemoryRepository(keyValueStore: keyValueStore);

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
