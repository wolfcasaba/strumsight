# ADR 0070 — Beépített practice katalógus: `const` adat, stabil ID-k, szinkron repository

- **Státusz:** elfogadva
- **Dátum:** 2026-07-30
- **Kör:** E02-R04 (SDD Ch3, Kör 4) — itt döntve, ugyanabban a körben implementálva.
- **Előzmény:** [ADR 0066](0066-practice-tick-time-model.md) (480 PPQ időalap),
  [ADR 0068](0068-practice-domain-model-contracts.md) (domain-szerződések).
  Implementer-motor: [ADR 0069](0069-two-engine-implementer-pool.md).

## Kontextus

A Kör 4 a Practice V2 első TARTALMI rétege: tíz beépített gyakorlat. Négy
kérdést itt kell egyszer eldönteni, mert a Kör 5 (adapterek), Kör 6 (target
compiler) és Kör 18 (perzisztencia) mind erre épül, és az ID-k már a felhasználó
haladási adataiban is megjelennek.

## Döntés

### 1. A katalógus `const` adat, nem generált és nem IO

`BuiltinPracticeCatalog` egy `const` `List<PracticeDefinition>`-t tart. Nincs
JSON-betöltés, nincs asset-olvasás, nincs kódgenerátor. Indok: a katalógus a
telepítéssel együtt szállított, offline garanciás tartalom (az app 0-request
offline-garanciáját rendszer-szintű teszt őrzi), a `const` pedig fordítási
időben kikényszeríti az immutabilitást — az [ADR 0068](0068-practice-domain-model-contracts.md)
caller-immutability szerződése így triviálisan teljesül.

**Következmény:** hibás katalógus-adat fordítási hibaként vagy a `validate()`
tesztben bukik, nem futásidőben a felhasználónál.

### 2. ID-séma: `builtin.<lowerCamelSlug>.v1`

Az ID stabil, perzisztálható, és **tartalmi változáskor új verzió-utótagot kap**
(`v2`), sosem felülírást. Indok: a haladási/statisztikai rekordok definition-ID-t
tárolnak; egy gyakorlat néma átírása visszamenőleg hazuggá tenné a korábbi
sessionöket. A régi ID a katalógusban maradhat vagy kivezethető — de az azonos
ID mindig azonos tartalmat jelent.

### 3. A user-facing szöveg csak ARB-kulcs, a domain nem tárol mondatot

`titleKey` / `descriptionKey` konvenciója:
`practiceCatalog<PascalSlug>Title` / `…Description`. A kulcs nem tartalmaz
szóközt — ez a „nincs hardcoded user-facing angol szöveg" acceptance gépi
mércéje (regex-teszt). A **tényleges en/hu fordítás nem ebben a körben kerül be**,
hanem az első UI-hívóval együtt: egy sosem megjelenített ARB-kulcs halott
fordítási teher, a lógó kulcs kockázatát pedig a konvenció-teszt fedi.

### 4. A repository szinkron, `Future` nélkül

```dart
abstract interface class PracticeCatalogRepository {
  List<PracticeDefinition> all();
  PracticeDefinition? byId(String id);
  List<PracticeDefinition> byMode(PracticeMode mode);
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty);
}
```

Indok: `const` adat mögé `Future`-t tenni hamis aszinkronitás — a hívó
életciklus-kezelést és hibaágat írna olyasmire, ami nem tud elromlani. A későbbi
user-created / felhő-katalógus (Kör 18+) SAJÁT, aszinkron szerződést kap; a
kettőt nem olvasztjuk össze előre.

`byId` ismeretlen ID-re `null` — nem dob és nem találgat, összhangban a
`practiceModeFromCode` / `practiceScoreDimensionFromCode` „no guessing fallback"
mintájával.

**Sorrend:** a `all()` a deklarációs sorrendet adja vissza, minden hívásnál
azonosat; a katalógus rendezése authored döntés (könnyűtől nehezedő), nem
futásidejű rendezés. Tesztben tételesen kipinnelve.

### 5. Mód-specifikus alapértelmezett scoring profilok

A négy új `const ScoringProfile` (`chordChangeDefault`, `chordProgressionDefault`,
`rhythmOnlyDefault`, `freePracticeOpen`) a `scoring_profile.dart`-ban él, a
`legacyLearnParity` MELLETT. A `legacyLearnParity` az E02-R01 baseline-mérce
része: **befagyasztott**, egyetlen mezője sem módosulhat, és a `strumPattern`
gyakorlatok továbbra is ezt használják.

## Következmények

- A katalógus bővítése tiszta adat-PR: új `const` bejegyzés + a kipinnelt
  ID-lista frissítése; kódváltozás nem kell.
- Az `all()` visszaadott listája nem módosítható — a hívó nem rendezheti át
  helyben; szűrni a repository metódusaival vagy másolaton kell.
- A `rhythmOnly` gyakorlatok eseményei is hordoznak `direction`-t, mert az
  [ADR 0068](0068-practice-domain-model-contracts.md) `eventScorableMissing`
  szabálya minden nem-marker eseménytől megköveteli a chord VAGY direction
  célt. Hogy ebből mi számít pontba, azt a mód `scoredDimensions` halmaza
  dönti el, nem az adat.
