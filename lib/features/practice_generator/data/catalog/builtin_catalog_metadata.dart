/// A beépített gyakorlatok tervezői metaadata (2026-09-05).
///
/// **Miért kell.** A `PracticeEngineCatalogAdapter` négy mezőt vár a hívótól,
/// mert a `PracticeDefinition` nem hordozza őket, és a hiányzót NEM pótolja
/// alapértékkel: kizárja a jelöltet egy figyelmeztetéssel. Ez szándékos őr —
/// a kód megtagadja a kitalált adatot. Amíg ez a tábla nem létezett, a
/// katalógus üres volt, és emiatt dobott a `exerciseCandidateResolverProvider`.
///
/// **A négyből három levezetett, egy szerzett.**
///
/// * `offlineAvailable` — MÉRT tény: a beépített gyakorlatok a csomagban
///   vannak, hálózat nélkül is futnak. Mind a tíznél `true`.
/// * `contentRevision` — a definíció `schemaVersion`-jéből képzett, nem
///   kitalált érték.
/// * `prerequisites` — a `guitar.tuned` minden gyakorlatra igaz (a fixture-ök
///   már használt konvenciója); az akkordos gyakorlatok emellett a saját
///   akkordjaikat követelik.
/// * `loadProfile` — **SZERZETT**, a gyakorlat SAJÁT tartalmából és a
///   gitártanítás bevett sorrendjéből levezetve. A levezetés minden
///   gyakorlatnál kiírva olvasható alább.
///
/// ## A hat dimenzió értelmezése
///
/// A kognitív terhelést az *elem-interaktivitás* adja: a kognitívterhelés-
/// elmélet szerint egy feladat belső (intrinsic) terhelése azon múlik, hány
/// elemet kell EGYSZERRE a munkamemóriában tartani, és a zenetanulás
/// kifejezetten magas belső terhelésű, mert a ritmus, a hangmagasság és a
/// dinamika egyszerre hat egymásra. Ezért itt megszámoljuk, hány elemet
/// követel a gyakorlat egyidejűleg:
///
/// | elemek száma | szint |
/// |---|---|
/// | 1 (csak ritmus) | `low` |
/// | 2 (ritmus + irány VAGY ritmus + akkordváltás) | `medium` |
/// | 3+ (ritmus + irány + akkordforma + váltás) | `high` |
///
/// * **`frettingHand`** — a fogó kéz terhelése. Akkord-cél nélkül `low`.
///   Nyitott akkordok közti váltás **horgony-ujjal** `medium`; horgony-ujj
///   NÉLKÜLI váltás vagy barré `high`.
/// * **`pickingHand`** — a pengető kéz terhelése a tanítási sorrend szerint:
///   negyed lefelé (`low`) → folyamatos nyolcad váltakozás (`medium`) →
///   ütemsúlyon kívüli, szinkópált helyzetek (`high`).
/// * **`repetition`** — mennyire ismétlődő a tartalom. Egyetlen, végig
///   ismételt sejt `high`; ütemenként változó tartalom `medium`/`low`.
/// * **`novelty`** — mennyi ÚJ anyag van benne egy végigjátszás alatt.
/// * **`concentration`** — a tartós figyelem igénye: a sűrűség, a hossz és a
///   hibázás költsége együtt.
///
/// **Források a szerzett értékek mögött.** A tanítási sorrend (csak lefelé →
/// váltakozó → akkordváltás → szinkópa), az F barré mint a legnehezebb kezdő
/// akkord (első érintő, magasabb húrfeszülés, teljes barré), a G→D váltás
/// horgony-ujj NÉLKÜLI volta (minden ujj felemelkedik), és az Em→C váltás
/// horgony-ujja (a 2. ujj a D húron marad) — mind a gitárpedagógiai
/// gyakorlatból, nem a fejlesztő becsléséből.
///
/// **Amit ez a tábla NEM tesz.** Nem méri a felhasználót és nem állít
/// tudományos pontosságot. Tervezői besorolás, amit a `low`/`medium`/`high`
/// hármas szándékosan durvára is fog. Ha egy érték rossznak bizonyul, ez az
/// EGY hely, ahol javítani kell.
library;

import 'package:strumsight/features/practice/public.dart'
    show BuiltinPracticeCatalog, PracticeDefinition;

import '../../domain/model/exercise_candidate.dart';
import '../adapter/practice_engine_catalog_adapter.dart';

/// Minden gyakorlat előfeltétele: hangolt gitár. A `PracticeCatalogEntry`
/// üres listát nem fogad el, és ez a követelmény minden gyakorlatra IGAZ —
/// nem töltelék.
const String prerequisiteTunedGuitar = 'guitar.tuned';

