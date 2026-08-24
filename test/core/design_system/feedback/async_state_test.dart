import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  final themes = {
    'dark': SsDarkTheme.data(),
    'light': SsLightTheme.data(),
    'high contrast': SsHighContrastTheme.data(),
  };

  Future<void> pumpThemed(WidgetTester tester, ThemeData theme, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: child),
      ),
    );
  }

  group('A2 — offline/sync-pending/degraded keep cached content visible, not a '
      'full-screen failure style', () {
    testWidgets('offline renders the banner ABOVE the content, not '
        'instead of it', (tester) async {
      await pumpThemed(
        tester,
        themes['dark']!,
        SsAsyncState(
          status: SsAsyncStatus.offline,
          content: const Text('cached-content-marker'),
          skeleton: const SizedBox(),
          loadingSemanticLabel: 'Loading',
          emptyState: const SizedBox(),
          failureState: const SizedBox(),
          permissionState: const SizedBox(),
          blockedState: const SizedBox(),
          offlineBanner: const Text('offline-banner-marker'),
          syncPendingBanner: const SizedBox(),
          degradedBanner: const SizedBox(),
        ),
      );

      expect(find.text('cached-content-marker'), findsOneWidget);
      expect(find.text('offline-banner-marker'), findsOneWidget);
      expect(find.byType(SsFailureState), findsNothing);
      expect(
        tester.getTopLeft(find.text('offline-banner-marker')).dy,
        lessThan(tester.getTopLeft(find.text('cached-content-marker')).dy),
      );
    });

    testWidgets('syncPending and degraded also keep content mounted', (
      tester,
    ) async {
      for (final status in [
        SsAsyncStatus.syncPending,
        SsAsyncStatus.degraded,
      ]) {
        await pumpThemed(
          tester,
          themes['light']!,
          SsAsyncState(
            status: status,
            content: const Text('cached-content-marker-2'),
            skeleton: const SizedBox(),
            loadingSemanticLabel: 'Loading',
            emptyState: const SizedBox(),
            failureState: const SizedBox(),
            permissionState: const SizedBox(),
            blockedState: const SizedBox(),
            offlineBanner: const SizedBox(),
            syncPendingBanner: const Text('sync-banner-marker'),
            degradedBanner: const Text('degraded-banner-marker'),
          ),
        );

        expect(
          find.text('cached-content-marker-2'),
          findsOneWidget,
          reason: status.name,
        );
      }
    });
  });

  group('A5 — the empty state always offers an action', () {
    testWidgets('SsEmptyState renders a tappable action button', (
      tester,
    ) async {
      var tapped = false;
      await pumpThemed(
        tester,
        themes['dark']!,
        SsEmptyState(
          icon: Icons.library_music_outlined,
          title: 'Nothing here yet',
          message: 'Add your first song to get started.',
          actionLabel: 'Add a song',
          onAction: () => tapped = true,
        ),
      );

      final actionFinder = find.byKey(const ValueKey('ss-empty-state-action'));
      expect(actionFinder, findsOneWidget);

      await tester.tap(actionFinder);
      expect(tapped, isTrue);
    });
  });

  group('A6 — the skeleton holds geometry and carries no readable content', () {
    testWidgets('SsSkeleton reserves exactly the declared box', (tester) async {
      await pumpThemed(
        tester,
        themes['dark']!,
        const SsSkeleton(width: 120, height: 40),
      );

      expect(tester.getSize(find.byType(SsSkeleton)), const Size(120, 40));
    });

    testWidgets('SsSkeleton is excluded from the semantics tree', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await pumpThemed(
        tester,
        themes['dark']!,
        Semantics(
          key: const ValueKey('probe-semantics'),
          container: true,
          label: 'probe',
          child: const SsSkeleton(width: 120, height: 40),
        ),
      );

      // Only the outer probe label reaches semantics — the skeleton itself
      // contributed nothing (no placeholder text, no announced content).
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('probe-semantics')))
            .label,
        'probe',
      );

      handle.dispose();
    });

    testWidgets('SsAsyncState announces the loading label ONCE for the whole '
        'skeleton region, not per individual box', (tester) async {
      final handle = tester.ensureSemantics();

      await pumpThemed(
        tester,
        themes['dark']!,
        SsAsyncState(
          status: SsAsyncStatus.loading,
          content: const SizedBox(),
          skeleton: const Column(
            children: [
              SsSkeleton(width: 100, height: 20),
              SsSkeleton(width: 80, height: 20),
            ],
          ),
          loadingSemanticLabel: 'Loading content',
          emptyState: const SizedBox(),
          failureState: const SizedBox(),
          permissionState: const SizedBox(),
          blockedState: const SizedBox(),
          offlineBanner: const SizedBox(),
          syncPendingBanner: const SizedBox(),
          degradedBanner: const SizedBox(),
        ),
      );

      expect(
        tester.getSemantics(find.byType(SsAsyncState)).label,
        'Loading content',
      );

      handle.dispose();
    });
  });

  group('A8 — every status renders in every theme', () {
    for (final entry in themes.entries) {
      testWidgets('${entry.key} theme renders every SsAsyncStatus', (
        tester,
      ) async {
        final permissionPresentation = SsFailurePresentation.from(
          en,
          MicrophonePermissionState.permanentlyDenied.failure!,
        );
        final failurePresentation = SsFailurePresentation.from(
          en,
          const NetworkFailure(code: FailureCode.networkUnavailable),
        );

        for (final status in SsAsyncStatus.values) {
          await pumpThemed(
            tester,
            entry.value,
            SsAsyncState(
              status: status,
              content: const Text('content'),
              skeleton: const SsSkeleton(width: 40, height: 16),
              loadingSemanticLabel: 'Loading',
              emptyState: SsEmptyState(
                icon: Icons.library_music_outlined,
                title: 'Nothing here yet',
                message: 'Add your first song to get started.',
                actionLabel: 'Add a song',
                onAction: () {},
              ),
              failureState: SsFailureState(
                presentation: failurePresentation,
                onRetry: () {},
                onContinueOffline: () {},
              ),
              permissionState: SsPermissionState(
                kind: SsPermissionKind.microphone,
                rationale: 'StrumSight needs the mic to hear you play.',
                consequence: 'Without it, chord detection cannot run.',
                presentation: permissionPresentation,
                onOpenSettings: () {},
              ),
              blockedState: const Text('blocked'),
              offlineBanner: const Text('offline'),
              syncPendingBanner: const Text('sync'),
              degradedBanner: const Text('degraded'),
            ),
          );
          await tester.pump();

          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} / ${status.name}',
          );
        }
      });
    }
  });
}
