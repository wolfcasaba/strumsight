import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// The one-screen recap shown when a Live session that actually had
/// strums is finished: what happened (strums, distinct chords, time) and
/// one concrete next step — never a silent jump back to the hub.
///
/// Pure presentation: every number is handed in by the caller (the Live
/// screen counts strokes and reads the chord timeline it already owns);
/// this widget opens no resource and reads no provider.
///
/// Pops with `true` when the learner chose the guided course, `false`/null
/// for "Done".
class LiveSummaryDialog extends StatelessWidget {
  const LiveSummaryDialog({
    required this.strums,
    required this.chords,
    required this.seconds,
    super.key,
  });

  /// Distinct strokes counted this session (the streak's own counter).
  final int strums;

  /// Distinct chord labels the timeline confirmed this session.
  final int chords;

  /// Wall-clock seconds between the first strum and Finish.
  final int seconds;

  /// Below this many strokes the recap suggests playing a little longer
  /// rather than pointing at the course — a 3-strum session is not a
  /// signal the detector (or the learner) can build on.
  static const int shortSessionStrums = 8;

  bool get isShortSession => strums < shortSessionStrums;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      key: const ValueKey('live-summary-dialog'),
      title: Text(l10n.liveSummaryTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Stat(
            icon: Icons.graphic_eq,
            label: l10n.liveSummaryStrums(strums),
          ),
          const SizedBox(height: 8),
          _Stat(
            icon: Icons.music_note_outlined,
            label: l10n.liveSummaryChords(chords),
          ),
          const SizedBox(height: 8),
          _Stat(
            icon: Icons.timer_outlined,
            label: l10n.liveSummaryDuration(seconds ~/ 60, seconds % 60),
          ),
          const SizedBox(height: 16),
          Text(
            isShortSession
                ? l10n.liveSummaryTipShort
                : l10n.liveSummaryTipCourse,
            key: const ValueKey('live-summary-tip'),
            style: textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        if (!isShortSession)
          TextButton(
            key: const ValueKey('live-summary-course'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.liveSummaryOpenCourse),
          ),
        FilledButton(
          key: const ValueKey('live-summary-done'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.liveSummaryDone),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
  }
}
