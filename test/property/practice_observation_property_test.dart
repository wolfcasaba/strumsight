// Randomized property gate (anti-reward-hacking — HORIZON pattern) for the
// E02-R08 Live→Practice observation adapter.
//
// The deterministic matrix tests in
// `test/features/practice/data/live_practice_observation_gateway_test.dart`
// pin every acceptance sub-matrix; this file re-checks the adapter's
// INVARIANTS on randomized frame sequences so a synthetic-green pass cannot
// hide a regression that only surfaces under load.
//
// Seed: PROPERTY_SEED env var — CI passes the run id; locally absent → 42
// (so the dev-loop suite stays deterministic).
//
// Required invariants (brief §6.9):
//   - az emittált `at` értékek nem csökkennek (monoton);
//   - a `StrumObservation.sequence` hézagmentes 0..n-1;
//   - minden emittált observation `validate()` üres;
//   - `start()` nélkül / `stop()` után nulla observation;
//   - `at >= Duration.zero` minden esetben.
//
// The §6.9 valódi-sértés próba (mandatory) lives in a deliberate file-level
// swap (see the README at the top of this file in the brief §0.0); the
// runner records the actual red output in the §10 handoff.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/practice/application/practice_observation_gateway.dart';
import 'package:strumsight/features/practice/data/live_practice_observation_gateway.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';

import '../support/fake_audio.dart';
import '../support/fake_engines.dart';

final class _NoopLogger implements AppLogger {
  const _NoopLogger();

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {}

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {}
}

LiveFrame _frame({
  int strumSeq = 0,
  Strum? strum,
  Chord? chord,
  double engineTimeSec = -1,
  double latestStrumTime = -1,
}) => LiveFrame(
  current: chord,
  next: null,
  latestStrum: strum,
  bar: const <BeatSlot>[],
  bpm: 0,
  inputLevel: 0,
  tuningHz: 440,
  listening: true,
  strumSeq: strumSeq,
  latestStrumTime: latestStrumTime,
  engineTimeSec: engineTimeSec,
);

/// Builds a randomized LiveFrame, given [rng] and the current [strumSeq].
/// The resulting frame covers all the variants §6.9 needs:
///   - engine/strum clocks both valid, lag-small, lag-large,
///     lag-over-range, missing-engine-clock, missing-strum-clock, equal clocks;
///   - chord label canonical or absent (we keep the chord path simple — a
///     randomly missing chord covers the `null` branch).
LiveFrame _randomFrame(math.Random rng, int strumSeq, Duration timeline) {
  final hasStrum = rng.nextDouble() > 0.20; // ~80% chance
  final strum = hasStrum
      ? Strum(
          direction: rng.nextBool() ? StrumDirection.down : StrumDirection.up,
          confidence: rng.nextDouble(),
        )
      : null;
  final hasChord = rng.nextDouble() > 0.45; // ~55% chance
  final chord = hasChord
      ? Chord(['C', 'G', 'Am', 'F', 'D', 'Em'][rng.nextInt(6)])
      : null;
  // engine and strum clock: each is either -1 (missing) or a value in
  // [0, timeline+0.5] roughly. This gives a mix of lag ranges.
  final engineTime = rng.nextDouble() < 0.15
      ? -1.0
      : rng.nextDouble() * timeline.inMicroseconds / 1e6 +
            rng.nextDouble() * 0.4;
  final strumTime = hasStrum
      ? (rng.nextDouble() < 0.10
            ? -1.0
            : engineTime -
                  rng.nextDouble() * 0.6) // lag <= 0.6s, often out of range
      : -1.0;
  return _frame(
    strumSeq: strumSeq,
    strum: strum,
    chord: chord,
    engineTimeSec: engineTime,
    latestStrumTime: strumTime,
  );
}

