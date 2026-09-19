// E-R29a (2026-09-08 re-audit, MAJOR M8) — the tutor's three student-owned
// settings survive a restart.
//
// Before this round `tutorConsentControllerProvider`,
// `tutorProfileControllerProvider` and `tutorLearningGoalControllerProvider`
// were in-memory only. A student granted model use, typed a weekly practice
// budget and named a goal; the next cold start silently threw all three
// away — while the conversation and memory repositories sitting next to
// them in the same file were already durable, so the loss was invisible and
// looked like the app had forgotten on purpose.
//
// The measurement here is a RESTART: two `ProviderContainer`s over ONE
// `InMemoryKeyValueStore`. Container one is the session that writes; the
// next container is the next cold start, and it reads the disk the first
// one left behind. Asserting on the store's map instead would prove only
// that a write happened — not that `build()` can decode it back.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/ai_tutor/data/local/tutor_profile_codec.dart';
import 'package:strumsight/features/ai_tutor/domain/models/learning_goal.dart';
import 'package:strumsight/features/ai_tutor/domain/models/student_profile.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';

import '../../../support/preference_store.dart';

/// One cold start over [store]. Torn down with the test, so the next
/// container in the same cell really is a separate session.
ProviderContainer _session(InMemoryKeyValueStore store) {
  final container = ProviderContainer(
    overrides: [preferenceStoreOverride(store)],
  );
  addTearDown(container.dispose);
  return container;
}

LearningGoal _goal({String id = 'goal-1'}) => LearningGoal(
  id: id,
  statement: 'Clean up my A to D changes',
  category: LearningGoalCategory.cleanChordChanges,
  priority: LearningGoalPriority.high,
  status: LearningGoalStatus.active,
);

