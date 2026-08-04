// Windowed strum-direction lane.
//
// Brief §5.1: lane only renders the viewport+buffer window. Each visible
// event exposes an `arrow_upward` / `arrow_downward` icon — the lane never
// relies on colour alone.

import 'package:flutter/material.dart';

import '../../../../core/music/strum.dart';
import '../../domain/models/song_event.dart';

/// Windowed strum-direction lane. Renders only the strokes that fall inside
/// the current viewport window. Each stroke is labelled with an icon and
/// the screen-reader text in addition to any colour cue.
final class StrumLane extends StatelessWidget {
  const StrumLane({
    super.key,
    required this.events,
    required this.viewportStart,
    required this.viewportEnd,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  final List<SongStrumEvent> events;
  final Duration viewportStart;
  final Duration viewportEnd;
  final EdgeInsets padding;

  int get visibleCount {
    var count = 0;
    for (final event in events) {
      if (event.at >= viewportEnd || event.at < viewportStart) continue;
      count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final totalDuration = viewportEnd <= viewportStart
        ? Duration.zero
        : viewportEnd - viewportStart;
    final visible = <_WindowedStroke>[];
    for (final event in events) {
      if (event.at >= viewportEnd || event.at < viewportStart) continue;
      final clamped = event.at < viewportStart
          ? Duration.zero
          : (event.at > viewportEnd ? totalDuration : event.at - viewportStart);
      visible.add(_WindowedStroke(direction: event.direction, at: clamped));
    }
    return Padding(
      padding: padding,
      child: SizedBox(
        key: const Key('song-trainer-strum-lane'),
        height: 36,
        child: Row(
          children: <Widget>[
            for (final stroke in visible)
              Expanded(
                flex: stroke.at.inMicroseconds == 0
                    ? 1
                    : stroke.at.inMicroseconds,
                child: Semantics(
                  label: stroke.direction == StrumDirection.down
                      ? 'down'
                      : 'up',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Icon(
                      stroke.direction == StrumDirection.down
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      color: colors.onSurface,
                      size: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _WindowedStroke {
  const _WindowedStroke({required this.direction, required this.at});

  final StrumDirection? direction;
  final Duration at;
}
