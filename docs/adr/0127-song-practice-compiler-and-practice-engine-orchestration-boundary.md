# ADR 0127 — Song practice-compiler és Practice engine orchestration boundary

- **Státusz:** Elfogadva (E03-R19 pre-flight, 2026-08-04)
- **Kör:** E03-R19 — Practice compiler és chord/rhythm trainer
- **Kontext-ADR-ek:** [0077](0077-practice-session-controller-architecture.md)
  (Practice session controller + lease-tulajdonlás), 0111 §2 (observation
  gateway data-boundary), [0125](0125-song-trainer-setup-configuration-boundary.md)
  (TrainerConfig/TrainerRange), [0126](0126-song-transport-backing-playback-boundary.md)
  (SongTransport).

## Kontextus

A Song Trainer egy `SongDocument` kiválasztott track+range-ét
determinisztikus gyakorló-menetté kell fordítsa, majd a Practice V2 motort
vezényelje és annak eredményét visszamappelje song-koordinátákra (revision /
track / event / measure / section). A brief tiltja a chord/rhythm/direction
scorer újraimplementálását és a Practice feature belső importját — a Song
Trainer kizárólag a Practice **publikus** felületén keresztül nyúlhat a
motorhoz.

**Pre-flight méréssel (2026-08-04) igazolt tények:**

1. **A compiler bemenete kész és publikus.** A `PracticeDefinition`
   (`mode`, `source`, `meter`, `defaultTempo`, `totalBeats`, `events`,
   `scoringProfile`, `sourceReference`) és a `PracticeEvent`
   (`id`, `position`, `duration`, `chord`, `direction`, `accent`, `optional`,
   `marker`) már a `lib/features/practice/public.dart` exporton van. A
   `PracticeEvent.id` + `PracticeDefinition.sourceReference` a source-mapping
   horgai — nincs szükség új Practice modelltípusra a fordításhoz.

2. **A Practice session-runtime felület NEM volt publikus.** A
   `PracticeSessionController`, a `PracticeSessionInput`/`Command`/`Signal`
   család, a `PracticeSessionEffect` család, a `PracticeSessionState` +
   `PracticeSessionStatus`, a `PracticeSessionResult` / `PracticeAttemptResult`
   / `PracticeVerdict` (+ `PracticeFinishReason`, `PracticeAttemptOutcome`,
   `TimingGrade`, `ChordOutcome`) és a session-provider felület a Practice
   feature belső könyvtáraiban élt, nem a `public.dart`-on. Ez a brief §5.1
   Kötött döntés 1 hard gate-je.

3. **A mikrofon-lease tulajdonosa mérve nem a controller.** Az
   `AudioSessionCoordinator.acquire()` egyetlen hívója a `MicCapture`
   (`lib/core/audio/mic_capture.dart:82`); a Practice controller ADR 0077 §10
   szerint kifejezetten NEM birtokolja a lease-t — a
   `PracticeObservationGateway` (production `LivePracticeObservationGateway`,
   `practice/data/`, a `strumEngineProvider` + `microphonePermissionGateway`
   fölött) hajtja a megfigyelést, és a lease a live úton folyik. Az A9
   réteg-tisztasági guard tiltja, hogy az `application/` réteg (így a
   `song_trainer/application/trainer/`) az `AudioSessionCoordinator`-t, a
   `StrumEngine`-t vagy a gateway-t közvetlenül elérje.

## Döntés

1. **A `SongPracticeCompiler` tiszta függvény** — nem mutálja a
   `SongDocument`-et, a range startját local beat 0-ra tolja, és minden
   fordított `PracticeEvent`-hez `SongEventReference`-t őriz
   (`PracticeEvent.id` ↔ song revision/track/event/measure/section). A
   compiler kizárólag a már publikus Practice definíció-típusokat használja;
   új Practice típust nem vezet be és Practice-belsőt nem importál.

