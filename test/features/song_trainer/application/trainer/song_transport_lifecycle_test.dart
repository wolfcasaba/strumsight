import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/platform/app_lifecycle.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_command.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_state.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';

void main() {
  late FakeBackingAudioPlayer player;
  late FakeAppLifecycleEvents lifecycle;
  late SongTransport transport;

  setUp(() {
    player = FakeBackingAudioPlayer();
    lifecycle = FakeAppLifecycleEvents();
    transport = SongTransport(
      player: player,
      clock: FakeSongTransportClock(),
      lifecycleEvents: lifecycle,
    );
  });

  tearDown(() => transport.dispose());

  test(
    'backgrounding pauses safely and foregrounding never resumes loudly',
    () async {
      await _start(transport);

      lifecycle.emit(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      expect(transport.state.phase, SongTransportPhase.paused);
      expect(
        transport.state.interruptionReason,
        SongTransportInterruptionReason.appBackground,
      );
      expect(player.pauseCalls, 1);

      lifecycle.emit(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(transport.state.phase, SongTransportPhase.paused);
      expect(player.playCalls, 1);
    },
  );

  test('route and audio interruptions move playback to paused without a '
      'microphone lease', () async {
    await _start(transport);

    await transport.handleInterruption(
      SongTransportInterruptionReason.audioRouteChanged,
    );

    expect(transport.state.phase, SongTransportPhase.paused);
    expect(
      transport.state.interruptionReason,
      SongTransportInterruptionReason.audioRouteChanged,
    );
    expect(player.pauseCalls, 1);
    expect(player.microphoneLeaseRequests, 0);
  });

  test('dispose closes player and event subscription so a late position event '
      'cannot mutate the state', () async {
    await _start(transport);
    final stateBeforeDispose = transport.state;

    await transport.dispose();
    player.emitPosition(const Duration(seconds: 9));
    await Future<void>.delayed(Duration.zero);

    expect(player.disposeCalls, 1);
    expect(transport.state, stateBeforeDispose);
  });
}

Future<void> _start(SongTransport transport) async {
  await transport.dispatch(PrepareSongTransport(asset: _asset));
  await transport.dispatch(const StartSongTransport());
}

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('lifecycle-backing'),
  sha256: 'b' * 64,
  extension: 'mp3',
  byteLength: 1024,
  mimeType: 'audio/mpeg',
  durationMs: 10000,
);

final class FakeAppLifecycleEvents implements AppLifecycleEvents {
  final List<void Function(AppLifecycleState)> _listeners =
      <void Function(AppLifecycleState)>[];

  @override
  void addListener(void Function(AppLifecycleState state) listener) {
    _listeners.add(listener);
  }

  @override
  void dispose() => _listeners.clear();

  void emit(AppLifecycleState state) {
    for (final listener in List<void Function(AppLifecycleState)>.of(
      _listeners,
    )) {
      listener(state);
    }
  }

  @override
  void removeListener(void Function(AppLifecycleState state) listener) {
    _listeners.remove(listener);
  }
}
