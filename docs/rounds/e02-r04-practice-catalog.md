# E02-R04 — Practice catalog és beépített gyakorlatok

- **Státusz:** PLANNING (indítás: 2026-07-30, kód olvasva: `main @ be6bad0`)
- **SDD:** `docs/sdd/03-epic-02-practice-engine.md` — „Kör 4 — Practice catalog és beépített gyakorlatok"
- **Előfeltétel:** E02-R03 merge-ölve (PR #24) — a domain-szerződések készen állnak
- **Implementer motor:** **MiniMax M3** ([ADR 0069](../adr/0069-two-engine-implementer-pool.md) §15.6 besorolás: `const` adatkatalógus = volumenmunka)
- **Indítás:** `tools/mm-round.sh <munkapéldány> docs/rounds/e02-r04-practice-catalog.md /tmp/mm-e02-r04.log`
- **Kiosztott ADR:** **0070** — a katalógus-szerződés. **Az ADR-t Claude írja; az implementer NEM hoz létre és NEM módosít `docs/adr/` fájlt.**

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

Te vagy ennek a körnek az IMPLEMENTERE. Nem te tervezel és nem te review-zol.
Probléma esetén a jelzés az ELSŐ lépés, nem az utolsó:

```bash
tools/codex-signal.sh progress "<egy sor>"   # opcionális, nem zárja le a kört
tools/codex-signal.sh done    "<egy sor>"    # lezárja: kész, minden gate zöld
tools/codex-signal.sh stopped "<egy sor>"    # lezárja: brief-ütközés, nincs mit implementálni
tools/codex-signal.sh blocked "<egy sor>"    # lezárja: a gate 3 javítási kísérlet után is piros
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne commitolj, ne
pusholj — a CI-dispatch, a PR és a merge Claude-oldal.

Ha bármelyik követelmény ütközik a §4 engedélyezett-fájllistával vagy egy
meglévő teszttel: **ÁLLJ MEG**, küldd a `stopped` jelzést, és jelentsd az
ütközést — ne kerüld meg csendben.

## 1. Cél

Egyetlen offline, `const` beépített gyakorlatkatalógus, legalább tíz valid
`PracticeDefinition`-nel, stabil ID-kkel, determinisztikus sorrenddel, mód- és
nehézség-szerinti szűréssel — plusz a domain-oldali repository-szerződés és egy
minimális Riverpod application-réteg. Hívó UI ebben a körben NEM készül; a
katalógus a Kör 5 (adapterek), Kör 6 (target compiler) és Kör 18 (perzisztencia)
bemenete.

## 2. Jelenlegi állapot (mért tények, `main @ be6bad0`)

### 2.1 Ami már kész (E02-R02 + E02-R03 — NEM e kör dolga újraírni)

- `lib/features/practice/domain/model/` — 17 pure-Dart fájl. A katalógus által
  használt típusok és pontos API-juk:
  - `PracticeDefinition` (`practice_definition.dart:19`) — `const` konstruktor,
    kötelező: `id, schemaVersion, titleKey, descriptionKey, mode, source, meter,
    defaultTempo, totalBeats, events, scoringProfile, skillTags`; opcionális:
    `sourceReference`, `difficulty` (alap: `beginner`). `validate()` ellenőrzi az
    esemény-rendezettséget, az ID- és pozíció-duplikátumot, a `totalBeats`
    **kizárólagos** felső korlátot és a profil↔mód egyezést.
  - `PracticeEvent` (`practice_event.dart:40`) — `id`, `position`, opcionális
    `duration`, `chord`, `direction`, `accent`, `optional`, `marker`.
  - `BeatPosition` (`beat_position.dart`) — 480 PPQ integer tick;
    `BeatPosition.quarters(n)`, `.eighths(n)`, `.sixteenths(n)`,
    `.eighthTriplets(n)`, `.fromTicks(n)`; `ticksPerBeat = 480`.
  - `Tempo(bpm)` — 30.0–300.0 zárt tartomány.
  - `Meter({required beatsPerBar, beatUnit = 4})` — támogatott `beatUnit`: {2,4,8}.
  - `PracticeMode` (`practice_mode.dart:4`) — `scoredDimensions` MÓDONKÉNT KÖTÖTT:
    `strumPattern` = {rhythm, direction}, `chordChanges` = {chord, rhythm},
    `chordProgression` = {rhythm, direction, chord}, `rhythmOnly` = {rhythm},
    `freePractice` = {} (üres).
  - `ScoringProfile` (`scoring_profile.dart:55`) — a súlyok egész százalékok, és
    ha a map nem üres, **pontosan 100**-ra kell összegződniük; a három ablakra
    `perfect <= good <= match` és mindhárom szigorúan pozitív.
  - `PracticeSource` — `builtin('builtin')` a mi értékünk.
  - `PracticeDifficulty` — `beginner` / `intermediate` / `advanced`.
- `ScoringProfile.legacyLearnParity` (`scoring_profile.dart:68`) — a Learn-parity
  baseline profil (rhythm 55 / direction 45, 280/50/120 ms). **BEFAGYASZTOTT**:
  ez a profil az E02-R01 baseline-mérce része, egyetlen mezője sem módosulhat.
- `isCanonicalPracticeChordLabel` (`practice_event.dart:35`) — a `chord` mező csak
  kereszttel írt dúr/moll címke lehet (`C, Cm, C#, C#m, D, … B, Bm`) vagy `null`.
  **`F#m` és `A#` igen, `Bb` és `Cmaj7` NEM.**

### 2.2 Gépi őrök, amik már védenek

- `test/features/practice/domain/domain_purity_test.dart` — a
  `lib/features/practice/domain/` fa alatt tiltja: `DateTime.now(`, `Stopwatch(`,
  `Random(`, `print(`, flutter/riverpod/dio/shared_preferences import, l10n import.
  **Az új `domain/repository/` fájl ennek az őrnek a hatálya alatt lesz.**
- `test/core/architecture_dependency_test.dart` — rétegfüggőségi guard.
- `test/features/practice/domain/practice_validation_test.dart` — a
  `PracticeValidationCode.values` halmazt tételesen kipinneli.

### 2.3 Ami MÉG NINCS (ezt hozza ez a kör)

- `lib/features/practice/` alatt csak `domain/model/` létezik — nincs
  `domain/repository/`, `data/`, `application/`.
- Nincs egyetlen `PracticeDefinition` példány sem a production kódban.
- `lib/l10n/app_en.arb`-ban négy „practice" kulcs van, egyik sem katalógus-cím.

### 2.4 Fontos következmény, amit a tervezés során mértem

`PracticeEvent.validate()` a **nem-marker** eseménytől megköveteli, hogy legyen
`chord` VAGY `direction` (`eventScorableMissing`). Ezért a `rhythmOnly` gyakorlat
eseményei is **kötelezően hordoznak `direction`-t** — a mód dönti el, hogy azt
pontozza-e, nem az adat. Ez nem hiba, hanem a szerződés; a katalógus ehhez
igazodik (§5.4).

## 3. Scope

### 3.1 Benne van

1. `PracticeCatalogRepository` domain-szerződés (pure interface).
2. `BuiltinPracticeCatalog` — `const` adat, ≥10 gyakorlat, determinisztikus sorrend.
3. Négy új `const ScoringProfile` a `legacyLearnParity` mellé (§5.3).
4. Minimális Riverpod application-réteg (repository-provider + katalógus-provider).
5. Unit-tesztek (§6).

### 3.2 NINCS benne (kifejezetten kívül)

- **ARB szövegek.** A definíciók csak KULCSOT hordoznak; a tényleges en/hu
  fordítás akkor kerül be, amikor az első UI-hívó megjelenik (Kör 12+). Az
  `lib/l10n/*.arb` ebben a körben **tilos zóna**.
- UI, képernyő, route, navigáció.
- Adapterek (Kör 5), target compiler (Kör 6), matcher/scorer (Kör 9–10).
- A legacy Learn/Song tartalom bármilyen módosítása.
- Bármilyen DSP/ML paraméter (AGENTS.md §9).

## 4. Engedélyezett fájlok

| Fájl | Miért |
|---|---|
| `lib/features/practice/domain/repository/practice_catalog_repository.dart` | ÚJ — pure repository-szerződés |
| `lib/features/practice/data/builtin_practice_catalog.dart` | ÚJ — `const` katalógus-adat |
| `lib/features/practice/application/practice_catalog_controller.dart` | ÚJ — Riverpod providerek |
| `lib/features/practice/domain/model/scoring_profile.dart` | a négy új `const` profil (§5.3) — **`legacyLearnParity` érintetlen** |
| `test/features/practice/data/builtin_practice_catalog_test.dart` | ÚJ — katalógus-tesztek |
| `test/features/practice/application/practice_catalog_controller_test.dart` | ÚJ — provider-tesztek |
| `test/features/practice/domain/scoring_profile_test.dart` | meglévő — az új profilok tesztjei ide jönnek |

**Tilos zóna** (ha bármelyikhez hozzá kellene nyúlni: MEGÁLLÁS és jelentés):
`lib/l10n/**`, `docs/adr/**`, `docs/rounds/**`, `HANDOFF.md`, `pubspec.yaml`,
`.github/**`, `lib/features/learn/**`, `lib/features/live/**`, `ml/**`,
`docs/rag/**`, minden `lib/features/practice/domain/model/*.dart` a
`scoring_profile.dart` KIVÉTELÉVEL, és minden meglévő teszt a
`scoring_profile_test.dart` kivételével.

## 5. Kötött architekturális döntések (ADR 0070 — nem újratárgyalhatók)

### 5.1 ID-séma

`builtin.<lowerCamelSlug>.v1` — pl. `builtin.quarterDownstrokes.v1`. Az ID
**stabil és perzisztálható**; tartalmi változás új `v2` ID-t kap, sosem
felülírást. Az ID-ben csak `[a-zA-Z0-9.]` szerepelhet.

### 5.2 ARB-kulcs konvenció

`titleKey` = `practiceCatalog<PascalSlug>Title`, `descriptionKey` =
`practiceCatalog<PascalSlug>Description` (pl.
`practiceCatalogQuarterDownstrokesTitle`). A kulcs **nem tartalmaz szóközt** —
ez a „nincs hardcoded user-facing angol szöveg a domainben" acceptance gépi
mércéje.

### 5.3 A négy új `const ScoringProfile` (a `scoring_profile.dart`-ban,
a `legacyLearnParity` MELLÉ, nem helyette)

