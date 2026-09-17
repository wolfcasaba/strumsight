import 'package:flutter/services.dart';

import 'codec/platform_audio_decoder.dart';

/// The one channel the Android decoder answers on.
///
/// Kotlin side: `AudioDecoderChannel.kt` under
/// `android/app/src/main/kotlin/com/wolfcasaba/strumsight/audio/`, registered
/// from `MainActivity.configureFlutterEngine`.
const MethodChannel audioDecoderMethodChannel = MethodChannel(
  'strumsight/audio_decoder',
);

/// Carries [PlatformAudioDecoder]'s calls over a [MethodChannel] and turns the
/// transport's exceptions into the Flutter-free [AudioDecoderPlatformError].
///
/// A [MissingPluginException] means no native side is registered — iOS, web,
/// desktop, or an Android build without the channel — so it surfaces as
/// `unsupported_platform` rather than a decode failure.
final class MethodChannelAudioDecoderBridge
    implements AudioDecoderPlatformBridge {
  const MethodChannelAudioDecoderBridge({
    MethodChannel channel = audioDecoderMethodChannel,
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AudioDecoderPlatformError(
          code: 'unsupported_platform',
          message: error.message,
        ),
        stackTrace,
      );
    } on PlatformException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AudioDecoderPlatformError(code: error.code, message: error.message),
        stackTrace,
      );
    }
  }
}
