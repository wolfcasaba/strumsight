// A3/A4 — the analyzer-leak severity ladder on the import surfaces (ADR 0284
// §Döntés 3, round brief §0.0/B/R8 + §6.1's four measured-input rows):
//
//   below threshold — no warnings at all: no lelet-region, confirm enabled.
//   at threshold    — a real, non-`fatal.` warning code: shown, confirm
//                      still enabled.
//   above threshold (a) — a `fatal.`-prefixed PREVIEW warning (the pin
//                      test's synthetic producer): confirm disabled.
//   above threshold (b) — the REAL blocking producer, `SongImportPhase
//                      .failure` + `failureCode` (an `ImportRegistryException`
//                      from the registry, e.g. `MusicXmlImportFailureCode
//                      .doctypeForbidden`): the failure is NAMED and there is
//                      ZERO confirm/"continue anyway" affordance.
//
// A4 requires the warning and the blocking cases to differ both visually
// (icon, color role) and semantically (Semantics label) — never just a
// louder version of the same look.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/import/import_preview.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_controller.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_state.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/importer_registry.dart';
import 'package:strumsight/features/song_trainer/data/importers/musicxml_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/musicxml_mapper.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_import_preview_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_import_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

void main() {
  Widget previewApp(ImportPreview preview) => ProviderScope(
    child: MaterialApp(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SongImportPreviewScreen(preview: preview),
    ),
  );

  testWidgets(
    'below threshold: no warnings means no lelet-region and confirm enabled',
    (tester) async {
      await tester.pumpWidget(
        previewApp(
          ImportPreview(
            displayName: 'clean.musicxml',
            byteLength: 10,
            format: 'MusicXML',
            warnings: const <String>[],
          ),
        ),
      );

      expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'at threshold: a real non-fatal warning code is shown as a warning and '
    'confirm stays enabled',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        previewApp(
          ImportPreview(
            displayName: 'quantized.musicxml',
            byteLength: 10,
            format: 'MusicXML',
            warnings: const <String>[MusicXmlMapWarningCode.timingQuantized],
          ),
        ),
      );

      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^Import warning: ${RegExp.escape(MusicXmlMapWarningCode.timingQuantized)}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'above threshold (a): a fatal.-prefixed preview warning disables confirm '
    'and looks/reads distinct from a warning',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        previewApp(
          ImportPreview(
            displayName: 'bad.mid',
            byteLength: 3,
            format: 'MIDI',
            warnings: const <String>['fatal.unsupported'],
          ),
        ),
      );

      // PONTOSAN EGY FilledButton (R7 pin) — disabled, no bypass.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      // Visually distinct from the warning case: error icon + error color
      // role, not the warning icon/color.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
      // Semantically distinct: a different Semantics label prefix.
      expect(
        find.bySemanticsLabel(RegExp('^Fatal import issue: fatal.unsupported')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'above threshold (b): the real SongImportPhase.failure + failureCode '
    'names the blocking error and offers zero confirm/"continue anyway" '
    'affordance',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = SongImportController(
        registry: ImporterRegistry(
          importers: <SongImporter>[
            _AlwaysBlockingImporter(MusicXmlImportFailureCode.doctypeForbidden),
          ],
        ),
        repository: InMemorySongRepository(),
        workspaceRoot: () async =>
            throw StateError('workspace is not used before confirmPreview'),
      );
      addTearDown(controller.dispose);
      final picker = _OneShotPicker(
        ImportSourceFile(
          displayName: 'evil.musicxml',
          byteLength: 4,
          openRead: () => Stream<List<int>>.value(<int>[1, 2, 3, 4]),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            songImportControllerProvider.overrideWithValue(controller),
            songFilePickerAdapterProvider.overrideWithValue(picker),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SongImportScreen(),
          ),
        ),
      );

      controller.requestSelection();
      await tester.pumpAndSettle();

      expect(controller.state.phase, SongImportPhase.failure);
      expect(
        controller.state.failureCode,
        MusicXmlImportFailureCode.doctypeForbidden,
      );

      // The failure is NAMED — the exact failureCode is on screen.
      expect(
        find.textContaining(MusicXmlImportFailureCode.doctypeForbidden),
        findsOneWidget,
      );
      // Same blocking visual language as the preview's fatal case: error
      // icon + error color role, distinct from the (unused here) warning
      // styling.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^Blocking import error: '
            '${RegExp.escape(MusicXmlImportFailureCode.doctypeForbidden)}',
          ),
        ),
        findsOneWidget,
      );

      // Zero confirm/"continue anyway" affordance: the only action offered
      // is "Choose a file" (a fresh pick, not confirming the blocked one),
      // and there is no `songImportConfirm`-labelled control anywhere.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SongImportScreen)),
      );
      expect(find.text(l10n.songImportConfirm), findsNothing);
      expect(find.text(l10n.songImportChooseFile), findsOneWidget);
      semantics.dispose();
    },
  );
}

/// Recognises everything by extension but always fails the content probe —
/// the real `ImportRegistryException` producer path
/// (`ImporterRegistry.probe` → no importer recognises → throws), not the
/// pin test's synthetic `fatal.` preview warning.
final class _AlwaysBlockingImporter implements SongImporter {
  const _AlwaysBlockingImporter(this._failureCode);

  final String _failureCode;

  @override
  Set<String> get supportedExtensions => const <String>{'musicxml'};

  @override
  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) async => ImportProbeResult.failure(_failureCode);

  @override
  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  ) => throw UnimplementedError('probe always fails before import() is used');
}

final class _OneShotPicker implements FilePickerAdapter {
  _OneShotPicker(this._source);

  ImportSourceFile? _source;

  @override
  Future<void> dispose() async {}

  @override
  Future<ImportSourceFile?> pickSongFile() async {
    final source = _source;
    _source = null;
    return source;
  }
}
