// Windowed tablature lane.
//
// Brief §5.1: lane only renders the viewport+buffer window. Each visible
// note exposes a string/fret label and a screen-reader semantic in addition
// to its colour.

import 'package:flutter/material.dart';

import '../../domain/models/song_event.dart';

/// Windowed tablature lane. Renders only the notes that fall inside the
/// current viewport window. Each note shows the (string, fret) pair as
/// text alongside the colour cue.
final class TablatureLane extends StatelessWidget {
  const TablatureLane({
    super.key,
    required this.events,
    required this.viewportStart,
    required this.viewportEnd,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  final List<SongNoteEvent> events;
  final Duration viewportStart;
  final Duration viewportEnd;
  final EdgeInsets padding;

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
    final visible = <_WindowedTab>[];
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
        _WindowedTab(
          stringIndex: event.stringIndex,
          fret: event.fret,
          start: localStart,
          end: localEnd,
        ),
      );
    }
    return Padding(
      padding: padding,
      child: SizedBox(
        key: const Key('song-trainer-tablature-lane'),
        height: 36,
        child: Row(
          children: <Widget>[
            for (final tab in visible)
              Expanded(
                flex: (tab.end - tab.start).inMicroseconds,
                child: Semantics(
                  label: tab.semanticLabel,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.tertiary,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Center(
                      child: Text(
                        tab.semanticLabel,
                        style: TextStyle(color: colors.onTertiary),
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

final class _WindowedTab {
  const _WindowedTab({
    required this.stringIndex,
    required this.fret,
    required this.start,
    required this.end,
  });

  final int? stringIndex;
  final int? fret;
  final Duration start;
  final Duration end;

  String get semanticLabel {
    if (stringIndex == null || fret == null) return 'note';
    return 'string ${stringIndex! + 1} fret ${fret!}';
  }
}
