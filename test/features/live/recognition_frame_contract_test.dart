import 'package:flutter_test/flutter_test.dart';

// Imported EXCLUSIVELY via the barrel (not the direct domain files): if the
// E14-R04 additive export in public.dart ever goes missing, this whole file
// fails to COMPILE rather than silently skipping the acceptance point (§6.7).
import 'package:strumsight/features/live/public.dart';

RecognitionRuntimeInfo _runtimeInfo() => const RecognitionRuntimeInfo(
  strumModelId: 'strum_crnn_live_3c.bin',
  strumModelVersion: 1,
  strumModelSha256:
      'aa11bb22cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd6',
  chordEngineId: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
  sampleRate: 44100,
  frontendVersion: RecognitionRuntimeInfo.frontendCrnnV1,
);

StrumPrediction _strum({
  double pDown = 0.6,
  double pUp = 0.3,
  double pNoStrum = 0.1,
  double? calibratedConfidence,
}) => StrumPrediction(
  onsetTimeSec: 12.5,
  verdictTimeSec: 12.57,
  pDown: pDown,
  pUp: pUp,
  pNoStrum: pNoStrum,
  calibratedConfidence: calibratedConfidence,
  modelId: 'strum_crnn_live_3c.bin',
);

ChordPrediction _chord({
  RecognitionDecision decision = RecognitionDecision.confirmed,
  double? calibratedConfidence,
  RecognitionRejectReason? rejectReason,
}) => ChordPrediction(
  label: 'Am',
  root: 'A',
  quality: 'min',
  pNoChord: 0.05,
  pUnknown: 0.1,
  calibratedConfidence: calibratedConfidence,
  stabilityFrames: 6,
  sourceEngine: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
  decision: decision,
  rejectReason: rejectReason,
);

