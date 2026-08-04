import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation_config.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/audio/live_pitch_observation_gateway.dart';

import '../../../../support/fake_audio.dart';

const _sampleRate = 44100;

Float64List _sine(double frequency) => Float64List.fromList([
  for (var index = 0; index < 4096; index++)
    0.3 * math.sin(2 * math.pi * frequency * index / _sampleRate),
]);

void main() {
  test(
    'uses an injected lease-owning frame source exactly once and releases it on stop',
    () async {
      final now = DateTime.utc(2026, 8, 4, 12);
      final source = _LeaseCountingFrameSource();
      final gateway = LivePitchObservationGateway(
        source: source,
        now: () => now,
      );
      final observations = <PitchObservation>[];
      final subscription = gateway.observations.listen(observations.add);
      addTearDown(subscription.cancel);
      addTearDown(gateway.dispose);

      expect(
        await gateway.start(const PitchObservationConfig()),
        isA<Success<void>>(),
      );
      expect(
        await gateway.start(const PitchObservationConfig()),
        isA<Success<void>>(),
      );
      expect(source.leaseAcquires, 1);

      source.emit(PitchPcmFrame(samples: _sine(110), capturedAt: now));
      source.emit(PitchPcmFrame(samples: _sine(110), capturedAt: now));
      await Future<void>.delayed(Duration.zero);

      expect(observations, hasLength(2));
      expect(observations.last.midiPitch, 45);
      expect(observations.last.stable, isTrue);

      expect(await gateway.stop(), isA<Success<void>>());
      expect(await gateway.stop(), isA<Success<void>>());
      expect(source.leaseReleases, 1);
    },
  );

  test(
    'disposing the MicCapture adapter returns its only acquired lease',
    () async {
      final coordinator = AudioSessionCoordinator();
      final capture = FakeAudioCapture();
      final source = MicCapturePitchFrameSource(
        micCapture: fakeMicCapture(
          owner: AudioOwner.live,
          coordinator: coordinator,
          capture: capture,
        ),
      );
      final gateway = LivePitchObservationGateway(source: source);

      expect(
        await gateway.start(const PitchObservationConfig()),
        isA<Success<void>>(),
      );
      expect(coordinator.activeOwner, AudioOwner.live);

      await gateway.dispose();

      expect(capture.isRunning, isFalse);
      expect(coordinator.activeOwner, isNull);
    },
  );

  test(
    'MicCapture frame source releases its lease when disposed without a gateway',
    () async {
      final coordinator = AudioSessionCoordinator();
      final source = MicCapturePitchFrameSource(
        micCapture: fakeMicCapture(
          coordinator: coordinator,
          capture: FakeAudioCapture(sampleRate: 48000),
        ),
      );

      expect((await source.start()).valueOrNull, 48000);
      expect((await source.start()).valueOrNull, 48000);
      expect(coordinator.activeOwner, AudioOwner.live);

      await source.dispose();

      expect(coordinator.activeOwner, isNull);
    },
  );

  test(
    'keeps the latency limit inclusive and marks a later frame unstable',
    () async {
      final now = DateTime.utc(2026, 8, 4, 12);
      final source = _LeaseCountingFrameSource();
      final gateway = LivePitchObservationGateway(
        source: source,
        now: () => now,
      );
      final observations = <PitchObservation>[];
      final subscription = gateway.observations.listen(observations.add);
      addTearDown(subscription.cancel);
      addTearDown(gateway.dispose);
      await gateway.start(const PitchObservationConfig());

      final atLimit = now.subtract(const Duration(milliseconds: 100));
      source.emit(PitchPcmFrame(samples: _sine(110), capturedAt: atLimit));
      source.emit(PitchPcmFrame(samples: _sine(110), capturedAt: atLimit));
      final aboveLimit = now.subtract(const Duration(microseconds: 100001));
      source.emit(PitchPcmFrame(samples: _sine(110), capturedAt: aboveLimit));
      await Future<void>.delayed(Duration.zero);

      expect(observations[1].stable, isTrue);
      expect(observations.last.stable, isFalse);
    },
  );
}

final class _LeaseCountingFrameSource implements PitchFrameSource {
  final StreamController<PitchPcmFrame> _frames =
      StreamController<PitchPcmFrame>.broadcast();
  int leaseAcquires = 0;
  int leaseReleases = 0;

  @override
  Stream<PitchPcmFrame> get frames => _frames.stream;

  @override
  Future<AppResult<int>> start() async {
    leaseAcquires++;
    return const Success<int>(_sampleRate);
  }

  @override
  Future<AppResult<void>> stop() async {
    leaseReleases++;
    return const Success<void>(null);
  }

  @override
  Future<void> dispose() => _frames.close();

  void emit(PitchPcmFrame frame) => _frames.add(frame);
}
