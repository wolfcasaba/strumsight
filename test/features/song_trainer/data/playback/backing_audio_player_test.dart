import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/playback/backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/local_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/playback/playback_capabilities.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';

void main() {
  test('local adapter rejects an unsupported format before reading or playing '
      'the asset', () async {
    final handle = _FakeLocalPlaybackHandle();
    final adapter = LocalBackingAudioPlayer(
      assetReader: (_) async => AppResult<Uint8List?>.success(Uint8List(1)),
      handle: handle,
      capabilities: _capabilities,
    );
    addTearDown(adapter.dispose);

    final result = await adapter.prepare(_wavAsset);

    expect(result.isFailure, isTrue);
    expect(
      result.failureOrNull!.code,
      BackingAudioPlayerFailureCode.unsupportedFormat,
    );
    expect(handle.setBytesCalls, 0);
  });

  test(
    'local adapter maps a missing asset to a stable prepare failure',
    () async {
      final adapter = LocalBackingAudioPlayer(
        assetReader: (_) async => const AppResult<Uint8List?>.success(null),
        handle: _FakeLocalPlaybackHandle(),
        capabilities: _capabilities,
      );
      addTearDown(adapter.dispose);

      final result = await adapter.prepare(_mp3Asset);

      expect(result.isFailure, isTrue);
      expect(
        result.failureOrNull!.code,
        BackingAudioPlayerFailureCode.missingAsset,
      );
    },
  );

  test(
    'local adapter maps a decoder failure to a stable prepare failure',
    () async {
      final adapter = LocalBackingAudioPlayer(
        assetReader: (_) async => AppResult<Uint8List?>.success(Uint8List(2)),
        handle: _FakeLocalPlaybackHandle(failSetBytes: true),
        capabilities: _capabilities,
      );
      addTearDown(adapter.dispose);

      final result = await adapter.prepare(_mp3Asset);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.code, BackingAudioPlayerFailureCode.prepare);
    },
  );

  test('local adapter forwards bytes and events and remains explicit about '
      'an unsupported rate', () async {
    final handle = _FakeLocalPlaybackHandle();
    final adapter = LocalBackingAudioPlayer(
      assetReader: (_) async => AppResult<Uint8List?>.success(Uint8List(2)),
      handle: handle,
      capabilities: _capabilities,
    );
    addTearDown(adapter.dispose);

    final events = <BackingPlaybackEvent>[];
    final subscription = adapter.events.listen(events.add);
    addTearDown(subscription.cancel);

    expect((await adapter.prepare(_mp3Asset)).isSuccess, isTrue);
    expect((await adapter.play()).isSuccess, isTrue);
    handle.emitPosition(const Duration(milliseconds: 51));
    await Future<void>.delayed(Duration.zero);

    expect(handle.setBytesCalls, 1);
    expect(
      events,
      contains(const BackingPositionEvent(Duration(milliseconds: 51))),
    );

    final rate = await adapter.setRate(1.25);
    expect(rate.isFailure, isTrue);
    expect(
      rate.failureOrNull!.code,
      BackingAudioPlayerFailureCode.unsupportedRate,
    );
  });
}

const PlaybackCapabilities _capabilities = PlaybackCapabilities(
  canSeek: true,
  canChangeRate: false,
  preservesPitchWhenRateChanges: false,
  positionPrecision: Duration(milliseconds: 17),
  supportedFormats: <String>{'mp3'},
);

final SongAssetReference _mp3Asset = SongAssetReference(
  id: SongAssetId('mp3-backing'),
  sha256: 'c' * 64,
  extension: 'mp3',
  byteLength: 2,
  mimeType: 'audio/mpeg',
  durationMs: 1000,
);

final SongAssetReference _wavAsset = SongAssetReference(
  id: SongAssetId('wav-backing'),
  sha256: 'd' * 64,
  extension: 'wav',
  byteLength: 2,
  mimeType: 'audio/wav',
  durationMs: 1000,
);

final class _FakeLocalPlaybackHandle implements LocalPlaybackHandle {
  _FakeLocalPlaybackHandle({this.failSetBytes = false});

  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  final bool failSetBytes;
  int setBytesCalls = 0;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _completions.close();
  }

  void emitPosition(Duration position) => _positions.add(position);

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setBytes(Uint8List bytes, {String? mimeType}) async {
    setBytesCalls++;
    if (failSetBytes) throw StateError('decoder failure');
  }

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}
