# ADR 0551 — A gyakorlás akkord-„konfidenciájának" megszüntetése: bizonyíték-állapot a kitalált szám helyett, és a javító-hurok

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R38 · **Épít rá:** ADR 0505 (döntési állapotgép), ADR 0516 (`LiveFrame.chordDecision`), ADR 0535 (hat `signal*` ok), ADR 0271 §1 (UNKNOWN > CONFIDENTLY WRONG)

## Kontextus (mért)

- `lib/features/practice/data/live_practice_observation_gateway.dart:249`
  (a kör előtti fán): `ChordObservation(at: at, label: chordLabel, confidence: 1.0)`.
  A fájl saját fejléce mondta ki, hogy az `1.0` azért van ott, mert a
  `LiveFrame`-nek nincs akkord-konfidencia mezője, és hogy az érték „nem mért"-et
  jelent — csakhogy a fogyasztók **számként** olvasták.
- Két fogyasztó olvasta: `chord_change_analyzer.dart:167`
  (`_hasUsableConfidence`, `>= minimumConfidence`) és
  `chord_change_analyzer.dart:332` (rendezés). Mindkettő számára minden
  megfigyelés használhatónak látszott — **azok is, amelyeket a felismerő
  kifejezetten elutasított**.
- Következmény a pontozásban: `practice_chord_scorer.dart` az ablak
  leghosszabb stabil címkéjét hasonlítja a célhoz. Ha egy bizonytalan olvasat
  rossz címkét hordozott, az `ChordOutcome.wrong` + `scorePerMille: 0` lett.
  **A játékost a modell saját bizonytalanságáért büntettük.**
- Az `uncertain` szó a kör előtt a teljes `lib/features/practice/**`-ben nem
  fordult elő (mért, `grep`).
- A `LiveFrame` viszont ADR 0516 óta hordozza a `chordDecision`-t és a
  `chordRejectReason`-t, a `LivePipeline` mindig ki is tölti.
- Amit NEM tudunk: nincs mérés arról, hogy éles játék közben a képkockák hány
  százaléka bizonytalan. Ezért a kör **nem hangol** egyetlen küszöböt sem; a
  coverage mezőt azért vezeti be, hogy ez a szám végre MÉRHETŐ legyen.

## Döntés

### D1 — `ChordEvidence`: a DÖNTÉS dönt, nem a szám

```dart
enum ChordEvidence { measured, uncertain, rejected }
```

`isEvidence` kimerítő `switch`-csel, `default` nélkül. A gateway a
`LiveFrame.chordDecision`-t képezi le rá: `confirmed → measured`;
`candidate | provisional | uncertain | expired → uncertain`;
`rejected → rejected`; `null → measured` (a tipizált döntést nem adó legacy
producerek — mockok, `LiveFrameAdapter`, onboarding — pontozhatók maradnak,
különben ez a kör csendben kikapcsolná a pontozásukat).

A `lib/features/practice/domain/` a `check_architecture.dart`
`sharedDomainMustRemainFrameworkIndependent` szabálya alatt áll, ezért a
domain **nem** importálja a Live enumot: a reject-ok stabil KÓDKÉNT
(`RecognitionRejectReason.name`) utazik a megfigyelésen, és csak a
prezentációs réteg fejti vissza.

### D2 — `ChordObservation.confidence` nullázható, és a `null` „NEM MÉRT"

Nem 0 és nem 1. Az élő akkordút nem mér konfidenciát
(`ChordPrediction.calibratedConfidence` szándékosan `null`, ADR 0516 D2),
tehát nincs mit írni oda. `validate()` a `null`-t nem tekinti sem
tartományon kívülinek, sem nem-végesnek. A `StrumObservation` érintetlen: ott
van valódi mért szám.

`chord_change_analyzer._hasUsableConfidence` új szabálya: először a bizonyíték
(nem-bizonyíték → sosem használható), aztán — ha van szám — a küszöb. A
`null` szám + `measured` bizonyíték **használható**: a „nem mért" nem
azonos a „küszöb alatt"-tal.

### D3 — A pontozó csak bizonyítékot lát

`practice_chord_scorer._scoreEvent`: az ablakban lévő megfigyelésekből a
nem-bizonyítékok kiesnek. Ha ezután nem marad semmi, az eredmény
`ChordOutcome.insufficientData` a D4-es új okkal — **sosem** `wrong`, és
sosem `noDetection` (a felismerő megtagadása nem azonos azzal, hogy a játékos
nem játszott semmit).

