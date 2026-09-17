// E16-R01/A4 — the playhead moves without a backing track.
//
// MEASURED gap: `SongTransport` computed `activePosition` from its stopwatch
// correctly but only PUBLISHED a state when the backing player emitted a
// position sample. A song with no audio track — every imported or hand-built
// song, since neither path attaches audio — produced zero updates while
// "playing", so the Stage's lanes stood still at 0:00 forever.
//
// Two layers are measured here: the transport's use of a tick source (with a
// hand-driven double, so the assertion is deterministic), and the production
// `Timer.periodic` source itself under `FakeAsync`.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_command.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_state.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_tick_source.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';

void main() {
  late FakeBackingAudioPlayer player;
  late FakeSongTransportClock clock;
  late ManualSongTransportTickSource ticker;
  late SongTransport transport;

  setUp(() {
    player = FakeBackingAudioPlayer();
    clock = FakeSongTransportClock();
    ticker = ManualSongTransportTickSource();
    transport = SongTransport(player: player, clock: clock, tickSource: ticker);
  });

  tearDown(() => transport.dispose());

  test(
    'a song without a backing asset still reaches ready and plays',
    () async {
      await transport.dispatch(const PrepareSongTransport(asset: null));

      expect(transport.state.phase, SongTransportPhase.ready);
      expect(player.playCalls, 0);

      await transport.dispatch(const StartSongTransport());

      expect(transport.state.phase, SongTransportPhase.playing);
      // The silent transport never touches the player.
      expect(player.playCalls, 0);
      expect(ticker.isRunning, isTrue);
      expect(ticker.startedCount, 1);
    },
  );

  test('one second of silent playback publishes a moved playhead', () async {
    final published = <Duration>[];
    final subscription = transport.states.listen(
      (state) => published.add(state.activePosition),
    );
    addTearDown(subscription.cancel);

    await transport.dispatch(const PrepareSongTransport(asset: null));
    await transport.dispatch(const StartSongTransport());

    clock.advance(const Duration(seconds: 1));
    ticker.tick();
    await Future<void>.delayed(Duration.zero);

    expect(published.last, const Duration(seconds: 1));
    expect(transport.state.activePosition, const Duration(seconds: 1));
  });

  test('pausing stops the ticker and freezes the playhead', () async {
    await transport.dispatch(const PrepareSongTransport(asset: null));
    await transport.dispatch(const StartSongTransport());
    clock.advance(const Duration(seconds: 2));
    ticker.tick();

    await transport.dispatch(const PauseSongTransport());

    expect(transport.state.phase, SongTransportPhase.paused);
    expect(ticker.isRunning, isFalse);
    expect(ticker.stoppedCount, 1);
    expect(transport.state.activePosition, const Duration(seconds: 2));

    // A tick that arrives after the stop is inert.
    ticker.tick();
    expect(transport.state.activePosition, const Duration(seconds: 2));
  });

  test('disposing the transport stops the ticker', () async {
    await transport.dispatch(const PrepareSongTransport(asset: null));
    await transport.dispatch(const StartSongTransport());

    await transport.dispose();

    expect(ticker.isRunning, isFalse);
  });

  test('the tempo scale is applied to the silent playhead', () async {
    await transport.dispatch(const PrepareSongTransport(asset: null));
    await transport.dispatch(const SetSongTransportSpeed(0.5));
    await transport.dispatch(const StartSongTransport());

    clock.advance(const Duration(seconds: 4));
    ticker.tick();

    expect(transport.state.activePosition, const Duration(seconds: 2));
  });

  test('a fresh backing sample keeps the playhead, not the ticker', () async {
    final backingPlayer = FakeBackingAudioPlayer();
    final backingClock = FakeSongTransportClock();
    final backingTicker = ManualSongTransportTickSource();
    final backed = SongTransport(
      player: backingPlayer,
      clock: backingClock,
      tickSource: backingTicker,
    );
    addTearDown(backed.dispose);
    await backed.dispatch(PrepareSongTransport(asset: _asset));
    await backed.dispatch(const StartSongTransport());

    backingClock.advance(const Duration(seconds: 1));
    backingPlayer.emitPosition(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(backed.state.activePosition, const Duration(seconds: 1));

    // Within the grace window the tick must not publish its own value.
    final published = <Duration>[];
    final subscription = backed.states.listen(
      (state) => published.add(state.activePosition),
    );
    addTearDown(subscription.cancel);
    backingTicker.tick();
    await Future<void>.delayed(Duration.zero);

    expect(published, isEmpty);
  });

  group('TimerSongTransportTickSource', () {
    test('fires at ~60 Hz and stops on demand', () {
      fakeAsync((async) {
        final source = TimerSongTransportTickSource();
        var ticks = 0;
        source.start(() => ticks++);

        async.elapse(const Duration(milliseconds: 100));
        expect(ticks, 6);

        source.stop();
        async.elapse(const Duration(milliseconds: 100));
        expect(ticks, 6);
        expect(source.isRunning, isFalse);
      });
    });

    test('start is idempotent', () {
      fakeAsync((async) {
        final source = TimerSongTransportTickSource();
        var ticks = 0;
        source.start(() => ticks++);
        source.start(() => ticks++);

        async.elapse(const Duration(milliseconds: 32));
        expect(ticks, 2);
        source.stop();
      });
    });
  });
}

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('backing'),
  sha256: 'a' * 64,
  extension: 'mp3',
  byteLength: 100,
  mimeType: 'audio/mpeg',
  durationMs: 4000,
);