| konstans | id | súlyok (összeg = 100) | ablakok (match/perfect/good) | küszöbök (completion/overall) |
|---|---|---|---|---|
| `chordChangeDefault` | `chordChangeDefault` | chord 60, rhythm 40 | 280 / 50 / 120 ms | 85 / 70 |
| `chordProgressionDefault` | `chordProgressionDefault` | rhythm 40, direction 25, chord 35 | 280 / 50 / 120 ms | 85 / 70 |
| `rhythmOnlyDefault` | `rhythmOnlyDefault` | rhythm 100 | 280 / 50 / 120 ms | 85 / 70 |
| `freePracticeOpen` | `freePracticeOpen` | **üres map** | 280 / 50 / 120 ms | 0 / 0 |

`extraStrumPolicy`: mind a négynél `ExtraStrumPolicy.ignore` (a `freePracticeOpen`
kivételével, ahol szintén `ignore`). A `strumPattern` gyakorlatok a meglévő
`legacyLearnParity` profilt használják — új profilt hozzá NEM készítünk.

### 5.4 A tíz gyakorlat (kötött tábla)

`schemaVersion: 1`, `source: PracticeSource.builtin`, `sourceReference: null`
mindenhol. `totalBeats` = a gyakorlat teljes hossza negyedekben
(`BeatPosition.quarters(n)`), és **kizárólagos** felső korlát.

