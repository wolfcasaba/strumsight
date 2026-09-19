import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/recognition_rollout_stage.dart';

// Imported EXCLUSIVELY via the barrel (not the direct model file): if the
// E14-R03 additive export in public.dart ever goes missing, this whole file
// fails to COMPILE rather than silently skipping the acceptance point (§6).
import 'package:strumsight/features/live/public.dart';
import 'package:strumsight/features/live/providers/live_lab_provider.dart';

RecognitionRuntimeInfo _activatedInfo({FallbackReason? fallbackReason}) =>
    RecognitionRuntimeInfo(
      strumModelId: 'strum_crnn_live_3c.bin',
      strumModelVersion: 1,
      strumModelSha256:
          'aa11bb22cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd6',
      chordEngineId: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
      sampleRate: 44100,
      frontendVersion: RecognitionRuntimeInfo.frontendCrnnV1,
      fallbackReason: fallbackReason,
    );

void main() {
  group('RecognitionRuntimeInfo — model contract', () {
    test('every FallbackReason is one of the 5 stable, closed codes', () {
      expect(FallbackReason.values.length, 5);
      expect(FallbackReason.values.map((r) => r.name).toSet(), {
        'assetMissing',
        'assetUnreadable',
        'parseFailed',
        'shapeMismatch',
        'disabledByFlag',
      });
    });

    test('JSON round-trip is lossless for an activated info', () {
      final info = _activatedInfo();
      final decoded = RecognitionRuntimeInfo.fromJson(info.toJson());
      expect(decoded, info);
      expect(decoded.fallbackReason, isNull);
    });

    test('JSON round-trip is lossless for a fallback info', () {
      final info = RecognitionRuntimeInfo.fallback(
        FallbackReason.shapeMismatch,
        sampleRate: 48000,
      );
      final decoded = RecognitionRuntimeInfo.fromJson(info.toJson());
      expect(decoded, info);
      expect(decoded.fallbackReason, FallbackReason.shapeMismatch);
    });

    // --- E14-R23 / E14-R26 additions (ADR 0548 D5, ADR 0549 D1) ------------
    // RED before this round: the four chord fields, the recognition mode and
    // the shadow stage did not exist on this type.

    test('the new fields default to the fail-closed, model-free shape', () {
      final info = _activatedInfo();
      expect(info.recognitionMode, RecognitionMode.free);
      expect(info.shadowStage, RecognitionRolloutStage.off);
      expect(info.chordModelId, RecognitionRuntimeInfo.chordModelNone);
      expect(info.chordModelVersion, 0);
      expect(info.chordModelSha256, '');
      expect(info.chordFallbackReason, isNull);
    });

    test('JSON round-trip is lossless with every shadow band populated', () {
      final info = _activatedInfo().withShadowBands(
        recognitionMode: RecognitionMode.guided,
        shadowStage: RecognitionRolloutStage.shadow,
        chordModelId: RecognitionRuntimeInfo.chordModelCrnn,
        chordModelVersion: 1,
        chordModelSha256: 'ab' * 32,
        chordFallbackReason: FallbackReason.shapeMismatch,
      );
      final decoded = RecognitionRuntimeInfo.fromJson(info.toJson());
      expect(decoded, info);
      expect(decoded.recognitionMode, RecognitionMode.guided);
      expect(decoded.shadowStage, RecognitionRolloutStage.shadow);
      expect(decoded.chordFallbackReason, FallbackReason.shapeMismatch);
    });

    test('a legacy JSON without the new keys decodes fail-CLOSED', () {
      final legacy = <String, dynamic>{
        'strumModelId': 'strum_crnn_live_3c.bin',
        'strumModelVersion': 1,
        'strumModelSha256': 'cd' * 31,
        'chordEngineId': RecognitionRuntimeInfo.chordEngineNnlsViterbi,
        'sampleRate': 44100,
        'frontendVersion': RecognitionRuntimeInfo.frontendCrnnV1,
        'fallbackReason': null,
      };
      final decoded = RecognitionRuntimeInfo.fromJson(legacy);
      expect(decoded.recognitionMode, RecognitionMode.free);
      expect(decoded.shadowStage, RecognitionRolloutStage.off);
      expect(decoded.chordModelId, RecognitionRuntimeInfo.chordModelNone);
      expect(decoded.chordFallbackReason, isNull);
    });

    test('an unknown mode/stage on the wire reads back as the safe one', () {
      final json = _activatedInfo().toJson()
        ..['recognitionMode'] = 'omniscient'
        ..['shadowStage'] = 'ga-plus';
      final decoded = RecognitionRuntimeInfo.fromJson(json);
      expect(
        decoded.recognitionMode,
        RecognitionMode.free,
        reason: 'an unreadable regime must never widen to guided',
      );
      expect(
        decoded.shadowStage,
        RecognitionRolloutStage.off,
        reason: 'an unreadable stage must never widen to a running one',
      );
    });

    test('the two bands report SEPARATE fallbacks', () {
      final info = RecognitionRuntimeInfo.fallback(
        FallbackReason.assetMissing,
        sampleRate: 44100,
      ).withShadowBands(chordFallbackReason: FallbackReason.parseFailed);
      expect(info.fallbackReason, FallbackReason.assetMissing);
      expect(info.chordFallbackReason, FallbackReason.parseFailed);
      expect(
        RecognitionRuntimeInfo.fromJson(info.toJson()),
        info,
        reason: 'one band failing must never be reported as the other',
      );
    });

    test('withShadowBands never relabels which model DECIDED', () {
      final base = _activatedInfo();
      final withShadow = base.withShadowBands(
        shadowStage: RecognitionRolloutStage.shadow,
        chordModelId: RecognitionRuntimeInfo.chordModelCrnn,
      );
      expect(withShadow.strumModelId, base.strumModelId);
      expect(withShadow.strumModelSha256, base.strumModelSha256);
      expect(withShadow.chordEngineId, base.chordEngineId);
      expect(withShadow.fallbackReason, base.fallbackReason);
      expect(withShadow, isNot(base));
    });

    test('fallbackReason serializes to its enum name, not an index', () {
      final json = _activatedInfo(
        fallbackReason: FallbackReason.parseFailed,
      ).toJson();
      expect(json['fallbackReason'], 'parseFailed');
    });

    test('equality/hashCode compare every field', () {
      final a = _activatedInfo();
      final b = _activatedInfo();
      final different = _activatedInfo(
        fallbackReason: FallbackReason.assetMissing,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(different));
    });

    test('RecognitionRuntimeInfo.fallback is the canonical neutral shape', () {
      final info = RecognitionRuntimeInfo.fallback(
        FallbackReason.assetMissing,
        sampleRate: 44100,
      );
      expect(info.strumModelId, 'none');
      expect(info.strumModelVersion, 0);
      expect(info.strumModelSha256, '');
      expect(info.fallbackReason, FallbackReason.assetMissing);
    });
  });

  group(
    '5. LiveLabState carries runtime info (R3 — additive, no wiring yet)',
    () {
      test('initial state has a null runtimeInfo', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(container.read(liveLabProvider).runtimeInfo, isNull);
      });

      test('reportRuntimeInfo distinguishes activated from fallback', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final activated = _activatedInfo();
        container.read(liveLabProvider.notifier).reportRuntimeInfo(activated);
        expect(container.read(liveLabProvider).runtimeInfo, activated);
        expect(
          container.read(liveLabProvider).runtimeInfo?.fallbackReason,
          isNull,
        );

        final fallback = RecognitionRuntimeInfo.fallback(
          FallbackReason.assetMissing,
          sampleRate: 44100,
        );
        container.read(liveLabProvider.notifier).reportRuntimeInfo(fallback);
        expect(container.read(liveLabProvider).runtimeInfo, fallback);
        expect(container.read(liveLabProvider).runtimeInfo, isNot(activated));
        expect(
          container.read(liveLabProvider).runtimeInfo?.fallbackReason,
          FallbackReason.assetMissing,
        );
      });

      test('reportRuntimeInfo(null) clears it back to null', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container
            .read(liveLabProvider.notifier)
            .reportRuntimeInfo(_activatedInfo());
        container.read(liveLabProvider.notifier).reportRuntimeInfo(null);

        expect(container.read(liveLabProvider).runtimeInfo, isNull);
      });
    },
  );
}