void main() {
  group('RecognitionDecision / RecognitionRejectReason — model 1/5', () {
    test('RecognitionDecision has exactly the six ADR 0505 D3 states', () {
      expect(RecognitionDecision.values.map((d) => d.name).toSet(), {
        'candidate',
        'provisional',
        'confirmed',
        'uncertain',
        'rejected',
        'expired',
      });
    });

    test('RecognitionRejectReason has exactly the six ADR 0505 D3 reasons', () {
      expect(RecognitionRejectReason.values.map((r) => r.name).toSet(), {
        'lowConfidence',
        'unstable',
        'signalQuality',
        'noChord',
        'modelUnavailable',
        'timeout',
      });
    });

    test('JSON round-trip is lossless for every RecognitionDecision', () {
      for (final decision in RecognitionDecision.values) {
        expect(RecognitionDecision.fromJson(decision.toJson()), decision);
      }
    });

    test('JSON round-trip is lossless for every RecognitionRejectReason', () {
      for (final reason in RecognitionRejectReason.values) {
        expect(RecognitionRejectReason.fromJson(reason.toJson()), reason);
      }
    });

    // Fail-closed cell 1/5 (ADR 0505 D6, L619): an unrecognised value is a
    // typed error, never a silent fallback.
    test('an unknown RecognitionDecision value throws, not falls back', () {
      expect(
        () => RecognitionDecision.fromJson('not-a-real-decision'),
        throwsArgumentError,
      );
    });

    // The enum has no "keys" of its own, but the same missing-data shape
    // (json['missing'] resolves to `null`, not a string) must still fail
    // closed instead of silently returning `null`.
    test('a missing/null RecognitionDecision value throws, not null', () {
      final Map<String, Object?> json = {};
      expect(
        () => RecognitionDecision.fromJson(json['decision']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an unknown RecognitionRejectReason value throws, not falls back', () {
      expect(
        () => RecognitionRejectReason.fromJson('not-a-real-reason'),
        throwsArgumentError,
      );
    });
  });

  group('StrumPrediction — model 2/5', () {
    // ADR 0505 D4 — the numeric threshold matrix is measured, not chosen for
    // being "nicer". Do NOT swap these pDown/pUp pairs. §6.1 requires the
    // PAIR (decision + rejectReason) measured on all three cells, not just
    // decision.
    test('directionMargin threshold is inclusive on the rejection side', () {
      final below = _strum(pDown: 0.460, pUp: 0.440);
      final exactlyOn = _strum(pDown: 0.475, pUp: 0.425);
      final above = _strum(pDown: 0.600, pUp: 0.300);

      expect(below.directionMargin, closeTo(0.02, 1e-9));
      expect(below.decision, RecognitionDecision.uncertain);
      expect(below.rejectReason, RecognitionRejectReason.lowConfidence);

      expect(exactlyOn.directionMargin, closeTo(0.05, 1e-9));
      expect(exactlyOn.decision, RecognitionDecision.uncertain);
      expect(exactlyOn.rejectReason, RecognitionRejectReason.lowConfidence);

      expect(above.directionMargin, closeTo(0.30, 1e-9));
      expect(above.decision, RecognitionDecision.confirmed);
      expect(above.rejectReason, isNull);
    });

    test('directionMargin is always |pDown - pUp|, never stored', () {
      final prediction = _strum(pDown: 0.9, pUp: 0.1);
      expect(prediction.directionMargin, closeTo(0.8, 1e-9));
    });

    // Acceptance §6.4 — never copy the raw probability into the calibrated
    // slot "temporarily".
    test('calibratedConfidence stays null and is never the raw pDown', () {
      final prediction = _strum(
        pDown: 0.9,
        pUp: 0.05,
        calibratedConfidence: null,
      );
      expect(prediction.calibratedConfidence, isNull);
      expect(prediction.calibratedConfidence, isNot(prediction.pDown));
    });

    test('JSON round-trip is lossless with a null calibratedConfidence', () {
      final prediction = _strum();
      final decoded = StrumPrediction.fromJson(prediction.toJson());
      expect(decoded, prediction);
      expect(decoded.calibratedConfidence, isNull);
    });

    test(
      'JSON round-trip is lossless with a measured calibratedConfidence',
      () {
        final prediction = _strum(calibratedConfidence: 0.82);
        final decoded = StrumPrediction.fromJson(prediction.toJson());
        expect(decoded, prediction);
        expect(decoded.calibratedConfidence, closeTo(0.82, 1e-9));
      },
    );

    test('decision/directionMargin/rejectReason in the wire payload are '
        're-derived, not trusted', () {
      final json = _strum(pDown: 0.9, pUp: 0.1).toJson();
      // Tamper with the derived fields a hostile/stale producer might send.
      json['decision'] = 'uncertain';
      json['directionMargin'] = 0.0;
      json['rejectReason'] = 'lowConfidence';

      final decoded = StrumPrediction.fromJson(json);
      expect(decoded.decision, RecognitionDecision.confirmed);
      expect(decoded.directionMargin, closeTo(0.8, 1e-9));
      expect(decoded.rejectReason, isNull);
    });

    // MAJOR-2 fix-round cell — the wire form carries the derived pairing.
    test('toJson carries the derived rejectReason paired with decision', () {
      final uncertain = _strum(pDown: 0.460, pUp: 0.440);
      final confirmed = _strum(pDown: 0.600, pUp: 0.300);
      expect(uncertain.toJson()['rejectReason'], 'lowConfidence');
      expect(confirmed.toJson()['rejectReason'], isNull);
    });

    // MINOR-1 fix-round cell — a calibrated confidence outside 0..1 must
    // fail loudly at the contract edge, not silently pass through to the
    // legacy adapter's debug-only assert.
    test('a calibratedConfidence outside 0..1 throws on decode', () {
      final tooHigh = _strum(calibratedConfidence: 0.5).toJson()
        ..['calibratedConfidence'] = 1.4;
      final tooLow = _strum(calibratedConfidence: 0.5).toJson()
        ..['calibratedConfidence'] = -0.1;
      expect(() => StrumPrediction.fromJson(tooHigh), throwsArgumentError);
      expect(() => StrumPrediction.fromJson(tooLow), throwsArgumentError);
    });

    // Fail-closed cell 2/5 (ADR 0505 D6, L619).
    test('a missing calibratedConfidence KEY throws — distinct from null', () {
      final json = _strum().toJson()..remove('calibratedConfidence');
      expect(() => StrumPrediction.fromJson(json), throwsArgumentError);
    });

    test(
      'a missing modelId key throws a typed error, not a partial object',
      () {
        final json = _strum().toJson()..remove('modelId');
        expect(() => StrumPrediction.fromJson(json), throwsArgumentError);
      },
    );

    test('fromJson rejects a non-object payload', () {
      expect(
        () => StrumPrediction.fromJson('not an object'),
        throwsArgumentError,
      );
    });
  });

  group('ChordPrediction — model 3/5', () {
    // ADR 0505 D3/R7 — unlike StrumPrediction, decision is NOT derived this
    // round: two predictions with identical probabilities but different
    // constructor-supplied decisions must keep their own decision.
    test('decision is constructor-received this round, not derived', () {
      final rejected = _chord(decision: RecognitionDecision.rejected);
      final confirmed = _chord(decision: RecognitionDecision.confirmed);
      expect(rejected.pNoChord, confirmed.pNoChord);
      expect(rejected.pUnknown, confirmed.pUnknown);
      expect(rejected.decision, RecognitionDecision.rejected);
      expect(confirmed.decision, RecognitionDecision.confirmed);
    });

    test('calibratedConfidence stays null and is never the raw pNoChord', () {
      final prediction = _chord(calibratedConfidence: null);
      expect(prediction.calibratedConfidence, isNull);
      expect(prediction.calibratedConfidence, isNot(prediction.pNoChord));
    });

    test('JSON round-trip is lossless with a null calibratedConfidence', () {
      final prediction = _chord();
      final decoded = ChordPrediction.fromJson(prediction.toJson());
      expect(decoded, prediction);
    });

    test(
      'JSON round-trip is lossless with a measured calibratedConfidence',
      () {
        final prediction = _chord(calibratedConfidence: 0.77);
        final decoded = ChordPrediction.fromJson(prediction.toJson());
        expect(decoded, prediction);
      },
    );

    // Fail-closed cell 3/5 (ADR 0505 D6, L619).
    test('a missing sourceEngine key throws, not a partial object', () {
      final json = _chord().toJson()..remove('sourceEngine');
      expect(() => ChordPrediction.fromJson(json), throwsArgumentError);
    });

    test('a missing decision key throws, not a default decision', () {
      final json = _chord().toJson()..remove('decision');
      expect(() => ChordPrediction.fromJson(json), throwsArgumentError);
    });

    // MAJOR-2 fix-round cell — rejectReason is constructor-received (§0.0
    // R7), not derived: it must round-trip independently of decision.
    test('rejectReason is constructor-received, paired with the reject-side '
        'decision the caller supplies', () {
      final uncertain = _chord(
        decision: RecognitionDecision.uncertain,
        rejectReason: RecognitionRejectReason.lowConfidence,
      );
      final confirmed = _chord(
        decision: RecognitionDecision.confirmed,
        rejectReason: null,
      );
      expect(uncertain.rejectReason, RecognitionRejectReason.lowConfidence);
      expect(confirmed.rejectReason, isNull);
    });

    test('JSON round-trip is lossless with a non-null rejectReason', () {
      final prediction = _chord(
        decision: RecognitionDecision.uncertain,
        rejectReason: RecognitionRejectReason.lowConfidence,
      );
      final decoded = ChordPrediction.fromJson(prediction.toJson());
      expect(decoded, prediction);
      expect(decoded.rejectReason, RecognitionRejectReason.lowConfidence);
    });

    // Fail-closed cell — a missing rejectReason KEY throws, distinct from an
    // explicit null (ADR 0505 D6, L619).
    test('a missing rejectReason KEY throws — distinct from null', () {
      final json = _chord().toJson()..remove('rejectReason');
      expect(() => ChordPrediction.fromJson(json), throwsArgumentError);
    });

    // MINOR-1 fix-round cell.
    test('a calibratedConfidence outside 0..1 throws on decode', () {
      final tooHigh = _chord(calibratedConfidence: 0.5).toJson()
        ..['calibratedConfidence'] = 1.4;
      final tooLow = _chord(calibratedConfidence: 0.5).toJson()
        ..['calibratedConfidence'] = -0.1;
      expect(() => ChordPrediction.fromJson(tooHigh), throwsArgumentError);
      expect(() => ChordPrediction.fromJson(tooLow), throwsArgumentError);
    });
  });

  group('SignalQualitySnapshot — model 4/5', () {
    test('the unknown default has every metric null and state unknown', () {
      const snapshot = SignalQualitySnapshot.unknown;
      expect(snapshot.state, SignalQualityState.unknown);
      expect(snapshot.peakDbfs, isNull);
      expect(snapshot.rmsDbfs, isNull);
      expect(snapshot.noiseFloorDbfs, isNull);
      expect(snapshot.clippedSampleRatio, isNull);
      expect(snapshot.silentRatio, isNull);
      expect(snapshot.activeRegionRatio, isNull);
      expect(snapshot.tonalness, isNull);
    });

    test('JSON round-trip is lossless for the unknown default', () {
      const snapshot = SignalQualitySnapshot.unknown;
      final decoded = SignalQualitySnapshot.fromJson(snapshot.toJson());
      expect(decoded, snapshot);
    });

    test('JSON round-trip is lossless for a fully measured snapshot', () {
      const snapshot = SignalQualitySnapshot(
        state: SignalQualityState.good,
        peakDbfs: -6.0,
        rmsDbfs: -18.0,
        noiseFloorDbfs: -50.0,
        clippedSampleRatio: 0.0,
        silentRatio: 0.02,
        activeRegionRatio: 0.98,
        tonalness: 0.7,
      );
      final decoded = SignalQualitySnapshot.fromJson(snapshot.toJson());
      expect(decoded, snapshot);
    });

    // Fail-closed cell 4/5 (ADR 0505 D6, L619).
    test('a missing state key throws — no silent good default', () {
      final json = SignalQualitySnapshot.unknown.toJson()..remove('state');
      expect(() => SignalQualitySnapshot.fromJson(json), throwsArgumentError);
    });

    test('a missing (nullable) metric key throws — missing != null', () {
      final json = SignalQualitySnapshot.unknown.toJson()..remove('peakDbfs');
      expect(() => SignalQualitySnapshot.fromJson(json), throwsArgumentError);
    });
  });

  group('RecognitionFrame — model 5/5', () {
    test('schemaVersion defaults to the current contract version', () {
      final frame = RecognitionFrame(
        frameTimeSec: 1.0,
        runtimeInfo: _runtimeInfo(),
      );
      expect(frame.schemaVersion, RecognitionFrame.currentSchemaVersion);
      expect(RecognitionFrame.currentSchemaVersion, 1);
    });

    // Acceptance §6.5 — chord- and direction-confidence are carried
    // separately and can differ.
    test('chord- and direction-confidence are carried separately', () {
      final frame = RecognitionFrame(
        frameTimeSec: 1.0,
        runtimeInfo: _runtimeInfo(),
        strum: _strum(calibratedConfidence: 0.9),
        chord: _chord(calibratedConfidence: 0.4),
      );
      expect(frame.strum!.calibratedConfidence, closeTo(0.9, 1e-9));
      expect(frame.chord!.calibratedConfidence, closeTo(0.4, 1e-9));
      expect(
        frame.strum!.calibratedConfidence,
        isNot(frame.chord!.calibratedConfidence),
      );
    });

    test('JSON round-trip is lossless with strum and chord present', () {
      final frame = RecognitionFrame(
        frameTimeSec: 3.25,
        runtimeInfo: _runtimeInfo(),
        strum: _strum(calibratedConfidence: 0.9),
        chord: _chord(calibratedConfidence: 0.4),
        signalQuality: const SignalQualitySnapshot(
          state: SignalQualityState.good,
          rmsDbfs: -18.0,
        ),
      );
      final decoded = RecognitionFrame.fromJson(frame.toJson());
      expect(decoded, frame);
    });

    test('JSON round-trip is lossless with no strum/chord yet', () {
      final frame = RecognitionFrame(
        frameTimeSec: 0.0,
        runtimeInfo: _runtimeInfo(),
      );
      final decoded = RecognitionFrame.fromJson(frame.toJson());
      expect(decoded, frame);
      expect(decoded.strum, isNull);
      expect(decoded.chord, isNull);
      expect(decoded.signalQuality, SignalQualitySnapshot.unknown);
    });

    // Acceptance §6.6 — an unknown schemaVersion is a typed error.
    test('an unknown schemaVersion throws, never a best-effort read', () {
      final json = RecognitionFrame(
        frameTimeSec: 1.0,
        runtimeInfo: _runtimeInfo(),
      ).toJson();
      json['schemaVersion'] = 2;
      expect(() => RecognitionFrame.fromJson(json), throwsArgumentError);
    });

    // Fail-closed cell 5/5 (ADR 0505 D6, L619).
    test('a missing runtimeInfo key throws, not a partial frame', () {
      final json = RecognitionFrame(
        frameTimeSec: 1.0,
        runtimeInfo: _runtimeInfo(),
      ).toJson()..remove('runtimeInfo');
      expect(() => RecognitionFrame.fromJson(json), throwsArgumentError);
    });

    test('a missing frameTimeSec key throws, not a partial frame', () {
      final json = RecognitionFrame(
        frameTimeSec: 1.0,
        runtimeInfo: _runtimeInfo(),
      ).toJson()..remove('frameTimeSec');
      expect(() => RecognitionFrame.fromJson(json), throwsArgumentError);
    });

    test(
      'a missing strum/chord KEY throws — distinct from an explicit null',
      () {
        final json = RecognitionFrame(
          frameTimeSec: 1.0,
          runtimeInfo: _runtimeInfo(),
        ).toJson()..remove('strum');
        expect(() => RecognitionFrame.fromJson(json), throwsArgumentError);
      },
    );
  });
}
