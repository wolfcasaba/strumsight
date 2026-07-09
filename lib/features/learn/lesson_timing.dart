import 'model/lesson.dart';

/// Pure timing maths for the play-along highway. No clocks/tickers here so the
/// beat→pixel mapping and count-in are exhaustively testable; the screen feeds
/// in elapsed seconds from its ticker.
class LessonTiming {
  LessonTiming._();

  /// Musical beats elapsed for [elapsedSec] at [bpm].
  static double beatForElapsed(double elapsedSec, double bpm) =>
      elapsedSec * bpm / 60.0;

  /// The playhead in beats: negative during the [countInBeats] count-in, 0 when
  /// the first event should reach the strike line, then advancing with the music.
  static double playhead(double elapsedSec, double bpm, int countInBeats) =>
      beatForElapsed(elapsedSec, bpm) - countInBeats;

  /// Horizontal position of an event given the current [playheadBeat]. Events
  /// ahead of the playhead sit to the right of the strike line and flow left
  /// toward it as time advances; it lands on [strikeX] when its beat == playhead.
  static double xForEvent(
    double eventBeat,
    double playheadBeat,
    double pxPerBeat,
    double strikeX,
  ) =>
      strikeX + (eventBeat - playheadBeat) * pxPerBeat;

  /// During the count-in (playhead < 0) the number to flash, 1..countInBeats;
  /// null once the lesson has started.
  static int? countInNumber(double playheadBeat, int countInBeats) {
    if (playheadBeat >= 0) return null;
    final n = playheadBeat.floor() + countInBeats + 1;
    return n.clamp(1, countInBeats);
  }

  /// Whether the lesson (plus a one-bar ring-out) has finished.
  static bool isFinished(
    double playheadBeat,
    double totalBeats,
    int beatsPerBar,
  ) =>
      playheadBeat >= totalBeats + beatsPerBar;

  /// The events whose position is currently within the visible lane, so the
  /// widget only lays out what's on screen.
  static List<LessonEvent> visibleEvents(
    List<LessonEvent> events,
    double playheadBeat, {
    double aheadBeats = 8,
    double behindBeats = 2,
  }) =>
      [
        for (final e in events)
          if (e.beat >= playheadBeat - behindBeats &&
              e.beat <= playheadBeat + aheadBeats)
            e,
      ];
}
