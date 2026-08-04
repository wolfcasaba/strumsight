// Windowed chord lane.
//
// Brief §5.1: "Lane csak viewport+buffer window; teljes dal widgetlistája
// TILOS." The lane computes the visible window from the configured viewport
// width and the active playhead position, then renders only that slice. The
// backing event list is never expanded into a full widget tree.

import 'package:flutter/material.dart';

import '../../domain/models/song_event.dart';

/// Windowed, accessible chord lane. Renders only the chord symbols that fall
/// inside the current viewport window — the backing list may contain
/// thousands of events.
final class ChordLane extends StatelessWidget {
  const ChordLane({
    super.key,
    required this.events,
    required this.viewportStart,
    required this.viewportEnd,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  final List<SongChordEvent> events;
  final Duration viewportStart;
  final Duration viewportEnd;
  final EdgeInsets padding;

  /// Number of events the lane actually widgetizes for the current window.
  int get visibleCount {
    var count = 0;
    for (final event in events) {
      final eventEnd = event.start + event.duration;
      if (event.start >= viewportEnd || eventEnd <= viewportStart) continue;
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
    final visible = <_WindowedChord>[];
    for (final event in events) {
      final eventEnd = event.start + event.duration;
      if (event.start >= viewportEnd || eventEnd <= viewportStart) continue;
      final localStart = event.start < viewportStart
          ? Duration.zero
          : event.start - viewportStart;
      final localEnd = eventEnd > viewportEnd
          ? totalDuration
          : eventEnd - viewportStart;
      visible.add(
        _WindowedChord(
          label: event.symbol.label,
          start: localStart,
          end: localEnd,
        ),
      );
    }
    return Padding(
      padding: padding,
      child: SizedBox(
        key: const Key('song-trainer-chord-lane'),
        height: 36,
        child: Row(
          children: <Widget>[
            for (final chord in visible)
              Expanded(
                flex: (chord.end - chord.start).inMicroseconds,
                child: Semantics(
                  label: chord.label,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primary,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Center(
                      child: Text(
                        chord.label,
                        style: TextStyle(color: colors.onPrimary),
                      ),
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

final class _WindowedChord {
  const _WindowedChord({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final Duration start;
  final Duration end;
}
