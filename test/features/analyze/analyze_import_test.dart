// Round 179 — importing your own audio runs the SAME DSP a mic recording does.
// AnalyzeController.analyzeImported takes decoded PCM (no mic) and drives the
// screen to `done` with a real timeline, credits practice, and is safely inert
// mid-record / on empty audio.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/providers/analyze_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/synth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  (ProviderContainer, AnalyzeController) rig() {
    final container = ProviderContainer();
    return (container, container.read(analyzeControllerProvider.notifier));
  }

  test('an imported clip analyzes to done with a real timeline', () async {
    final (container, controller) = rig();
    addTearDown(container.dispose);

    // ~2 s of C major, at 16 kHz (a common imported/exported rate).
    final pcm = chordSignal(cMajorFreqs, seconds: 2.0, sampleRate: 16000);
    await controller.analyzeImported(pcm.toList(), 16000);

    final s = container.read(analyzeControllerProvider);
    expect(s.phase, AnalyzePhase.done);
    expect(s.result, isNotNull);
    expect(s.result!.durationSec, closeTo(2.0, 0.1));
    expect(s.result!.chords, isNotEmpty,
        reason: 'the imported chord should appear on the timeline');

    // Let the fire-and-forget practice/streak writes settle before the
    // container is torn down (the real app never disposes this fast).
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('empty / invalid imported audio is a no-op (stays idle)', () async {
    final (container, controller) = rig();
    addTearDown(container.dispose);

    await controller.analyzeImported(const [], 16000);
    expect(container.read(analyzeControllerProvider).phase, AnalyzePhase.idle);

    await controller.analyzeImported([0.1, 0.2, 0.3], 0); // bad sample rate
    expect(container.read(analyzeControllerProvider).phase, AnalyzePhase.idle);
  });
}
