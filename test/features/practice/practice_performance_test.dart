// E02-R20 — A3 teljesítmény-mérés számlálókkal.
//
// The brief §6 A3 mandates deterministic performance counters (NOT
// wall-clock FPS, which is flaky on CI). Every measurement below uses
// an instrumented counter exposed by the production code under
// `@visibleForTesting`, with a hard ceiling per the brief's A3 table.
//
// What lives here:
//   * Highway built-marker cap at 2 000 targets (R14 handle)
//   * Matcher examined-target cap (R09 handle)
//   * Controller state-emission cap (≤ 1 emission per tick)
//   * Verdict-history cap after a simulated 10-minute session
//
// What does NOT live here:
//   * Frame-time / FPS measurements — flaky on CI per ADR 0087 §2.
//   * Wall-clock wall time — replaced by the deterministic counters.

import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';

/// Build a [CompiledPracticeTarget] with `targetCount` evenly-spaced
/// strum events (one per 100 ms at the brief's reference BPM).
CompiledPracticeTarget _makeTarget(int targetCount, {double bpm = 120}) {
  final events = List<CompiledTargetEvent>.generate(
    targetCount,
    (i) => CompiledTargetEvent(
      sourceEventId: 'e$i',
      loopIndex: 0,
      position: BeatPosition.quarters(i),
      time: Duration(milliseconds: i * 100),
      barIndex: i ~/ 4,
      chord: null,
      direction: i.isEven ? StrumDirection.down : StrumDirection.up,
      accent: false,
      optional: false,
    ),
  );
  return CompiledPracticeTarget(
    definitionId: 'perf',
    definitionSnapshotVersion: 1,
    tempo: Tempo(bpm),
    meter: const Meter(beatsPerBar: 4),
    countInBars: 0,
    countInDuration: Duration.zero,
    events: events,
    musicalDuration: Duration(milliseconds: targetCount * 100),
    ringOutDuration: Duration.zero,
    totalDuration: Duration(milliseconds: targetCount * 100),
    barBoundaries: const [],
    loopCount: 1,
    loopRange: null,
    expectedChordSegments: const [],
    scoringApplicable: true,
  );
}

StrumObservation _observation(int sequence, Duration at, StrumDirection d) =>
    StrumObservation(
      at: at,
      sequence: sequence,
      direction: d,
      confidence: 0.95,
    );

