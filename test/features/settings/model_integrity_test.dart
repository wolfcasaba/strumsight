// E13-R35 — A6 (ADR 0292 §5.1): a downloaded model can only activate behind
// a REAL checksum comparison, and there is no path — warned-through or
// otherwise — to activate one that fails it. The three §6.1 cells:
//   below threshold — missing/mismatched checksum → blocked, no bypass
//   at threshold     — a valid checksum, known source → activatable
//   above threshold  — valid checksum + a previous working version →
//                       activatable, with a rollback path
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/offline_ai/data/offline_model_source.dart';
import 'package:strumsight/features/offline_ai/model/offline_model.dart';
import 'package:strumsight/features/offline_ai/providers/offline_model_controller.dart';
import 'package:strumsight/features/offline_ai/screens/model_manager_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

OfflineModelAsset _asset({
  required List<int> bytes,
  required String declared,
}) => OfflineModelAsset(
  modelId: 'strumsight-detector',
  version: '2.0.0',
  expectedSha256: declared,
  bytes: bytes,
);

final class _ScriptedSource implements OfflineModelSource {
  _ScriptedSource(this.result);
  final AppResult<OfflineModelAsset> result;

  @override
  Future<AppResult<OfflineModelAsset>> fetchCandidate(String modelId) async =>
      result;
}

