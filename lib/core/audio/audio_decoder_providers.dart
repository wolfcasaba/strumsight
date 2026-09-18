import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'codec/platform_audio_decoder.dart';
import 'method_channel_audio_decoder_bridge.dart';

/// The transport used to reach the native decoder. Tests override this with a
/// fake bridge instead of standing up a `MethodChannel`.
final audioDecoderPlatformBridgeProvider = Provider<AudioDecoderPlatformBridge>(
  (_) => const MethodChannelAudioDecoderBridge(),
);

/// THE compressed-audio decoder: an imported MP3/M4A/OGG/FLAC/WAV becomes mono
/// float32 PCM here, entirely on device. Fails with
/// `audio.unsupported_platform` anywhere but Android (round K2).
final platformAudioDecoderProvider = Provider<PlatformAudioDecoder>(
  (ref) => PlatformAudioDecoder(
    bridge: ref.watch(audioDecoderPlatformBridgeProvider),
  ),
);
