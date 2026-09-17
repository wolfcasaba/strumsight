/// K1 — "audio file as a backing track" capability matrix.
///
/// The editor may attach exactly what the player can prepare. This cell
/// walks all seven attachable containers plus one rejected outsider
/// (`txt`) across BOTH playback implementations: the real
/// [LocalBackingAudioPlayer] capability object and its
/// [FakeBackingAudioPlayer] mirror. Reverting `supportedFormats` to
/// `{mp3, wav}` turns the `m4a` / `mp4` / `aac` / `ogg` / `flac` rows red
/// here first.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';
import 'package:strumsight/features/song_trainer/data/playback/backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/local_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/playback_capabilities.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';

void main() {
  test('the attachable set and the playable set are the same set', () {
    expect(
      PlatformFilePickerAdapter.supportedAudioExtensions.toSet(),
      supportedBackingAudioFormats,
    );
    const real = LocalBackingAudioPlayer.defaultLocalPlaybackCapabilities;
    expect(real.supportedFormats, supportedBackingAudioFormats);
    final fake = FakeBackingAudioPlayer();
    addTearDown(fake.dispose);
    expect(fake.capabilities.supportedFormats, supportedBackingAudioFormats);
  });

  for (final extension in <String>[
    'mp3',
    'm4a',
    'mp4',
    'aac',
    'ogg',
    'flac',
    'wav',
  ]) {
    test('real player prepares a .$extension backing asset', () async {
      final handle = _RecordingHandle();
      final player = LocalBackingAudioPlayer(
        assetReader: (_) async =>
            AppResult<Uint8List?>.success(Uint8List.fromList(<int>[1, 2])),
        handle: handle,
      );
      addTearDown(player.dispose);

      final result = await player.prepare(_asset(extension));

      expect(result.isSuccess, isTrue, reason: extension);
      expect(handle.setBytesCalls, 1, reason: extension);
      expect(handle.lastMimeType, isNotNull, reason: extension);
    });

    test('fake player prepares a .$extension backing asset', () async {
      final player = FakeBackingAudioPlayer();
      addTearDown(player.dispose);

      final result = await player.prepare(_asset(extension));

      expect(result.isSuccess, isTrue, reason: extension);
    });
  }

  test('both players reject a non-audio container before any read', () async {
    final handle = _RecordingHandle();
    var reads = 0;
    final player = LocalBackingAudioPlayer(
      assetReader: (_) async {
        reads++;
        return AppResult<Uint8List?>.success(Uint8List.fromList(<int>[1]));
      },
      handle: handle,
    );
    addTearDown(player.dispose);
    final fake = FakeBackingAudioPlayer();
    addTearDown(fake.dispose);

    final real = await player.prepare(_asset('txt'));
    final mirrored = await fake.prepare(_asset('txt'));

    expect(
      real.failureOrNull?.code,
      BackingAudioPlayerFailureCode.unsupportedFormat,
    );
    expect(
      mirrored.failureOrNull?.code,
      BackingAudioPlayerFailureCode.unsupportedFormat,
    );
    expect(reads, 0);
    expect(handle.setBytesCalls, 0);
  });
}

SongAssetReference _asset(String extension) => SongAssetReference(
  id: SongAssetId('backing-$extension'),
  sha256: 'a' * 64,
  extension: extension,
  byteLength: 2,
  mimeType: PlatformFilePickerAdapter.mimeTypesByExtension[extension],
);

final class _RecordingHandle implements LocalPlaybackHandle {
  var setBytesCalls = 0;
  String? lastMimeType;

  @override
  Stream<void> get completions => const Stream<void>.empty();

  @override
  Stream<Duration> get positions => const Stream<Duration>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setBytes(Uint8List bytes, {String? mimeType}) async {
    setBytesCalls++;
    lastMimeType = mimeType;
  }

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}