Vállalt mellékhatás, kimondva: egy tartott akkord közepén lévő absztinens
képkocka többé nem VÁGJA KETTÉ a stabil szakaszt, mert a rendszer ott valójában
nem figyelt meg váltást. Ez ugyanannak a szabálynak a következetes
alkalmazása; enélkül a „nem bizonyíték" fél-igazság maradna.

### D4 — Külön ok-kód: `practice.metric.chord_uncertain`

Nem olvad bele a `chord_unstable`-be. A kettő két különböző mondat:

| kód | kiről szól |
|---|---|
| `practice.metric.chord_unstable` | a JÁTÉKOS nem tartotta stabilan |
| `practice.metric.chord_uncertain` | az APP nem állt ki az olvasata mellett |

Ugyanaz az érv, amiért az ADR 0535 hat `signal*` okra bontotta az egy
„jelminőség" gyűjtőt: az egy vödörbe kevert diagnózishoz nem lehet helyes
tanácsot adni. Attribútum-szinten a `chord_uncertain` MEGELŐZI a
`chord_unstable`-t, mert az a hiba, amit a felhasználó közvetlenül orvosolhat
(közelebb a mikrofonhoz, csendesebb szoba), és az, amit a javító-hurok
kimondhat.

### D5 — Coverage a pontszám MELLETT, sosem benne

`PracticeChordScore.recognitionCoverage` = bizonyítékot hordozó akkord-
megfigyelések ÷ összes akkord-megfigyelés, `MetricValue`-ként. Nulla
megfigyelésnél `MetricNotApplicable` — a `0.0` azt állítaná, hogy a felismerő
elbukott, holott meg sem kérdezték.

Ez az absztinencia őszinte helye. A kör elfogadási feltétele — „a score nem
változik pusztán attól, hogy a modell bizonytalan" — így teljesíthető úgy, hogy
az információ mégsem vész el: a score állandó, a coverage esik.

`PracticeSessionResult` bővítése ugyanezzel a mezővel (a terv R38/2. pontja)
ebbe a körbe **nem** fért bele: a típus a perzisztált history-szerializálón és
a mapperen keresztül a tárolt formátumot is érinti, aminek saját migrációs
köre van. A kör riportja NOT-DONE-ként viszi tovább.

### D6 — A javító-hurok: TISZTA projekció, nem új reducer-állapot

`resolvePracticeCorrection(matches, chord, observations) → PracticeCorrection?`
— total és determinisztikus, óra és I/O nélkül. A reducer állapotgépe
érintetlen (a megbízás kikötése); a korrekció a MÁR lefutott pontozási menet
vetülete, és magától eltűnik, amint a következő cél tisztán zárul.

A szabály sorrendje szándékos:

1. csak a LEGUTÓBB lezárult, nem opcionális célt nézi — a javító-hurok az
   utolsó dologról szól, nem a session naplójáról;
2. ha ott a felismerő absztinált (`chord_uncertain`), a korrekció a felismerő
   SAJÁT reject-oka. Ez a vizsgálat áll ELÖL: „játssz C-t"-et mondani annak,
   akit az app nem hallott, hamis vád (ADR 0271 §1);
3. különben, ha a cél kimaradt vagy magabiztosan rossz akkord szólt, a
   korrekció az elvárt akkord — vagy, akkord nélküli célnál, maga a cél.

A `PracticeCorrectionBanner` a reject-okot **ugyanazokkal** az ARB-kulcsokkal
mondja ki, mint a Live `UncertaintyReasonBanner` (`liveReject*`). Két
kimerítő `switch` ugyanazon az enumon (a domain nem érhet a Live widget-
réteghez), ezért a párhuzamosságot **teszt** rögzíti mind a 11 okra: ha
valaha szétcsúsznak, az piros lesz, nem észrevétlen.

Ismeretlen vagy hiányzó kód esetén a banner a generikus „nem tudta kivenni"
mondatot adja, nem tippel okot.

## Következmények

- **Vállalt:** egy meglévő cella frissült, mert a RÉGI (hibás) viselkedést
  rögzítette: `live_practice_observation_gateway_test.dart` két helyen
  `chords.single.confidence == 1.0`-t várt. Most `isNull`.
- **Vállalt:** `PracticeMetricReasonCode.values` bővült, ezért a
  `practice_direction_scorer_test.dart` teljes-halmaz cellája frissült.
- **Nem vállalt / NEEDS-MEASUREMENT:** hogy éles játékban mennyi az absztinencia
  aránya — a coverage mező pontosan ezért létezik, de számot csak valódi
  eszközös session ad.
- **Nem vállalt:** az „egy tapos ismétlés a leggyengébb szakaszra" (a terv
  R38/3. pontja) — külön kör, saját UI-döntéssel.
