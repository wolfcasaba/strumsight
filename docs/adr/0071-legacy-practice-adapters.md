# ADR 0071 — Legacy practice adapterek: veszteséges akkord-normalizálás, `AppResult`-szerződés, `displayTitle`

- **Státusz:** elfogadva
- **Dátum:** 2026-07-30
- **Kör:** E02-R05 (SDD Ch3, Kör 5) — itt döntve, ugyanabban a körben implementálva.
- **Előzmény:** [ADR 0065](0065-practice-engine-v2-parallel-rollout.md) (párhuzamos
  rollout), [ADR 0066](0066-practice-tick-time-model.md) (480 PPQ időalap),
  [ADR 0067](0067-practice-gradual-learn-migration.md) (parity-mérce),
  [ADR 0068](0068-practice-domain-model-contracts.md) (domain-szerződések),
  [ADR 0070](0070-builtin-practice-catalog-contract.md) (katalógus).
  Implementer-motor: [ADR 0069](0069-two-engine-implementer-pool.md).

## Kontextus

A Kör 5 a meglévő tartalmat (Learn leckék, user Songok, Analyze-importok, napi
kihívás) `PracticeDefinition` formára hozza — a régi implementáció törlése
NÉLKÜL ([ADR 0065](0065-practice-engine-v2-parallel-rollout.md): a legacy motor
addig marad, amíg a parity zöld és a valódi eszközös teszt le nem zárult).

Az adapterek megírásához négy kérdést mérni kellett a mai kódon, mert
mindegyikre a Kör 6 (target compiler), Kör 9–10 (matcher/scorer) és Kör 18
(perzisztencia) is épül.

### Mért tények (`main @ 6c2ed3c`)

1. **A detektor akkord-szótára pontosan 24 keresztes dúr/moll címke.**
   `MlChordDecoder.majmin25Labels` (`N.C.` + 12 dúr + 12 moll) és a DSP-oldali
   `ChordMatcher._qualities` (`''` = dúr, `'m'` = moll) ugyanazt a halmazt adja.
   Ez betű szerint az [ADR 0068](0068-practice-domain-model-contracts.md)
   `isCanonicalPracticeChordLabel` halmaza.
2. **A legacy tartalom ennél gazdagabb címkéket hordoz.**
   `Lessons.twoFingerFrame` = `Em7`/`Cmaj7`, `Lessons.bluesShuffle` = `A7`/`D7`;
   a `chord_shape.dart` szótárban `Bb`, `Asus4`, `Cadd9`, `A7sus4` is van, és a
   Song-builder progresszió-picker `F#m`/`C#m`/`G#m`-et is ad.
3. **Ezek a célok ma is pontozhatatlanok.** A `LessonScorer._gradeChords`
   pontos string-egyenlőséget használ (`_chordAt(t) == s.chord`), a detektor
   pedig `Em7`-et sosem jelent — a `twoFingerFrame`/`bluesShuffle` akkord-slotjai
   a mai motorban **mindig** `chordMiss`-ek. Az akkord ráadásul a Learn-ben csak
   másodlagos számláló: a befagyasztott `ScoringProfile.legacyLearnParity` súlyai
   `rhythm 55 / direction 45` — akkord-dimenzió nincs benne.
4. **A user-tartalom neve nem lokalizálható kulcs.** A `PracticeDefinition`
   ma csak `titleKey`/`descriptionKey`-t hordoz (ADR 0070 §3: a domain nem tárol
   mondatot). Egy Song neve vagy egy Analyze-import címe viszont felhasználói
   adat, amit sem ARB-kulcsnak álcázni, sem eldobni nem szabad.

## Döntés

### 1. Az adapterek tiszta függvények, `AppResult<PracticeDefinition>` visszatéréssel

Az adapterek a `lib/features/practice/data/adapters/` alatt élnek, tiszta
(állapotmentes, óra- és véletlen-mentes) top-level függvények, és **sosem
dobnak**: minden konverzió `AppResult<PracticeDefinition>`-t ad
(`core/foundation/app_result.dart`, SDD Ch2 §7.1).

Indok: a bemenet részben perzisztált, kézzel is szerkeszthető adat (Song JSON,
mentett Analyze session), tehát a hibás bemenet **várt** hiba — a házi szabály
szerint érték, nem kivétel. A `BeatPosition.fromLegacyBeats` viszont negatív és
nem-véges bemenetre dob, ezért az adapter az ilyen értékeket előzetes őrrel
fogja el, és a hívó soha nem lát kivételt.

Új stabil hibakód: **`FailureCode.practiceContentUnsupported`**
(`'practice.content_unsupported'`), `ValidationFailure`-ben. A `cause` a
diagnosztikai ok (domain validációs kódok listája) — csak logolásra, sosem
renderelve.

