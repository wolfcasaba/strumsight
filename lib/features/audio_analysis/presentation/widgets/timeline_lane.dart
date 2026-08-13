import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../controllers/timeline_viewport.dart';

enum TimelineLaneKind {
  waveform,
  chord,
  beatBar,
  onset,
  timing,
  dynamics,
  pitch,
  hotspot,
}

final class TimelineLaneItem {
  const TimelineLaneItem({required this.start, this.end, this.label});
  factory TimelineLaneItem.point(Duration time, {String? label}) =>
      TimelineLaneItem(start: time, label: label);
  final Duration start;
  final Duration? end;
  final String? label;
  Duration get finish => end ?? start;
}

/// Canvas-based lane. Only items in one visible-window's worth of buffer are
/// forwarded to the painter, so event count cannot grow the widget tree.
final class TimelineLane extends StatelessWidget {
  const TimelineLane({
    required this.kind,
    required this.title,
    required this.summary,
    required this.viewport,
    required this.items,
    this.degraded = false,
    super.key,
  });
  final TimelineLaneKind kind;
  final String title;
  final String summary;
  final TimelineViewport viewport;
  final List<TimelineLaneItem> items;
  final bool degraded;

  /// Returns only the evidence that can affect the painted viewport: its
  /// visible range plus a half-window buffer on each side (one extra window
  /// total). This makes the virtualisation bound directly unit-testable.
  static List<TimelineLaneItem> visibleItemsFor(
    List<TimelineLaneItem> items,
    TimelineViewport viewport,
  ) {
    final buffer = viewport.visibleDuration ~/ 2;
    final windowStart = viewport.start - buffer;
    final windowEnd = viewport.end + buffer;
    return items
        .where((item) => item.finish > windowStart && item.start < windowEnd)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visible = visibleItemsFor(items, viewport);
    return Semantics(
      container: true,
      label:
          '$title: $summary${degraded ? '. ${AppLocalizations.of(context).analysisTimelineLimitedConfidence}' : ''}',
      child: Card(
        key: Key('timeline-lane-${kind.name}'),
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (degraded)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        AppLocalizations.of(
                          context,
                        ).analysisTimelineLimitedConfidence,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 42,
                width: double.infinity,
                child: CustomPaint(painter: _LanePainter(viewport, visible)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _LanePainter extends CustomPainter {
  const _LanePainter(this.viewport, this.items);
  final TimelineViewport viewport;
  final List<TimelineLaneItem> items;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff4876ff)
      ..strokeWidth = 2;
    for (final item in items) {
      final x =
          viewport.pixelForTime(item.start) /
          viewport.logicalWidth *
          size.width;
      final endX =
          viewport.pixelForTime(item.finish) /
          viewport.logicalWidth *
          size.width;
      canvas.drawLine(
        Offset(x, 4),
        Offset(endX == x ? x : endX, size.height - 4),
        paint,
      );
      if (endX == x) canvas.drawCircle(Offset(x, size.height / 2), 2, paint);
    }
  }

  @override
  bool shouldRepaint(_LanePainter oldDelegate) =>
      oldDelegate.viewport != viewport || oldDelegate.items != items;
}
