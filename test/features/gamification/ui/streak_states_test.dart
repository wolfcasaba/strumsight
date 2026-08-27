import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

/// Round E13-R32, §6/A5 + §0.0.B/B6 + §6.1 "A5 — a széria-státusz három
/// cellája".
///
/// The A5 acceptance criterion is measured against `StreakEvaluationReason`
/// (not `StreakGraceState`, which the pre-flight measured as unreachable —
/// its only value is `none`). The threshold is `graceDays = 1`
/// (`default_streak_policy.dart`), the predicate is `gap <= graceDays`, and
/// the three cells are:
///
///   | gap | expected reason |
///   |-----|------------------|
///   |  0  | grace            |
///   |  1  | grace (ON the threshold — inclusive) |
///   |  2  | broken           |
///
/// plus a fourth, orthogonal cell: a planned-rest day must resolve to
/// `plannedRest`, never `broken` — the §6.1 "hibás implementáció" this cell
/// catches is "a pihenőnap a széria végeként".
AppLocalizations _english() => AppLocalizationsEn();

StreakState _baseState({
  int lastQualifiedDay = 100,
  Set<int> plannedRestDays = const <int>{},
}) => StreakState(
  current: 5,
  longest: 10,
  lastQualifiedDay: lastQualifiedDay,
  totalQualifiedDays: 20,
  freezes: 0,
  plannedRestDays: plannedRestDays,
);

Future<void> _pumpStatusCard(
  WidgetTester tester,
  StreakEvaluationReason reason,
) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: StreakStatusCard(reason: reason)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = StreakService();

  group('measured input — DefaultStreakPolicy.config.graceDays', () {
    test('the threshold is 1, matching §0.0.B/B6', () {
      expect(DefaultStreakPolicy().config.graceDays, 1);
    });
  });

  group('§6.1 A5 cell 1 — gap below/at/above the graceDays threshold', () {
    test('gap=0 (the same day re-evaluated) resolves to grace', () {
      final evaluation = service.evaluate(
        StreakEvaluationRequest(previous: _baseState(), epochDay: 100),
      );
      expect(evaluation.reason, StreakEvaluationReason.grace);
    });

    test('gap=1 (exactly on the threshold, inclusive) resolves to grace', () {
      final evaluation = service.evaluate(
        StreakEvaluationRequest(previous: _baseState(), epochDay: 101),
      );
      expect(evaluation.reason, StreakEvaluationReason.grace);
    });

    test('gap=2 (past the threshold) resolves to broken', () {
      final evaluation = service.evaluate(
        StreakEvaluationRequest(previous: _baseState(), epochDay: 102),
      );
      expect(evaluation.reason, StreakEvaluationReason.broken);
    });
  });

  group('§6.1 A5 cell 2 — planned rest is distinct from broken, never the '
      'streak ending', () {
    test('a planned-rest epoch day resolves to plannedRest, not broken', () {
      final evaluation = service.evaluate(
        StreakEvaluationRequest(
          previous: _baseState(
            lastQualifiedDay: 100,
            plannedRestDays: const {105},
          ),
          epochDay: 105,
        ),
      );
      expect(evaluation.reason, StreakEvaluationReason.plannedRest);
      expect(evaluation.reason, isNot(StreakEvaluationReason.broken));
    });

    test('the SAME gap (5 days) without a planned-rest day resolves to '
        'broken — the two cells share nothing but the reason enum', () {
      final evaluation = service.evaluate(
        StreakEvaluationRequest(
          previous: _baseState(lastQualifiedDay: 100),
          epochDay: 105,
        ),
      );
      expect(evaluation.reason, StreakEvaluationReason.broken);
    });
  });

  group('the rendered status card sources its title from the correct ARB key '
      'per reason (L403 — measure the caption and the data source, not the '
      'widget type)', () {
    testWidgets('grace renders streakV2GraceTitle', (tester) async {
      await _pumpStatusCard(tester, StreakEvaluationReason.grace);
      expect(find.text(_english().streakV2GraceTitle), findsOneWidget);
    });

    testWidgets('broken renders streakV2BrokenTitle', (tester) async {
      await _pumpStatusCard(tester, StreakEvaluationReason.broken);
      expect(find.text(_english().streakV2BrokenTitle), findsOneWidget);
    });

    testWidgets('plannedRest renders streakV2PlannedRestTitle — '
        'distinct from BOTH grace and broken titles', (tester) async {
      await _pumpStatusCard(tester, StreakEvaluationReason.plannedRest);
      expect(find.text(_english().streakV2PlannedRestTitle), findsOneWidget);
      expect(find.text(_english().streakV2BrokenTitle), findsNothing);
      expect(find.text(_english().streakV2GraceTitle), findsNothing);
    });

    testWidgets('the StreakDetailScreen only shows the recovery CTA for the '
        'broken reason, never for grace or plannedRest', (tester) async {
      Future<void> pumpDetail(StreakEvaluationReason reason) =>
          tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: StreakDetailScreen(
                state: _baseState(),
                reason: reason,
                weeklyConsistencyDays: 3,
                onRecoveryPressed: () {},
              ),
            ),
          );

      await pumpDetail(StreakEvaluationReason.grace);
      expect(find.byKey(const Key('streak-recovery-cta')), findsNothing);

      await pumpDetail(StreakEvaluationReason.plannedRest);
      expect(find.byKey(const Key('streak-recovery-cta')), findsNothing);

      await pumpDetail(StreakEvaluationReason.broken);
      final cta = find.byKey(const Key('streak-recovery-cta'));
      await tester.scrollUntilVisible(cta, 100);
      expect(cta, findsOneWidget);
    });
  });

  group('real-violation probe — a plannedRest-as-broken regression must turn '
      'this suite red', () {
    test('asserting plannedRest == broken (the hibás implementáció) fails', () {
      final evaluation = service.evaluate(
        StreakEvaluationRequest(
          previous: _baseState(
            lastQualifiedDay: 100,
            plannedRestDays: const {105},
          ),
          epochDay: 105,
        ),
      );
      // The correct behaviour already asserted above is
      // reason == plannedRest. A regression that treats a planned rest
      // day as the streak ending would make this equality hold instead
      // — assert it does NOT, so a future regression is caught here too.
      expect(evaluation.reason == StreakEvaluationReason.broken, isFalse);
    });
  });
}