| # | id | mód | ütem | BPM | nehézség | totalBeats | tartalom |
|---|---|---|---|---|---|---|---|
| 1 | `builtin.quarterDownstrokes.v1` | strumPattern | 4/4 | 70 | beginner | 16 | 16 negyed, mind `down` |
| 2 | `builtin.alternatingEighths.v1` | strumPattern | 4/4 | 70 | beginner | 16 | 32 nyolcad, `down`/`up` váltakozva, ütemenként `down`-nal kezdve |
| 3 | `builtin.folkPattern.v1` | strumPattern | 4/4 | 80 | beginner | 16 | `D - D U - U D U` nyolcadrácson, ütemenként ismételve (ütemenként 6 esemény, a 2. és 5. nyolcad szünet) |
| 4 | `builtin.gToDChanges.v1` | chordChanges | 4/4 | 60 | beginner | 32 | negyedek; ütemenként váltakozva `G` és `D`, minden esemény `down` iránnyal |
| 5 | `builtin.emToCChanges.v1` | chordChanges | 4/4 | 60 | beginner | 32 | ua., `Em` és `C` |
| 6 | `builtin.cGAmFProgression.v1` | chordProgression | 4/4 | 70 | intermediate | 16 | negyed `down`-ok; ütemenként `C`, `G`, `Am`, `F` |
| 7 | `builtin.firstWaltz.v1` | strumPattern | **3/4** | 90 | beginner | 12 | ütemenként `down`, `up`, `up` a három negyeden |
| 8 | `builtin.syncopatedUps.v1` | strumPattern | 4/4 | 90 | intermediate | 16 | ütemenként: negyed `down` az 1-en, majd `up` a 2., 3. és 4. ütés utáni nyolcadon |
| 9 | `builtin.rhythmOnlyQuarters.v1` | rhythmOnly | 4/4 | 70 | beginner | 16 | 16 negyed, mind `down` (a `direction` kötelező, §2.4 — a mód nem pontozza) |
| 10 | `builtin.freePracticeTemplate.v1` | freePractice | 4/4 | 80 | beginner | 16 | **üres eseménylista** + `freePracticeOpen` profil |

