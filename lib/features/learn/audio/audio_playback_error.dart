import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;

/// Which audio output failed. The screen maps this to a localized message —
/// the raw platform error is never shown to the user.
enum AudioOutputSource {
  /// The metronome click (a "running" metronome that makes no sound).
  metronomeClick,

  /// A chord pad / reference tone from the shared backing player.
  chordPad,
}

/// A typed, user-surfaceable audio-output failure (audit H20 / L12).
///
/// Playback stays fire-and-forget — a click must never stall the lesson
/// clock — but it is no longer *silent*: the failure lands here and the
/// consuming screen renders a localized message chosen from [source].
@immutable
class AudioPlaybackError {
  const AudioPlaybackError({required this.source, required this.detail});

  /// Which output produced the failure.
  final AudioOutputSource source;

  /// Developer-facing description of the platform error, for logs only. It
  /// MUST NOT be rendered — the user sees the localized message instead.
  final String detail;

  @override
  String toString() => 'AudioPlaybackError(${source.name}: $detail)';
}

/// True when [error] only means "this platform has no audio backend wired
/// up" — a headless unit/widget test, or a host build without the plugin.
/// Both audio classes are documented as a no-op there, so it stays a no-op
/// instead of accusing the user's device of a fault.
///
/// Anything else (a platform refusal, a decoder error, a denied audio focus)
/// IS a real failure the player must be told about.
bool isAudioBackendAbsent(Object error) {
  if (error is MissingPluginException ||
      error is UnimplementedError ||
      error is UnsupportedError) {
    return true;
  }
  // `audioplayers` wraps platform errors in its own exception type, so the
  // wrapped "no implementation" form is matched on the message too.
  final text = error.toString();
  return text.contains('MissingPluginException') ||
      text.contains('No implementation found');
}