/// A hat dimenzió egy gyakorlatra, a levezetés indoklásával.
final class _Profile {
  const _Profile(this.loadProfile, this.prerequisites);

  final ExerciseLoadProfile loadProfile;
  final List<String> prerequisites;
}

const LoadLevel _low = LoadLevel.low;
const LoadLevel _mid = LoadLevel.medium;
const LoadLevel _high = LoadLevel.high;

ExerciseLoadProfile _profile({
  required LoadLevel cognitive,
  required LoadLevel frettingHand,
  required LoadLevel pickingHand,
  required LoadLevel repetition,
  required LoadLevel novelty,
  required LoadLevel concentration,
}) => ExerciseLoadProfile(
  cognitive: cognitive,
  frettingHand: frettingHand,
  pickingHand: pickingHand,
  repetition: repetition,
  novelty: novelty,
  concentration: concentration,
);

/// Gyakorlat-azonosító → tervezői profil.
final Map<String, _Profile> _metadata = <String, _Profile>{
  // 1. Negyed lefelé pengetések. A tanítási sorrend LEGELSŐ eleme: „a
  //    legalapvetőbb pengetés a kezdőnek a csupa lefelé". Egyetlen elem
  //    (ritmus), állandó irány, akkord-cél nélkül. Végig azonos sejt.
  'builtin.quarterDownstrokes.v1': _Profile(
    _profile(
      cognitive: _low,
      frettingHand: _low,
      pickingHand: _low,
      repetition: _high,
      novelty: _low,
      concentration: _low,
    ),
    const <String>[prerequisiteTunedGuitar],
  ),

  // 2. Váltakozó nyolcadok. A sorrend MÁSODIK foka, és a forrás szerint
  //    „minden összetettebb pengetés alapja". Két elem: ritmus + irány.
  //    Kétszeres eseménysűrűség ugyanazon a tempón → a figyelem igénye nő.
  'builtin.alternatingEighths.v1': _Profile(
    _profile(
      cognitive: _mid,
      frettingHand: _low,
      pickingHand: _mid,
      repetition: _high,
      novelty: _low,
      concentration: _mid,
    ),
    const <String>[prerequisiteTunedGuitar],
  ),

  // 3. Folk-minta (D - D U - U D U). A folyamatos mozgásba ÉKELT szünetek
  //    a szinkópa alapkészsége — a pengető kéz megy tovább, de nem szólal
  //    meg minden nyolcadon. Ütemenként belül változó tartalom, ezért az
  //    ismétlés csak közepes.
  'builtin.folkPattern.v1': _Profile(
    _profile(
      cognitive: _mid,
      frettingHand: _low,
      pickingHand: _high,
      repetition: _mid,
      novelty: _mid,
      concentration: _high,
    ),
    const <String>[prerequisiteTunedGuitar],
  ),

  // 4. G ↔ D váltás. A fogó kéz terhelése MAGAS, és ez nem becslés: a G→D
  //    váltásban NINCS horgony-ujj — minden ujj felemelkedik, és mindegyiket
  //    a semmiből kell visszatenni. Ezért nehezebb, mint az Em↔C (5.), noha
  //    mindkettő nyitott akkord. A pengetés negyed lefelé, tehát könnyű.
  'builtin.gToDChanges.v1': _Profile(
    _profile(
      cognitive: _mid,
      frettingHand: _high,
      pickingHand: _low,
      repetition: _high,
      novelty: _low,
      concentration: _mid,
    ),
    const <String>[
      prerequisiteTunedGuitar,
      'chord.gMajor',
      'chord.dMajor',
    ],
  ),

  // 5. Em ↔ C váltás. KÖZEPES fogó-kéz terhelés: a váltásnak van horgony-
  //    ujja (a 2. ujj a D húron marad), tehát nem minden ujj mozdul. Ez a
  //    különbség a 4. gyakorlathoz képest a mért pedagógiai különbség, nem
  //    ízlés kérdése.
  'builtin.emToCChanges.v1': _Profile(
    _profile(
      cognitive: _mid,
      frettingHand: _mid,
      pickingHand: _low,
      repetition: _high,
      novelty: _low,
      concentration: _mid,
    ),
    const <String>[
      prerequisiteTunedGuitar,
      'chord.eMinor',
      'chord.cMajor',
    ],
  ),

  // 6. C / G / Am / F akkordmenet. A fogó kéz terhelése MAGAS az F miatt: az
  //    F a kezdők legnehezebb akkordja — az első érintőn kell teljes barrét
  //    fogni, ahol a húrfeszülés a legnagyobb. A kognitív terhelés is magas:
  //    négy elem hat egyszerre (ritmus + irány + négy akkordforma + három
  //    váltás). Négy KÜLÖNBÖZŐ ütem → magas újdonság, közepes ismétlés.
  //    A definíció maga is `intermediate` nehézségűnek jelöli.
  'builtin.cGAmFProgression.v1': _Profile(
    _profile(
      cognitive: _high,
      frettingHand: _high,
      pickingHand: _low,
      repetition: _mid,
      novelty: _high,
      concentration: _high,
    ),
    const <String>[
      prerequisiteTunedGuitar,
      'chord.cMajor',
      'chord.gMajor',
      'chord.aMinor',
      'chord.fMajor',
    ],
  ),

  // 7. Keringő 3/4-ben (D U U). Az ÚJ elem itt az ütemmutató: a 3/4 az első
  //    kilépés a négynegyedből, ezért az újdonság közepes. A pengetés
  //    ütemenként azonos alakzat, akkord-cél nélkül.
  'builtin.firstWaltz.v1': _Profile(
    _profile(
      cognitive: _mid,
      frettingHand: _low,
      pickingHand: _mid,
      repetition: _high,
      novelty: _mid,
      concentration: _mid,
    ),
    const <String>[prerequisiteTunedGuitar],
  ),

  // 8. Szinkópált felfelé pengetések az ütemsúly UTÁNI nyolcadokon. A
  //    források szerint ez a pengető kéz legnehezebb kezdő készsége: a
  //    felfelé mozgást kell hangsúlyozni úgy, hogy a le-fel mozgás
  //    folyamatos marad. A definíció is `intermediate`.
  'builtin.syncopatedUps.v1': _Profile(
    _profile(
      cognitive: _high,
      frettingHand: _low,
      pickingHand: _high,
      repetition: _high,
      novelty: _mid,
      concentration: _high,
    ),
    const <String>[prerequisiteTunedGuitar],
  ),

  // 9. Csak ritmus. A pontozás sem irányt, sem akkordot nem néz — egyetlen
  //    elem marad. A katalógus legkisebb terhelésű gyakorlata; ez a
  //    visszatérési pont, ha a tervező könnyíteni akar.
  'builtin.rhythmOnlyQuarters.v1': _Profile(
    _profile(
      cognitive: _low,
      frettingHand: _low,
      pickingHand: _low,
      repetition: _high,
      novelty: _low,
      concentration: _low,
    ),
    const <String>[prerequisiteTunedGuitar],
  ),

  // 10. Szabad gyakorlás. Nincs előírt esemény és nincs pontozás, tehát
  //     nincs mit ismételni sem — az ismétlés `low`, nem `high`. Ez a
  //     különbség a 9.-hez képest: ott előírt sejt ismétlődik, itt semmi
  //     nincs előírva.
  'builtin.freePracticeTemplate.v1': _Profile(
    _profile(
      cognitive: _low,
      frettingHand: _low,
      pickingHand: _low,
      repetition: _low,
      novelty: _low,
      concentration: _low,
    ),
    const <String>[prerequisiteTunedGuitar],
  ),
};

