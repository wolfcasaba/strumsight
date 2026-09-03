// E15-R08 — dedicated RewardInboxScreen coverage. §0.0.A/R4 G2: this screen
// had no test file before this round. §0.0.A/R5: the A3 cells below use the
// exact 360x640 phone viewport (not the flutter_test 800x600 default) so a
// real overflow is actually measured, not masked (L558).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/domain/profile/reward_inbox_item.dart';
import 'package:strumsight/features/gamification/presentation/screens/reward_inbox_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

AppLocalizations _english() => AppLocalizationsEn();

RewardEvent _event(String id) => RewardEvent(
  id: id,
  kind: RewardKind.dailyReward,
  titleKey: 'Daily reward $id',
  bodyKey: 'You practiced today.',
  earnedXp: 15,
  earnedAt: DateTime.utc(2026, 8, 22, 9),
  sourceLedgerId: 'ledger-$id',
);

RewardInboxItem _item(String id, {bool seen = false}) => RewardInboxItem(
  id: id,
  event: _event(id),
  addedAt: DateTime.utc(2026, 8, 22, 9),
  seen: seen,
);

Future<void> _pump(
  WidgetTester tester, {
  List<RewardInboxItem> items = const <RewardInboxItem>[],
  int pendingCount = 0,
  int quarantinedCount = 0,
  VoidCallback? onRetryPending,
  ValueChanged<RewardInboxItem>? onItemSelected,
  ValueChanged<RewardInboxItem>? onMarkSeen,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: RewardInboxScreen(
        items: items,
        onItemSelected: onItemSelected ?? (_) {},
        onMarkSeen: onMarkSeen ?? (_) {},
        pendingCount: pendingCount,
        quarantinedCount: quarantinedCount,
        onRetryPending: onRetryPending,
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1 — the screen imports the design system for its rows', () {
    testWidgets('inbox entries render inside a themed surface, no exception', (
      tester,
    ) async {
      await _pump(tester, items: <RewardInboxItem>[_item('evt-1')]);
      expect(find.byKey(const Key('reward-inbox-list')), findsOneWidget);
      expect(find.byKey(const Key('reward-inbox-entry-evt-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('m3 — reward-inbox-list is the shared scroll carrier', () {
    testWidgets(
      'branch is distinguished by reward-inbox-empty vs entry keys, not '
      'reward-inbox-list',
      (tester) async {
        // reward-inbox-list now sits on the CustomScrollView, which is
        // present in BOTH branches (needed so the pending-rewards card,
        // count header, and rows all scroll together — E15-R08 review m3).
        // The branch distinction lives in reward-inbox-empty (empty only)
        // vs reward-inbox-entry-* (non-empty only).
        await _pump(tester);
        expect(find.byKey(const Key('reward-inbox-list')), findsOneWidget);
        expect(find.byKey(const Key('reward-inbox-empty')), findsOneWidget);
        expect(find.byKey(const Key('reward-inbox-entry-evt-1')), findsNothing);

        await _pump(tester, items: <RewardInboxItem>[_item('evt-1')]);
        expect(find.byKey(const Key('reward-inbox-list')), findsOneWidget);
        expect(find.byKey(const Key('reward-inbox-empty')), findsNothing);
        expect(
          find.byKey(const Key('reward-inbox-entry-evt-1')),
          findsOneWidget,
        );
      },
    );
  });

  group('A2 — empty state is token-styled, no fabricated action', () {
    testWidgets('an empty inbox renders the empty state, no button', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byKey(const Key('reward-inbox-empty')), findsOneWidget);
      expect(find.text(_english().rewardInboxEmptyTitle), findsOneWidget);
      // §0.0.A/R7 — no claim/action button is fabricated for this state.
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'an empty inbox with pending items still shows the pending card',
      (tester) async {
        var retried = false;
        await _pump(
          tester,
          pendingCount: 2,
          onRetryPending: () => retried = true,
        );
        expect(find.byKey(const Key('reward-inbox-empty')), findsOneWidget);
        expect(retried, isFalse);
      },
    );
  });

  group('A3 — phone viewport (360x640), textScaler 1.5/2.0/2.5, en+hu', () {
    final items = <RewardInboxItem>[_item('evt-1'), _item('evt-2', seen: true)];

    for (final scale in <double>[1.5, 2.0, 2.5]) {
      for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
        testWidgets(
          '$scale / ${locale.languageCode} — list state, no overflow',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await _pump(
              tester,
              items: items,
              pendingCount: 1,
              onRetryPending: () {},
              locale: locale,
              textScale: scale,
            );

            expect(find.byType(CustomScrollView), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          '$scale / ${locale.languageCode} — empty state, no overflow',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await _pump(tester, locale: locale, textScale: scale);

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('M2 — seen vs unseen backgrounds are genuinely different', () {
    testWidgets(
      'unseen and seen entries render distinct tile background colors',
      (tester) async {
        await _pump(
          tester,
          items: <RewardInboxItem>[_item('evt-1'), _item('evt-2', seen: true)],
        );

        Color? materialColorFor(String id) => tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byKey(Key('reward-inbox-entry-$id')),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color;

        final unseenColor = materialColorFor('evt-1');
        final seenColor = materialColorFor('evt-2');
        expect(
          unseenColor,
          isNot(equals(seenColor)),
          reason:
              'seen vs unseen rows must use genuinely different background '
              'tokens — an identical pair loses the read/unread signal',
        );
      },
    );
  });

  group('tap behaviour — selecting an unseen item marks it seen', () {
    testWidgets(
      'tapping an unseen entry calls onMarkSeen then onItemSelected',
      (tester) async {
        RewardInboxItem? seen;
        RewardInboxItem? selected;
        final item = _item('evt-1');
        await _pump(
          tester,
          items: <RewardInboxItem>[item],
          onMarkSeen: (i) => seen = i,
          onItemSelected: (i) => selected = i,
        );

        await tester.tap(find.byKey(const Key('reward-inbox-entry-tap-evt-1')));
        await tester.pump();

        expect(seen?.id, 'evt-1');
        expect(selected?.id, 'evt-1');
      },
    );

    testWidgets('tapping an already-seen entry never calls onMarkSeen', (
      tester,
    ) async {
      var markSeenCalls = 0;
      RewardInboxItem? selected;
      final item = _item('evt-1', seen: true);
      await _pump(
        tester,
        items: <RewardInboxItem>[item],
        onMarkSeen: (_) => markSeenCalls += 1,
        onItemSelected: (i) => selected = i,
      );

      await tester.tap(find.byKey(const Key('reward-inbox-entry-tap-evt-1')));
      await tester.pump();

      expect(markSeenCalls, 0);
      expect(selected?.id, 'evt-1');
    });
  });
}