2. **A Practice `public.dart` additívan exportálja a session-runtime
   felületet**, hogy a Song Trainer a motort a publikus boundaryn keresztül
   vezényelhesse: a controller, az input/effect/state/status, a
   session/attempt result + verdict, és a session-provider/gateway-típus/
   recorder-típus felület. Csak a `public.dart` módosul (már az
   engedélyezett listán) — a re-exportált szimbólumok forrásfájljai
   változatlanok. Az implementer minden importált szimbólumról bizonyítja,
   hogy a `public.dart`-on van; ami additív export nélkül nem érhető el
   (belső Practice-szerkesztést kívánna) → STOP + bridge brief-revízió
   (nem néma scope-tágítás).

3. **A scoring dimenzió kizárólag track-capability szerint aktív.** Chord
   target csak akkor kap chord-scoringot, ha a track chordokat hordoz; a
   `direction` target csak ismert `StrumDirection` mellett kap direction
   scoringot (unknown → `PracticeEvent.direction == null`, direction n.a.). A
   fordító a scoring-profilt a track képességéből vezeti, nem a nyers
   `TrainerMode`-ból.

4. **A lease-tulajdonlás nem költözik.** A scoring mód a Practice motoron
   keresztül (a valós observation gateway-jel) szerzi a lease-t; a
   playback-only mód NEM konstruál/aktivál scoring gateway-t és NEM olvassa a
   mikrofon-permission providert (acceptance: playback-only mic provider
   call count 0). A Song Trainer controller sosem éri el közvetlenül az
   `AudioSessionCoordinator`-t.

7. **A hat track-profil publikus `PracticeEvent` + `ScoringProfile.weights`
   encodinggal (§0.0 R6), NINCS Practice-modellváltozás.** A rhythm-only cél a
   már létező `builtin.rhythmOnlyQuarters` mintát követi: `StrumDirection.down`
   placeholder az esemény-validáció kielégítésére + `rhythm`-only súlyú profil,
   mert az aggregátor a súlyozatlan dimenziót nem pontozza. A chord kanonikus
   major/minor label kell legyen; a `pitch` scoring tilos.

6. **Tempo/meter-változás: single reference-tempo normalizált idővonal
   (§0.0 R5), compiler-only.** A Practice pontozás mérve tisztán idő-alapú
   (`PracticeEventMatcher.matchWindow` `Duration` a `target.time` körül;
   `PracticeTimingScorer` az `offset.abs()`-t osztályozza). A compiler a
   range-et egy reference tempóra + kezdő meterre normalizálja, és minden
   event-et a `SongTimeMap` szerinti VALÓS onset-idejére (a TempoMap-en át)
   helyez, `T_ref` melletti tick-pozícióként. Így a cél-időpontok onset-hűek a
   tempóváltáson át is; a pontozás helyes. A változó-meter metronóm-rács
   ebben a körben nem támogatott (a range kezdő metere; a scoringot nem
   érinti). NINCS Practice-modell/`compilePracticeTarget` változás.

5. **A Practice-típust importáló Song Trainer fájlok az `application/`
   rétegben élnek, nem a `domain/`-ban (§0.0 R4).** A merge-elt
   song_trainer domain-purity guard
   (`test/features/song_trainer/domain/song_document_test.dart`,
   `_findPurityViolations` `'cross-feature import'` regex) tiltja, hogy
   bármely `lib/features/song_trainer/domain/**` fájl `features/practice/…`-t
   importáljon — a `practice/public.dart`-ot is. A `SongPracticeCompiler` és a
   `SongTrainerResult` cross-feature adapterek (Practice-típust hordoznak),
   ezért az `application/trainer/` rétegbe kerülnek, ahol a globális
   architektúra-guard a `public.dart`-célú cross-feature importot engedi. A
   `SongEventReference` tiszta song-koordináta marad a `domain/models/`-ban,
   Practice-import nélkül. A merge-elt guard NEM módosul (a mérce nem
   módosulhat attól, akit mér).

## Következmények

- A Practice publikus felülete bővül; a bővítés additív és auditált, más
  feature belső importja továbbra is tilos.
- A measure/section aggregáció csak akkor lehet hamisan sikeres, ha a source
  mapping hiányzik — ezért minden target referenciája mérendő teszttel
  (brief §9 kockázat, §6 acceptance).
- A pitch scoring, a trainer screen/heatmap és bármely új scorer ebben a
  körben tilos marad.
