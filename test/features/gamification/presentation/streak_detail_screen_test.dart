import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/l10n/app_localizations_hu.dart';

AppLocalizations _english() => AppLocalizationsEn();
AppLocalizations _hungarian() => AppLocalizationsHu();

StreakState _state() => StreakState(
  current: 3,
  longest: 8,
  lastQualifiedDay: 20400,
  totalQualifiedDays: 12,
  freezes: 2,
);

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  StreakEvaluationReason reason = StreakEvaluationReason.qualified,
  int weeklyConsistencyDays = 4,
  double textScale = 1,
  bool disableAnimations = false,
  VoidCallback? onRecoveryPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: StreakDetailScreen(
          state: _state(),
          reason: reason,
          weeklyConsistencyDays: weeklyConsistencyDays,
          onRecoveryPressed: onRecoveryPressed ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

Map<String, Object?> _arb(String path) =>
    Map<String, Object?>.from(jsonDecode(File(path).readAsStringSync()) as Map);

List<String> _brokenCopies(String path) {
  final locale = _arb(path);
  return <String>[
    locale['streakV2BrokenTitle']! as String,
    locale['streakV2BrokenBody']! as String,
    locale['streakV2RecoveryCta']! as String,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1 — compassionate reason-code presentation', () {
    testWidgets('every evaluation reason has a visible, typed status card', (
      tester,
    ) async {
      for (final reason in StreakEvaluationReason.values) {
        await _pump(tester, reason: reason);

        expect(
          find.byKey(const Key('streak-status-card')),
          findsOneWidget,
          reason: 'reason=$reason',
        );
        expect(tester.takeException(), isNull, reason: 'reason=$reason');
      }
    });

    test('every broken title, body, and recovery CTA is compassionate', () {
      final copiesByLocale = <String, List<String>>{
        'en': _brokenCopies('lib/l10n/features/gamification_en.arb'),
        'hu': _brokenCopies('lib/l10n/features/gamification_hu.arb'),
      };

      for (final entry in copiesByLocale.entries) {
        for (final copy in entry.value) {
          final normalized = copy.toLowerCase();
          expect(normalized, isNot(contains('!')));
          expect(normalized, isNot(contains('lost')));
          expect(normalized, isNot(contains('lose')));
          expect(normalized, isNot(contains('hurry')));
          expect(normalized, isNot(contains('urgent')));
          expect(normalized, isNot(contains('deadline')));
          expect(normalized, isNot(contains('elveszett')));
          expect(normalized, isNot(contains('veszíts')));
          expect(normalized, isNot(contains('sürg')));
          expect(normalized, isNot(contains('határidő')));
          expect(normalized, isNot(contains('within')));
          expect(normalized, isNot(contains('napon belül')));
          expect(
            normalized,
            isNot(matches(RegExp(r'\\b\\d+\\s*(?:day|days|nap)\\b'))),
            reason: '${entry.key} copy must not include a text countdown',
          );
        }
      }
      expect(copiesByLocale['en']![1].toLowerCase(), contains('skill'));
      expect(copiesByLocale['en']![1].toLowerCase(), contains('stays'));
      expect(copiesByLocale['hu']![1].toLowerCase(), contains('tudás'));
      expect(copiesByLocale['hu']![1].toLowerCase(), contains('veled marad'));
    });
  });

  group('A2 + A3 — recovery and planned rest', () {
    testWidgets(
      'broken state exposes one recovery callback without a countdown',
      (tester) async {
        var recoveryCalls = 0;
        await _pump(
          tester,
          reason: StreakEvaluationReason.broken,
          onRecoveryPressed: () => recoveryCalls += 1,
        );

        final recoveryCta = find.byKey(const Key('streak-recovery-cta'));
        await tester.scrollUntilVisible(recoveryCta, 100);
        expect(recoveryCta, findsOneWidget);
        expect(find.textContaining(RegExp(r'\d{1,2}:\d{2}')), findsNothing);

        await tester.tap(recoveryCta);
        await tester.pump();
        expect(recoveryCalls, 1);
      },
    );

    testWidgets('only planned rest shows the protection explanation', (
      tester,
    ) async {
      await _pump(tester, reason: StreakEvaluationReason.plannedRest);
      expect(find.text(_english().streakV2PlannedRestTitle), findsOneWidget);

      await _pump(tester, reason: StreakEvaluationReason.broken);
      expect(find.text(_english().streakV2PlannedRestTitle), findsNothing);
    });
  });

  group('A4 — caller-fed weekly consistency', () {
    for (final value in <int>[0, 4, 7]) {
      testWidgets('renders supplied weekly consistency $value of 7', (
        tester,
      ) async {
        await _pump(tester, weeklyConsistencyDays: value);
        expect(
          find.bySemanticsLabel(_english().streakV2WeeklySemantics(value)),
          findsOneWidget,
        );
      });
    }

    testWidgets('keeps supplied weekly consistency for a broken state', (
      tester,
    ) async {
      await _pump(
        tester,
        reason: StreakEvaluationReason.broken,
        weeklyConsistencyDays: 4,
      );
      expect(
        find.bySemanticsLabel(_english().streakV2WeeklySemantics(4)),
        findsOneWidget,
      );
    });

    test('rejects weekly consistency outside the caller-validated range', () {
      expect(
        () => StreakDetailScreen(
          state: _state(),
          reason: StreakEvaluationReason.qualified,
          weeklyConsistencyDays: -1,
          onRecoveryPressed: () {},
        ),
        throwsArgumentError,
      );
      expect(
        () => StreakDetailScreen(
          state: _state(),
          reason: StreakEvaluationReason.qualified,
          weeklyConsistencyDays: 8,
          onRecoveryPressed: () {},
        ),
        throwsArgumentError,
      );
    });
  });

  group('A5 + A6 — compatibility and presentation boundary', () {
    test('the shipping streak route remains wired to the legacy screen', () {
      final router = File('lib/app/routing/app_router.dart').readAsStringSync();
      expect(
        router,
        contains(
          'GoRoute(path: AppRoutes.streak, builder: (_, _) => const StreakScreen())',
        ),
      );
    });

    test('new presentation files have no user-facing literals or data owners', () {
      const paths = <String>[
        'lib/features/gamification/presentation/screens/streak_detail_screen.dart',
        'lib/features/gamification/presentation/widgets/streak_status_card.dart',
        'lib/features/gamification/presentation/widgets/weekly_consistency_card.dart',
      ];
      final userString = RegExp(r'''(?:Text|label|tooltip)\s*[:(]\s*['"]''');
      const forbiddenOwners = <String>[
        'DateTime.now',
        'Provider',
        'Repository',
        'Navigator.',
        'GoRouter',
        'weeklyConsistency(',
      ];

      for (final path in paths) {
        final source = File(path).readAsStringSync();
        expect(userString.hasMatch(source), isFalse, reason: path);
        for (final owner in forbiddenOwners) {
          expect(
            source,
            isNot(contains(owner)),
            reason: '$path contains $owner',
          );
        }
      }
    });

    testWidgets('English and Hungarian values both render from ARB keys', (
      tester,
    ) async {
      await _pump(tester, reason: StreakEvaluationReason.broken);
      expect(find.text(_english().streakV2BrokenTitle), findsOneWidget);

      await _pump(
        tester,
        locale: const Locale('hu'),
        reason: StreakEvaluationReason.broken,
      );
      expect(find.text(_hungarian().streakV2BrokenTitle), findsOneWidget);
    });
  });

  group('A3 — phone viewport (360x640), textScaler 1.5/2.0/2.5, en+hu '
      '(§0.0.A/R5 — the exact mandated cell shape, in addition to the '
      'existing 320x568/412x732 coverage above)', () {
    for (final scale in <double>[1.5, 2.0, 2.5]) {
      for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
        testWidgets(
          '$scale / ${locale.languageCode} — broken reason, no overflow',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await _pump(
              tester,
              locale: locale,
              reason: StreakEvaluationReason.broken,
              textScale: scale,
            );

            expect(find.byType(ListView), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('A7 + A8 — responsive and accessible feedback', () {
    for (final size in <Size>[const Size(320, 568), const Size(412, 732)]) {
      for (final scale in <double>[1, 2, 3]) {
        testWidgets(
          '$size at $scale text scale stays scrollable without overflow',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await _pump(
              tester,
              reason: StreakEvaluationReason.broken,
              textScale: scale,
            );

            expect(find.byType(ListView), findsOneWidget);
            if (scale >= 2) {
              final currentMetric = find.bySemanticsLabel(
                _english().streakV2CurrentSemantics(3),
              );
              await tester.scrollUntilVisible(currentMetric, 100);
              final metricCards = find.byType(Card, skipOffstage: false);
              expect(metricCards, findsNWidgets(4));
              expect(
                tester.getSize(metricCards.first).height,
                greaterThan(80),
                reason: 'metric cards must grow instead of clipping large text',
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      'all value cards expose complete unit-bearing semantic labels',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester);

        final labels = <String>[
          _english().streakV2CurrentSemantics(3),
          _english().streakV2LongestSemantics(8),
          _english().streakV2TotalSemantics(12),
          _english().streakV2FreezesSemantics(2),
          _english().streakV2WeeklySemantics(4),
        ];
        for (final label in labels) {
          final card = find.bySemanticsLabel(label);
          await tester.scrollUntilVisible(card, 100);
          expect(card, findsOneWidget);
        }
        handle.dispose();
      },
    );

    test('English metric semantics use the correct plural form', () {
      final semantics = <String Function(int)>[
        _english().streakV2CurrentSemantics,
        _english().streakV2LongestSemantics,
        _english().streakV2TotalSemantics,
      ];

      for (final semantic in semantics) {
        expect(semantic(0), endsWith('0 days'));
        expect(semantic(1), endsWith('1 day'));
        expect(semantic(2), endsWith('2 days'));
      }
    });

    testWidgets(
      'reduced motion removes the transition duration but preserves status semantics',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, reason: StreakEvaluationReason.broken);
        expect(
          tester
              .widget<AnimatedContainer>(
                find.byKey(const Key('streak-status-transition')),
              )
              .duration,
          isNot(Duration.zero),
        );
        expect(
          find.bySemanticsLabel(
            _english().streakV2StatusSemantics(
              _english().streakV2BrokenTitle,
              _english().streakV2BrokenBody,
            ),
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.favorite_outline), findsOneWidget);

        await _pump(
          tester,
          reason: StreakEvaluationReason.broken,
          disableAnimations: true,
        );
        expect(
          tester
              .widget<AnimatedContainer>(
                find.byKey(const Key('streak-status-transition')),
              )
              .duration,
          Duration.zero,
        );
        expect(
          find.bySemanticsLabel(
            _english().streakV2StatusSemantics(
              _english().streakV2BrokenTitle,
              _english().streakV2BrokenBody,
            ),
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
        handle.dispose();
      },
    );
  });
}