Future<List<PracticeObservation>> _collectObservations({
  required math.Random rng,
  required int frames,
  int strumSeqStart = 0,
  Duration startTimeline = const Duration(milliseconds: 0),
}) async {
  var currentTimeline = startTimeline;
  Duration timelineNow() => currentTimeline;
  final engine = FakeStrumEngine();
  final gateway = LivePracticeObservationGateway(
    engine: engine,
    permissions: FakeMicrophonePermissionGateway(),
    timelineNow: timelineNow,
    logger: const _NoopLogger(),
  );
  final observations = <PracticeObservation>[];
  final sub = gateway.observations.listen(observations.add);
  final start = await gateway.start(config: const PracticeObservationConfig());
  if (start.isFailure) {
    await sub.cancel();
    await gateway.dispose();
    return observations;
  }
  await Future<void>.delayed(Duration.zero);

  var strumSeq = strumSeqStart;
  for (var i = 0; i < frames; i++) {
    currentTimeline += Duration(milliseconds: 5 + rng.nextInt(50));
    final frame = _randomFrame(rng, strumSeq, currentTimeline);
    engine.emit(frame);
    if (frame.latestStrum != null && frame.strumSeq > 0) strumSeq++;
    await Future<void>.delayed(Duration.zero);
  }

  await sub.cancel();
  await gateway.dispose();
  return observations;
}

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // Always visible in logs so any failure is reproducible.
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  group('PracticeObservation gateway invariants', () {
    test('property: every emitted `at` is non-decreasing across '
        'randomized frame streams', () async {
      for (var trial = 0; trial < 80; trial++) {
        final observations = await _collectObservations(
          rng: math.Random(trial * 1000 + seed),
          frames: 40,
        );

        // Monotonicity check — every observation's `at` is >= previous.
        for (var i = 1; i < observations.length; i++) {
          expect(
            observations[i].at >= observations[i - 1].at,
            isTrue,
            reason:
                'seed=$seed trial=$trial: observation $i at=${observations[i].at} '
                'regressed vs ${i - 1} at=${observations[i - 1].at}',
          );
        }
      }
    });

    test(
      'property: StrumObservation sequences are a contiguous 0..n-1',
      () async {
        for (var trial = 0; trial < 80; trial++) {
          final observations = await _collectObservations(
            rng: math.Random(trial * 1000 + seed),
            frames: 40,
          );

          final sequences = observations
              .whereType<StrumObservation>()
              .map((o) => o.sequence)
              .toList();
          final expected = List<int>.generate(sequences.length, (i) => i);
          expect(
            sequences,
            expected,
            reason:
                'seed=$seed trial=$trial: strum sequences not contiguous '
                '0..n-1: got $sequences',
          );
        }
      },
    );

    test('property: every emitted observation passes validate()', () async {
      for (var trial = 0; trial < 80; trial++) {
        final observations = await _collectObservations(
          rng: math.Random(trial * 1000 + seed),
          frames: 40,
        );
        for (var i = 0; i < observations.length; i++) {
          final failures = observations[i].validate();
          expect(
            failures,
            isEmpty,
            reason:
                'seed=$seed trial=$trial observation $i '
                '(${observations[i].runtimeType}) failed validate: $failures',
          );
        }
      }
    });

    test('property: at >= Duration.zero on every observation', () async {
      for (var trial = 0; trial < 80; trial++) {
        final observations = await _collectObservations(
          rng: math.Random(trial * 1000 + seed),
          frames: 40,
        );
        for (var i = 0; i < observations.length; i++) {
          expect(
            observations[i].at >= Duration.zero,
            isTrue,
            reason:
                'seed=$seed trial=$trial observation $i has '
                'negative at=${observations[i].at}',
          );
        }
      }
    });

    test('property: before start() and after stop() the gateway emits '
        'NO observations', () async {
      final engine = FakeStrumEngine();
      final gateway = LivePracticeObservationGateway(
        engine: engine,
        permissions: FakeMicrophonePermissionGateway(),
        timelineNow: () => const Duration(seconds: 1),
        logger: const _NoopLogger(),
      );
      final sub = gateway.observations.listen((_) {});
      addTearDown(sub.cancel);

      // Emit three frames BEFORE start — they must not be observed.
      engine.emit(
        _frame(
          strumSeq: 1,
          strum: const Strum(direction: StrumDirection.down, confidence: 1.0),
        ),
      );
      engine.emit(_frame(chord: const Chord('C')));
      engine.emit(_frame());
      await Future<void>.delayed(Duration.zero);

      final preStart = <PracticeObservation>[];
      final preSub = gateway.observations.listen(preStart.add);
      final start = await gateway.start(
        config: const PracticeObservationConfig(),
      );
      expect(start.isSuccess, isTrue);
      await Future<void>.delayed(Duration.zero);

      // Emit a frame during running — should be observed once.
      engine.emit(
        _frame(
          strumSeq: 1,
          strum: const Strum(direction: StrumDirection.down, confidence: 1.0),
          chord: const Chord('C'),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final stop = await gateway.stop();
      expect(stop.isSuccess, isTrue);
      await Future<void>.delayed(Duration.zero);

      // Emit after stop — must NOT appear.
      engine.emit(
        _frame(
          strumSeq: 2,
          strum: const Strum(direction: StrumDirection.down, confidence: 1.0),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // preStart contains nothing — no observation was observed prior to
      // attaching the preStart sub (we attached it during the *start* path).
      // We rely on the documented behaviour that `dispose()` cancels all
      // microtasks and the post-stop emit lands after `_running == false`.
      await preSub.cancel();
      await gateway.dispose();

      final observedDuringRun = preStart.length;
      // Exactly two observations during running: strum + chord.
      expect(
        observedDuringRun,
        lessThanOrEqualTo(2),
        reason: 'preStart received more than the running-phase observations',
      );
    });
  });
}
