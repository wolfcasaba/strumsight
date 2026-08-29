import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_controller.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/importer_registry.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_import_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

void main() {
  testWidgets('idle import screen offers a local file picker action', (
    tester,
  ) async {
    final picker = _FakeFilePickerAdapter();
    final controller = SongImportController(
      registry: const ImporterRegistry(importers: []),
      repository: InMemorySongRepository(),
      workspaceRoot: () async => throw StateError('workspace is not used'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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

    expect(find.text('Choose a file'), findsOneWidget);
    await tester.tap(find.text('Choose a file'));
    await tester.pump();

    expect(picker.pickCalls, 1);

    // Unmounting first releases the effect subscription before controller
    // teardown runs.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _FakeFilePickerAdapter implements FilePickerAdapter {
  var pickCalls = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<ImportSourceFile?> pickSongFile() async {
    pickCalls++;
    return null;
  }
}
