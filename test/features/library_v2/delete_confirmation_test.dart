// E13-R28 — A4 (the delete confirmation names its scope) and A5 (the
// surface never implements deletion itself — a use case is always called).
//
// The three mandatory §6.1 cells: raw-only, result-only and everything —
// each must state a DIFFERENT consequence, naming what survives (or that
// nothing does).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/library_v2/domain/library_delete_actions.dart';
import 'package:strumsight/features/library_v2/domain/library_delete_scope.dart';
import 'package:strumsight/features/library_v2/domain/library_item.dart';
import 'package:strumsight/features/library_v2/widgets/library_delete_section.dart';
import 'package:strumsight/features/library_v2/widgets/library_theme_scope.dart';
import 'package:strumsight/l10n/app_localizations.dart';

final class _RecordingDeleteActions implements LibraryDeleteActions {
  final calls = <(String, LibraryDeleteScope)>[];

  @override
  Future<AppResult<void>> delete(String id, LibraryDeleteScope scope) async {
    calls.add((id, scope));
    return const AppResult<void>.success(null);
  }
}

Future<void> _pump(
  WidgetTester tester,
  AnalysisLibraryItem item,
  LibraryDeleteActions actions,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LibraryThemeScope(
          child: LibraryDeleteSection(
            item: item,
            actions: actions,
            onDeleted: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  final fullItem = AnalysisLibraryItem(
    id: 'delete-me',
    title: 'Deletable Session',
    createdAt: DateTime.utc(2026, 8, 1),
    syncStatus: LibrarySyncStatus.synced,
    hasRawAudio: true,
    hasResult: true,
  );

  group(
    '§6.1 — the three delete-scope cells each name a different consequence',
    () {
      testWidgets('raw-only: the confirmation states the result remains', (
        tester,
      ) async {
        final actions = _RecordingDeleteActions();
        await _pump(tester, fullItem, actions);

        await tester.tap(find.byKey(const ValueKey('library-delete-raw-only')));
        await tester.pumpAndSettle();

        expect(find.text(l10n.libraryV2DeleteRawConsequence), findsOneWidget);
        expect(find.text(l10n.libraryV2DeleteResultConsequence), findsNothing);
        expect(
          find.text(l10n.libraryV2DeleteEverythingConsequence),
          findsNothing,
        );

        await tester.tap(find.byKey(const ValueKey('ss-confirmation-confirm')));
        await tester.pumpAndSettle();

        expect(actions.calls, [('delete-me', LibraryDeleteScope.rawOnly)]);
      });

      testWidgets(
        'result-only: the confirmation states the raw recording remains',
        (tester) async {
          final actions = _RecordingDeleteActions();
          await _pump(tester, fullItem, actions);

          await tester.tap(
            find.byKey(const ValueKey('library-delete-result-only')),
          );
          await tester.pumpAndSettle();

          expect(
            find.text(l10n.libraryV2DeleteResultConsequence),
            findsOneWidget,
          );
          expect(find.text(l10n.libraryV2DeleteRawConsequence), findsNothing);

          await tester.tap(
            find.byKey(const ValueKey('ss-confirmation-confirm')),
          );
          await tester.pumpAndSettle();

          expect(actions.calls, [('delete-me', LibraryDeleteScope.resultOnly)]);
        },
      );

      testWidgets('everything: the confirmation states it is irreversible', (
        tester,
      ) async {
        final actions = _RecordingDeleteActions();
        await _pump(tester, fullItem, actions);

        await tester.tap(
          find.byKey(const ValueKey('library-delete-everything')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.libraryV2DeleteEverythingConsequence),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('ss-confirmation-confirm')));
        await tester.pumpAndSettle();

        expect(actions.calls, [('delete-me', LibraryDeleteScope.everything)]);
      });
    },
  );

  group(
    'A5 — the surface never implements deletion itself (machine-checked)',
    () {
      test(
        'no forbidden storage primitive appears anywhere under lib/features/library_v2/',
        () {
          final forbidden = [
            'JsonDocumentStore',
            'JsonCollectionStore',
            'keyValueStoreProvider',
            '.save(',
            '.write(',
          ];
          final offenders = <String>[];
          final dir = Directory('lib/features/library_v2');
          for (final entity in dir.listSync(recursive: true)) {
            if (entity is! File || !entity.path.endsWith('.dart')) continue;
            final source = entity.readAsStringSync();
            for (final token in forbidden) {
              if (source.contains(token)) {
                offenders.add('${entity.path}: $token');
              }
            }
          }
          expect(offenders, isEmpty, reason: offenders.join('\n'));
        },
      );
    },
  );
}
