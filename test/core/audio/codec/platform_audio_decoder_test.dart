import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/platform_audio_decoder.dart';
import 'package:strumsight/core/audio/method_channel_audio_decoder_bridge.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/input/input_limits.dart';

/// Contract cells for the compressed-audio platform decoder (round K2).
///
/// The Kotlin side cannot run here, so the channel is mocked at the binary
/// messenger: every call still travels through the real `MethodChannel` and the
/// real `StandardMethodCodec`, which is what makes the Uint8List float32 wire
/// shape and the `PlatformException` -> `FailureCode` mapping measurable
/// without a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) handler;

  void answerWith(List<double> samples, {int durationMs = 3000}) {
    handler = (call) async {
      if (call.method == 'probe') return _probeReply(durationMs: durationMs);
      return _decodeReply(samples);
    };
  }

  setUp(() {
    calls = <MethodCall>[];
    handler = (call) async => _probeReply();
    messenger.setMockMethodCallHandler(audioDecoderMethodChannel, (call) async {
      calls.add(call);
      return handler(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(audioDecoderMethodChannel, null);
  });

  group('decodeToPcm', () {
    test('forwards path, target rate and maxSeconds', () async {
      answerWith(<double>[0]);

      await _decoder().decodeToPcm(
        '/sdcard/riff.mp3',
        targetSampleRate: 22050,
        maxSeconds: const Duration(milliseconds: 2500),
      );

      final methods = calls.map((call) => call.method).toList();
      expect(methods, <String>['probe', 'decodeToPcm']);
      expect(calls.first.arguments, containsPair('path', '/sdcard/riff.mp3'));
      expect(calls.last.arguments, <String, Object?>{
        'path': '/sdcard/riff.mp3',
        'targetSampleRate': 22050,
        'maxSeconds': 2.5,
      });
    });

    test('omitted options travel as null', () async {
      answerWith(<double>[0]);

      await _decoder().decodeToPcm('/sdcard/riff.mp3');

      expect(calls.last.arguments, <String, Object?>{
        'path': '/sdcard/riff.mp3',
        'targetSampleRate': null,
        'maxSeconds': null,
      });
    });

    test('the reply becomes a mono Float32List', () async {
      const samples = <double>[0, 0.5, -0.5, 1];
      answerWith(samples);

      final result = await _decoder().decodeToPcm('/sdcard/riff.mp3');

      final decoded = (result as Success<DecodedPcm>).value;
      expect(decoded.samples, isA<Float32List>());
      expect(decoded.frames, 4);
      expect(decoded.channelCount, 1);
      expect(decoded.sampleRate, 44100);
      expect(decoded.samples.toList(), samples);
    });

    test('a frame count the payload contradicts fails', () async {
      handler = (call) async {
        if (call.method == 'probe') return _probeReply();
        return <String, Object?>{
          ..._decodeReply(<double>[0, 1]),
          'frames': 7,
        };
      };

      final result = await _decoder().decodeToPcm('/sdcard/riff.mp3');

      expect(result.failureOrNull?.code, FailureCode.audioDecoderFailed);
    });

    test('every channel code maps to a stable failure code', () async {
      const mapping = <String, String>{
        'no_audio_track': FailureCode.audioNoAudioTrack,
        'unsupported_container': FailureCode.audioUnsupportedContainer,
        'decoder_failed': FailureCode.audioDecoderFailed,
        'file_not_found': FailureCode.audioFileNotFound,
        'too_long': FailureCode.audioClipTooLong,
        'unsupported_platform': FailureCode.audioUnsupportedPlatform,
        'a_code_this_build_has_never_seen': FailureCode.audioDecoderFailed,
      };

      for (final entry in mapping.entries) {
        handler = (call) async {
          if (call.method == 'probe') return _probeReply();
          throw PlatformException(code: entry.key, message: 'boom');
        };

        final result = await _decoder().decodeToPcm('/sdcard/riff.mp3');

        expect(
          result.failureOrNull?.code,
          entry.value,
          reason: 'channel code ${entry.key}',
        );
      }
    });

    test('a probe-side error is mapped too', () async {
      handler = (call) async {
        throw PlatformException(code: 'no_audio_track', message: 'no audio');
      };

      final result = await _decoder().decodeToPcm('/sdcard/clip.mp4');

      expect(result.failureOrNull?.code, FailureCode.audioNoAudioTrack);
      expect(calls.map((call) => call.method), <String>['probe']);
    });
  });

  group('Dart-side guards', () {
    test('a non-Android platform never touches the channel', () async {
      final decoder = _decoder(isSupportedPlatform: false);

      final result = await decoder.decodeToPcm('/sdcard/riff.mp3');

      expect(result.failureOrNull?.code, FailureCode.audioUnsupportedPlatform);
      expect(calls, isEmpty);
    });

    test('probe is refused on a non-Android platform too', () async {
      final decoder = _decoder(isSupportedPlatform: false);

      final result = await decoder.probe('/sdcard/riff.mp3');

      expect(result.failureOrNull?.code, FailureCode.audioUnsupportedPlatform);
      expect(calls, isEmpty);
    });

    test('a missing file never reaches the channel', () async {
      final decoder = _decoder(exists: false);

      final result = await decoder.decodeToPcm('/gone.mp3');

      expect(result.failureOrNull?.code, FailureCode.audioFileNotFound);
      expect(calls, isEmpty);
    });

    test('a file over the byte limit never reaches the channel', () async {
      final oversized = AudioDecoderLimits.maxFileBytes + 1;
      final decoder = _decoder(lengthBytes: oversized);

      final result = await decoder.decodeToPcm('/huge.flac');

      expect(result.failureOrNull?.code, FailureCode.audioFileTooLarge);
      expect(calls, isEmpty);
    });

    test('a probed duration over the limit stops before decoding', () async {
      handler = (call) async => _probeReply(durationMs: 11 * 60 * 1000);

      final result = await _decoder().decodeToPcm('/long.m4a');

      expect(result.failureOrNull?.code, FailureCode.audioClipTooLong);
      expect(calls.map((call) => call.method), <String>['probe']);
    });

    test('maxSeconds caps a long clip instead of rejecting it', () async {
      answerWith(<double>[0.25], durationMs: 60 * 60 * 1000);

      final result = await _decoder().decodeToPcm(
        '/long.m4a',
        maxSeconds: const Duration(seconds: 30),
      );

      expect(result.isSuccess, isTrue);
      expect(calls.last.arguments, containsPair('maxSeconds', 30.0));
    });

    test('an unregistered native side reads as unsupported', () async {
      messenger.setMockMethodCallHandler(audioDecoderMethodChannel, null);

      final result = await _decoder().decodeToPcm('/sdcard/riff.mp3');

      expect(result.failureOrNull?.code, FailureCode.audioUnsupportedPlatform);
    });
  });

  group('probe', () {
    test('decodes the container metadata', () async {
      handler = (call) async => _probeReply(durationMs: 12345);

      final result = await _decoder().probe('/sdcard/riff.mp3');

      final probe = (result as Success<AudioProbe>).value;
      expect(probe.durationMs, 12345);
      expect(probe.sampleRate, 44100);
      expect(probe.channelCount, 2);
      expect(probe.mime, 'audio/mpeg');
      expect(probe.hasKnownDuration, isTrue);
    });

    test('an undeclared duration stays honest', () async {
      handler = (call) async => _probeReply(durationMs: -1);

      final result = await _decoder().probe('/sdcard/stream.ogg');

      final probe = (result as Success<AudioProbe>).value;
      expect(probe.hasKnownDuration, isFalse);
    });

    test('a malformed reply is a decode failure', () async {
      handler = (call) async => <String, Object?>{'durationMs': 'soon'};

      final result = await _decoder().probe('/sdcard/riff.mp3');

      expect(result.failureOrNull?.code, FailureCode.audioDecoderFailed);
    });
  });

  test('the core limits mirror the audio_analysis input limits', () {
    expect(AudioDecoderLimits.maxFileBytes, InputLimits.maxFileBytes);
    expect(AudioDecoderLimits.maxDuration, InputLimits.maxDuration);
  });
}

PlatformAudioDecoder _decoder({
  bool isSupportedPlatform = true,
  bool exists = true,
  int lengthBytes = 4096,
}) => PlatformAudioDecoder(
  bridge: const MethodChannelAudioDecoderBridge(),
  isSupportedPlatform: isSupportedPlatform,
  statReader: (_) => (exists: exists, lengthBytes: lengthBytes),
);

Map<String, Object?> _probeReply({int durationMs = 3000}) => <String, Object?>{
  'durationMs': durationMs,
  'sampleRate': 44100,
  'channelCount': 2,
  'mime': 'audio/mpeg',
};

Map<String, Object?> _decodeReply(List<double> samples) => <String, Object?>{
  'sampleRate': 44100,
  'channelCount': 1,
  'frames': samples.length,
  'pcm': _float32LeBytes(samples),
};

Uint8List _float32LeBytes(List<double> samples) {
  final bytes = Uint8List(samples.length * 4);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    data.setFloat32(i * 4, samples[i], Endian.little);
  }
  return bytes;
}