**Záró szabály minden adapterben:** a felépített definíció `validate()`-je fut,
és nem üres eredmény esetén az adapter `Failure`-t ad. Érvénytelen
`PracticeDefinition` nem hagyhatja el az adaptert.

### 2. Az akkordcímke-normalizálás VESZTESÉGES, és ez nem parity-rontás

`legacyPracticeChordLabel(String?) → String?` a maj/min-halmazra redukál:

| bemenet | kimenet | szabály |
|---|---|---|
| `''`, `'   '`, `null` | `null` | strum-only cél |
| `Em`, `F#m`, `C` | változatlan | már kanonikus |
| `Em7`, `Am7`, `Emin` | `Em`, `Am`, `Em` | `m` (de nem `maj`) kezdetű utótag → moll |
| `Cmaj7`, `C7`, `Cadd9`, `Asus4`, `A7sus4` | `C`, `C`, `C`, `A`, `A` | egyéb utótag → dúr |
| `Bb`, `Db`, `Cb`, `E#` | `A#`, `C#`, `B`, `F` | b-s írásmód → kereszt |
| `G/B` | `G` | slash-akkord basszusa elhagyva |
| `H`, `x`, `Ω` | `null` | értelmezhetetlen gyök → strum-only cél |

Indok a veszteségre: a fenti §Kontextus 1–3 miatt egy `Em7` cél a **mai**
motorban is örökre eltalálhatatlan. Az adapter tehát nem ront le egy működő
állapotot, hanem egy holt célt tesz élővé — és mivel az adaptált tartalom
`strumPattern` módban fut (§3), ahol az akkord nem pontozott dimenzió, a
befagyasztott parity-profil egyetlen kimenete sem mozdul.

Indok arra, hogy az értelmezhetetlen címke `null`, nem hiba: egyetlen furcsa
akkordcímke miatt egy egész user-song konvertálhatatlanná tétele rosszabb
felhasználói kimenet, mint azt az egy ütemet strum-only célként vinni tovább.

**Utófeltétel, gépi mércével:** a normalizáló minden nem-`null` kimenetére
`isCanonicalPracticeChordLabel` igaz — és ezt a `Lessons.all` teljes tartalmán
is ellenőrizzük (ez zárja az E02-R03 review NOTE-3-át).

### 3. Az adaptált tartalom módja `strumPattern`, profilja `legacyLearnParity`

Minden Lesson-, Song-, Analyze- és Daily-Challenge-eredetű definíció
`PracticeMode.strumPattern` + `ScoringProfile.legacyLearnParity` — egyetlen
kivétellel: az **eseménymentes** Analyze-import `PracticeMode.freePractice` +
`ScoringProfile.freePracticeOpen` (a `strumPattern` üres eseménylistával
`events.empty` miatt érvénytelen lenne).

Indok: az adapterek dolga a parity, nem a gazdagítás. A `chordChanges` /
`chordProgression` mód gazdagabb pontozása authored katalógus-tartalomra való
(ADR 0070), nem konvertált legacy anyagra — a konvertált tartalomnak bitre a
régi mércével kell mérnie, különben a Kör 9–10 parity-tesztje már nem
összehasonlítható a befagyasztott baseline-nal.

Következmény: az üres Analyze-klip nem hiba, hanem szabad gyakorlás — ez a SDD
„empty result safe behavior" elvárásának a konkrét alakja.

### 4. `PracticeDefinition.displayTitle` — új, opcionális mező

A `PracticeDefinition` kap egy `String? displayTitle` mezőt (alap: `null`).
Szemantika: **már megjelenítendő, NEM lokalizálandó** szöveg; a UI szabálya
`displayTitle ?? l10n(titleKey)`.

Indok: a §Kontextus 4 szerinti user-adatot (`Song.name`, `Lesson.name`,
Analyze-import címe, `DailyChallenge.name`) sem ARB-kulcsként hazudni, sem
elveszíteni nem szabad. A `titleKey`-nek két szemantikát adni (hol kulcs, hol
nyers szöveg, a `source` alapján megkülönböztetve) néma megjelenítési hibához
vezetne; egy külön mező ezt kizárja.

Az adaptált definíciók `titleKey`-e forrásfajta-szintű ARB-kulcs
(`practiceSourceLessonTitle`, `practiceSourceSongTitle`,
`practiceSourceAnalyzeTitle`, `practiceSourceDailyChallengeTitle` + `…Description`
párjuk) — fallback arra az esetre, ha nincs `displayTitle`. Az ARB-bejegyzések
az első UI-hívóval jönnek (ADR 0070 §3 változatlan: most csak kulcs, nincs
fordítás).