**Akkord-mező szabály:** `strumPattern` és `rhythmOnly` események `chord: null`-t
hordoznak (a hangnem-kontextus a leírás-kulcsba tartozik, nem pontozott célba);
`chordChanges` és `chordProgression` események kötelezően hordoznak `chord`-ot ÉS
`direction`-t.

**Esemény-ID:** `<definitionSlug>.e<sorszám>` nullától vagy egytől indexelve —
egy definíción belül egyedi, a választott séma végig konzisztens.

**`skillTags`:** minden gyakorlat legalább egy stabil, `lowerCamel` címkét kap
(pl. `downstrokes`, `eighthNotes`, `chordChanges`, `waltz`, `syncopation`,
`freePlay`); a címkék `const` listában.

### 5.5 Repository-szerződés (domain, pure)

```dart
abstract interface class PracticeCatalogRepository {
  List<PracticeDefinition> all();
  PracticeDefinition? byId(String id);
  List<PracticeDefinition> byMode(PracticeMode mode);
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty);
}
```

Szinkron, `Future` nélkül (a katalógus `const` adat, nincs IO). A visszaadott
listák **nem módosíthatók** (`List.unmodifiable` vagy `const`), és a sorrend
minden hívásnál azonos: a katalógus deklarációs sorrendje (§5.4 táblasorrend).
`byId` ismeretlen ID-re `null`-t ad, nem dob és nem találgat.

### 5.6 Application-réteg

Riverpod 3, kézzel írt providerek (NINCS codegen), a házi idióma szerint
(`final xProvider = Provider<T>((ref) { … });`):

- `practiceCatalogRepositoryProvider` → `PracticeCatalogRepository`
  (`BuiltinPracticeCatalog` példány),
- `practiceCatalogProvider` → `List<PracticeDefinition>` (a teljes katalógus).

Az application-fájl NEM importál flutter widgetet, csak
`package:flutter_riverpod/flutter_riverpod.dart`-ot és a domain/data típusokat.

### 5.7 A data-réteg tisztasága

`builtin_practice_catalog.dart` csak a domain-modelleket importálja. Tilos benne:
flutter, riverpod, dio, shared_preferences import, `DateTime.now(`, `Random(`,
`print(`, l10n import. (A domain purity-őr a `data/`-ra nem terjed ki, ezért ezt
§6.7 saját teszt fogja őrizni.)

## 6. Acceptance criteria (mind gépi)

1. **≥10 definíció**, pontosan a §5.4 tíz ID-jével, ebben a sorrendben — a teszt
   tételesen kipinneli az ID-listát.
2. **Minden definíció valid:** `definition.validate()` üres listát ad
   MINDEGYIKRE. (Ez fogja el a rossz `totalBeats`-et, a rendezetlen eseményeket,
   a profil↔mód eltérést és a nem-kanonikus akkordcímkét.)
3. **Egyedi ID-k:** a tíz definíció ID-je duplikátummentes (explicit
   duplicate-ID teszt).
4. **Determinisztikus sorrend:** `all()` kétszeri hívása azonos sorrendű listát
   ad, és a sorrend megegyezik a kipinnelt ID-listával.
5. **Szűrés:** `byMode` és `byDifficulty` a várt részhalmazt adja (legalább
   `strumPattern`, `chordChanges` és `beginner` esetre tételesen), `byId`
   ismeretlen ID-re `null`.
6. **3/4 gyakorlat helyes:** a `builtin.firstWaltz.v1` metere
   `beatsPerBar == 3`, `totalBeats.ticks == 12 * 480`, és minden eseménye
   negyedrácson van.