void main() {
  group('the real checksum verification — pure logic', () {
    test('a mismatched checksum is rejected, and the mismatch is real (not '
        'a stub returning false)', () {
      final good = _asset(bytes: const [1, 2, 3], declared: '');
      final actual = offlineModelChecksum(good.bytes);
      final tampered = _asset(bytes: const [1, 2, 3], declared: 'f' * 64);

      expect(actual, isNot('f' * 64));
      expect(verifyOfflineModelAsset(tampered).verified, isFalse);
      expect(verifyOfflineModelAsset(tampered).actualSha256, actual);
    });

    test('a missing (empty) declared checksum never accidentally verifies', () {
      final asset = _asset(bytes: const [9, 9, 9], declared: '');
      expect(verifyOfflineModelAsset(asset).verified, isFalse);
    });

    test('a genuinely matching checksum verifies', () {
      final bytes = const [10, 20, 30, 40];
      final declared = offlineModelChecksum(bytes);
      final asset = _asset(bytes: bytes, declared: declared);
      expect(verifyOfflineModelAsset(asset).verified, isTrue);
    });

    test('declared checksum comparison is case-insensitive', () {
      final bytes = const [1, 2, 3, 4, 5];
      final declared = offlineModelChecksum(bytes).toUpperCase();
      final asset = _asset(bytes: bytes, declared: declared);
      expect(verifyOfflineModelAsset(asset).verified, isTrue);
    });
  });

  group('OfflineModelController — the three §6.1 cells', () {
    test(
      'below threshold: a bad checksum blocks activation, active stays null',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final controller = container.read(
          offlineModelControllerProvider.notifier,
        );

        controller.activate(_asset(bytes: const [1, 2], declared: 'bad'));

        final state = container.read(offlineModelControllerProvider);
        expect(state.phase, OfflineModelPhase.blockedIntegrity);
        expect(state.active, isNull);
      },
    );

    test('at threshold: a valid checksum from a known source activates', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        offlineModelControllerProvider.notifier,
      );
      final bytes = const [5, 5, 5];
      final asset = _asset(bytes: bytes, declared: offlineModelChecksum(bytes));

      controller.activate(asset);

      final state = container.read(offlineModelControllerProvider);
      expect(state.phase, OfflineModelPhase.active);
      expect(state.active, same(asset));
      expect(state.previous, isNull);
    });

    test('above threshold: verified + a previous working version → activatable '
        'WITH a rollback path', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        offlineModelControllerProvider.notifier,
      );
      final v1bytes = const [1];
      final v1 = _asset(
        bytes: v1bytes,
        declared: offlineModelChecksum(v1bytes),
      );
      final v2bytes = const [2];
      final v2 = _asset(
        bytes: v2bytes,
        declared: offlineModelChecksum(v2bytes),
      );

      controller.activate(v1);
      controller.activate(v2);

      final state = container.read(offlineModelControllerProvider);
      expect(state.phase, OfflineModelPhase.activeWithRollback);
      expect(state.active, same(v2));
      expect(state.previous, same(v1));

      controller.rollback();
      final rolledBack = container.read(offlineModelControllerProvider);
      expect(rolledBack.active, same(v1));
      expect(rolledBack.previous, isNull);
    });

    test(
      // Javító kör 1, F5: a fetch-layer problem (network, storage, any other
      // transport/IO failure) never reaches the checksum comparison at all,
      // so it must NOT read as an integrity verdict.
      'a fetch/network failure is a distinct phase from a real checksum '
      'mismatch — it never claims a checksum was even compared',
      () async {
        final container = ProviderContainer(
          overrides: [
            offlineModelSourceProvider.overrideWithValue(
              _ScriptedSource(const Failure(NetworkFailure())),
            ),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(
          offlineModelControllerProvider.notifier,
        );

        await controller.checkAndActivate('strumsight-detector');

        final state = container.read(offlineModelControllerProvider);
        expect(state.phase, OfflineModelPhase.fetchFailed);
        expect(state.phase, isNot(OfflineModelPhase.blockedIntegrity));
        expect(state.active, isNull);
      },
    );

    test('a bad candidate NEVER overwrites a good, already-active version', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        offlineModelControllerProvider.notifier,
      );
      final goodBytes = const [7];
      final good = _asset(
        bytes: goodBytes,
        declared: offlineModelChecksum(goodBytes),
      );
      controller.activate(good);

      controller.activate(_asset(bytes: const [8], declared: 'wrong'));

      final state = container.read(offlineModelControllerProvider);
      expect(state.phase, OfflineModelPhase.blockedIntegrity);
      expect(
        state.active,
        same(good),
        reason: 'a failed re-check must not clear the still-good active asset',
      );
    });
  });

  group('ModelManagerScreen — the valódi-sértés próba surface (§10)', () {
    Future<void> pump(WidgetTester tester, OfflineModelSource source) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [offlineModelSourceProvider.overrideWithValue(source)],
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ModelManagerScreen(),
            ),
          ),
        );

    testWidgets(
      'below threshold: NO activation control is rendered at all — not '
      'disabled, absent',
      (tester) async {
        final badBytes = const [1, 2, 3];
        await pump(
          tester,
          _ScriptedSource(
            Success(_asset(bytes: badBytes, declared: 'not-the-real-hash')),
          ),
        );

        await tester.tap(find.text('Check for model'));
        await tester.pumpAndSettle();

        // Shown in both the status card and the (button-free) action area —
        // the important assertion is the total ABSENCE of any button below.
        expect(
          find.text("Not activated — checksum could not be verified"),
          findsWidgets,
        );
        // No button anywhere offers to activate despite the failed check.
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);

        // Javító kör 1, F1: the ORIGINAL two assertions above only ruled out
        // FilledButton/OutlinedButton — an `SsButton(variant: tertiary)`
        // "Activate anyway" affordance renders a `TextButton` and would have
        // sailed straight through them (measured: the security-reviewer
        // injected exactly that and got a 10/10 GREEN baseline). Scope the
        // check to the blocked-integrity area specifically and assert there
        // is no `ButtonStyleButton` of ANY variant (Filled/Outlined/Text/
        // Elevated all extend it) and no bare `InkWell` tap target either —
        // there must be NO way to turn this area into an activation control,
        // however it is styled.
        final blockedArea = find.byKey(
          const Key('modelManagerBlockedIntegrity'),
        );
        expect(blockedArea, findsOneWidget);
        expect(
          find.descendant(
            of: blockedArea,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
          findsNothing,
          reason:
              'covers FilledButton/OutlinedButton/TextButton/ElevatedButton — '
              'i.e. every SsButton variant, not just the two checked above',
        );
        expect(
          find.descendant(of: blockedArea, matching: find.byType(InkWell)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: blockedArea,
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('at threshold: a verified model activates and shows active', (
      tester,
    ) async {
      final bytes = const [4, 5, 6];
      await pump(
        tester,
        _ScriptedSource(
          Success(_asset(bytes: bytes, declared: offlineModelChecksum(bytes))),
        ),
      );

      await tester.tap(find.text('Check for model'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Verified and active'), findsOneWidget);
      expect(find.text('Roll back to previous version'), findsNothing);
    });

    testWidgets(
      // Javító kör 1, F5: a fetch/network failure must not read like — or
      // dead-end like — a tampered-model alarm. The Check action stays, and
      // neither the checksum-blocked text nor the blocked-integrity area
      // (which is button-free BY DESIGN, A6) is shown for it.
      'a fetch failure keeps the Check action available and does not show '
      'the checksum-blocked message',
      (tester) async {
        await pump(tester, _ScriptedSource(const Failure(NetworkFailure())));

        await tester.tap(find.text('Check for model'));
        await tester.pumpAndSettle();

        expect(
          find.text("Not activated — checksum could not be verified"),
          findsNothing,
        );
        expect(
          find.byKey(const Key('modelManagerBlockedIntegrity')),
          findsNothing,
        );
        expect(find.byKey(const Key('modelManagerCheck')), findsOneWidget);
        final checkButton = tester.widget<SsButton>(
          find.byKey(const Key('modelManagerCheck')),
        );
        expect(checkButton.onPressed, isNotNull);
      },
    );
  });
}
