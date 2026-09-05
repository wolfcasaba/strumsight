// A beépített gyakorlat-katalógus és a tervezői metaadat mérése.
//
// MÉRT hiány (2026-09-05): a fában NEM volt éles `PracticeCatalogReader` —
// csak tesztekben. Emiatt az `exerciseCandidateResolverProvider` élesben
// `UnimplementedError`-t dobott, és a gyakorlástervező négy képernyője
// elérhetetlen maradt.
//
// A cellák nem azt mérik, hogy „van adat", hanem hogy a SZERZETT tervezői
// besorolás azt mondja, amit a gitárpedagógia — és hogy a katalógus meg a
// tábla nem tud szétcsúszni.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/public.dart'
    show BuiltinPracticeCatalog;
import 'package:strumsight/features/practice_generator/data/catalog/builtin_catalog_metadata.dart';
import 'package:strumsight/features/practice_generator/data/catalog/builtin_catalog_reader.dart';
import 'package:strumsight/features/practice_generator/data/generation/generation_plan_input_assembler.dart';
import 'package:strumsight/features/practice_generator/domain/model/exercise_candidate.dart';

void main() {
  const reader = BuiltinPracticeCatalogReader();

  group('a katalógus minden beépített gyakorlatot átenged', () {
    test('F1 — nincs kizárt jelölt', () {
      final snapshot = reader.read();

      // Az adapter a hiányzó metaadatú jelöltet KIZÁRJA, figyelmeztetéssel.
      // Egy üres warnings-lista tehát azt méri, hogy MINDEN gyakorlat
      // teljes metaadatot kapott — nem azt, hogy az adapter elnéző.
      expect(snapshot.warnings, isEmpty);
      expect(
        snapshot.candidates.length,
        const BuiltinPracticeCatalog().all().length,
      );
    });

    test('F2 — a tábla és a katalógus nem csúszhat szét', () {
      // Ha valaki új gyakorlatot vesz fel profil nélkül, ez a cella pirosra
      // vált — nem az F1, ami csak a kizárást nézné.
      final definitionIds = <String>{
        for (final definition in const BuiltinPracticeCatalog().all())
          definition.id,
      };

      expect(profiledExerciseIds(), definitionIds);
    });
  });

  group('a szerzett terhelési profil a gitárpedagógiát követi', () {
    ExerciseCandidate candidate(String id) =>
        reader.read().candidates.firstWhere((c) => c.exerciseId == id);

    test('F3 — a legelső gyakorlat a legkisebb terhelésű', () {
      // A tanítási sorrend legelső eleme a csupa lefelé pengetés: egyetlen
      // elem (ritmus), akkord-cél nélkül.
      final first = candidate('builtin.quarterDownstrokes.v1');

      expect(first.loadProfile.cognitive, LoadLevel.low);
      expect(first.loadProfile.frettingHand, LoadLevel.low);
      expect(first.loadProfile.pickingHand, LoadLevel.low);
    });

    test('F4 — a G→D fogó-kéz terhelése NAGYOBB, mint az Em→C-é', () {
      // Ez a cella a pedagógiai különbséget rögzíti, nem ízlést: a G→D
      // váltásban nincs horgony-ujj (minden ujj felemelkedik), az Em→C-ben
      // viszont a 2. ujj a helyén marad. Ha valaki a két profilt
      // egyformára állítja, ez pirosra vált.
      final gToD = candidate('builtin.gToDChanges.v1');
      final emToC = candidate('builtin.emToCChanges.v1');

      expect(
        gToD.loadProfile.frettingHand.index,
        greaterThan(emToC.loadProfile.frettingHand.index),
      );
    });

    test('F5 — az F-et tartalmazó menet fogó-keze a legnehezebb', () {
      // Az F a kezdők legnehezebb akkordja: az első érintőn teljes barré,
      // ahol a húrfeszülés a legnagyobb.
      final progression = candidate('builtin.cGAmFProgression.v1');

      expect(progression.loadProfile.frettingHand, LoadLevel.high);
      expect(progression.prerequisites, contains('chord.fMajor'));
    });

    test('F6 — a szinkópált gyakorlat pengető keze a legnehezebb', () {
      final syncopated = candidate('builtin.syncopatedUps.v1');
      final alternating = candidate('builtin.alternatingEighths.v1');

      expect(syncopated.loadProfile.pickingHand, LoadLevel.high);
      // Kontroll: a váltakozó nyolcad a SORRENDBEN előbb áll, tehát
      // könnyebb — a hármas így a sorrendet méri, nem egy önkényes címkét.
      expect(
        alternating.loadProfile.pickingHand.index,
        lessThan(syncopated.loadProfile.pickingHand.index),
      );
    });

    test('F7 — minden gyakorlat előfeltétele a hangolt gitár', () {
      for (final candidate in reader.read().candidates) {
        expect(
          candidate.prerequisites,
          contains(prerequisiteTunedGuitar),
          reason: candidate.exerciseId,
        );
      }
    });
  });

  group('a beosztás felé menő terhelési szint', () {
    test('F8 — a domináns szint a MAXIMUM, nem az átlag', () {
      // Egy egyébként könnyű gyakorlat, aminek EGY dimenziója nehéz (pl. az
      // F barré fogó-keze), átlagolva közepesnek látszana, és a beosztó
      // könnyebbnek hinné, mint amilyen.
      const mostlyLow = ExerciseLoadProfile(
        cognitive: LoadLevel.low,
        frettingHand: LoadLevel.high,
        pickingHand: LoadLevel.low,
        repetition: LoadLevel.low,
        novelty: LoadLevel.low,
        concentration: LoadLevel.low,
      );

      expect(dominantLoadLevel(mostlyLow), LoadLevel.high);
      // Kontroll: a csupa alacsony profil alacsony marad — a függvény nem
      // „mindig high"-ot ad.
      expect(
        dominantLoadLevel(const ExerciseLoadProfile.all(LoadLevel.low)),
        LoadLevel.low,
      );
    });
  });
}