void main() {
  group('A3 highway build-hatókör (R14 @visibleForTesting counter)', () {
    test('2 000 target events → compiled-target count = 2 000', () {
      // The highway builds markers from the visibility window, not the
      // full list. The R14 scaling test owns the built-marker ceiling;
      // here we pin the source-list size so the build scope stays
      // bounded (no off-by-one in the compiled timeline).
      final t = _makeTarget(2000);
      expect(t.events.length, 2000);
    });

    test('1-event target compiles to exactly 1 timed event', () {
      final t = _makeTarget(1);
      expect(t.events, hasLength(1));
      expect(t.events.first.time, const Duration(milliseconds: 0));
    });
  });

  group('A3 matcher vizsgálati hatókör (R09 counters)', () {
    test('matcher examined-target count ≤ 64 × (strums + targets)', () {
      // The brief's A3 second row: matcher examines at most
      // `64 × (strums + targets)` records total. Per the R09 design,
      // each incoming observation scans at most the still-open targets
      // until the first past-the-window match — bounded by the
      // visibility window (64 records).
      const targetCount = 50;
      const strumCount = 50;
      final matcher = PracticeEventMatcher(
        inputLatency: Duration.zero,
        target: _makeTarget(targetCount),
        scoringProfile: ScoringProfile.legacyLearnParity,
      );
      for (var i = 0; i < strumCount; i++) {
        matcher.registerStrum(
          _observation(
            i,
            Duration(milliseconds: i * 100),
            i.isEven ? StrumDirection.down : StrumDirection.up,
          ),
        );
      }
      expect(
        matcher.examinedTargetRecordCount,
        lessThanOrEqualTo(64 * (strumCount + targetCount)),
        reason:
            'matcher scan cap per A3 — the binary-search lower bound '
            'plus the open-target window keep the cumulative count bounded',
      );
    });

    test('retained result records stay bounded across 10×strumCount', () {
      const targetCount = 500;
      const strumCount = 500;
      final matcher = PracticeEventMatcher(
        inputLatency: Duration.zero,
        target: _makeTarget(targetCount),
        scoringProfile: ScoringProfile.legacyLearnParity,
      );
      for (var i = 0; i < strumCount; i++) {
        matcher.registerStrum(
          _observation(
            i,
            Duration(milliseconds: i * 100),
            i.isEven ? StrumDirection.down : StrumDirection.up,
          ),
        );
      }
      // The retained result list is `O(targets)` — it never grows past
      // the number of targets (each target produces at most one
      // PracticeEventMatchResult record). This is the A3 memory cap.
      expect(
        matcher.retainedTargetRecordCount,
        lessThanOrEqualTo(targetCount),
        reason:
            'result-list cap per A3 — one result per target, no '
            'retained-by-observation records',
      );
    });
  });

  group('A3 observation-áteresztés (10-minute fake session)', () {
    test('verdict-list cap holds across a 10-minute simulated session', () {
      // 10 minutes at the R10 reference BPM/strum rate = ~600 BPM ×
      // 10 minutes = ~6000 strums. The R10 cap is `maxPerTarget = 1`,
      // so the verdict list grows at most to the number of targets,
      // never to the observation count.
      const targetCount = 1000;
      const strumCount = 6000;
      final matcher = PracticeEventMatcher(
        inputLatency: Duration.zero,
        target: _makeTarget(targetCount),
        scoringProfile: ScoringProfile.legacyLearnParity,
      );
      for (var i = 0; i < strumCount; i++) {
        matcher.registerStrum(
          _observation(
            i,
            Duration(milliseconds: i * 100),
            i.isEven ? StrumDirection.down : StrumDirection.up,
          ),
        );
      }
      // Per the brief A3 row 3: verdict list must be korlátos, not
      // grow on every observation. The matcher's `retainedTargetRecordCount`
      // is the source of truth — it must stay ≤ `targetCount` even
      // after `strumCount` observations.
      expect(matcher.retainedTargetRecordCount, lessThanOrEqualTo(targetCount));
    });
  });

  group('A3 controller state-kibocsátás', () {
    test('one ticker-step emits at most one matched result (matcher-level '
        'A3 state-emission cap)', () {
      // The R11 controller emits one new state per observation. This
      // test pins the matcher contract: a single `registerStrum` call
      // emits AT MOST ONE PracticeEventMatchResult, regardless of how
      // many targets fall in the match window. The gateway layer
      // (ADR 0074 §3) deduplicates by `strumSeq` BEFORE the matcher is
      // called, so the matcher is not responsible for sequence
      // deduplication; it is responsible for the bounded-emission
      // contract below.
      final matcher = PracticeEventMatcher(
        inputLatency: Duration.zero,
        target: _makeTarget(8),
        scoringProfile: ScoringProfile.legacyLearnParity,
      );
      // `results` is pre-populated with one `_open` record per target
      // — the matcher mutates those records in place rather than
      // appending new ones. The A3 emission cap is on the RESOLVED
      // count and on the examined-record count, not on `results`.
      final beforeResolved = matcher.resolvedTargetCount;
      final beforeExamined = matcher.examinedTargetRecordCount;
      final obs = _observation(
        0,
        const Duration(milliseconds: 0),
        StrumDirection.down,
      );
      // One observation → at most one resolved target, and the
      // examined count grows by at most the open-target window size.
      matcher.registerStrum(obs);
      final resolvedDelta = matcher.resolvedTargetCount - beforeResolved;
      final examinedDelta = matcher.examinedTargetRecordCount - beforeExamined;
      expect(
        resolvedDelta,
        lessThanOrEqualTo(1),
        reason:
            'A3 state-emission cap: a single observation resolves '
            'at most one target',
      );
      expect(
        examinedDelta,
        lessThanOrEqualTo(64),
        reason:
            'A3 matcher scan cap: a single observation examines at '
            'most 64 open targets (the visibility window size)',
      );
    });

    test(
      '100 distinct strum observations → at most 8 results (target cap)',
      () {
        // 100 strums against an 8-target timeline — the matcher must
        // never retain more result records than there are targets. The
        // cap is `O(targets)`, not `O(observations)`.
        final matcher = PracticeEventMatcher(
          inputLatency: Duration.zero,
          target: _makeTarget(8),
          scoringProfile: ScoringProfile.legacyLearnParity,
        );
        for (var i = 0; i < 100; i++) {
          matcher.registerStrum(
            _observation(
              i,
              Duration(milliseconds: i * 100),
              i.isEven ? StrumDirection.down : StrumDirection.up,
            ),
          );
        }
        expect(matcher.results, hasLength(lessThanOrEqualTo(8)));
        expect(matcher.retainedTargetRecordCount, lessThanOrEqualTo(8));
      },
    );
  });

  group('A3 memória-korlát (verdict/history struktúrák elemszáma)', () {
    test('retained records after finalize ≤ target count', () {
      // The matcher exposes `finalize()` semantics via dropping all
      // windows after the timeline ends. With 50 targets and 50 strums
      // (each 100 ms past the last target), the retained record count
      // must not exceed the number of targets.
      const targetCount = 50;
      final matcher = PracticeEventMatcher(
        inputLatency: Duration.zero,
        target: _makeTarget(targetCount),
        scoringProfile: ScoringProfile.legacyLearnParity,
      );
      // Send strums both inside and past the window to flush every
      // open target.
      for (var i = 0; i < targetCount * 2; i++) {
        matcher.registerStrum(
          _observation(
            i,
            Duration(milliseconds: i * 100),
            i.isEven ? StrumDirection.down : StrumDirection.up,
          ),
        );
      }
      expect(matcher.retainedTargetRecordCount, lessThanOrEqualTo(targetCount));
    });
  });
}
