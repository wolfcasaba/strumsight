import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/progress/model/practice_entry.dart';
import 'package:strumsight/features/share/model/weekly_recap.dart';
import 'package:strumsight/features/share/share_content.dart';
import 'package:strumsight/features/share/widgets/wrapped_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

/// Round 151 — "Strum Wrapped" weekly recap (chunk 017 rec #5: the
/// Wrapped-style recap is the category's strongest install hook).
PracticeEntry _e(int day, int seconds, {int strokes = 0, double? accuracy}) =>
    PracticeEntry(
      day: day,
      source: PracticeSource.learn,
      seconds: seconds,
      strokes: strokes,
      directionAccuracy: accuracy,
    );

/// MI-H (E09, R-handoff) — pump the recap card under a localized MaterialApp
/// so `AppLocalizations.of(context)` resolves the `shareCard*` keys added to
/// `community_{en,hu}.arb`. The original tests pumped under a bare
/// `MaterialApp` and asserted on English literals directly.
Future<void> _pumpWrapped(
  WidgetTester tester, {
  required WeeklyRecap recap,
  required String weekLabel,
  Locale locale = const Locale('en'),
}) => tester.pumpWidget(
  MaterialApp(
    theme: SsLightTheme.data(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: WrappedCard(recap: recap, weekLabel: weekLabel),
      ),
    ),
  ),
);

void main() {
  group('WeeklyRecap.fromEntries', () {
    test('rolls up exactly the trailing 7 days', () {
      final recap = WeeklyRecap.fromEntries(
        [
          _e(93, 600), // 8 days ago — outside the window
          _e(94, 300, strokes: 40), // exactly 6 days back — inside
          _e(98, 240, strokes: 30, accuracy: 0.8),
          _e(100, 60, strokes: 10, accuracy: 0.6), // today
          _e(100, 120, strokes: 20),
        ],
        today: 100,
        streak: 4,
      );

      expect(recap.minutes, 12); // (300+240+60+120)/60
      expect(recap.sessions, 4);
      expect(recap.strokes, 100);
      expect(recap.daysPracticed, 3);
      expect(recap.bestDay, 94, reason: '300 s is the biggest single day');
      expect(recap.averageAccuracy, closeTo(0.7, 1e-9));
      expect(recap.streak, 4);
      expect(recap.isEmpty, isFalse);
    });

    test('a sub-minute week still reads 1 minute, never a braggy zero', () {
      final recap = WeeklyRecap.fromEntries([
        _e(100, 27, strokes: 8),
      ], today: 100);
      expect(recap.minutes, 1, reason: 'the 27-second first win is not "0"');
    });

    test('an empty week reports empty with null accuracy/bestDay', () {
      final recap = WeeklyRecap.fromEntries([_e(50, 600)], today: 100);
      expect(recap.isEmpty, isTrue);
      expect(recap.averageAccuracy, isNull);
      expect(recap.bestDay, isNull);
      expect(recap.minutes, 0);
    });
  });

  test('the caption carries the stats, moat and install link', () {
    final caption = ShareContent.wrappedCaption(
      minutes: 42,
      daysPracticed: 5,
      strokes: 980,
      streak: 6,
      averageAccuracy: 0.87,
    );
    expect(caption, contains('42 min'));
    expect(caption, contains('5/7 days'));
    expect(caption, contains('87%'));
    expect(caption, contains('6-day streak'));
    expect(caption, contains(ShareContent.installUrl));
    expect(caption, contains('#StrumSightChallenge'));
  });

  testWidgets('the card survives heavy-user numbers without overflow (r160)', (
    tester,
  ) async {
    const recap = WeeklyRecap(
      minutes: 2100, // 5 h/day for a week — the realistic ceiling
      sessions: 99,
      strokes: 25000,
      daysPracticed: 7,
      bestDay: 100,
      averageAccuracy: 1.0,
      streak: 365,
    );
    await _pumpWrapped(tester, recap: recap, weekLabel: 'Jul 6 – Jul 12');
    // Overflow paints throw in tests — reaching here green IS the assert.
    expect(find.text('2100'), findsOneWidget);
    expect(find.text('25000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card renders the recap values', (tester) async {
    const recap = WeeklyRecap(
      minutes: 42,
      sessions: 9,
      strokes: 980,
      daysPracticed: 5,
      bestDay: 100,
      averageAccuracy: 0.87,
      streak: 6,
    );
    await _pumpWrapped(tester, recap: recap, weekLabel: 'Jul 6 – Jul 12');
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text('42'), findsOneWidget);
    expect(find.text('5/7'), findsOneWidget);
    expect(find.text('980'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    // Streak line now resolves through l10n (MI-H) — the placeholder ICU
    // pattern produces `6-day streak` for `en` and `6 napos sorozat` for `hu`.
    // The 🔥 is a GLYPH, not copy, so it stays outside the ARB value and in
    // front of it on the card (2026-09-19 integration: the `main` card's
    // pixel-pinned layout keeps the emoji).
    expect(
      find.text('🔥 ${l10n.shareCardWrappedStreakLine(6)}'),
      findsOneWidget,
    );
    expect(find.text('Jul 6 – Jul 12'), findsOneWidget);
  });

  // MI-H — en and hu both render through `AppLocalizations.of(context)` and
  // the rendered streak text must differ between locales (regression guard
  // for the parity rule in `test/l10n/arb_parity_test.dart`).
  for (final locale in [const Locale('en'), const Locale('hu')]) {
    testWidgets('MI-H: WrappedCard streak line resolves through l10n '
        '(${locale.languageCode})', (tester) async {
      const recap = WeeklyRecap(
        minutes: 42,
        sessions: 9,
        strokes: 980,
        daysPracticed: 5,
        bestDay: 100,
        averageAccuracy: 0.87,
        streak: 6,
      );
      await _pumpWrapped(
        tester,
        recap: recap,
        weekLabel: 'Jul 6 – Jul 12',
        locale: locale,
      );
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(
        find.text('🔥 ${l10n.shareCardWrappedStreakLine(6)}'),
        findsOneWidget,
      );
    });
  }
}
