import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  testWidgets('empty library offers an import entry point', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SongLibraryScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('No songs yet. Import a file to start your library.'),
      findsOneWidget,
    );
    expect(find.text('Import'), findsOneWidget);
  });
}
