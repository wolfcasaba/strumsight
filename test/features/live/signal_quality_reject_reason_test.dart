// ADR 0535 (E17-R15) — the merged `signalQuality` reject reason is SPLIT into
// six typed reasons, one per non-`good` `SignalQualityState`. These cells are
// the machine-checkable spec of D1 (one reason per state, pairwise distinct,
// no collector tag) and D2 (exhaustive mapping in the engine, signal quality
// still deciding BEFORE `noChord`).

import 'package:flutter_test/flutter_test.dart';
// `LivePipeline` stays a direct import — the DSP/ML engine is deliberately
// NOT exported by the barrel (public.dart's own NOTE); every domain type is
// imported from the barrel, like the neighbouring live tests.
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/public.dart';

/// The ADR 0535 D1 table, spelled out here so a silent re-mapping in the
/// engine fails this file rather than passing by construction.
const _mapping = <SignalQualityState, RecognitionRejectReason>{
  SignalQualityState.tooQuiet: RecognitionRejectReason.signalTooQuiet,
  SignalQualityState.tooLoud: RecognitionRejectReason.signalTooLoud,
  SignalQualityState.clipping: RecognitionRejectReason.signalClipping,
  SignalQualityState.tooNoisy: RecognitionRejectReason.signalTooNoisy,
  SignalQualityState.speechLike: RecognitionRejectReason.signalSpeechLike,
  SignalQualityState.unstable: RecognitionRejectReason.signalUnstable,
};

void main() {
  group('ADR 0535 D1 — every non-good signal state gets its OWN reason', () {
    for (final MapEntry(key: state, value: expected) in _mapping.entries) {
      test('${state.name} rejects with ${expected.name}', () {
        final (decision, reason) = LivePipeline.debugDeriveChordDecision(
          chordLatched: false,
          hasMatch: true,
          signalQualityState: state,
        );
        expect(decision, RecognitionDecision.rejected);
        expect(reason, expected);
      });
    }

    test('the six mapped reasons are pairwise distinct — the merged '
        'collector tag is gone', () {
      expect(_mapping.values.toSet(), hasLength(_mapping.length));
      expect(_mapping.length, 6);
    });
  });

  group('ADR 0535 D2 — good/unknown never produce a signal reason', () {
    const neutral = <SignalQualityState>[
      SignalQualityState.good,
      SignalQualityState.unknown,
    ];
    for (final state in neutral) {
      test('${state.name}: the reason is never a signal* member', () {
        for (final hasMatch in const [true, false]) {
          final (_, reason) = LivePipeline.debugDeriveChordDecision(
            chordLatched: false,
            hasMatch: hasMatch,
            signalQualityState: state,
          );
          expect(reason, isNotNull);
          expect(
            reason!.name.startsWith('signal'),
            isFalse,
            reason:
                '${state.name} with hasMatch=$hasMatch must not blame the '
                'signal, got ${reason.name}',
          );
        }
      });
    }
  });

  group(
    'ADR 0535 D2 — signal quality still precedes noChord (ADR 0516 D4)',
    () {
      test('no match AND tooLoud -> signalTooLoud, never noChord', () {
        final (decision, reason) = LivePipeline.debugDeriveChordDecision(
          chordLatched: false,
          hasMatch: false,
          signalQualityState: SignalQualityState.tooLoud,
        );
        expect(decision, RecognitionDecision.rejected);
        expect(reason, RecognitionRejectReason.signalTooLoud);
      });
    },
  );
}
