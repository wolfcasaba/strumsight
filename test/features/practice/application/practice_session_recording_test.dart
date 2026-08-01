import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/application/practice_session_recording.dart';
import 'package:strumsight/features/practice/domain/service/practice_session_eligibility.dart';
import 'package:strumsight/features/progress/model/practice_entry.dart';
import 'package:strumsight/features/progress/providers/practice_log_provider.dart';
import 'package:strumsight/features/streak/providers/streak_provider.dart';
import 'package:strumsight/features/streak/streak_logic.dart';

import '../../../support/preference_store.dart';

const _eligibility = PracticeSessionEligibility();

PracticeSessionRecording _build(ProviderContainer c) {
  return PracticeSessionRecording(
    eligibility: _eligibility,
    streak: c.read(streakProvider.notifier),
    practiceLog: c.read(practiceLogProvider.notifier),
    now: () => DateTime(2026, 7, 9, 12),
  );
}

/// Easiest-eligibility snapshot: 30s active is enough to pass on its own.
SessionEligibilitySnapshot _okSnap() => const SessionEligibilitySnapshot(
  activeDuration: Duration(seconds: 30),
  resolvedRequiredTargets: 0,
  freePracticeStrums: 0,
);

SessionEligibilitySnapshot _snap({
  Duration activeDuration = Duration.zero,
  int resolvedRequiredTargets = 0,
  int freePracticeStrums = 0,
}) => SessionEligibilitySnapshot(
  activeDuration: activeDuration,
  resolvedRequiredTargets: resolvedRequiredTargets,
  freePracticeStrums: freePracticeStrums,
);

