# ADR 0092 — Song Trainer × Practice Engine integráció

**Státusz:** elfogadva (Epic 3 baseline round, E03-R01, pre-flight, 2026-08-02).
Formalizálja a [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md)
§8.2–8.3 (függőségi irány, kereszt-feature szabály), §21 (Practice Engine
integráció) tervezetét kötelező érvényű döntéssé. A tényleges implementáció
külön kör (E03-R19 — Practice compiler, chord & rhythm); ez a kör (E03-R01)
csak a határt és a szerződést rögzíti, kódot nem ír. Előfeltétele
[ADR 0089](0089-song-document-v2.md) (`SongDocument`/`SongId`/`revision`) és a
Chapter 3 Practice Engine publikus szerződése
(`lib/features/practice/public.dart`).

## Kontextus

A Practice Engine V2 (Epic 2) determinisztikus `PracticeDefinition` →
`compilePracticeTarget` → `PracticeEventMatcher`/scorer láncot ad, amely
**nem ismeri a Song Trainert** — bemenete egy önálló
`PracticeDefinition`/`PracticeSessionConfig`, kimenete `PracticeVerdict`/
`PracticeMetrics`. A jelen pre-flight (§0.0, mérve) megerősítette, hogy
`lib/features/practice/public.dart` **nem exportálja** a Song Trainer
compilerhez és eredmény-visszamappinghez szükséges teljes kontraktumot
(pl. `PracticeScoreAggregator`, `PracticeVerdict` konkrét típus, `TimingGrade`,
`ChordOutcome`, a timing/chord scorer implementációk) — ez hard pre-flight
gate volt, és az E03-R01 scope-ja kifejezetten kizárja mind a Practice-belső
importot, mind a Practice public contract néma bővítését (a kör briefje §3,
§5.4).

Az Epic 3 §8.2 szerint a Song Trainer domain nem importálhat Practice Engine
presentation fájlt, és az integráció kizárólag domain- vagy
application-szintű publikus kontraktuson keresztül történhet — ez az ADR
rögzíti, MELYIK irányban és MILYEN alakban.

## Döntés

1. **Egyirányú függőség: Song Trainer → Practice Engine, sosem fordítva.** A
   Practice Engine nem tud a Song Trainerről, nem importálhatja azt, és nem
   kaphat Song Trainer-specifikus ágat a saját kódjában. A Song Trainer a
   Practice Engine-t kizárólag annak `lib/features/practice/public.dart`
   exportjain keresztül érheti el.
2. **`SongPracticeCompiler` a fordítási határ.** A Song Trainer domain/
   application rétege egy saját `SongPracticeCompiler` kontraktust definiál
   (`compile({song, trackId, range, mode, config}) → AppResult<PracticeDefinition>`),
   amely a kiválasztott track és range eseményeit Chapter 3
   `PracticeDefinition`-né fordítja. A compiler:
   - nem módosítja a `SongDocument`-et;
   - csak a kiválasztott range eseményeit használja, a range elejét local
     beat 0-ra transzformálva;
   - megőrzi a source position mappinget (measure/section ID-k);
   - figyelembe veszi a speed multipliert, capót és transpositiont;
   - csak a ténylegesen támogatott scoring dimenziót kapcsolja be (§7
     capability modell — "őszinte korlátozás", ugyanaz az elv, mint a Free
     Practice honest summary ADR 0082-nél);
   - determinisztikus outputot ad ugyanazon bemenetre.
3. **Explicit forrás-visszamapping típus, nem implicit index-egyezés.**
   Minden `PracticeEvent`-hez opcionális `SongEventReference` tartozik
   (`songId`, `songRevision`, `trackId`, `sourceEventId`, `measureIndex`,
   opcionális `sectionId`). Ez teszi lehetővé a heatmapet, a problem-measure
   azonosítást, a retry-range generálást, a progress-aggregációt és az
   editorba visszaugrást a Practice Engine belső reprezentációjának
   ismerete NÉLKÜL.
4. **A Practice-oldali hiányzó exportok bővítése előfeltétel-jellegű, nem
   ehhez a körhöz tartozó munka.** Ha egy későbbi kör (E03-R19) a
   compiler/result-mapping megírásakor Practice-oldali típust igényel, amit a
   `public.dart` ma nem exportál, az egy **Practice Engine-oldali**,
   scope-jelölt bővítés (a Practice feature saját allowed_paths-ában), nem a
   Song Trainer belső importja — a kereszt-feature szabály (§8.3) csak a
   publikus boundary bővítését engedi, a belső fájlok közvetlen elérését
   soha.
5. **Practice result → SongTrainerResult visszamapping a Song Trainer
   oldalán él.** A Practice Session eredményét (measure metrics, section
   metrics, source event verdict, loop attempt, speed, selected track,
   selected range, unsupported dimension summary) a Song Trainer alakítja
   át — a Practice Engine kimeneti típusa (`PracticeVerdict`/
   `PracticeMetrics`) változatlan marad, nem kap Song Trainer-specifikus
   mezőt.

## Alternatívák

- **A Practice Engine domain közvetlen importja a Song Trainerből** (a
  `public.dart` boundary megkerülésével): elvetve — ez pontosan a §8.2
  tiltott mintája, és néma coupling-et hozna létre a Practice belső
  reprezentációjához, ami a legkisebb Practice-oldali refaktort is törné a
  Song Trainer felől.
- **A Practice Engine bővítése Song Trainer-tudatos ággal** (pl. a compiler
  a Practice feature-be kerülne): elvetve — megsértené az egyirányú
  függőséget és a Practice Engine Epic 2-ben lezárt, önálló
  determinisztikus szerződését (ADR 0075/0076); a Practice Engine-nek nem
  szabad tudnia a hívó feature identitásáról.

## Következmények

- Az E03-R19 kör (Practice compiler, chord & rhythm) implementációja előtt
  külön kell auditálni, mely Practice-oldali típusokat kell exportálni a
  `public.dart`-ból — ez az audit NEM ennek a körnek (E03-R01), hanem az
  E03-R19 pre-flightjának feladata, saját, célzott allowed_paths-szal a
  Practice feature-ön belül.
- A `SongEventReference` a §21.3 szerinti mezőkészlettel a jövőbeli
  heatmap/progress/retry-range funkciók (§23.4, §26) stabil alapja —
  módosítása visszamenőleg minden korábbi Practice-eredmény mappingjét
  érintené, ezért mezőbővítés csak additív lehet.
- A monophonic pitch scoring (§22) egy külön, ehhez az ADR-hez hasonlóan
  egyirányú integrációs mintát követ majd (E03-R20 kör) — ez az ADR csak a
  Chord & Rhythm útvonalat rögzíti; a pitch-scorer határ külön döntés, ha a
  mintától eltér.
