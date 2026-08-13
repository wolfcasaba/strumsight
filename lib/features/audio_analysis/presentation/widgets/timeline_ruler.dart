import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../controllers/timeline_viewport.dart';
import 'labels_adapter.dart';

final class TimelineRulerLabels {
  const TimelineRulerLabels({required this.interval, required this.positions});
  final Duration interval;
  final List<Duration> positions;
}

/// A compact ruler whose labels are derived from the visible window, rather
/// than a fixed grid density that would overlap on long recordings.
final class TimelineRuler extends StatelessWidget {
  const TimelineRuler({required this.viewport, super.key});
  final TimelineViewport viewport;

  static TimelineRulerLabels labelsFor(TimelineViewport viewport) {
    final target = viewport.visibleDuration.inMilliseconds / 5;
    const candidates = <int>[
      100,
      250,
      500,
      1000,
      2000,
      5000,
      10000,
      30000,
      60000,
    ];
    final milliseconds = candidates.firstWhere(
      (value) => value >= target,
      orElse: () => candidates.last,
    );
    final first =
        (viewport.start.inMilliseconds ~/ milliseconds) * milliseconds;
    final positions = <Duration>[];
    for (
      var value = first;
      value <= viewport.end.inMilliseconds;
      value += milliseconds
    ) {
      if (value >= viewport.start.inMilliseconds) {
        positions.add(Duration(milliseconds: value));
      }
    }
    return TimelineRulerLabels(
      interval: Duration(milliseconds: milliseconds),
      positions: positions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = labelsFor(viewport);
    return SizedBox(
      height: 28,
      child: Stack(
        children: <Widget>[
          for (final time in labels.positions)
            Positioned(
              left: viewport.pixelForTime(time),
              child: Text(
                AppLocalizationsOverviewLabels(
                  AppLocalizations.of(context),
                ).formatDuration(time),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}
