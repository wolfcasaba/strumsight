import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../audio/audio_playback_error.dart';

/// Finder handle for the surfaced audio-output message.
const Key audioOutputErrorKey = Key('audio-output-error');

/// A quiet inline notice that the device refused to play a sound.
///
/// Audit H20 / L12: the metronome could look like it was running while
/// producing no sound at all, and a chord tap could stay mute, with nothing
/// anywhere saying why. The audio components now publish a typed
/// [AudioPlaybackError]; this widget is the visible, localized end of that
/// chain. It renders nothing while every watched output is healthy, so a
/// working screen is unchanged.
class AudioOutputErrorNotice extends StatefulWidget {
  const AudioOutputErrorNotice({required this.sources, super.key});

  /// The audio components to watch (`Metronome.lastError`,
  /// `Backing.lastError`). The first non-null error is the one shown.
  final List<ValueListenable<AudioPlaybackError?>> sources;

  @override
  State<AudioOutputErrorNotice> createState() => _AudioErrorNoticeState();
}

class _AudioErrorNoticeState extends State<AudioOutputErrorNotice> {
  @override
  void initState() {
    super.initState();
    _subscribe(widget.sources);
  }

  @override
  void didUpdateWidget(AudioOutputErrorNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(oldWidget.sources, widget.sources)) return;
    _unsubscribe(oldWidget.sources);
    _subscribe(widget.sources);
  }

  @override
  void dispose() {
    _unsubscribe(widget.sources);
    super.dispose();
  }

  void _subscribe(List<ValueListenable<AudioPlaybackError?>> sources) {
    for (final source in sources) {
      source.addListener(_onErrorChanged);
    }
  }

  void _unsubscribe(List<ValueListenable<AudioPlaybackError?>> sources) {
    for (final source in sources) {
      // Safe after the notifier itself was disposed (ChangeNotifier allows
      // removeListener on a disposed instance).
      source.removeListener(_onErrorChanged);
    }
  }

  void _onErrorChanged() {
    if (mounted) setState(() {});
  }

  AudioPlaybackError? get _error {
    for (final source in widget.sources) {
      final error = source.value;
      if (error != null) return error;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    // The platform error text is never rendered — only this localized line.
    final message = switch (error.source) {
      AudioOutputSource.metronomeClick => l10n.audioOutputMetronomeFailed,
      AudioOutputSource.chordPad => l10n.audioOutputChordFailed,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.volume_off_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              key: audioOutputErrorKey,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
