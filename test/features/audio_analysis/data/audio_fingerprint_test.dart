import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/data/cache/audio_fingerprint.dart';

void main() {
  test('fingerprint is deterministic for identical normalized PCM', () {
    final samples = <double>[0, .125, -.125, .5, -.5];

    final fingerprints = <String>{
      for (var index = 0; index < 100; index++)
        AudioFingerprint.compute(
          samples: samples,
          sampleRate: 44100,
          channelCount: 1,
          preprocessingVersion: 'preprocess-v1',
        ),
    };

    expect(fingerprints, hasLength(1));
  });

  test('fingerprint changes when one sample changes', () {
    final common = <String, Object>{
      'sampleRate': 44100,
      'channelCount': 1,
      'preprocessingVersion': 'preprocess-v1',
    };

    final first = AudioFingerprint.compute(
      samples: const <double>[0, .125, -.125],
      sampleRate: common['sampleRate']! as int,
      channelCount: common['channelCount']! as int,
      preprocessingVersion: common['preprocessingVersion']! as String,
    );
    final changed = AudioFingerprint.compute(
      samples: const <double>[0, .125, -.25],
      sampleRate: common['sampleRate']! as int,
      channelCount: common['channelCount']! as int,
      preprocessingVersion: common['preprocessingVersion']! as String,
    );

    expect(changed, isNot(first));
  });

  test('fingerprint has a fixed non-reconstructable SHA-256 length', () {
    final short = AudioFingerprint.compute(
      samples: const <double>[.1],
      sampleRate: 44100,
      channelCount: 1,
      preprocessingVersion: 'preprocess-v1',
    );
    final long = AudioFingerprint.compute(
      samples: List<double>.filled(1000, .1),
      sampleRate: 44100,
      channelCount: 1,
      preprocessingVersion: 'preprocess-v1',
    );

    expect(short, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(long, hasLength(64));
  });

  test('content fingerprint has no filename input', () {
    final first = AudioFingerprint.compute(
      samples: const <double>[0, .2, -.2],
      sampleRate: 44100,
      channelCount: 1,
      preprocessingVersion: 'preprocess-v1',
    );
    final renamed = AudioFingerprint.compute(
      samples: const <double>[0, .2, -.2],
      sampleRate: 44100,
      channelCount: 1,
      preprocessingVersion: 'preprocess-v1',
    );

    expect(renamed, first);
  });
}
