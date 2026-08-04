// Non-blocking loop feedback banner.
//
// The feedback widget is intentionally non-blocking: the loop verdict
// streams into it as the trail resolves, but the user can always keep
// playing. The screen-reader live region is throttled to one update per
// second; the visible colour cue is paired with an icon and text.

import 'package:flutter/material.dart';

/// One brief verdict that pops into the loop feedback region.
final class SongLoopFeedbackMessage {
  const SongLoopFeedbackMessage({
    required this.headline,
    required this.detail,
    required this.outcome,
    required this.announcedAt,
  });

  final String headline;
  final String detail;
  final SongLoopFeedbackOutcome outcome;
  final DateTime announcedAt;
}

enum SongLoopFeedbackOutcome { pass, retry, neutral }

/// Throttled, non-blocking feedback. The screen-reader live region reads only
/// the most recent message; if less than [minimumAnnounceGap] has passed
/// since the last one, the new message is queued.
final class SongLoopFeedback extends StatefulWidget {
  const SongLoopFeedback({
    super.key,
    required this.messages,
    this.minimumAnnounceGap = const Duration(milliseconds: 1000),
  });

  final List<SongLoopFeedbackMessage> messages;
  final Duration minimumAnnounceGap;

  @override
  State<SongLoopFeedback> createState() => _SongLoopFeedbackState();
}

class _SongLoopFeedbackState extends State<SongLoopFeedback> {
  SongLoopFeedbackMessage? _displayed;

  @override
  void initState() {
    super.initState();
    _displayed = widget.messages.isEmpty ? null : widget.messages.last;
  }

  @override
  void didUpdateWidget(SongLoopFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.isEmpty) {
      setState(() => _displayed = null);
      return;
    }
    final latest = widget.messages.last;
    final current = _displayed;
    if (current == null ||
        latest.announcedAt.difference(current.announcedAt) >=
            widget.minimumAnnounceGap) {
      setState(() => _displayed = latest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _displayed;
    if (displayed == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final tone = switch (displayed.outcome) {
      SongLoopFeedbackOutcome.pass => colors.primary,
      SongLoopFeedbackOutcome.retry => colors.error,
      SongLoopFeedbackOutcome.neutral => colors.surfaceContainerHighest,
    };
    final icon = switch (displayed.outcome) {
      SongLoopFeedbackOutcome.pass => Icons.check,
      SongLoopFeedbackOutcome.retry => Icons.replay,
      SongLoopFeedbackOutcome.neutral => Icons.info_outline,
    };
    return Semantics(
      liveRegion: true,
      label: '${displayed.headline}. ${displayed.detail}',
      child: Container(
        key: const Key('song-trainer-loop-feedback'),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: tone,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: colors.onSurface),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    displayed.headline,
                    style: TextStyle(color: colors.onSurface),
                  ),
                  Text(
                    displayed.detail,
                    style: TextStyle(color: colors.onSurface),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
