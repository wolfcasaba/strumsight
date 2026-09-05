// E14-R12 — the RecognitionStabilizer's provider wiring (ADR 0518 D5): a
// held chord produces exactly one timeline card, and a single-frame foreign
// blip between two held segments produces none. Driven through the real
// providers (ChordTimelineController -> RecognitionStabilizer ->
// reduceChordTimeline) with a FakeStrumEngine standing in for the mic, same
// pattern as live_announcement_throttle_test.dart's non-widget rig.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/chord_timeline_provider.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';

import '../../support/fake_engines.dart';

LiveFrame _frame(String label) => LiveFrame(
  current: Chord(label),
  next: null,
  latestStrum: null,
  bar: const <BeatSlot>[],
  bpm: 0,
  inputLevel: 0,
  tuningHz: 440,
  listening: true,
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '3a: 10 held frames of the same chord give exactly one timeline card',
    () async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);
      final container = ProviderContainer(
        overrides: [strumEngineProvider.overrideWithValue(engine)],
      );
      addTearDown(container.dispose);
      container.listen(chordTimelineProvider, (prev, next) {});

      for (var i = 0; i < 10; i++) {
        engine.emit(_frame('A'));
        await _flush();
      }

      final events = container.read(chordTimelineProvider);
      expect(events.length, 1);
      expect(events.single.chord.label, 'A');
    },
  );

  test('3b: a single-frame foreign blip between two held A segments spawns '
      'no card', () async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    final container = ProviderContainer(
      overrides: [strumEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);
    container.listen(chordTimelineProvider, (prev, next) {});

    for (var i = 0; i < 3; i++) {
      engine.emit(_frame('A'));
      await _flush();
    }
    engine.emit(_frame('B'));
    await _flush();
    for (var i = 0; i < 3; i++) {
      engine.emit(_frame('A'));
      await _flush();
    }

    final events = container.read(chordTimelineProvider);
    expect(
      events.length,
      1,
      reason: 'the single-frame B blip must never reach the timeline',
    );
    expect(events.single.chord.label, 'A');
  });
}
