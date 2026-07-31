// Matrix-driven tests for the Live→Practice observation adapter (E02-R08).
//
// Each acceptance sub-matrix in the brief (§6.2–§6.8) gets its own group; the
// individual cells of a matrix are written as separate tests so a fixture
// default cannot accidentally land on a passing point.
//
// The §6.2 lag-guard matrix is now read on the **derived** `lag` (R1 brief
// revision): the value placed in the test is what the formula produces in
// IEEE 754 (e.g. `1.0 − 0.5001 = 0.4999`), not what the input pair "should"
// conceptually mean.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/practice/application/practice_observation_gateway.dart';
import 'package:strumsight/features/practice/data/live_practice_observation_gateway.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_validation.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_engines.dart';

/// A local recording logger for the §6.8 discipline tests — the brief
/// mandates a per-file implementation rather than a shared support fake.
final class _RecordingAppLogger implements AppLogger {
  final List<String> warnings = [];
  final List<String> infos = [];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {
    infos.add(event);
  }

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    warnings.add(event);
  }

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {}
}

/// A scripted permission gateway: different answers for `currentState()` and
/// `request()`. Lets us hit the brief's "request() után granted" branch
/// without modifying the shared `FakeMicrophonePermissionGateway`.
final class _ScriptedPermissionGateway implements MicrophonePermissionGateway {
  _ScriptedPermissionGateway({
    required this.currentStateResult,
    required this.requestResult,
  });

  final MicrophonePermissionState currentStateResult;
  final MicrophonePermissionState requestResult;

  int currentStateCalls = 0;
  int requestCalls = 0;

  @override
  Future<MicrophonePermissionState> currentState() async {
    currentStateCalls++;
    return currentStateResult;
  }

  @override
  Future<MicrophonePermissionState> request() async {
    requestCalls++;
    return requestResult;
  }
}

typedef _TimelineFn = Duration Function();

class _Harness {
  _Harness({
    required this.gateway,
    required this.engine,
    required this.logger,
    required this.errors,
    required this.observations,
    required this.observationsSub,
  });

  final LivePracticeObservationGateway gateway;
  final FakeStrumEngine engine;
  final _RecordingAppLogger logger;
  final List<Object> errors;
  final List<PracticeObservation> observations;
  final StreamSubscription<PracticeObservation> observationsSub;
}

Future<_Harness> _spinUp({
  _TimelineFn? timeline,
  MicrophonePermissionState permissionState = MicrophonePermissionState.granted,
}) async {
  final engine = FakeStrumEngine();
  final permissions = FakeMicrophonePermissionGateway(state: permissionState);
  final logger = _RecordingAppLogger();
  final observations = <PracticeObservation>[];
  final errors = <Object>[];
  final gateway = LivePracticeObservationGateway(
    engine: engine,
    permissions: permissions,
    timelineNow: timeline ?? () => Duration.zero,
    logger: logger,
  );
  final observationsSub = gateway.observations.listen(
    observations.add,
    onError: errors.add,
  );
  final start = await gateway.start(config: const PracticeObservationConfig());
  expect(
    start.isSuccess,
    isTrue,
    reason: 'gateway start must succeed for tests',
  );
  await Future<void>.delayed(Duration.zero);
  return _Harness(
    gateway: gateway,
    engine: engine,
    logger: logger,
    errors: errors,
    observations: observations,
    observationsSub: observationsSub,
  );
}

LiveFrame _frame({
  int strumSeq = 0,
  Strum? strum,
  Chord? chord,
  double engineTimeSec = -1,
  double latestStrumTime = -1,
  bool listening = true,
}) => LiveFrame(
  current: chord,
  next: null,
  latestStrum: strum,
  bar: const <BeatSlot>[],
  bpm: 0,
  inputLevel: 0,
  tuningHz: 440,
  listening: listening,
  strumSeq: strumSeq,
  latestStrumTime: latestStrumTime,
  engineTimeSec: engineTimeSec,
);

Strum _strum(double confidence) =>
    Strum(direction: StrumDirection.down, confidence: confidence);

Future<void> _pump() async => Future<void>.delayed(Duration.zero);