void main() {
  group('M8 — tutor consent survives a restart', () {
    test('a granted axis is read back by the next cold start', () {
      final store = InMemoryKeyValueStore();

      _session(store).read(tutorConsentControllerProvider.notifier)
        ..grantModelUse()
        ..grantEvaluationWithRedaction();

      final restored = _session(store).read(tutorConsentControllerProvider);

      expect(restored.modelUseGranted, isTrue);
      expect(restored.evaluationWithRedactionGranted, isTrue);
      expect(
        restored.persistentStorageGranted,
        isFalse,
        reason:
            'the three axes stay independent across the round trip — a '
            'restart must not silently widen consent (ADR 0132)',
      );
    });

    // The direction that matters more: a REVOCATION has to be as durable as
    // a grant. A layer that only ever wrote grants would resurrect a consent
    // the student took back, on the next launch, with no interaction at all.
    test('a revocation is durable — a restart cannot resurrect the grant', () {
      final store = InMemoryKeyValueStore();

      _session(store).read(tutorConsentControllerProvider.notifier)
        ..grantModelUse()
        ..revokeModelUse();

      final restored = _session(store).read(tutorConsentControllerProvider);

      expect(restored.modelUseGranted, isFalse);
    });

    test('an empty store starts fail-closed, with no axis granted', () {
      final store = InMemoryKeyValueStore();

      final consent = _session(store).read(tutorConsentControllerProvider);

      expect(consent.modelUseGranted, isFalse);
      expect(consent.persistentStorageGranted, isFalse);
      expect(consent.evaluationWithRedactionGranted, isFalse);
    });

    // A payload this build cannot read must not take the app down, and must
    // not be guessed at either: it degrades to the fail-closed default.
    test('an unreadable stored consent degrades to no consent at all', () {
      final store = InMemoryKeyValueStore({
        StorageKeys.tutorConsent: '{"schemaVersion":99}',
      });

      final consent = _session(store).read(tutorConsentControllerProvider);

      expect(consent.modelUseGranted, isFalse);
    });
  });

  group('M8 — the student and guitar profile survive a restart', () {
    test('an edited weekly budget and guitar name are read back', () {
      final store = InMemoryKeyValueStore();

      _session(store).read(tutorProfileControllerProvider.notifier)
        ..setWeeklyMinutes(150)
        ..setGuitarName('Road worn dreadnought');

      final restored = _session(store).read(tutorProfileControllerProvider);

      expect(restored.student.weeklyPracticeMinutes.value, 150);
      expect(restored.guitar.name.value, 'Road worn dreadnought');
      expect(
        restored.student.weeklyPracticeMinutes.provenance,
        StudentProfileFieldProvenance.userExplicit,
        reason: 'provenance is part of the record, not a decode-time default',
      );
      expect(
        restored.lastValidationCode,
        isNull,
        reason:
            'the validation code describes the last EDIT, not the student — '
            'it is deliberately not persisted',
      );
    });

    // A refused edit is not a stored edit: the model constructor throws, the
    // state keeps the old value, and nothing may reach the store either.
    test('an out-of-range edit is refused and never persisted', () {
      final store = InMemoryKeyValueStore();

      _session(store).read(tutorProfileControllerProvider.notifier)
        ..setWeeklyMinutes(150)
        ..setWeeklyMinutes(1000000);

      final restored = _session(store).read(tutorProfileControllerProvider);

      expect(restored.student.weeklyPracticeMinutes.value, 150);
    });

    test('an unreadable stored profile degrades to the fresh default', () {
      final store = InMemoryKeyValueStore({
        StorageKeys.tutorStudentProfile: 'not json at all',
      });

      final restored = _session(store).read(tutorProfileControllerProvider);

      expect(restored.student.weeklyPracticeMinutes.value, isNull);
      expect(restored.guitar.name.value, 'My guitar');
    });
  });

  group('M8 — learning goals survive a restart', () {
    test('added goals and their toggled status are read back in order', () {
      final store = InMemoryKeyValueStore();

      _session(store).read(tutorLearningGoalControllerProvider.notifier)
        ..addGoal(_goal())
        ..addGoal(_goal(id: 'goal-2'))
        ..toggleGoal('goal-1');

      final goals = _session(store).read(tutorLearningGoalControllerProvider);

      expect(goals, hasLength(2));
      expect(goals.first.id, 'goal-1');
      expect(goals.first.status, LearningGoalStatus.inactive);
      expect(goals.last.id, 'goal-2');
      expect(goals.last.status, LearningGoalStatus.active);
    });

    test('a removed goal stays removed across the restart', () {
      final store = InMemoryKeyValueStore();

      _session(store).read(tutorLearningGoalControllerProvider.notifier)
        ..addGoal(_goal())
        ..addGoal(_goal(id: 'goal-2'))
        ..removeGoal('goal-1');

      final goals = _session(store).read(tutorLearningGoalControllerProvider);

      expect(goals.map((goal) => goal.id), <String>['goal-2']);
    });

    // One unreadable document must cost the student ONE goal, not the whole
    // list — the rest of the list is still their own data.
    test('one corrupt document drops only itself', () {
      final readable = utf8.decode(
        const TutorProfileCodec().encodeLearningGoal(_goal(id: 'goal-2')),
      );
      final store = InMemoryKeyValueStore({
        StorageKeys.tutorLearningGoals: <String>['{"nope":true}', readable],
      });

      final goals = _session(store).read(tutorLearningGoalControllerProvider);

      expect(goals.map((goal) => goal.id), <String>['goal-2']);
    });
  });

  // The four keys are SETTINGS, not conversation content, so `delete all AI
  // data` (which walks `StorageKeys.tutorAiData`) deliberately does not
  // rewrite a consent decision or the profile the student typed. They are
  // still in the catalogue, which is what the namespace and uniqueness
  // guards in `key_value_store_test.dart` read.
  test('the four new keys are catalogued but outside the delete-all scope', () {
    const keys = <String>[
      StorageKeys.tutorConsent,
      StorageKeys.tutorStudentProfile,
      StorageKeys.tutorGuitarProfile,
      StorageKeys.tutorLearningGoals,
    ];

    for (final key in keys) {
      expect(StorageKeys.all, contains(key), reason: key);
      expect(StorageKeys.tutorAiData, isNot(contains(key)), reason: key);
    }
  });
}
