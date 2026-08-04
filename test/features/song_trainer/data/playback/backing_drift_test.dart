import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_command.dart';
import 'package:strumsight/features/song_trainer/data/playback/backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/local_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/playback_capabilities.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';

void main() {
  const capabilities = PlaybackCapabilities(
    canSeek: true,
    canChangeRate: true,
    preservesPitchWhenRateChanges: false,
    positionPrecision: Duration(milliseconds: 17),
    supportedFormats: <String>{'mp3'},
    minimumRate: 0.5,
    maximumRate: 1.5,
  );

  test(
    'production capability records the benchmarked 60 Hz sample precision',
    () {
      expect(
        LocalBackingAudioPlayer
            .defaultLocalPlaybackCapabilities
            .positionPrecision,
        const Duration(milliseconds: 17),
      );
    },
  );

  test('the benchmark-derived policy distinguishes threshold minus epsilon, '
      'threshold, and threshold plus epsilon', () {
    final policy = BackingDriftPolicy.fromCapabilities(capabilities);

    expect(policy.resyncThreshold, const Duration(milliseconds: 51));
    expect(
      policy
          .evaluate(
            masterPosition: const Duration(seconds: 1),
            samplePosition: const Duration(milliseconds: 1050),
          )
          .action,
      BackingDriftAction.tolerate,
    );
    expect(
      policy
          .evaluate(
            masterPosition: const Duration(seconds: 1),
            samplePosition: const Duration(milliseconds: 1051),
          )
          .action,
      BackingDriftAction.resyncAtMeasureBoundary,
    );
    expect(
      policy
          .evaluate(
            masterPosition: const Duration(seconds: 1),
            samplePosition: const Duration(milliseconds: 1052),
          )
          .action,
      BackingDriftAction.hardResync,
    );
  });

  test('a fake position sample is compared against the fake monotonic clock, '
      'then a hard drift resyncs to master time plus grid offset', () async {
    final player = FakeBackingAudioPlayer(capabilities: capabilities);
    final clock = FakeSongTransportClock();
    final transport = SongTransport(player: player, clock: clock);
    addTearDown(transport.dispose);

    await transport.dispatch(
      PrepareSongTransport(
        asset: _asset,
        gridOffset: const Duration(milliseconds: 80),
      ),
    );
    await transport.dispatch(const StartSongTransport());
    clock.advance(const Duration(seconds: 1));
    player.emitPosition(const Duration(milliseconds: 1132));
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.state.lastDriftReport!.action,
      BackingDriftAction.hardResync,
    );
    expect(player.lastSeekPosition, const Duration(milliseconds: 1080));
  });
}

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('drift-backing'),
  sha256: 'e' * 64,
  extension: 'mp3',
  byteLength: 1024,
  mimeType: 'audio/mpeg',
  durationMs: 10000,
);