Új validációs kód: **`definition.displayTitle.blank`** — a `null` megengedett,
de a csak whitespace-ből álló cím nem (az „üres címsor" néma UI-hiba lenne).
A stabil kódkészlet ezzel 60 → 61.

### 5. ID- és `sourceReference`-sémák

| forrás | definition ID | `sourceReference` |
|---|---|---|
| Lesson | `lesson.<lessonId>.v1` | `lesson:<lessonId>` |
| Lesson (Easy) | `lesson.<lessonId>.easy.v1` | `lesson:<lessonId>` |
| Song | `song.<songId>.v1` | `song:<songId>` |
| Analyze | `analyze.<sourceId>.v1` | `analyze:<sourceId>` |
| Daily Challenge | `dailyChallenge.<epochDay>.v1` | `dailyChallenge:<epochDay>` |

Az Easy-variáns akkor is külön ID-t kap, ha a `Lesson.simplified` történetesen
az eredeti leckét adja vissza — az ID a *kérés* azonosítója, nem a tartalomé,
így a haladási rekord egyértelmű marad.

Az esemény-ID mindig `<definitionId>.e<index>`, nulláról indexelve, a kiadási
sorrendben — ugyanaz a séma, mint a katalógusban (ADR 0070).

A napi kihívás ID-je a `DailyChallenge.day` epoch-napból jön, tehát
nap-stabil és óra-mentes: az adapter soha nem hív `DateTime.now()`-ot, a napot
a hívó adja.

### 6. Az Analyze-import tick-ütközése előre-tolással oldódik

A felvett klip pengetései tetszőleges másodperc-időpontokon állnak, a
`BeatPosition.fromLegacyBeats` pedig a legközelebbi tickre kerekít (480 PPQ,
90 BPM-en 1 tick ≈ 1,39 ms). Két, ugyanarra a tickre kerekedő pengetés a
domain `events.positionDuplicate` szabályába ütközne.

Döntés: az ütköző eseményt a **következő szabad tickre toljuk előre**
(monoton, ≤ pár ezredmásodperces eltolás). Indok: a detektált pengetések száma
a felhasználó teljesítményének mércéje — egy tick eltolás hallhatatlan, egy
eldobott pengetés viszont hamis „kihagytad" visszajelzést adna.

Ha az így kapott tick elérné a `totalBeats` kizárólagos határt (mert a
kerekítés a klip utolsó pengetését pont az ütemhatárra vitte), az idővonalat
**egy ütemmel megnöveljük**, nem az eseményt dobjuk el — ugyanaz az indok, egy
lépéssel következetesebben (E02-R05 review MINOR-2: az implementáció ezt a
jobb változatot választotta, a döntés utólag ide került). A növelés
KIZÁRÓLAG erre az esetre szól: egy szabályosan a határ alatt maradó utolsó
esemény soha nem nyújthatja meg az idővonalat (MINOR-1).

### 7. A legacy API-hoz nem nyúlunk

`Lesson`, `Lessons.*`, `Song.toLesson()`, `Lessons.fromAnalyze`,
`Lessons.fromDailyChallenge` és a `LessonScorer` változatlan marad; a Learn
képernyő útja bitre azonos. A Song-adapter kifejezetten **nem** hívja a
`toLesson()`-t (SDD Kör 5), hanem közvetlenül, validáltan épít — de az
eredményének esemény-szinten egyeznie kell vele (parity-teszt).

### 8. Songs `public.dart` — a cross-feature szabály miatt

A `lib/features/songs/` ma nem publikál barrel fájlt, a
`crossFeatureImportsMustUsePublicApi` szabály (`tool/check_architecture.dart`)
viszont tiltja a `practice → songs/model/song.dart` közvetlen importot, és az
architektúra-allowlist **csak zsugorodhat**. Ezért a kör létrehozza a
`lib/features/songs/public.dart` barrelt (a `Song`/`Setlist` modellel), és az
adapter azon keresztül importál.

## Következmények

- Az adapterek kimenete determinisztikus és offline; hívó UI ebben a körben
  nincs, a három practice feature-flag változatlanul OFF marad.
- A `PracticeDefinition` bővül egy opcionális mezővel — a Kör 4 katalógusa
  érintetlen marad (`displayTitle` ott `null`), a `const` konstruálhatóság nem
  sérül.
- A veszteséges akkord-redukció dokumentált és tesztelt; ha a detektor szótára
  később bővül (7-es akkordok), a normalizáló egy helyen lazítható.
- Nyitva marad (Kör 6+): a count-in, a ring-out és a tempó-skálázás — az
  adapter szándékosan csak a zenei tartalmat viszi át, a session-paramétereket
  nem.