void main() {
  group('§6.2 lag-guard matrix (read on derived lag)', () {
    Future<void> expectStrumAt({
      required double engineTime,
      required double latestStrum,
      required Duration timelineNow,
      required Duration expectedAt,
      required int lagWarningsAtEnd,
    }) async {
      final h = await _spinUp(timeline: () => timelineNow);
      addTearDown(h.gateway.dispose);
      addTearDown(h.observationsSub.cancel);

      h.engine.emit(
        _frame(
          strumSeq: 0,
          strum: _strum(1.0),
          engineTimeSec: engineTime,
          latestStrumTime: latestStrum,
        ),
      );
      await _pump();

      final strums = h.observations.whereType<StrumObservation>().toList();
      expect(strums, hasLength(1), reason: 'exactly one strum expected');
      expect(strums.single.at, expectedAt);
      expect(
        h.logger.warnings.where((w) => w.contains('lag')).length,
        lagWarningsAtEnd,
      );
    }

    // Row 1: (-1, -1) — hiányzó óra → lag = 0, no log.
    test(
      'row 1: (-1,-1), timelineNow=0 → at=0, no log',
      () => expectStrumAt(
        engineTime: -1,
        latestStrum: -1,
        timelineNow: Duration.zero,
        expectedAt: Duration.zero,
        lagWarningsAtEnd: 0,
      ),
    );
    test(
      'row 1: (-1,-1), timelineNow=10s → at=10s, no log',
      () => expectStrumAt(
        engineTime: -1,
        latestStrum: -1,
        timelineNow: const Duration(seconds: 10),
        expectedAt: const Duration(seconds: 10),
        lagWarningsAtEnd: 0,
      ),
    );

    // Row 2: (-1, 0.5) — hiányzó engine-óra → lag = 0, no log.
    test(
      'row 2: (-1,0.5), timelineNow=0 → at=0, no log',
      () => expectStrumAt(
        engineTime: -1,
        latestStrum: 0.5,
        timelineNow: Duration.zero,
        expectedAt: Duration.zero,
        lagWarningsAtEnd: 0,
      ),
    );
    test(
      'row 2: (-1,0.5), timelineNow=10s → at=10s, no log',
      () => expectStrumAt(
        engineTime: -1,
        latestStrum: 0.5,
        timelineNow: const Duration(seconds: 10),
        expectedAt: const Duration(seconds: 10),
        lagWarningsAtEnd: 0,
      ),
    );

    // Row 3: (1.0, -1) — hiányzó latestStrum-óra → lag = 0, no log.
    test(
      'row 3: (1.0,-1), timelineNow=0 → at=0, no log',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: -1,
        timelineNow: Duration.zero,
        expectedAt: Duration.zero,
        lagWarningsAtEnd: 0,
      ),
    );
    test(
      'row 3: (1.0,-1), timelineNow=10s → at=10s, no log',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: -1,
        timelineNow: const Duration(seconds: 10),
        expectedAt: const Duration(seconds: 10),
        lagWarningsAtEnd: 0,
      ),
    );

    // Row 4: (1.0, 1.0) — lag = 0 (lag nem > 0), no log.
    test(
      'row 4: (1.0,1.0), timelineNow=0 → at=0, no log',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 1.0,
        timelineNow: Duration.zero,
        expectedAt: Duration.zero,
        lagWarningsAtEnd: 0,
      ),
    );
    test(
      'row 4: (1.0,1.0), timelineNow=10s → at=10s, no log',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 1.0,
        timelineNow: const Duration(seconds: 10),
        expectedAt: const Duration(seconds: 10),
        lagWarningsAtEnd: 0,
      ),
    );

    // Row 5: (1.0, 1.10) — lag = -0.10 → lag = 0, no log (negatív, nem warning).
    test(
      'row 5: (1.0,1.10), timelineNow=0 → at=0, no log',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 1.10,
        timelineNow: Duration.zero,
        expectedAt: Duration.zero,
        lagWarningsAtEnd: 0,
      ),
    );
    test(
      'row 5: (1.0,1.10), timelineNow=10s → at=10s, no log',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 1.10,
        timelineNow: const Duration(seconds: 10),
        expectedAt: const Duration(seconds: 10),
        lagWarningsAtEnd: 0,
      ),
    );

    // Row 6: (1.0, 0.90) — lag = 0.10 (100 000 µs), levonva, no log.
    test(
      'row 6: (1.0,0.90), timelineNow=0 → at=0 (clamp), no log',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 0.90,
        timelineNow: Duration.zero,
        expectedAt: Duration.zero,
        lagWarningsAtEnd: 0,
      ),
    );
    test(
      'row 6: (1.0,0.90), timelineNow=10s → at=9.9s, no log',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 0.90,
        timelineNow: const Duration(seconds: 10),
        expectedAt: const Duration(milliseconds: 9900),
        lagWarningsAtEnd: 0,
      ),
    );

    // Row 7: (1.0, 0.5001) — lag = 0.4999 (499 900 µs), levonva, no log.
    //       A double-aritmetika 1.0 − 0.5001 = 0.4999000000000001 µs-ra kerekítve.
    test(
      'row 7: (1.0,0.5001), timelineNow=0 → at=0 (clamp), no log',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 0.5001,
        timelineNow: Duration.zero,
        expectedAt: Duration.zero,
        lagWarningsAtEnd: 0,
      ),
    );
    test(
      'row 7: (1.0,0.5001), timelineNow=10s → at=9.5001s, no log',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 0.5001,
        timelineNow: const Duration(seconds: 10),
        // 10 000 000 µs − 499 900 µs = 9 500 100 µs (= 9.500100 s).
        expectedAt: const Duration(microseconds: 9500100),
        lagWarningsAtEnd: 0,
      ),
    );

    // Row 8: (1.0, 0.50) — lag = 0.5 pontosan, szigorú < miatt NEM levonva,
    //       1 warning per hívás.
    test(
      'row 8: (1.0,0.50), timelineNow=0 → at=0 (lag nem levont), 1 warning',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 0.50,
        timelineNow: Duration.zero,
        expectedAt: Duration.zero,
        lagWarningsAtEnd: 1,
      ),
    );
    test(
      'row 8: (1.0,0.50), timelineNow=10s → at=10s (lag nem levont), 1 warning',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 0.50,
        timelineNow: const Duration(seconds: 10),
        expectedAt: const Duration(seconds: 10),
        lagWarningsAtEnd: 1,
      ),
    );

    // Row 9: (1.0, 0.4999) — lag = 0.5001 (szigorúan a határ fölött),
    //       NEM levonva, 1 warning per hívás.
    test(
      'row 9: (1.0,0.4999), timelineNow=0 → at=0 (lag nem levont), 1 warning',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 0.4999,
        timelineNow: Duration.zero,
        expectedAt: Duration.zero,
        lagWarningsAtEnd: 1,
      ),
    );
    test(
      'row 9: (1.0,0.4999), timelineNow=10s → at=10s (lag nem levont), 1 warning',
      () => expectStrumAt(
        engineTime: 1.0,
        latestStrum: 0.4999,
        timelineNow: const Duration(seconds: 10),
        expectedAt: const Duration(seconds: 10),
        lagWarningsAtEnd: 1,
      ),
    );
  });

  group('§6.3 confidence-határ matrix', () {
    Future<void> expectEmission(
      double confidence, {
      required bool expected,
    }) async {
      final h = await _spinUp();
      addTearDown(h.gateway.dispose);
      addTearDown(h.observationsSub.cancel);

      h.engine.emit(_frame(strumSeq: 0, strum: _strum(confidence)));
      await _pump();

      final strums = h.observations.whereType<StrumObservation>().toList();
      expect(
        strums,
        expected ? hasLength(1) : isEmpty,
        reason: 'confidence=$confidence',
      );
    }

    test('confidence=0.0 below threshold → no observation', () {
      return expectEmission(0.0, expected: false);
    });

    test('confidence=0.5499 below threshold → no observation', () {
      return expectEmission(0.5499, expected: false);
    });

    test('confidence=0.55 exactly at threshold → observation emitted', () {
      return expectEmission(0.55, expected: true);
    });

    test('confidence=0.5501 above threshold → observation emitted', () {
      return expectEmission(0.5501, expected: true);
    });

    test('confidence=1.0 maximum → observation emitted', () {
      return expectEmission(1.0, expected: true);
    });

    // NOTE: a non-finite confidence (NaN, ±Infinity) cannot reach the
    // adapter through the public LiveFrame API — `Strum`'s constructor asserts
    // `0 <= confidence <= 1`, and that constructor is the only path a frame
    // can carry a strum. The defensive `isFinite` guard in the adapter is
    // correct (reviewable by inspection) but vacuously reachable from public
    // input; see the §10 handoff follow-up.

    test(
      'below-threshold strum advances dedup so the same seq does not re-emit',
      () async {
        final h = await _spinUp();
        addTearDown(h.gateway.dispose);
        addTearDown(h.observationsSub.cancel);

        h.engine.emit(_frame(strumSeq: 1, strum: _strum(0.1)));
        await _pump();
        // Same strumSeq again with passing confidence — must NOT emit, because
        // the dedup anchor advanced even though the first strum was rejected.
        h.engine.emit(_frame(strumSeq: 1, strum: _strum(0.9)));
        await _pump();

        final strums = h.observations.whereType<StrumObservation>().toList();
        expect(strums, isEmpty);
      },
    );
  });

  group('§6.4 monotonitás és sűrű sorszám', () {
    test('változatlan timelineNow mellett a nagy lagú frame után '
        'a lag nélküli frame at-ja nem kisebb', () async {
      var timeline = const Duration(milliseconds: 2000);
      final h = await _spinUp(timeline: () => timeline);
      addTearDown(h.gateway.dispose);
      addTearDown(h.observationsSub.cancel);

      // First frame: lag = 0.4 s (latestStrum=0.6), applied (<0.5).
      // at = 2.0 − 0.4 = 1.6 s.
      h.engine.emit(
        _frame(
          strumSeq: 0,
          strum: _strum(1.0),
          engineTimeSec: 1.0,
          latestStrumTime: 0.6,
        ),
      );
      await _pump();

      // Second frame: same timeline, no lag → at = 2.0 s, must NOT be < 1.6 s.
      h.engine.emit(
        _frame(
          strumSeq: 1,
          strum: _strum(1.0),
          engineTimeSec: 1.0,
          latestStrumTime: 1.0,
        ),
      );
      await _pump();

      final strums = h.observations.whereType<StrumObservation>().toList();
      expect(strums.map((o) => o.at), [
        const Duration(milliseconds: 1600),
        const Duration(milliseconds: 2000),
      ]);
    });

    test('strumSeq 5→9 ugrás → observation sequence 0,1', () async {
      final h = await _spinUp();
      addTearDown(h.gateway.dispose);
      addTearDown(h.observationsSub.cancel);

      h.engine.emit(_frame(strumSeq: 5, strum: _strum(1.0)));
      await _pump();
      h.engine.emit(_frame(strumSeq: 9, strum: _strum(1.0)));
      await _pump();

      final sequences = h.observations
          .whereType<StrumObservation>()
          .map((o) => o.sequence)
          .toList();
      expect(sequences, [0, 1]);
    });

    test(
      'két küszöb feletti strum között egy küszöb alatti → sequence 0,1',
      () async {
        final h = await _spinUp();
        addTearDown(h.gateway.dispose);
        addTearDown(h.observationsSub.cancel);

        h.engine.emit(_frame(strumSeq: 0, strum: _strum(0.9)));
        await _pump();
        h.engine.emit(_frame(strumSeq: 1, strum: _strum(0.1)));
        await _pump();
        h.engine.emit(_frame(strumSeq: 2, strum: _strum(0.9)));
        await _pump();

        final sequences = h.observations
            .whereType<StrumObservation>()
            .map((o) => o.sequence)
            .toList();
        expect(sequences, [0, 1]);
      },
    );

    test('start → 3 strum → stop → start → 1 strum: utolsó sequence=0, '
        'at nem a régi lastEmittedAt-ra clampelve', () async {
      var timeline = const Duration(seconds: 5);
      final h = await _spinUp(timeline: () => timeline);
      addTearDown(h.observationsSub.cancel);

      // First session: 3 strums.
      for (var i = 0; i < 3; i++) {
        h.engine.emit(_frame(strumSeq: i, strum: _strum(1.0)));
        await _pump();
      }
      final stop = await h.gateway.stop();
      expect(stop.isSuccess, isTrue);
      expect(h.engine.stopCalls, 1);

      // Move the clock back — second start() must zero the baseline.
      timeline = const Duration(milliseconds: 100);
      final start = await h.gateway.start(
        config: const PracticeObservationConfig(),
      );
      expect(start.isSuccess, isTrue);
      await _pump();

      h.engine.emit(_frame(strumSeq: 0, strum: _strum(1.0)));
      await _pump();

      final strums = h.observations.whereType<StrumObservation>().toList();
      expect(strums, hasLength(4));
      final last = strums.last;
      expect(last.sequence, 0);
      expect(last.at, const Duration(milliseconds: 100));

      await h.gateway.dispose();
    });
  });

  group('§6.5 chord-mintavétel matrix', () {
    test(
      'ugyanaz a label 10 frame-en belül → pontosan 1 ChordObservation',
      () async {
        final h = await _spinUp();
        addTearDown(h.gateway.dispose);
        addTearDown(h.observationsSub.cancel);

        for (var i = 0; i < 10; i++) {
          h.engine.emit(_frame(chord: const Chord('C')));
          await _pump();
        }

        final chords = h.observations.whereType<ChordObservation>().toList();
        expect(chords, hasLength(1));
        expect(chords.single.label, 'C');
        expect(chords.single.confidence, 1.0);
      },
    );

    test('label-váltás C → G → új observation', () async {
      final h = await _spinUp();
      addTearDown(h.gateway.dispose);
      addTearDown(h.observationsSub.cancel);

      h.engine.emit(_frame(chord: const Chord('C')));
      await _pump();
      h.engine.emit(_frame(chord: const Chord('G')));
      await _pump();

      final chords = h.observations.whereType<ChordObservation>().toList();
      expect(chords.map((c) => c.label), ['C', 'G']);
    });

    test(
      'akkord → nincs akkord → label:null observation is kiadódik',
      () async {
        final h = await _spinUp();
        addTearDown(h.gateway.dispose);
        addTearDown(h.observationsSub.cancel);

        h.engine.emit(_frame(chord: const Chord('C')));
        await _pump();
        h.engine.emit(_frame());
        await _pump();

        final chords = h.observations.whereType<ChordObservation>().toList();
        expect(chords.map((c) => c.label), ['C', null]);
      },
    );

    test('nem kanonikus label a detektorból (Em7, G/B, H) → redukció, '
        'observation validate() üres', () async {
      final h = await _spinUp();
      addTearDown(h.gateway.dispose);
      addTearDown(h.observationsSub.cancel);

      h.engine.emit(_frame(chord: const Chord('Em7')));
      await _pump();
      h.engine.emit(_frame(chord: const Chord('G/B')));
      await _pump();
      h.engine.emit(_frame(chord: const Chord('H')));
      await _pump();

      final chords = h.observations.whereType<ChordObservation>().toList();
      expect(chords.map((c) => c.label), ['Em', 'G', null]);
      for (final chord in chords) {
        expect(chord.validate(), isEmpty);
      }
    });

    test(
      'változatlan label, de eltelt chordStableDuration → újramintavétel',
      () async {
        var timeline = const Duration(seconds: 0);
        final h = await _spinUp(timeline: () => timeline);
        addTearDown(h.gateway.dispose);
        addTearDown(h.observationsSub.cancel);

        h.engine.emit(_frame(chord: const Chord('C')));
        await _pump();
        timeline = const Duration(milliseconds: 200); // > 180 ms
        h.engine.emit(_frame(chord: const Chord('C')));
        await _pump();

        final chords = h.observations.whereType<ChordObservation>().toList();
        expect(chords, hasLength(2));
        expect(chords.every((c) => c.label == 'C'), isTrue);
      },
    );

    test('a Live úton a confidence mindig 1.0, és chordMinConfidence=0.99 '
        'SEM szűr chordot', () async {
      final engine = FakeStrumEngine();
      final permissions = FakeMicrophonePermissionGateway();
      final logger = _RecordingAppLogger();
      final gateway = LivePracticeObservationGateway(
        engine: engine,
        permissions: permissions,
        timelineNow: () => Duration.zero,
        logger: logger,
      );
      final observations = <PracticeObservation>[];
      final observationSub = gateway.observations.listen(observations.add);
      addTearDown(observationSub.cancel);
      addTearDown(gateway.dispose);

      final start = await gateway.start(
        config: const PracticeObservationConfig(chordMinConfidence: 0.99),
      );
      expect(start.isSuccess, isTrue);
      await _pump();

      engine.emit(_frame(chord: const Chord('C')));
      await _pump();

      final chords = observations.whereType<ChordObservation>().toList();
      expect(chords, hasLength(1));
      expect(chords.single.confidence, 1.0);
    });
  });

  group('§6.6 életciklus', () {
    test('start ×2 → mindkettő Success, engine.startCalls == 1', () async {
      final h = await _spinUp();
      addTearDown(h.gateway.dispose);
      addTearDown(h.observationsSub.cancel);

      final second = await h.gateway.start(
        config: const PracticeObservationConfig(),
      );
      expect(second.isSuccess, isTrue);
      expect(h.engine.startCalls, 1);
    });

    test('stop ×2 → mindkettő Success, engine.stopCalls == 1', () async {
      final h = await _spinUp();
      addTearDown(h.gateway.dispose);
      addTearDown(h.observationsSub.cancel);

      final second = await h.gateway.stop();
      expect(second.isSuccess, isTrue);
      expect(h.engine.stopCalls, 1);
    });

    test('dispose után start/stop → Failure (gateway disposed)', () async {
      final engine = FakeStrumEngine();
      final permissions = FakeMicrophonePermissionGateway();
      final logger = _RecordingAppLogger();
      final gateway = LivePracticeObservationGateway(
        engine: engine,
        permissions: permissions,
        timelineNow: () => Duration.zero,
        logger: logger,
      );
      await gateway.dispose();

      final start = await gateway.start(
        config: const PracticeObservationConfig(),
      );
      final stop = await gateway.stop();
      expect(
        start.failureOrNull?.code,
        FailureCode.practiceObservationGatewayDisposed,
      );
      expect(
        stop.failureOrNull?.code,
        FailureCode.practiceObservationGatewayDisposed,
      );
    });

    test('setExpectedChord → engine.expectedChordCalls utolsó eleme a label; '
        'stop után az utolsó elem null', () async {
      final h = await _spinUp();
      addTearDown(h.gateway.dispose);
      addTearDown(h.observationsSub.cancel);

      h.gateway.setExpectedChord('G');
      expect(h.engine.expectedChordCalls.last, 'G');

      await h.gateway.stop();
      expect(h.engine.expectedChordCalls.last, isNull);
    });

    test('setExpectedChord a start előtt → sikeres start után az engine '
        'megkapja a labelt', () async {
      final engine = FakeStrumEngine();
      final permissions = FakeMicrophonePermissionGateway();
      final logger = _RecordingAppLogger();
      final gateway = LivePracticeObservationGateway(
        engine: engine,
        permissions: permissions,
        timelineNow: () => Duration.zero,
        logger: logger,
      );
      final observationSub = gateway.observations.listen((_) {});
      addTearDown(observationSub.cancel);
      addTearDown(gateway.dispose);

      gateway.setExpectedChord('G');
      await gateway.start(config: const PracticeObservationConfig());
      await _pump();

      expect(engine.expectedChordCalls.last, 'G');
    });
  });

  group('§6.7 hibaleképezés', () {
    test('megtagadott engedély → Failure(PermissionFailure), '
        'engine.startCalls==0', () async {
      final engine = FakeStrumEngine();
      final permissions = FakeMicrophonePermissionGateway(
        state: MicrophonePermissionState.denied,
      );
      final logger = _RecordingAppLogger();
      final gateway = LivePracticeObservationGateway(
        engine: engine,
        permissions: permissions,
        timelineNow: () => Duration.zero,
        logger: logger,
      );
      addTearDown(gateway.dispose);

      final result = await gateway.start(
        config: const PracticeObservationConfig(),
      );
      expect(result.failureOrNull, isA<PermissionFailure>());
      expect(engine.startCalls, 0);
    });

    test('request() után granted → engine.startCalls==1', () async {
      final engine = FakeStrumEngine();
      final permissions = _ScriptedPermissionGateway(
        currentStateResult: MicrophonePermissionState.denied,
        requestResult: MicrophonePermissionState.granted,
      );
      final logger = _RecordingAppLogger();
      final gateway = LivePracticeObservationGateway(
        engine: engine,
        permissions: permissions,
        timelineNow: () => Duration.zero,
        logger: logger,
      );
      addTearDown(gateway.dispose);

      final result = await gateway.start(
        config: const PracticeObservationConfig(),
      );
      expect(result.isSuccess, isTrue);
      expect(permissions.requestCalls, 1);
      expect(engine.startCalls, 1);
    });

    test('érvénytelen config → Failure(configurationInvalid), '
        'engine.startCalls==0', () async {
      final engine = FakeStrumEngine();
      final permissions = FakeMicrophonePermissionGateway();
      final logger = _RecordingAppLogger();
      final gateway = LivePracticeObservationGateway(
        engine: engine,
        permissions: permissions,
        timelineNow: () => Duration.zero,
        logger: logger,
      );
      addTearDown(gateway.dispose);

      final result = await gateway.start(
        config: const PracticeObservationConfig(strumMinConfidence: 1.5),
      );
      final failure = result.failureOrNull;
      expect(failure, isA<ConfigurationFailure>());
      expect(failure!.code, FailureCode.configurationInvalid);
      final cause = failure.cause as List<PracticeValidationFailure>;
      expect(
        cause.map((f) => f.code),
        contains(PracticeValidationCode.observationConfigConfidenceOutOfRange),
      );
      expect(engine.startCalls, 0);
    });

    test(
      'engine stream AudioFailure(audioSessionBusy) → stream hiba ugyanaz, '
      'engine.stopCalls==1, stream nem zárul be, újabb start sikerül',
      () async {
        final h = await _spinUp();
        addTearDown(h.observationsSub.cancel);

        const failure = AudioFailure(code: FailureCode.audioSessionBusy);
        h.engine.emitError(failure);
        await _pump();

        expect(h.errors, [failure]);
        expect(h.engine.stopCalls, 1);

        final restart = await h.gateway.start(
          config: const PracticeObservationConfig(),
        );
        expect(restart.isSuccess, isTrue);
        addTearDown(h.gateway.dispose);
      },
    );

    test(
      'engine stream StateError → AudioFailure(practiceObservationStreamFailed)',
      () async {
        final h = await _spinUp();
        addTearDown(h.observationsSub.cancel);

        h.engine.emitError(StateError('boom'));
        await _pump();

        expect(h.errors, hasLength(1));
        final failure = h.errors.single as AudioFailure;
        expect(failure.code, FailureCode.practiceObservationStreamFailed);
        addTearDown(h.gateway.dispose);
      },
    );

    test('a hiba után beküldött frame NEM ad observationt', () async {
      final h = await _spinUp();
      addTearDown(h.observationsSub.cancel);

      h.engine.emitError(StateError('boom'));
      await _pump();

      h.engine.emit(_frame(strumSeq: 0, strum: _strum(1.0)));
      await _pump();

      final strums = h.observations.whereType<StrumObservation>().toList();
      expect(strums, isEmpty);
      addTearDown(h.gateway.dispose);
    });
  });

  group('§6.8 log-fegyelem', () {
    test('200 érvényes, observationt adó frame feldolgozása után a logger '
        'a start/stop páron kívül nem kap bejegyzést', () async {
      final h = await _spinUp();
      addTearDown(h.observationsSub.cancel);

      for (var i = 0; i < 200; i++) {
        h.engine.emit(_frame(strumSeq: i, strum: _strum(1.0)));
        await _pump();
      }
      await h.gateway.stop();

      expect(h.logger.warnings, isEmpty);
      expect(h.logger.infos, [
        'practice_observation_capture_started',
        'practice_observation_capture_stopped',
      ]);

      await h.gateway.dispose();
    });

    test('tíz, tartományon kívüli lagú frame ugyanabban a másodpercben → '
        '1 warning', () async {
      final h = await _spinUp();
      addTearDown(h.gateway.dispose);
      addTearDown(h.observationsSub.cancel);

      for (var i = 0; i < 10; i++) {
        h.engine.emit(
          _frame(
            strumSeq: i,
            strum: _strum(1.0),
            engineTimeSec: 1.0,
            latestStrumTime: 0.4999, // lag = 0.5001 → out of range (row 9)
          ),
        );
        await _pump();
      }

      expect(h.logger.warnings.where((w) => w.contains('lag')).length, 1);
    });
  });
}
