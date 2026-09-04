import 'package:flutter_test/flutter_test.dart';

// public.dart doesn't (and shouldn't, this round) re-export BeatSlot; it's
// only needed here to build a legacy LiveFrame fixture, same as
// live_widgets_test.dart does.
import 'package:strumsight/features/live/model/beat_slot.dart';

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

ChordPrediction _chordWith(RecognitionDecision decision) => ChordPrediction(
  label: 'Am',
  root: 'A',
  quality: 'min',
  pNoChord: 0.05,
  pUnknown: 0.1,
  calibratedConfidence: null,
  stabilityFrames: 6,
  sourceEngine: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
  decision: decision,
);

LiveFrame _baseFrame() => const LiveFrame(
  current: null,
  next: null,
  latestStrum: null,
  bar: <BeatSlot>[],
  bpm: 120,
  inputLevel: 0.3,
  tuningHz: 440,
  listening: true,
  strumSeq: 4,
);

void main() {
  group(
    'LiveFrameAdapter — backward compatibility matrix (ADR 0505 D5, §6.3)',
    () {
      // The MAI (today's) `_chordLatched == false` truth: only `confirmed`
      // shows a chord; every other RecognitionDecision produces `current:
      // null` — never "upgraded" to show something just so there is
      // something to show.
      const expectations = <RecognitionDecision, bool>{
        RecognitionDecision.candidate: false,
        RecognitionDecision.provisional: false,
        RecognitionDecision.confirmed: true,
        RecognitionDecision.uncertain: false,
        RecognitionDecision.rejected: false,
        RecognitionDecision.expired: false,
      };

      for (final entry in expectations.entries) {
        test(
          '${entry.key.name} → current ${entry.value ? 'present' : 'null'}',
          () {
            final frame = RecognitionFrame(
              frameTimeSec: 5.0,
              runtimeInfo: _runtimeInfo(),
              chord: _chordWith(entry.key),
            );

            final legacy = LiveFrameAdapter.toLiveFrame(frame, _baseFrame());

            if (entry.value) {
              expect(legacy.current, isNotNull);
              expect(legacy.current!.label, 'Am');
            } else {
              expect(legacy.current, isNull);
            }
          },
        );
      }

      test(
        'a RecognitionFrame with no chord prediction at all → current null',
        () {
          final frame = RecognitionFrame(
            frameTimeSec: 5.0,
            runtimeInfo: _runtimeInfo(),
          );

          final legacy = LiveFrameAdapter.toLiveFrame(frame, _baseFrame());

          expect(legacy.current, isNull);
        },
      );
    },
  );

  group('LiveFrameAdapter — fields the new contract does not model yet', () {
    test(
      'bar/bpm/inputLevel/tuningHz/listening/strumSeq pass through from base',
      () {
        final base = _baseFrame();
        final frame = RecognitionFrame(
          frameTimeSec: 5.0,
          runtimeInfo: _runtimeInfo(),
        );

        final legacy = LiveFrameAdapter.toLiveFrame(frame, base);

        expect(legacy.bar, base.bar);
        expect(legacy.bpm, base.bpm);
        expect(legacy.inputLevel, base.inputLevel);
        expect(legacy.tuningHz, base.tuningHz);
        expect(legacy.listening, base.listening);
        expect(legacy.strumSeq, base.strumSeq);
        // `next` isn't modelled by RecognitionFrame this round either.
        expect(legacy.next, base.next);
      },
    );

    test('engineTimeSec comes from the new frame, not the base', () {
      final legacy = LiveFrameAdapter.toLiveFrame(
        RecognitionFrame(frameTimeSec: 42.0, runtimeInfo: _runtimeInfo()),
        _baseFrame(),
      );

      expect(legacy.engineTimeSec, 42.0);
    });
  });

  group(
    'LiveFrameAdapter — calibratedConfidence never becomes a fabricated legacy confidence',
    () {
      test(
        'an uncalibrated strum reports legacy confidence 0, not the raw pDown',
        () {
          final frame = RecognitionFrame(
            frameTimeSec: 1.0,
            runtimeInfo: _runtimeInfo(),
            strum: StrumPrediction(
              onsetTimeSec: 1.0,
              verdictTimeSec: 1.05,
              pDown: 0.95,
              pUp: 0.05,
              pNoStrum: 0.0,
              calibratedConfidence: null,
              modelId: 'strum_crnn_live_3c.bin',
            ),
          );

          final legacy = LiveFrameAdapter.toLiveFrame(frame, _baseFrame());

          expect(legacy.latestStrum, isNotNull);
          expect(legacy.confidence, 0);
        },
      );

      test(
        'a calibrated strum reports the calibrated value as legacy confidence',
        () {
          final frame = RecognitionFrame(
            frameTimeSec: 1.0,
            runtimeInfo: _runtimeInfo(),
            strum: StrumPrediction(
              onsetTimeSec: 1.0,
              verdictTimeSec: 1.05,
              pDown: 0.95,
              pUp: 0.05,
              pNoStrum: 0.0,
              calibratedConfidence: 0.88,
              modelId: 'strum_crnn_live_3c.bin',
            ),
          );

          final legacy = LiveFrameAdapter.toLiveFrame(frame, _baseFrame());

          expect(legacy.confidence, closeTo(0.88, 1e-9));
        },
      );

      test('no strum prediction → no legacy latestStrum', () {
        final legacy = LiveFrameAdapter.toLiveFrame(
          RecognitionFrame(frameTimeSec: 1.0, runtimeInfo: _runtimeInfo()),
          _baseFrame(),
        );

        expect(legacy.latestStrum, isNull);
        expect(legacy.confidence, 0);
      });
    },
  );
}
