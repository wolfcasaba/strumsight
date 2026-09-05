import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/public.dart';
import 'package:strumsight/features/onboarding/public.dart';

import '../../core/storage/in_memory_key_value_store.dart';

/// ADR 0519 acceptance #1 (lépés-gép + hossz), #2 (rossz jelminőség) és #3
/// (megszakítás → nincs részleges profil).
void main() {
  const goodSnapshot = SignalQualitySnapshot(state: SignalQualityState.good);
  const tooQuietSnapshot = SignalQualitySnapshot(
    state: SignalQualityState.tooQuiet,
  );

  AudioSetupController buildController({
    AudioProfileStore? store,
    DateTime Function()? now,
  }) {
    return AudioSetupController(
      store: store ?? AudioProfileStore(InMemoryKeyValueStore()),
      micRouteId: 'wired-headset',
      sampleRateHz: 48000,
      now: now,
    );
  }

  group('acceptance #1 — the SDD step sequence and its duration budget', () {
    test('the sequence contains one silence, one strong down-strum, one '
        'up-strum, the four beginner chords (E, Am, G, C), and a closing '
        'position suggestion, in that order', () {
      final kinds = AudioSetupStep.sequence.map((s) => s.kind).toList();
      expect(kinds, [
        AudioSetupStepKind.silence,
        AudioSetupStepKind.strongDownStrum,
        AudioSetupStepKind.upStrum,
        AudioSetupStepKind.chordCheck,
        AudioSetupStepKind.chordCheck,
        AudioSetupStepKind.chordCheck,
        AudioSetupStepKind.chordCheck,
        AudioSetupStepKind.positionSuggestion,
      ]);

      final chords = AudioSetupStep.sequence
          .where((s) => s.kind == AudioSetupStepKind.chordCheck)
          .map((s) => s.expectedChord)
          .toList();
      expect(chords, ['E', 'Am', 'G', 'C']);
    });

    test('the sequence\'s own planned total duration falls inside the '
        'accepted 30-60s window', () {
      expect(
        isAudioSetupDurationAccepted(AudioSetupStep.totalPlannedDuration),
        isTrue,
      );
    });

    test('the boundary is inclusive on the top: 59s accepted, 60s accepted, '
        '61s rejected — cells built from integer-literal Durations, not a '
        'computed sum (ADR 0519 §0.0 measured: no floating-point edge)', () {
      expect(isAudioSetupDurationAccepted(const Duration(seconds: 59)), isTrue);
      expect(isAudioSetupDurationAccepted(const Duration(seconds: 60)), isTrue);
      expect(
        isAudioSetupDurationAccepted(const Duration(seconds: 61)),
        isFalse,
      );
    });

    test('below the 30s floor is rejected; exactly 30s is accepted', () {
      expect(
        isAudioSetupDurationAccepted(const Duration(seconds: 29)),
        isFalse,
      );
      expect(isAudioSetupDurationAccepted(const Duration(seconds: 30)), isTrue);
    });
  });

  group('acceptance #2 — bad signal quality never yields success', () {
    test('a tooQuiet fixture on any step ends the run as needsAttention with '
        'non-empty advice, and saves no profile', () async {
      final store = AudioProfileStore(InMemoryKeyValueStore());
      final controller = buildController(store: store);
      controller.start();

      AudioSetupResult? result;
      for (var i = 0; i < AudioSetupStep.sequence.length; i++) {
        final snapshot = i == 0 ? tooQuietSnapshot : goodSnapshot;
        result = await controller.recordStep(snapshot);
      }

      expect(result, isNotNull);
      expect(result!.outcome, AudioSetupOutcome.needsAttention);
      expect(result.advice, isNotEmpty);
      expect(result.profile, isNull);
      expect(store.read(), isNull);
    });

    test('an all-good run ends as success with a saved profile', () async {
      final store = AudioProfileStore(InMemoryKeyValueStore());
      final controller = buildController(store: store);
      controller.start();

      AudioSetupResult? result;
      for (var i = 0; i < AudioSetupStep.sequence.length; i++) {
        result = await controller.recordStep(goodSnapshot);
      }

      expect(result, isNotNull);
      expect(result!.outcome, AudioSetupOutcome.success);
      expect(result.profile, isNotNull);
      expect(store.read(), result.profile);
    });
  });

  group('acceptance #3 — interruption leaves no partial profile (D4, §7.1 '
      'falszifikációs próba)', () {
    test('abort() after a few recorded steps leaves the store empty — the '
        'save is atomic, never step-by-step', () async {
      final store = AudioProfileStore(InMemoryKeyValueStore());
      final controller = buildController(store: store);
      controller.start();

      await controller.recordStep(goodSnapshot);
      await controller.recordStep(goodSnapshot);
      controller.abort();

      expect(store.read(), isNull);
      expect(controller.status, AudioSetupRunStatus.aborted);
    });

    test('recordStep after abort() throws — the machine does not silently '
        'resume a dead run', () async {
      final controller = buildController();
      controller.start();
      await controller.recordStep(goodSnapshot);
      controller.abort();

      expect(() => controller.recordStep(goodSnapshot), throwsStateError);
    });
  });
}