/// A beépített gyakorlatok katalógus-bejegyzései.
///
/// A táblában NEM szereplő definíció bejegyzés nélkül marad — az adapter
/// ilyenkor kizárja, figyelmeztetéssel. Ez szándékos: egy új gyakorlat
/// profil nélkül NEM kerülhet be a tervezőbe csak azért, mert létezik.
List<PracticeCatalogEntry> builtinCatalogEntries() {
  final entries = <PracticeCatalogEntry>[];
  for (final definition in const BuiltinPracticeCatalog().all()) {
    final metadata = _metadata[definition.id];
    if (metadata == null) continue;
    entries.add(
      PracticeCatalogEntry(
        definition: definition,
        prerequisites: metadata.prerequisites,
        offlineAvailable: true,
        contentRevision: _contentRevision(definition),
        loadProfile: metadata.loadProfile,
      ),
    );
  }
  return List<PracticeCatalogEntry>.unmodifiable(entries);
}

/// Azok a definíció-azonosítók, amelyekhez VAN profil. A teszt ebből méri,
/// hogy a katalógus és a tábla nem csúszott szét.
Set<String> profiledExerciseIds() => Set<String>.unmodifiable(_metadata.keys);

String _contentRevision(PracticeDefinition definition) =>
    'builtin.v${definition.schemaVersion}';