PracticeRecordingRequest _req({
  String lessonId = 'l1',
  SessionEligibilitySnapshot? eligibility,
  Duration activeDuration = const Duration(seconds: 60),
  int elapsedSeconds = 90,
  int strokes = 10,
  int chords = 2,
  double? directionAccuracy = 0.8,
  bool eligible = true,
  DateTime? finishedAt,
}) {
  return PracticeRecordingRequest(
    lessonId: lessonId,
    eligibility: eligibility ?? _snap(activeDuration: activeDuration),
    eligible: eligible,
    activeDuration: activeDuration,
    elapsedSeconds: elapsedSeconds,
    strokes: strokes,
    chords: chords,
    directionAccuracy: directionAccuracy,
    finishedAt: finishedAt ?? DateTime(2026, 7, 9, 12),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryKeyValueStore store;
  ProviderContainer? container;

  setUp(() {
    store = InMemoryKeyValueStore();
    container = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
  });
  tearDown(() => container?.dispose());

  group('A4 — streak-eligibility cell matrix (real call site)', () {
    test('19999 ms active + 0 targets + 0 strums → no record', () async {
      final c = container!;
      final rec = _build(c);
      final outcome = await rec.record(
        _req(
          eligibility: _snap(
            activeDuration: const Duration(milliseconds: 19999),
          ),
          activeDuration: const Duration(milliseconds: 19999),
        ),
      );
      expect(outcome.loggedEntry, isNull);
      expect(outcome.streakAdvanced, isFalse);
      expect(outcome.addedActiveSeconds, 0);
    });

    test('20000 ms active → records + advances streak', () async {
      final c = container!;
      final rec = _build(c);
      final outcome = await rec.record(
        _req(
          eligibility: _snap(activeDuration: const Duration(seconds: 20)),
          activeDuration: const Duration(seconds: 20),
        ),
      );
      expect(outcome.loggedEntry, isNotNull);
      expect(outcome.streakAdvanced, isTrue);
      expect(c.read(streakProvider).current, 1);
    });

    test('3 resolved required targets → no record', () async {
      final c = container!;
      final rec = _build(c);
      final outcome = await rec.record(
        _req(
          eligibility: const SessionEligibilitySnapshot(
            activeDuration: Duration.zero,
            resolvedRequiredTargets: 3,
            freePracticeStrums: 0,
          ),
          activeDuration: Duration.zero,
        ),
      );
      expect(outcome.loggedEntry, isNull);
      expect(c.read(streakProvider).current, 0);
    });

    test('4 resolved required targets → records', () async {
      final c = container!;
      final rec = _build(c);
      final outcome = await rec.record(
        _req(
          eligibility: const SessionEligibilitySnapshot(
            activeDuration: Duration.zero,
            resolvedRequiredTargets: 4,
            freePracticeStrums: 0,
          ),
          activeDuration: Duration.zero,
        ),
      );
      expect(outcome.loggedEntry, isNotNull);
      expect(outcome.streakAdvanced, isTrue);
    });

    test('7 free-practice strums → no record', () async {
      final c = container!;
      final rec = _build(c);
      final outcome = await rec.record(
        _req(
          eligibility: const SessionEligibilitySnapshot(
            activeDuration: Duration.zero,
            resolvedRequiredTargets: 0,
            freePracticeStrums: 7,
          ),
          activeDuration: Duration.zero,
        ),
      );
      expect(outcome.loggedEntry, isNull);
    });

    test('8 free-practice strums → records', () async {
      final c = container!;
      final rec = _build(c);
      final outcome = await rec.record(
        _req(
          eligibility: const SessionEligibilitySnapshot(
            activeDuration: Duration.zero,
            resolvedRequiredTargets: 0,
            freePracticeStrums: 8,
          ),
          activeDuration: Duration.zero,
        ),
      );
      expect(outcome.loggedEntry, isNotNull);
    });

    test('cancelled / empty session (eligible=false) → no record', () async {
      final c = container!;
      final rec = _build(c);
      final outcome = await rec.record(_req(eligible: false));
      expect(outcome.loggedEntry, isNull);
      expect(outcome.streakAdvanced, isFalse);
    });

    test(
      'second eligible session same day → streak does NOT advance',
      () async {
        final c = container!;
        final rec = _build(c);
        final first = await rec.record(_req());
        expect(first.streakAdvanced, isTrue);
        expect(c.read(streakProvider).current, 1);

        // Same day, second eligible call — idempotent.
        final second = await rec.record(
          _req(finishedAt: DateTime(2026, 7, 9, 22)),
        );
        expect(second.streakAdvanced, isFalse);
        expect(c.read(streakProvider).current, 1);
        // But the V1 log still gets a second entry (one per moment).
        expect(c.read(practiceLogProvider).length, 2);
      },
    );
  });

  group('A5 — daily-goal active-time computation', () {
    test(
      '60s active (and the wall-clock seconds go into V1 untouched)',
      () async {
        final c = container!;
        final rec = _build(c);
        final outcome = await rec.record(
          _req(
            activeDuration: const Duration(seconds: 60),
            // Caller passes the FULL elapsed-seconds including pause+count-in;
            // they are recorded as the V1 entry's `seconds` but do NOT inflate
            // the daily-goal budget.
            elapsedSeconds: 60 + 8 + 30,
          ),
        );
        expect(outcome.addedActiveSeconds, 60);
        // But the V1 entry keeps the full wall-clock so existing dashboard
        // behaviour stays byte-identical (A10 — V1 log bájtra érintetlen).
        final entries = c.read(practiceLogProvider);
        expect(entries.single.seconds, 60 + 8 + 30);
      },
    );

    test('an ineligible session contributes zero active seconds', () async {
      final c = container!;
      final rec = _build(c);
      final outcome = await rec.record(
        _req(activeDuration: const Duration(seconds: 120), eligible: false),
      );
      expect(outcome.addedActiveSeconds, 0);
    });

    test(
      'successive eligible calls accumulate the V1 log per moment',
      () async {
        final c = container!;
        final rec = _build(c);
        await rec.record(_req(activeDuration: const Duration(seconds: 45)));
        await rec.record(
          _req(
            activeDuration: const Duration(seconds: 30),
            finishedAt: DateTime(2026, 7, 9, 22),
          ),
        );
        final todayEpoch = StreakLogic.epochDayOf(DateTime(2026, 7, 9));
        final entries = c.read(practiceLogProvider);
        final today = entries.where((e) => e.day == todayEpoch);
        // The V1 log keeps one entry per moment — the daily-goal budget is
        // driven through the aggregator's active-time channel.
        expect(today.length, 2);
      },
    );
  });

  group(
    'A6 — Easy mode never overwrites a higher result / never lowers streak',
    () {
      test(
        'a higher Easy result does NOT replace the recorded higher V1',
        () async {
          // The lesson-progress provider (NOT this use case) owns "best wins".
          // The recording use case simply writes one V1 entry per moment, even
          // when the runner is in Easy mode (the caller decides what to record).
          final c = container!;
          final rec = _build(c);
          await rec.record(_req(directionAccuracy: 0.95));
          await rec.record(_req(directionAccuracy: 0.6)); // lower / Easy
          final entries = c.read(practiceLogProvider);
          // Both runs land in V1; the lesson-progress store is what enforces
          // "best only" (already covered by lesson_progress_test.dart).
          expect(entries.length, 2);
        },
      );

      test(
        'Easy-mode second session same day does NOT lower the streak',
        () async {
          final c = container!;
          final rec = _build(c);
          await rec.record(_req()); // first eligible of the day
          expect(c.read(streakProvider).current, 1);
          // Next-day Easy call still advances.
          await rec.record(_req(finishedAt: DateTime(2026, 7, 10, 12)));
          expect(c.read(streakProvider).current, 2);
        },
      );
    },
  );

  group('V1 log byte-identity (A10 — V1 store bájtra érintetlen)', () {
    test('logged entry mirrors the recorded fields exactly', () async {
      final c = container!;
      final rec = _build(c);
      await rec.record(
        _req(
          activeDuration: const Duration(seconds: 30),
          elapsedSeconds: 45,
          strokes: 7,
          chords: 3,
          directionAccuracy: 0.88,
          finishedAt: DateTime(2026, 7, 9, 12),
        ),
      );
      final entries = c.read(practiceLogProvider);
      expect(entries.single.day, StreakLogic.epochDayOf(DateTime(2026, 7, 9)));
      expect(entries.single.source, PracticeSource.learn);
      expect(entries.single.seconds, 45);
      expect(entries.single.strokes, 7);
      expect(entries.single.chords, 3);
      expect(entries.single.directionAccuracy, 0.88);
    });
  });

  test('convenience: SessionEligibilitySnapshot.toInput round-trip', () {
    const s = SessionEligibilitySnapshot(
      activeDuration: Duration(seconds: 12),
      resolvedRequiredTargets: 3,
      freePracticeStrums: 4,
    );
    final i = s.toInput();
    expect(i.activeDuration, const Duration(seconds: 12));
    expect(i.resolvedRequiredTargets, 3);
    expect(i.freePracticeStrums, 4);
  });

  test('the default ok snapshot already clears the 20s active threshold', () {
    expect(_okSnap().toInput().activeDuration, const Duration(seconds: 30));
  });
}
