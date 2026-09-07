// Javító sáv 2026-09-06 (R8, audit §5.2 "Song trainer sebesség-slider").
//
// The slider shipped with `onChanged: null` because the controller had no
// backing-rate operation at all. It has one now, and these are its measured
// guarantees:
//
// C1 — a playback-only session accepts a supported rate and mirrors it into
//      the trainer state and the transport.
// C2 — the transport TIMELINE is rescheduled: the audio-clock-derived
//      position advances at the applied rate, not at 1x.
// C3 — the rate reaches the audio player itself once playback runs.
// C4 — changing the rate mid-playback keeps the session playing and does not
//      rewind the playhead.
// C5 — an unsupported rate is an explicit failure; nothing is applied.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_practice_compiler.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_controller.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_state.dart';
import 'package:strumsight/features/song_trainer/data/playback/backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';

void main() {
  group('SongTrainerController.setPlaybackRate', () {
    test('C1 — a playback-only session accepts a supported rate', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.controller.prepare();

      final applied = await harness.controller.setPlaybackRate(0.75);

      expect(harness.controller.canChangeBackingRate, isTrue);
      expect(applied.isSuccess, isTrue);
      expect(harness.controller.state.playbackRate, 0.75);
      expect(harness.transport.state.speed, 0.75);
    });

    test('C2 — the timeline advances at the applied rate', () async {
      final slow = _Harness();
      final normal = _Harness();
      addTearDown(slow.dispose);
      addTearDown(normal.dispose);
      await slow.controller.prepare();
      await normal.controller.prepare();

      expect((await slow.controller.setPlaybackRate(0.5)).isSuccess, isTrue);
      await slow.controller.start();
      await normal.controller.start();
      slow.clock.advance(const Duration(seconds: 2));
      normal.clock.advance(const Duration(seconds: 2));

      expect(slow.transport.state.phase, SongTransportPhase.playing);
      expect(slow.transport.state.activePosition, _oneSecond);
      expect(normal.transport.state.activePosition, _twoSeconds);
    });

    test('C3 — the rate reaches the audio player once playing', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.controller.prepare();

      await harness.controller.setPlaybackRate(0.5);
      expect(harness.player.lastRate, isNull);
      await harness.controller.start();

      expect(harness.player.lastRate, 0.5);
    });

    test('C4 — a mid-playback change keeps playing', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.controller.prepare();
      await harness.controller.start();
      harness.clock.advance(const Duration(seconds: 2));

      final applied = await harness.controller.setPlaybackRate(0.5);

      expect(applied.isSuccess, isTrue);
      expect(harness.player.lastRate, 0.5);
      expect(harness.transport.state.phase, SongTransportPhase.playing);
      expect(harness.transport.state.activePosition, _twoSeconds);
      harness.clock.advance(const Duration(seconds: 2));
      expect(harness.transport.state.activePosition, _threeSeconds);
    });

    test('C5 — an unsupported rate is an explicit failure', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.controller.prepare();

      final applied = await harness.controller.setPlaybackRate(4);

      expect(applied.isFailure, isTrue);
      expect(
        applied.failureOrNull!.code,
        BackingAudioPlayerFailureCode.unsupportedRate,
      );
      expect(harness.controller.state.playbackRate, 1);
      expect(harness.transport.state.speed, 1);
    });
  });
}

const Duration _oneSecond = Duration(seconds: 1);
const Duration _twoSeconds = Duration(seconds: 2);
const Duration _threeSeconds = Duration(seconds: 3);

final class _Harness {
  _Harness() {
    player = FakeBackingAudioPlayer();
    clock = FakeSongTransportClock();
    transport = SongTransport(player: player, clock: clock);
    controller = SongTrainerController(
      transport: transport,
      compilation: const SongPracticeCompilation.playbackOnly(),
      backingAsset: _asset,
    );
  }

  late final FakeBackingAudioPlayer player;
  late final FakeSongTransportClock clock;
  late final SongTransport transport;
  late final SongTrainerController controller;

  Future<void> dispose() async {
    await controller.dispose();
    await transport.dispose();
  }
}

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('backing'),
  sha256: 'a' * 64,
  extension: 'mp3',
  byteLength: 100,
  mimeType: 'audio/mpeg',
  durationMs: 1000,
);