7. **Data-réteg tisztaság-őr:** teszt olvassa be a
   `lib/features/practice/data/builtin_practice_catalog.dart` forrást és
   bukjon, ha az §5.7 tiltott mintáinak bármelyike szerepel benne.
8. **Kulcs-konvenció:** minden definíció `titleKey`/`descriptionKey` illeszkedik
   a `^practiceCatalog[A-Z][A-Za-z0-9]*(Title|Description)$` regexre (ez zárja ki
   a nyers angol szöveget).
9. **Új scoring profilok validak:** mind a négy új profil `validate()`-je üres,
   és a súlyok a mód `scoredDimensions` halmazával pontosan egyeznek.
10. **`legacyLearnParity` bitre változatlan** — a meglévő tesztje továbbra is zöld,
    és a diff nem érinti a konstans egyetlen mezőjét sem.
11. **Providerek:** `ProviderContainer`-ből olvasva a `practiceCatalogProvider`
    a teljes katalógust adja, és a `practiceCatalogRepositoryProvider`
    felülírható (override) teszt-repóval.
12. **Minden gate zöld** (§7), **piros teszt nélkül**.

## 7. Kötelező ellenőrzések

Külön hívásokként, PONTOSAN így — `&&` láncolás tilos, `analyze` és `test` soha
nem egy hívásban (OOM-védelem, AGENTS.md §12). A parancsok szűkítése a nyúlt
fájlokra **körbukás**:

```bash
~/flutter/bin/dart format --set-exit-if-changed lib test
~/flutter/bin/flutter analyze lib/ test/
~/flutter/bin/flutter test test/features/practice/
~/flutter/bin/flutter test test/core/architecture_dependency_test.dart
```

- A **teljes** suite + property gate + APK a CI-ben fut (ADR 0053) — a
  dispatch, a PR és a merge **Claude-oldal**. Az implementer `gh`-t NEM hív és
  NEM commitol.
- Ha egy MEGLÉVŐ teszt bukik: **MEGÁLLÁS és jelentés** — a mai viselkedést védő
  tesztet a zöldért átírni tilos.

## 8. Implementációs sorrend

1. `scoring_profile.dart` — a négy új konstans + tesztjeik (RED → GREEN).
2. `practice_catalog_repository.dart` — a szerződés.
3. `builtin_practice_catalog.dart` — a tíz definíció, a §5.4 tábla sorrendjében.
4. `builtin_practice_catalog_test.dart` — a §6 1–10 kritériumok.
5. `practice_catalog_controller.dart` + provider-teszt (§6.11).
6. Teljes gate-sor (§7).

## 9. Kockázatok

- **Profil↔mód eltérés.** A `PracticeDefinition.validate()` pontos halmaz-egyezést
  követel a profil súlykulcsai és a mód `scoredDimensions` halmaza között — a
  `chordProgression` HÁROM dimenziós. Ha a §6.2 teszt piros, először itt nézd.
- **`totalBeats` kizárólagos.** 4 ütem 4/4-ben = `quarters(16)`, és a legutolsó
  esemény a 15. negyeden (tick 7200) van, nem a 16-on.
- **Kanonikus akkordcímkék.** Csak keresztes dúr/moll (§2.1). `Bb`, `F#m7`,
  `Cmaj7` a `validate()`-et azonnal pirosra váltja.
- **Nyolcadrács a 3. és 8. gyakorlatnál.** `BeatPosition.eighths(n)` a helyes
  eszköz; a `fromLegacyBeats` **nem** használandó (az az adapterek hídja).
- **`freePractice` üres eseménylistája** csak azért valid, mert a mód
  `scoredDimensions`-e üres — ezért kell hozzá a `freePracticeOpen` üres súlyú
  profil is; a `legacyLearnParity` ott azonnal bukna.
- **Riverpod 3:** `AsyncValue` esetén `.value` (nullable), NEM `.valueOrNull` —
  ebben a körben szinkron providerek vannak, de ne csússzon be.

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Módosítások fájlonként

### 10.2 TDD RED → GREEN evidencia

### 10.3 A tisztaság-őr (§6.7) valódi-sértés próbája

### 10.4 Végső ellenőrzések tényleges kimenete (szó szerint)

### 10.5 Eltérések, nem futtatott ellenőrzések, follow-up

## 11. Review

(A review-jelentés linkje ide kerül: `docs/reviews/e02-r04-review.md`.)
