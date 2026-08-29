import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_import_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/guitar_pro_conversion_guidance.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

void main() {
  Widget app({Locale locale = const Locale('en')}) => ProviderScope(
    overrides: [
      songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
    ],
    child: MaterialApp(
      theme: SsLightTheme.data(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SongImportScreen(),
    ),
  );

  testWidgets('English guidance describes the offline conversion-only path', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    expect(find.byType(SongImportScreen), findsOneWidget);
    expect(find.byType(GuitarProConversionGuidance), findsOneWidget);
    expect(find.text('Convert a Guitar Pro file'), findsOneWidget);
    expect(
      find.textContaining('does not import Guitar Pro files directly'),
      findsOneWidget,
    );
    expect(find.textContaining('MusicXML, MXL, or MIDI'), findsNWidgets(2));
    expect(find.textContaining('may not be preserved'), findsOneWidget);
  });

  testWidgets(
    'Hungarian guidance is localized and exposes a screen-reader summary',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(locale: const Locale('hu')));

      expect(find.text('Guitar Pro fájl átalakítása'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Guitar Pro átalakítási útmutató. A Guitar Pro fájlokat a StrumSight '
          'nem importálja közvetlenül. A saját fájlodat a StrumSighton kívül '
          'alakítsd MusicXML, MXL vagy MIDI formátumba. Nincs feltöltés.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Offline munkafolyamat'), findsOneWidget);
      semantics.dispose();
    },
  );
}
