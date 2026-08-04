import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_command.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_state.dart';
import 'package:strumsight/features/song_trainer/application/trainer/transport_effect.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/playback_capabilities.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/services/song_time_map.dart';

void main() {
  late FakeBackingAudioPlayer player;
  late FakeSongTransportClock clock;
  late SongTransport transport;

  setUp(() {
    player = FakeBackingAudioPlayer(
      capabilities: const PlaybackCapabilities(
        canSeek: true,
        canChangeRate: true,
        preservesPitchWhenRateChanges: false,
        positionPrecision: Duration(milliseconds: 17),
        supportedFormats: <String>{'mp3'},
        minimumRate: 0.5,
        maximumRate: 1.5,
      ),
    );
    clock = FakeSongTransportClock();
    transport = SongTransport(player: player, clock: clock);
  });

  tearDown(() => transport.dispose());

  test('transition table accepts every specified direct edge and rejects all '
      'other phase pairs', () {
    const expected = <SongTransportPhase, Set<SongTransportPhase>>{
      SongTransportPhase.idle: <SongTransportPhase>{
        SongTransportPhase.preparing,
      },
      SongTransportPhase.preparing: <SongTransportPhase>{
        SongTransportPhase.ready,
        SongTransportPhase.error,
      },
      SongTransportPhase.ready: <SongTransportPhase>{
        SongTransportPhase.countIn,
        SongTransportPhase.playing,
        SongTransportPhase.stopping,
      },
      SongTransportPhase.countIn: <SongTransportPhase>{
        SongTransportPhase.playing,
        SongTransportPhase.paused,
        SongTransportPhase.stopping,
        SongTransportPhase.error,
      },
      SongTransportPhase.playing: <SongTransportPhase>{
        SongTransportPhase.paused,
        SongTransportPhase.seeking,
        SongTransportPhase.completed,
        SongTransportPhase.stopping,
        SongTransportPhase.error,
      },
      SongTransportPhase.paused: <SongTransportPhase>{
        SongTransportPhase.playing,
        SongTransportPhase.seeking,
        SongTransportPhase.stopping,
      },
      SongTransportPhase.seeking: <SongTransportPhase>{
        SongTransportPhase.playing,
        SongTransportPhase.paused,
        SongTransportPhase.error,
      },
      SongTransportPhase.completed: <SongTransportPhase>{
        SongTransportPhase.ready,
        SongTransportPhase.stopping,
      },
      SongTransportPhase.stopping: <SongTransportPhase>{
        SongTransportPhase.idle,
      },
      SongTransportPhase.error: <SongTransportPhase>{
        SongTransportPhase.preparing,
        SongTransportPhase.idle,
      },
    };

    for (final from in SongTransportPhase.values) {
      for (final to in SongTransportPhase.values) {
        expect(
          SongTransportTransitionTable.allows(from: from, to: to),
          expected[from]!.contains(to),
          reason: '$from -> $to',
        );
      }
    }
  });

  test('prepare, start, pause, seek, restart, finish and stop use a fake '
      'monotonic clock and expose the full phase path', () async {
    final prepared = await transport.dispatch(
      PrepareSongTransport(
        asset: _asset,
        gridOffset: const Duration(milliseconds: 80),
      ),
    );

    expect(prepared.phasePath, <SongTransportPhase>[
      SongTransportPhase.idle,
      SongTransportPhase.preparing,
      SongTransportPhase.ready,
    ]);
    expect(prepared.effects, contains(isA<PrepareBackingAudioEffect>()));

    final started = await transport.dispatch(const StartSongTransport());
    expect(started.phasePath, <SongTransportPhase>[
      SongTransportPhase.ready,
      SongTransportPhase.playing,
    ]);
    expect(player.playCalls, 1);

    clock.advance(const Duration(milliseconds: 250));
    expect(transport.state.activePosition, const Duration(milliseconds: 250));

    await transport.dispatch(const PauseSongTransport());
    expect(transport.state.phase, SongTransportPhase.paused);
    expect(transport.state.activePosition, const Duration(milliseconds: 250));

    final seeked = await transport.dispatch(
      SeekSongTransport(const Duration(seconds: 1)),
    );
    expect(seeked.phasePath, <SongTransportPhase>[
      SongTransportPhase.paused,
      SongTransportPhase.seeking,
      SongTransportPhase.paused,
    ]);
    expect(player.lastSeekPosition, const Duration(milliseconds: 1080));
    expect(transport.state.activePosition, const Duration(seconds: 1));

    await transport.dispatch(const ResumeSongTransport());
    await transport.dispatch(const FinishSongTransport());
    expect(transport.state.phase, SongTransportPhase.completed);

    final restarted = await transport.dispatch(const RestartSongTransport());
    expect(restarted.phasePath, <SongTransportPhase>[
      SongTransportPhase.completed,
      SongTransportPhase.ready,
    ]);
    expect(transport.state.activePosition, Duration.zero);

    await transport.dispatch(const StopSongTransport());
    await transport.dispatch(const StopSongTransport());
    expect(transport.state.phase, SongTransportPhase.idle);
    expect(player.stopCalls, 1);
  });

  test('count-in only starts backing playback when it completes', () async {
    await _prepare(transport);

    await transport.dispatch(const StartSongTransport(withCountIn: true));
    expect(transport.state.phase, SongTransportPhase.countIn);
    expect(player.playCalls, 0);

    await transport.dispatch(const CompleteCountIn());
    expect(transport.state.phase, SongTransportPhase.playing);
    expect(player.playCalls, 1);
  });

  test('only ready and paused phases may change rate; an invalid request '
      'keeps the phase and gives a controlled failure effect', () async {
    await _prepare(transport);
    await transport.dispatch(const StartSongTransport());
    await transport.dispatch(const PauseSongTransport());
    await transport.dispatch(const SetSongTransportSpeed(0.75));
    expect(transport.state.speed, 0.75);
    expect(player.lastRate, 0.75);

    await transport.dispatch(const ResumeSongTransport());
    final invalid = await transport.dispatch(const SetSongTransportSpeed(1.25));

    expect(transport.state.phase, SongTransportPhase.playing);
    expect(transport.state.speed, 0.75);
    expect(
      invalid.effects,
      contains(
        isA<TransportFailureEffect>().having(
          (effect) => effect.code,
          'code',
          SongTransportFailureCode.invalidTransition,
        ),
      ),
    );
  });

  test('a ready-phase speed is retained then applied after backing playback '
      'starts', () async {
    await _prepare(transport);

    await transport.dispatch(const SetSongTransportSpeed(0.75));

    expect(transport.state.speed, 0.75);
    expect(player.lastRate, isNull);

    await transport.dispatch(const StartSongTransport());

    expect(player.lastRate, 0.75);
  });

  test(
    'prepare failure is stable and reaches error without starting playback',
    () async {
      player.failNextPrepare();

      final result = await transport.dispatch(
        PrepareSongTransport(asset: _asset),
      );

      expect(result.phasePath, <SongTransportPhase>[
        SongTransportPhase.idle,
        SongTransportPhase.preparing,
        SongTransportPhase.error,
      ]);
      expect(
        transport.state.lastFailureCode,
        FakeBackingAudioPlayerFailureCode.prepare,
      );
      expect(player.playCalls, 0);
    },
  );

  test('grid offset is applied to a backing position while the master '
      'position itself remains clock-derived', () async {
    await _prepare(transport, gridOffset: const Duration(milliseconds: 120));
    await transport.dispatch(const StartSongTransport());
    clock.advance(const Duration(seconds: 2));

    expect(transport.state.activePosition, const Duration(seconds: 2));
    expect(
      transport.backingPositionFor(const Duration(seconds: 2)),
      const Duration(milliseconds: 2120),
    );
  });

  test('an optional SongTimeMap derives musical position from monotonic '
      'elapsed time without making the map a clock source', () async {
    await transport.dispose();
    player = FakeBackingAudioPlayer();
    clock = FakeSongTransportClock();
    transport = SongTransport(
      player: player,
      clock: clock,
      timeMap: SongTimeMap.fromTempoMap(TempoMap.constant(Tempo(120))),
    );
    await _prepare(transport);
    await transport.dispatch(const StartSongTransport());
    clock.advance(const Duration(seconds: 1));

    expect(transport.state.musicalPosition, BeatPosition.fromBeats(2));
  });
}

Future<void> _prepare(
  SongTransport transport, {
  Duration gridOffset = Duration.zero,
}) async {
  await transport.dispatch(
    PrepareSongTransport(asset: _asset, gridOffset: gridOffset),
  );
}

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('backing-asset'),
  sha256: 'a' * 64,
  extension: 'mp3',
  byteLength: 1024,
  mimeType: 'audio/mpeg',
  durationMs: 10000,
);
