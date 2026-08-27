// E13-R28 — A7: a sync conflict offers a real choice, never a silent
// overwrite (§5.6, ADR 0277, L06). §0.0/B3 measured that no sync-conflict
// storage type exists anywhere on the tree — this is `library_v2`'s own
// presentational model, and resolving it only calls the caller-supplied
// callback; it never writes a store.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/library_v2/domain/library_sync_conflict.dart';
import 'package:strumsight/features/library_v2/widgets/library_sync_conflict_view.dart';
import 'package:strumsight/l10n/app_localizations.dart';

final _conflict = LibrarySyncConflict(
  itemId: 'conflicted-item',
  localDescription: 'Recorded 3 minutes ago, on this device',
  localUpdatedAt: DateTime.utc(2026, 8, 20, 9),
  remoteDescription: 'Synced yesterday from another device',
  remoteUpdatedAt: DateTime.utc(2026, 8, 19),
);

Future<List<LibrarySyncResolution>> _pump(WidgetTester tester) async {
  final resolutions = <LibrarySyncResolution>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LibrarySyncConflictView(
          conflict: _conflict,
          onResolve: resolutions.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return resolutions;
}

void main() {
  group('A7 — both versions are shown and the user chooses', () {
    testWidgets('both the local and remote descriptions render', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text(_conflict.localDescription), findsOneWidget);
      expect(find.text(_conflict.remoteDescription), findsOneWidget);
    });

    testWidgets('choosing "keep local" resolves with keepLocal exactly once', (
      tester,
    ) async {
      final resolutions = await _pump(tester);

      await tester.tap(
        find.byKey(const ValueKey('library-sync-conflict-keep-local')),
      );
      await tester.pumpAndSettle();

      expect(resolutions, [LibrarySyncResolution.keepLocal]);
    });

    testWidgets(
      'choosing "keep remote" resolves with keepRemote exactly once',
      (tester) async {
        final resolutions = await _pump(tester);

        await tester.tap(
          find.byKey(const ValueKey('library-sync-conflict-keep-remote')),
        );
        await tester.pumpAndSettle();

        expect(resolutions, [LibrarySyncResolution.keepRemote]);
      },
    );
  });

  group('A7 — resolving a conflict never writes a store', () {
    test(
      'no forbidden storage primitive appears in the conflict view source',
      () {
        final source = File(
          'lib/features/library_v2/widgets/library_sync_conflict_view.dart',
        ).readAsStringSync();
        for (final token in [
          'JsonDocumentStore',
          'JsonCollectionStore',
          'keyValueStoreProvider',
          '.save(',
          '.write(',
        ]) {
          expect(
            source.contains(token),
            isFalse,
            reason: 'library_sync_conflict_view.dart must not reference $token',
          );
        }
      },
    );
  });
}
