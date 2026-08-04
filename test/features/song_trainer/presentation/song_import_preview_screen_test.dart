import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/import/import_preview.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_import_preview_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  testWidgets('fatal preview disables the import confirmation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SongImportPreviewScreen(
            preview: ImportPreview(
              displayName: 'bad.mid',
              byteLength: 3,
              format: 'MIDI',
              warnings: const <String>['fatal.unsupported'],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Import song'), findsOneWidget);
    expect(find.text('File size: 3 bytes'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
