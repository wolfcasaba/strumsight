import '../analyze/model/analyze_result.dart';
import '../live/model/chord.dart';
import '../live/model/strum.dart';

/// Pure builders for the shareable artifact (the "Strum Card"). Kept free of
/// Flutter/IO so the viral caption + glyph logic is unit-testable.
///
/// The growth thesis (see docs/rag/chunks/013): StrumSight's one feature no
/// competitor has — seeing DOWN ↓ / UP ↑ strokes — becomes a *shareable* card,
/// so every practice clip is a post that showcases the moat and carries an
/// install link back. The caption is intentionally English-global (hashtags +
/// symbols travel across locales); on-screen labels stay localised.
class ShareContent {
  ShareContent._();

  /// Where a share recipient goes to install. Swap for the Play Store / landing
  /// URL once published; the GitHub Release is the current public install path.
  static const String installUrl =
      'https://github.com/wolfcasaba/strumsight/releases/latest';

  /// Hashtags appended to every share caption (reach levers, kept English).
  /// `#StrumSightChallenge` seeds the UGC flywheel — a branded challenge tag is
  /// the cheapest reach multiplier (docs/rag/chunks/013).
  static const String hashtags =
      '#StrumSightChallenge #guitar #StrumSight #guitarpractice #learnguitar';

  /// The detected strum sequence as arrow glyphs, e.g. "↓ ↑ ↓ ↓ ↑".
  /// Capped at [max]; a trailing "…" marks truncation.
  static String strumGlyphs(AnalyzeResult result, {int max = 16}) {
    if (result.strums.isEmpty) return '';
    final shown = result.strums.take(max).map((s) => s.isDown ? '↓' : '↑');
    final more = result.strums.length > max ? ' …' : '';
    return shown.join(' ') + more;
  }

  /// The chord progression, capo-shifted for display like the rest of the app
  /// (detected − capo = the shape the player frets).
  static String chords(AnalyzeResult result, {int capo = 0}) =>
      Chord.transposeSummary(result.chordSummary, -capo);

  /// The social caption: hero chords + the moat line (↓/↑ counts) + BPM +
  /// attribution + install link + hashtags. Deterministic and locale-stable.
  static String caption(AnalyzeResult result, {int capo = 0}) {
    final prog = chords(result, capo: capo);
    final bpm = result.bpm > 0 ? '${result.bpm.round()} BPM' : null;
    final buf = StringBuffer()
      ..writeln('🎸 ${prog.isEmpty ? 'My riff' : prog}');
    // The headline: down/up strokes — the thing only StrumSight detects.
    final strokes = StringBuffer('↓ ${result.downCount} down · '
        '↑ ${result.upCount} up strokes');
    if (bpm != null) strokes.write(' @ $bpm');
    buf.writeln(strokes.toString());
    buf.writeln();
    buf.writeln('Caught by StrumSight — the only app that sees my '
        'DOWN ↓ / UP ↑ strums. 🎯');
    buf.writeln('Can you match my strum pattern? 👇');
    buf.writeln('Get it: $installUrl');
    buf.write(hashtags);
    return buf.toString();
  }

  /// A suggested share-file name (no spaces), unique-ish by the strum count so
  /// repeated shares don't collide in temp storage.
  static String fileName(AnalyzeResult result) {
    final n = result.strums.length;
    return 'strumsight-card-$n.png';
  }

  /// Caption for a completed-lesson brag card (Learn → share). Leads with the
  /// score + stars, keeps the moat + install link + UGC hashtag.
  static String lessonCaption({
    required String lessonName,
    required double accuracy,
    required int stars,
    required int maxCombo,
  }) {
    final pct = (accuracy * 100).round();
    final starStr = '⭐' * stars + '☆' * (3 - stars);
    final buf = StringBuffer()
      ..writeln('🎸 $lessonName — $pct% $starStr')
      ..writeln('Best combo: $maxCombo · scored on my DOWN ↓ / UP ↑ strums.')
      ..writeln()
      ..writeln('Learn guitar with StrumSight — the only app that grades your '
          'strum direction. 🎯')
      ..writeln('Get it: $installUrl')
      ..write(hashtags);
    return buf.toString();
  }

  /// Share-file name for a lesson score card.
  static String lessonFileName(String lessonId) =>
      'strumsight-score-$lessonId.png';

  /// Caption for the weekly "Strum Wrapped" recap (chunk 017 rec #5).
  static String wrappedCaption({
    required int minutes,
    required int daysPracticed,
    required int strokes,
    required int streak,
    double? averageAccuracy,
  }) {
    final buf = StringBuffer()
      ..writeln('🎸 My strum week: $minutes min · $daysPracticed/7 days · '
          '$strokes strums');
    if (averageAccuracy != null) {
      buf.writeln(
          '↓↑ direction accuracy: ${(averageAccuracy * 100).round()}%');
    }
    if (streak > 0) buf.writeln('🔥 $streak-day streak');
    buf
      ..writeln()
      ..writeln('Tracked by StrumSight — the only app that grades your '
          'strum direction. 🎯')
      ..writeln('Get it: $installUrl')
      ..write(hashtags);
    return buf.toString();
  }

  /// Share-file name for a weekly recap card (unique-ish per epoch day).
  static String wrappedFileName(int today) => 'strumsight-week-$today.png';

  /// Helper for the card's arrow row: the strum directions in order, capped.
  static List<StrumDirection> strumDirections(AnalyzeResult result,
          {int max = 16}) =>
      result.strums.take(max).map((s) => s.direction).toList();
}
