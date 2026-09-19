import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/learn/audio/audio_playback_error.dart';
import 'package:strumsight/features/learn/audio/chord_audio.dart';
import 'package:strumsight/features/learn/audio/clip_player.dart';
import 'package:strumsight/features/learn/audio/metronome.dart';

// Audit H20 / L12 — the click and the chord pad used to fail into an empty
// `catch (_) { /* Best-effort. */ }`: the metronome looked like it was
// running, a chord tap looked like it played, and nothing anywhere said
// otherwise. These tests inject a player that REFUSES the clip and prove the
// failure is surfaced as a typed error instead of being swallowed.

/// A player whose every clip is refused, like a device that denies audio
/// focus or cannot decode the buffer.
class _FailingClipPlayer implements ClipPlayer {
  _FailingClipPlayer(this.error);

  final Object error;
  int plays = 0;

  @override
  Future<void> play(Uint8List wav) async {
    plays++;
    throw error;
  }

  @override
  Future<void> dispose() async {}
}

/// A player that accepts every clip (the healthy device).
class _SilentClipPlayer implements ClipPlayer {
  int plays = 0;

  @override
  Future<void> play(Uint8List wav) async {
    plays++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('Metronome', () {
    test('a refused click is surfaced, not swallowed', () async {
      final player = _FailingClipPlayer(StateError('audio focus denied'));
      final metronome = Metronome(playerFactory: () => player);
      addTearDown(metronome.dispose);

      expect(metronome.lastError.value, isNull);
      await metronome.tick(accent: true);
      await pumpEventQueue();

      expect(player.plays, 1);
      final error = metronome.lastError.value;
      expect(error, isNotNull);
      expect(error!.source, AudioOutputSource.metronomeClick);
      expect(error.detail, contains('audio focus denied'));
    });

    test('the surfaced error notifies its listeners', () async {
      final player = _FailingClipPlayer(StateError('no output'));
      final metronome = Metronome(playerFactory: () => player);
      addTearDown(metronome.dispose);
      var notifications = 0;
      metronome.lastError.addListener(() => notifications++);

      await metronome.tick();
      await pumpEventQueue();

      expect(notifications, 1);
    });

    test('a player that cannot even be created is surfaced', () async {
      final metronome = Metronome(
        playerFactory: () => throw StateError('no audio device'),
      );
      addTearDown(metronome.dispose);

      await metronome.tick();
      await pumpEventQueue();

      final error = metronome.lastError.value;
      expect(error?.source, AudioOutputSource.metronomeClick);
    });

    test('a healthy player never raises an error', () async {
      final player = _SilentClipPlayer();
      final metronome = Metronome(playerFactory: () => player);
      addTearDown(metronome.dispose);

      await metronome.tick();
      await metronome.tick(accent: true);
      await pumpEventQueue();

      expect(player.plays, 2);
      expect(metronome.lastError.value, isNull);
    });

    test('an absent platform channel stays a no-op', () async {
      final player = _FailingClipPlayer(MissingPluginException('no impl'));
      final metronome = Metronome(playerFactory: () => player);
      addTearDown(metronome.dispose);

      await metronome.tick();
      await pumpEventQueue();

      expect(metronome.lastError.value, isNull);
    });

    test('clearError drops the surfaced failure', () async {
      final player = _FailingClipPlayer(StateError('boom'));
      final metronome = Metronome(playerFactory: () => player);
      addTearDown(metronome.dispose);

      await metronome.tick();
      await pumpEventQueue();
      expect(metronome.lastError.value, isNotNull);

      metronome.clearError();
      expect(metronome.lastError.value, isNull);
    });
  });

  group('Backing', () {
    test('a refused chord pad is surfaced, not swallowed', () async {
      final player = _FailingClipPlayer(StateError('decoder failed'));
      final backing = Backing(playerFactory: () => player);
      addTearDown(backing.dispose);

      expect(backing.lastError.value, isNull);
      await backing.playChord('C');
      await pumpEventQueue();

      expect(player.plays, 1);
      final error = backing.lastError.value;
      expect(error, isNotNull);
      expect(error!.source, AudioOutputSource.chordPad);
      expect(error.detail, contains('decoder failed'));
    });

    test('a refused reference tone is surfaced too', () async {
      final player = _FailingClipPlayer(StateError('busy'));
      final backing = Backing(playerFactory: () => player);
      addTearDown(backing.dispose);

      await backing.playTone(440);
      await pumpEventQueue();

      expect(backing.lastError.value?.source, AudioOutputSource.chordPad);
    });

    test('an unparseable label never raises an audio error', () async {
      final player = _FailingClipPlayer(StateError('boom'));
      final backing = Backing(playerFactory: () => player);
      addTearDown(backing.dispose);

      await backing.playChord('Zz9');
      await pumpEventQueue();

      expect(player.plays, 0);
      expect(backing.lastError.value, isNull);
    });

    test('a healthy player never raises an error', () async {
      final player = _SilentClipPlayer();
      final backing = Backing(playerFactory: () => player);
      addTearDown(backing.dispose);

      await backing.playChord('Am');
      await pumpEventQueue();

      expect(player.plays, 1);
      expect(backing.lastError.value, isNull);
    });
  });

  group('isAudioBackendAbsent', () {
    test('a missing platform channel counts as absent, not broken', () {
      expect(isAudioBackendAbsent(MissingPluginException('x')), isTrue);
      expect(isAudioBackendAbsent(UnimplementedError('desktop')), isTrue);
      const wrapped = 'wrapped MissingPluginException(play)';
      expect(isAudioBackendAbsent(StateError(wrapped)), isTrue);
    });

    test('a real playback failure is NOT absence', () {
      expect(isAudioBackendAbsent(StateError('audio focus denied')), isFalse);
      final platform = PlatformException(code: 'AudioError', message: 'busy');
      expect(isAudioBackendAbsent(platform), isFalse);
    });
  });
}
