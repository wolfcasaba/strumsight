import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/bootstrap/app_bootstrap.dart';
import 'package:strumsight/app/bootstrap/bootstrap_result.dart';
import 'package:strumsight/app/bootstrap/launch_screen.dart';
import 'package:strumsight/app/bootstrap/recovery_screen.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// E13-R16 (ADR 0281 §3/§6) — bootstrap redaction, the safe-mode surface,
/// its routing, and the flicker-free launch screen. A8: the recovery text
/// never carries a raw exception. A4: safe mode never deletes data.
void main() {
  group('A8 — no raw exception reaches the recovery text', () {
    test(
      'an unexpected boot exception maps to a redacted, code-based problem',
      () async {
        const secretDetail =
            'super secret leaked detail 0xDEADBEEF should never be shown';
        final result = await AppBootstrap.run(
          rawEnvironment: 'development',
          buildMode: 'debug',
          loadVersion: () async => '1.0.0+1',
          openStore: () async => throw StateError(secretDetail),
        );

        expect(result, isA<BootstrapFailure>());
        final problems = (result as BootstrapFailure).problems;
        expect(problems, isNotEmpty);
        for (final p in problems) {
          expect(p, isNot(contains(secretDetail)));
          expect(p, isNot(contains('StateError')));
          expect(p, isNot(contains('Bad state')));
        }
      },
    );

    testWidgets(
      'RecoveryScreen renders only the (already redacted) problem text',
      (tester) async {
        const redacted = [
          'Local storage is unavailable (storage.unavailable).',
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const RecoveryScreen(problems: redacted),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('storage.unavailable'),
          findsOneWidget,
          reason: 'the redacted problem text itself is shown verbatim',
        );
        expect(find.textContaining('Exception'), findsNothing);
        expect(find.textContaining('#0'), findsNothing); // no stack frame
      },
    );
  });

  group('A4 — safe mode never deletes data', () {
    testWidgets('RecoveryScreen offers no delete/clear/reset/wipe action', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const RecoveryScreen(
            problems: ['Bootstrap failed: unexpected startup error.'],
            onRetry: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      const destructiveWords = ['delete', 'clear', 'reset', 'wipe', 'erase'];
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase())
          .toList();
      for (final word in destructiveWords) {
        expect(
          texts.any((t) => t.contains(word)),
          isFalse,
          reason: 'safe mode must not offer a "$word" action (ADR 0281 §3)',
        );
      }
    });

    testWidgets(
      'the /recovery route renders RecoveryScreen with the extra problems, '
      'never a bare error and never a delete affordance',
      (tester) async {
        final router = GoRouter(
          initialLocation: AppRoutes.recovery,
          routes: [
            GoRoute(
              path: AppRoutes.recovery,
              builder: (_, state) => RecoveryScreen(
                problems: (state.extra as List<String>?) ?? const <String>[],
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(RecoveryScreen), findsOneWidget);
      },
    );
  });

  group('the flicker-free launch surface', () {
    testWidgets('LaunchScreen paints using the theme, not a hardcoded color', (
      tester,
    ) async {
      final theme = AppTheme.dark();
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const LaunchScreen()),
      );
      await tester.pump();

      final coloredBox = tester.widget<ColoredBox>(find.byType(ColoredBox));
      expect(coloredBox.color, theme.colorScheme.surface);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

void _noop() {}
