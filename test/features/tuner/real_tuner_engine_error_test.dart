import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/features/tuner/engine/real_tuner_engine.dart';

import '../../support/fake_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RealTunerEngine surfaces a mic start failure on the readings stream '
      '(never throws out of start) — parity with RealStrumEngine', () async {
    final engine = RealTunerEngine(
      mic: fakeMicCapture(
        owner: AudioOwner.tuner,
        capture: FakeAudioCapture(failWith: StateError('mic busy')),
      ),
    );
    addTearDown(engine.dispose);

    final errors = <Object>[];
    final sub = engine.readings.listen((_) {}, onError: errors.add);
    addTearDown(sub.cancel);

    // The injected capture throws (busy mic / platform error) — the engine
    // must convert that into a stream error the screen can render, exactly
    // like RealStrumEngine (round 13).
    await engine.start();
    await Future<void>.delayed(Duration.zero);

    expect(
      errors,
      isNotEmpty,
      reason: 'a mic failure must surface on the stream, not vanish',
    );
  });
}
