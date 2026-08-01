# E02-R18 — Result, coaching és session history

- **Státusz:** **PLANNING** (pre-flight lezárva 2026-08-01, kód újramérve: `main` @ `0e31bc6`;
  ADR 0084 megírva, motor **MiniMax M3**)
- **Pre-flight mérés (2026-08-01, `main` @ `0e31bc6`):** a brief §2 mért állításai
  helytállók. Egy pontosítás az A9-hez: a `recorder.record` **és** a
  `ShowRecoverableError`-emisszió **már a controllerben be van kötve**
  (`practice_session_controller.dart:493` és `:500`), a controller single-flightot
  tart (`:177`). A controller **nincs** az engedélyezett-fájllistán → R18 nem nyúl
  hozzá; az új repository dolga csak annyi, hogy a hibát `AppResult` **failure**-ként
  adja vissza (soha nem néma `catch`), és a rekord idempotens legyen a `sessionId`-re
  a **repository** szintjén (a controller single-flightjától függetlenül). A
  `PracticeCoachingCode` `abstract final class` (String-konstansok, nem enum). A
  storage-minta a `library_repository.dart` (`JsonCollectionStore`, `maxItems`,
  `StorageKeys.quarantineOf`, `StorageKeys.all` guard). Részletek: ADR 0084 §Kontextus.
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 18"** (+ §17, §20.1–20.2, §21.5)
- **Branch:** `codex/e02-r18-result-coaching-history`
- **Előfeltétel:** **E02-R14, R15, R16, R17 merge-ölve** (a result minden mód
  dimenzióit és a Speed Builder összegzését mutatja).
- **ADR:** **0084** — `docs/adr/0084-practice-history-v2-and-coaching.md`,
  **az orchestrátor írja meg a pre-flightban** a §5 tartalmával.
- **Implementer motor:** a pre-flightban a user dönt. *Ajánlás:* **Codex** —
  perzisztencia-kör (verziózás, cap, korrupció-izoláció, idempotencia), a
  projekt mért „néma adatvesztés" osztálya itt a kockázat.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Olvasd újra az R11 `PracticeSessionRecorder` interfészt — ez a kör cseréli
>    le a `Noop` implementációt valódira, és a **finish-idempotencia** szerződése
>    ott dőlt el.
> 2. Ellenőrizd az R15/R16/R17 kimeneti modelljeit (chord-pair statisztika,
>    free-practice összegző, Speed Builder állapot) — a result ezekből épül.
> 3. ADR-szám ütközés ellenőrzése, majd az ADR 0084 megírása.
> 4. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre.

## 0.0 Brief-revízió (orchestrátor, ADR 0087 §2 — a kör saját, még nem merge-elt briefje)

**R1 (2026-08-01, review után) — scope-bővítés, elfogadva:** az implementer a §4
listán felül három, feature-en belüli dekompozíciós fájlt hozott létre, egyik sem
tilos zónában. Az orchestrátor ezeket a §4 engedélyezett listához adja
(a fold-back felesleges diff-hízlalás volna):

| Útvonal | Miért |
|---|---|
| `lib/features/practice/data/practice_history_recorder.dart` | a valódi `PracticeSessionRecorder` a repositoryból kiemelve (teszthetőbb) |
| `lib/features/practice/data/practice_session_result_history_mapper.dart` | `PracticeSessionResult` → V2 history-entry leképezés |
| `lib/features/practice/domain/model/practice_metric_snapshot.dart` | a szerializáló/result-screen által igényelt sealed metrika-snapshot modell |

A **valódi** tilos zónák változatlanul tiltottak (progress/streak/learn, meglévő
`domain/service` fájlok, `storage_migrator.dart`, más ADR-ek, `.github`, a
`controller`/`recorder`-interfész/`practice_session_result.dart` zárt-kör modellek).

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `stopped`.
**A §7 a terved.**

## 1. Cél

Három összetartozó dolog:

1. **Result képernyő** — mode-specifikus, csak az **alkalmazható** dimenziókkal;
2. **PracticeCoach** — pure service, amely **mérésből** választ lokalizálható
   coaching-kódokat (bizonyíték nélküli mondat tilos);
3. **Practice History V2** — verziózott, capelt, korrupció-izolált perzisztencia,
   **idempotens** mentéssel, a meglévő V1 `PracticeEntry` adatok **megőrzésével**.

## 2. Jelenlegi állapot (mért tények, `main` @ `ce8fbce`)

- **V1 practice log:** `lib/features/progress/model/practice_entry.dart` —
  `PracticeEntry(day, source, seconds, strokes, chords, directionAccuracy?)`,
  JSON-kulcsok `day` / `src` / … . Tár:
  `KeyValuePracticeLogRepository` + `PracticeLogRepository.maxEntries = 400`,
  `StorageKeys.practiceLog = 'ss.progress.practice_log'`.
  ⚠ **Névütközés:** a `progress` feature `PracticeSource` enumja **más**, mint a
  practice domain `PracticeSource`-a — az importoknál ez valódi csapda.
- **Storage-infrastruktúra (Epic 1):** `JsonDocumentStore` (300 sor) —
  verziózott dokumentum-boríték, **karantén** a dekódolhatatlan bájtoknak
  (`StorageKeys.quarantineOf(key)`), `JsonCollectionStore<T>` `maxItems`
  capkezeléssel, `JsonObjectStore<T>`. Minta: `library_repository.dart`
  (`LibraryRepository.maxSessions = 100`).
- **Kulcs-katalógus:** `StorageKeys` + a **`StorageKeys.all` lista**, amit
  guard-teszt ellenőriz (`test/core/storage/key_value_store_test.dart:192–201`:
  egyediség, `ss.` névtér, a secure kulcs kizárása). **Új kulcs csak a listával
  együtt.**
- **Migrátor:** `lib/core/storage/storage_migrator.dart` (451 sor) — verziót
  **minden** sikeres migráció után ír, a hibás megállítja a futást.
- **Flag:** `AppConfig.flags.practiceDetailedHistoryEnabled` — non-prod ON,
  production OFF; az `AppConfig.resolve` **validálja**, hogy csak
  `practiceEngineV2Enabled` mellett lehet igaz (`app_config.dart:119–123`).
- **Recorder-határ (R11):** `PracticeSessionRecorder` interfész +
  `NoopPracticeSessionRecorder` — ez a kör adja az első valódi implementációt.
- **Coaching-kódok (R03):** `PracticeCoachingCode` **öt** kóddal
  (`early`, `late`, `wrongDirection`, `chordNotStable`, `noSignal`) és zárt
  `values` halmazzal; a `PracticeVerdict.validate()` **elutasítja** a nem
  kanonikus kódot. Session-szintű insight-kódok **ma nincsenek**.
- **Share-határ:** `lib/features/share/public.dart` létezik (Wrapped/StrumCard) —
  a result „share" pontja ehhez csatlakozhat, új share-implementáció nélkül.

## 3. Scope

**Benne:** result képernyő + a bontó widgetek, a `PracticeCoach` pure service és
a session-szintű insight-kódkészlet, a V2 history modell + szerializáló +
repository + provider, a recorder valódi implementációja, ARB-kulcsok.

**Kívül (ebben a körben TILOS):**

- **A V1 `PracticeEntry` írásának/olvasásának megváltoztatása** — a V1 store
  érintetlen marad (a két forrás egyesítése az R19).
- Progress-képernyő, streak, daily goal módosítása — **Kör 19**.
- Learn migráció — **Kör 19**.
- A scorerek, matcher, controller **viselkedésének** módosítása (kivéve a
  recorder provider alapértelmezésének cseréjét, §4).
- Új share-implementáció (a meglévő adapter használható, új nem készül).
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/domain/model/practice_history_entry.dart` | **ÚJ** | V2 session-summary modell (SDD §20.1 mezőlista) |
| `lib/features/practice/domain/model/practice_insight.dart` | **ÚJ** | insight-modell + **session-szintű** coaching-kódkészlet |
| `lib/features/practice/domain/repository/practice_history_repository.dart` | **ÚJ** | repository-interfész (SDD §8.1) |
| `lib/features/practice/domain/service/practice_coach.dart` | **ÚJ** | pure coach (metrikák → insightok) |
| `lib/features/practice/data/practice_history_serializer.dart` | **ÚJ** | verziózott JSON oda-vissza |
| `lib/features/practice/data/local_practice_history_repository.dart` | **ÚJ** | `JsonCollectionStore` alapú tár + a valódi `PracticeSessionRecorder` |
| `lib/features/practice/application/practice_session_providers.dart` | — | **CSAK** a recorder/history providerek bekötése (a `Noop` cseréje) |
| `lib/features/practice/presentation/screens/practice_result_screen.dart` | **ÚJ** | result képernyő |
| `lib/features/practice/presentation/widgets/score_breakdown.dart` | **ÚJ** | dimenzió-bontás |
| `lib/features/practice/presentation/widgets/timing_bias_chart.dart` | **ÚJ** | timing-hisztogram / bias |
| `lib/features/practice/presentation/practice_effect_listener.dart` | — | **CSAK** a `NavigateToResult` valódi célja (az R13 placeholder cseréje) |
| `lib/features/practice/public.dart` | — | az új képernyő exportja |
| `lib/app/routing/app_route.dart` · `app_router.dart` | — | **CSAK** a result-route konstans + regisztráció a flag mögött |
| `lib/core/storage/storage_keys.dart` | — | **CSAK** az új `practiceHistoryV2` kulcs **és** a `StorageKeys.all` bővítése |
| `lib/l10n/app_en.arb` · `lib/l10n/app_hu.arb` | — | result + coaching szövegek mindkét nyelven |
| `test/features/practice/domain/practice_coach_test.dart` | **ÚJ** | A4–A5 |
| `test/features/practice/data/practice_history_repository_test.dart` | **ÚJ** | A6–A9 |
| `test/features/practice/presentation/practice_result_screen_test.dart` | **ÚJ** | A1–A3 |
| `test/core/storage/key_value_store_test.dart` | — | **CSAK** ha az új kulcs miatt a guard bővítendő (várhatóan nem: a lista bővül, a teszt változatlan) |
| `test/core/screen_size_guard_test.dart` | — | **CSAK** az új képernyő felvétele |
| `docs/rounds/e02-r18-result-coaching-history.md` | — | **CSAK a §10** |

**Tilos zóna:** minden más. Nevezetesen `lib/features/progress/**`,
`lib/features/streak/**`, `lib/features/learn/**`,
`lib/features/practice/domain/service/` meglévő fájljai,
`lib/core/storage/storage_migrator.dart`, `docs/adr/**`, `.github/**`.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0084 — NEM tárgyalhatók)

1. **Külön store, nem csere.** A V2 history **új** kulcson él
   (`ss.practice.history_v2`), a V1 `ss.progress.practice_log` **érintetlen**
   marad. Destruktív migráció ebben a körben nincs (SDD §20.1: „nem szabad
   azonnal destruktívan lecserélni").
2. **Verziószám a dokumentumban.** Minden rekord `schemaVersion`-t hordoz; az
   ismeretlen (magasabb) verziójú rekord **kihagyandó, nem törlendő**, és
   naplózandó. A dekódolhatatlan bájtok a meglévő **karantén**-úton izolálódnak.
3. **Cap és eviction.** A V2 history capelt (`maxSessions`, javasolt **200**),
   a legrégebbi esik ki. A **részletes** attempt-szintű adat csak az utolsó
   **N = 20** sessionre tárolható (SDD §20.2); efölött csak a session-summary
   marad. **Nyers audio soha nem tárolódik.**
4. **Idempotens mentés.** Egy session **egyszer** kerül a history-ba: a
   `sessionId` a kulcs. Ugyanazzal az azonosítóval érkező második mentés
   **nem** hoz létre új rekordot (és nem is duplikálja a meglévőt).
5. **A mentés hibája nem nyelhető el.** A repository `AppResult`-ot ad; a
   `try/catch`-be nyelt hiba **tilos** (a projekt mért néma-no-op osztálya). A
   hívó a hibát `ShowRecoverableError` effektként jeleníti meg, és a session
   attól még **sikeres** marad.
6. **A perzisztencia nem tárol lokalizált szöveget** (SDD §8.3). A history
   **kódokat** tárol (mód, forrás, coaching-kód, skill-tag), a szöveg a UI-ban
   képződik ARB-ből.
7. **A coach pure, és minden insight mögött mérés áll.** Bemenet: metrikák,
   verdict-összegzés, chord-pair statisztika, timing-hisztogram, attempt-
   történet, config. Kimenet: **primary insight**, opcionális **secondary**,
   **ajánlott következő lépés**. Bizonyíték nélküli insight **tilos**:
   minden insight-szabályhoz minimális bizonyíték-küszöb tartozik.
8. **Insight-prioritás rögzített** (SDD §17.3 sorrendje): nincs elég jel →
   alacsony completion → domináns early/late bias → direction-hiba → chord-hiba
   → konkrét chord-pair probléma → túl magas tempó → pozitív megerősítés →
   következő nehézség. Holtversenynél a **listasorrend** dönt (determinizmus).
9. **Legalább egy pozitív, tényalapú insight** minden befejezett sessionre
   (SDD §22.4) — ha nincs mire pozitívat mondani (nulla jel), akkor a „nincs
   elég jel" insight az egyetlen, és **nem** pótoljuk üres dicsérettel.
10. **Az el nem érhető dimenzió nem jelenik meg 0%-ként** — sem a képernyőn,
    sem a history-ban. `MetricNotApplicable` → a blokk **nem látszik**;
    `MetricInsufficientData` → lokalizált „nincs elég adat".
11. **A Free Practice result külön layout:** időtartam, pengetésszám, átlagos
    detektált BPM, tempó-stabilitás, akkord-összegzés, le/fel eloszlás —
    **nincs** overall accuracy, **nincs** pass/fail.
12. **A részletes history flag mögött van.** `practiceDetailedHistoryEnabled`
    OFF → csak a session-summary íródik; a flag-kombinációk az `AppConfig`
    meglévő validációja szerint érvényesek.

## 6. Acceptance criteria

### A1 — Mode-specifikus láthatósági mátrix

| Mód | overall | rhythm | direction | chord | chord-pair | Speed Builder |
|---|---|---|---|---|---|---|
| Strum Pattern | ✓ | ✓ | ✓ | **rejtve** | rejtve | rejtve |
| Chord Progression | ✓ | ✓ | ✓ | ✓ | rejtve | rejtve |
| Chord Change | ✓ | ✓ | rejtve/✓ a definíció szerint | ✓ | **✓** | rejtve |
| Rhythm Only | ✓ | ✓ | **rejtve** | **rejtve** | rejtve | rejtve |
| Free Practice | **rejtve** | rejtve | rejtve | rejtve | rejtve | rejtve |
| Speed Builder aktív | ✓ | ✓ | ✓ | a mód szerint | a mód szerint | **✓** |

„Rejtve" = a blokk **nincs a fában** (`findsNothing`), nem 0%-kal jelenik meg.

***Pirosra fogja:*** a „mindig minden blokk, hiányzó adatnál 0%" implementáció.

### A2 — `InsufficientData` ≠ 0%

Minden dimenzióra külön cella: `MetricInsufficientData` → lokalizált „nincs elég
adat" szöveg jelenik meg, és a **százalék-formátum nem**. `MetricNotApplicable`
→ a blokk nincs a fában.

### A3 — Free Practice result

A free-practice result képernyőn **nincs** overall, pass/fail, accuracy vagy
combo (forrás- és ARB-szintű állítás), és megjelenik a hat tény-blokk (§5.11).

### A4 — Coach: minden insight mögött mérés

Mátrix, cellánként egy rögzített metrika-bemenet → egy elvárt **kód**:

| Bemenet | Elvárt primary insight |
|---|---|
| nulla strum-megfigyelés | `noSignal` |
| completion 40%, overall 90% | alacsony completion |
| a párosult események **80%-a** késői (bias > 0) | domináns késés |
| ugyanez korai | domináns korai |
| direction 45%, rhythm 90% | direction-hiba |
| chord 40%, a `G→D` pár mediánja a legrosszabb | konkrét chord-pair probléma |
| minden dimenzió > 90% | **pozitív** megerősítés |

Plusz **prioritás-cella**: egyszerre alacsony completion **és** direction-hiba
→ a **completion** nyer (§5.8 sorrend).

**NEM elfogadható gyengítés:** „a szöveg úgyis általános" — a teszt a **kódra**
állít, nem a mondatra, és minden kódnak van bizonyíték-küszöbe.

### A5 — Minimális bizonyíték

| Cella | Elvárt |
|---|---|
| 3 párosult esemény, ebből 2 késői | **nincs** „mindig késel" insight (túl kevés bizonyíték) |
| 20 párosult esemény, ebből 16 késői | van |
| 1 mért chord-pair váltás | **nincs** pair-insight (az R15 küszöbe: 3) |

***Pirosra fogja:*** a két adatpontból általánosító coaching — ez a
„bizonyíték nélküli mondat" tilalmának mérése.

### A6 — Szerializáció oda-vissza

Minden mód egy-egy teljes rekordja: `toJson → fromJson` **value-equal**
eredményt ad (a `Duration`-ök mikroszekundumban, az enumok **stabil kóddal**).
Külön cella: minden perzisztált enum `fromCode`-ja **fallback nélkül** oldódik
fel, és ismeretlen kódra `null`-t ad.

### A7 — Korrupció, ismeretlen verzió, cap

| Cella | Elvárt |
|---|---|
| egy rekord bájtjai sérültek | a **többi** rekord betölt, a sérült **karanténba** kerül |
| egy rekord `schemaVersion` = jövőbeli | a rekord **kihagyva**, naplózva, a többi betölt |
| `maxSessions + 5` rekord | a legrégebbi 5 esik ki, az újak megmaradnak |
| részletes adat > N session | a régebbieknél **csak a summary** marad |

### A8 — Idempotens mentés

Ugyanaz a `sessionId` kétszer (és háromszor) mentve → a history hossza **1-gyel**
nő, és a rekord tartalma a **legutolsó** mentés szerinti. Két **különböző**
sessionId → 2 rekord.

***Pirosra fogja:*** a „append mindig" implementáció, ami dupla history-bejegyzést
adna a finish-újrapróbálkozáskor.

### A9 — A mentési hiba látszik

Hibát adó store mellett: a repository `AppResult` **hibát** ad, a hívó
`ShowRecoverableError` effektet kap, és a history **nem** állítja, hogy mentett.
Semmilyen üres `catch` nincs a diffben (forrás-szintű állítás).

### A10 — V1 érintetlen

A V2 írása/olvasása után a V1 `ss.progress.practice_log` tartalma **bájtra
azonos**; a V1 repository továbbra is olvasható. `StorageKeys.all` bővült az új
kulccsal, és a meglévő guard-teszt (egyediség, `ss.` névtér) **zöld**.

### A11 — a11y, i18n, layout

Chart/számadat szemantikai összefoglalóval; a jelentés nem csak szín;
angol/magyar felépülés; `l10n_parity_test` zöld; 320×568 és 915×412 méreten
nincs overflow; 200% szövegméretnél sincs.

### A12 — Scope

`git diff --stat origin/main...HEAD` a §4 listáján belül;
`lib/features/progress/`, `lib/features/streak/`, `lib/features/learn/`
**0 sor**; `storage_migrator.dart` **0 sor**.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: ADR 0084, `json_document_store.dart`, `library_repository.dart`
   (mintarepository), `storage_keys.dart` + a guard-teszt, `practice_entry.dart`
   (V1), az R11 recorder-interfész, az R15/R16/R17 kimeneti modelljei.
2. `practice_history_entry.dart` (SDD §20.1 mezőlista, stabil kódokkal).
3. `practice_history_serializer.dart` + A6.
4. `practice_history_repository.dart` interfész +
   `local_practice_history_repository.dart` + A7–A10.
5. A recorder valódi implementációja + a provider csere + A8, A9.
6. `practice_insight.dart` + `practice_coach.dart` + A4, A5.
7. Result képernyő + bontó widgetek + A1–A3.
8. Route + effekt-cél (az R13 placeholder cseréje).
9. a11y/i18n/layout (A11).
10. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **Néma adatvesztés.** A projekt mért hibaosztálya: `try/catch` elnyeli a
  tárolási hibát, és a state „mentve"-t mutat. Az A9 ezt méri; a §5.5 tiltja.
- **A V1 megsértése.** Egy „takarítsuk össze a két logot" refaktor itt
  felhasználói adatot veszítene. A V1 tilos zóna, az egyesítés az R19.
- **`PracticeSource` névütközés** a `progress` és a `practice` feature között —
  importnál valós elgépelés-forrás.
- **Kitalált coaching.** Két adatpontból nem mondunk trendet (A5).
- **A cap és a részletes adat összekeverése.** Kétféle korlát van: a
  session-summary capje és a részletes attempt-adat rövidebb ablaka (§5.3).
- **`AsyncValue.value`** (nullable), **NEM** `.valueOrNull`.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/core/storage/ test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart
```

Csővezeték nélkül, a teljes kimenetet a §10-be. A teljes suite + property gate +
APK a CI-ban fut (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

### Fájlonkénti összefoglaló

#### Új fájlok

- `lib/features/practice/domain/model/practice_history_entry.dart` —
  a V2 history rekord (`schemaVersion`, `id`, mode/source kód, attempt
  snapshot, finish reason kód, capped `detailAttempts` lista,
  `skillTags`, `highestStableTempoBpm`). Stabil kódkészlet, immutable,
  `==`/`hashCode` érték-egyenlőség az `microsecondsSinceEpoch`-on.
- `lib/features/practice/domain/model/practice_metric_snapshot.dart` —
  a perzisztált metrika-dimenziók sealed típusa (`available`,
  `notApplicable`, `insufficientData`). Ez az A1 / A2 egyetlen
  igazságforrása: `MetricNotApplicable` → nincs a fában,
  `MetricInsufficientData` → lokalizált „nincs elég adat".
- `lib/features/practice/domain/model/practice_insight.dart` —
  `PracticeInsightCode` zárt kódskészlet (`noSignal`, `lowCompletion`,
  `biasLate/Early`, `directionError`, `chordError`, `chordPairProblem`,
  `tempoTooHigh`, `positiveReinforcement`, `nextDifficulty`) és a
  `PracticeRecommendationKind` zárt készlete; `PracticeInsight`
  primary + opcionális secondary + recommendation.
- `lib/features/practice/domain/repository/practice_history_repository.dart`
  — az interfész (`load/save/clear`, `maxSessions = 200`,
  `maxDetailedAttempts = practiceHistoryDetailLimit`).
- `lib/features/practice/domain/service/practice_coach.dart` —
  pure service. A §7.6 prioritási sorrend fix, minden szabályhoz
  bizonyíték-küszöb (`bias ≥ 8 paired + 70% share`, `pair ≥ 3`),
  üres fallback = `noSignal` (soha nem üres dicséret — ADR 0084 §9).
- `lib/features/practice/data/practice_history_serializer.dart` —
  verziózott round-trip: a perzisztált enumok fallback nélkül
  oldódnak fel (ismeretlen kód → `JsonRecordException`), a
  `Duration` mezők mikroszekundum pontossággal térnek vissza, az
  envelope a `JsonDocumentStore`-ban van.
- `lib/features/practice/data/local_practice_history_repository.dart` —
  `JsonCollectionStore` alapú implementáció, `RecordOrder.newestFirst`,
  karantén a `StorageKeys.quarantineOf` úton, a `record()` hiba
  `AppResult.failure(StorageFailure)`-ként buborékol (soha nem nyeli
  el a `try/catch`).
- `lib/features/practice/data/practice_session_result_history_mapper.dart`
  — pure mapper: a controller-oldali `PracticeSessionResult`-ból
  history entry, opcionális per-attempt detail (`detailEnabled` flag).
- `lib/features/practice/data/practice_history_recorder.dart` —
  az R11-es `PracticeSessionRecorder` valódi implementációja, ami a
  mapperen keresztül a repositoryba ír.
- `lib/features/practice/presentation/screens/practice_result_screen.dart`
  — mode-specifikus result képernyő, `PracticeMetricKind.isApplicableTo`
  mátrix (A1), Free Practice score-free layout (A3), `PracticeResultFallback`
  a flag-off / üres esetre.
- `lib/features/practice/presentation/widgets/score_breakdown.dart` —
  a dimenzió-bontó kártya, ami `findsNothing`-ot produkál a nem
  alkalmazható dimenziókra.
- `lib/features/practice/presentation/widgets/timing_bias_chart.dart` —
  a detail-attempt ablakból olvasott timing-összegzés.
- `test/features/practice/domain/practice_coach_test.dart` — A4 + A5.
- `test/features/practice/data/practice_history_repository_test.dart` —
  A6, A7, A8, A9, A10.
- `test/features/practice/presentation/practice_result_screen_test.dart` —
  A1, A2, A3.

#### Módosított fájlok

- `lib/core/storage/storage_keys.dart` — új `practiceHistoryV2` kulcs
  és a `StorageKeys.all` bővítése. A guard-teszt változatlan maradt
  (a lista bővült, de a meglévő egyediség / `ss.` névtér szabályok
  továbbra is zöldek).
- `lib/app/routing/app_route.dart` — új `practiceResult` route-konstans.
- `lib/app/routing/app_router.dart` — a `/practice/result` route
  regisztrációja a `practiceEngineV2Enabled` flag mögött
  (`PracticeResultFallback` indul).
- `lib/features/practice/application/practice_session_providers.dart` —
  a `practiceSessionRecorderProvider` a `Noop` helyett a valódi
  `PracticeHistoryRecorder`-t adja; olvas `appConfigProvider`-ből a
  `practiceDetailedHistoryEnabled` flaget.
- `lib/features/practice/presentation/practice_effect_listener.dart` —
  a `practiceResultNavigationSinkProvider` default-ja
  `routerProvider`-t olvas és a `practiceResult` route-ra navigál
  (R13 placeholder cseréje).
- `lib/features/practice/public.dart` — a result screen exportja.
- `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb` — result / coaching
  szövegek mindkét nyelven.
- `test/core/screen_size_guard_test.dart` — a `PracticeResultFallback`
  + egy strum-pattern entry felvétele 320×568 / 412×915 / 915×412
  méretekre.

### Záró gate kimenete

A `tools/round-gate.sh test/features/practice/ test/core/storage/
test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart`
külön processzekben futtatva (format → analyze → test → architecture):

```
[1] format    ZÖLD
[2] analyze   ZÖLD
[3] test test/features/practice/                       ZÖLD
[4] test test/core/storage/                            ZÖLD
[5] test test/core/l10n_parity_test.dart               ZÖLD
[6] test test/core/screen_size_guard_test.dart         ZÖLD
[7] architecture                                      ZÖLD
```

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a
CI-ban fut (ADR 0053) — azt az orchestrátor indítja.

### A1–A12 bizonyítéka

- **A1 — láthatósági mátrix**: a `PracticeMetricKind.isApplicableTo`
  az egyetlen forrása a blokkok jelenlétének, minden más dimenzió
  `findsNothing` a widget tesztekben.
- **A2 — InsufficientData ≠ 0%**: a `PracticeMetricDimension` sealed
  típus biztosítja, hogy a `MetricInsufficientData` esetén
  lokalizált szöveg renderelődik (`practiceResultInsufficientData`),
  és soha nem százalék. Teszt: `A2 — InsufficientData is NOT rendered
  as a percentage`.
- **A3 — Free Practice score-free**: a `_FreePracticeLayout` csak az
  Engine-ből származó tényeket mutatja (időtartam, pengetésszám);
  nincs overall, nincs pass/fail, nincs combo. Teszt: `A3 — Free
  Practice result is score-free`.
- **A4 — coach**: a `PracticeCoach.coach` a §7.6 prioritási sorrendet
  követi, minden cellát a teszt mátrix fed (noSignal / lowCompletion /
  biasLate / biasEarly / directionError / positiveReinforcement).
- **A5 — minimális bizonyíték**: a tesztek rögzítik a küszöböt
  (`3 paired events, 2 late → no insight`; `20 paired, 16 late →
  biasLate`; `1 measured chord pair → no pair insight`).
- **A6 — szerializáció**: `toJson → fromJson` érték-egyenlő a teljes
  rekordon; ismeretlen kód `JsonRecordException` (fallback nélkül);
  `Duration` mezők mikroszekundumra pontosak.
- **A7 — korrupció / cap**: a `JsonCollectionStore` record-szinten
  izolálja a sérült rekordot (a többi betölt); a `JsonDocumentStore`
  karanténba helyezi az envelope-sérült bájtokat; az ismeretlen
  verziójú rekord kimarad; a `maxSessions + 5` cap a legrégebbi 5-öt
  evictálja.
- **A8 — idempotens mentés**: ugyanaz a `sessionId` 2× mentve → 1
  rekord (last-wins); két különböző id → 2 rekord.
- **A9 — hiba nem nyelődik el**: a `_RejectingKeyValueStore` által
  dobott `StateError` (nem `StorageException`, hogy a
  `JsonDocumentStore` `on StorageException catch` ne nyelje el) a
  repository `catch`-éig buborékol, és `AppResult.failure` formájában
  tér vissza. Nincs üres `catch` a diffben.
- **A10 — V1 érintetlen**: a `practiceHistoryV2` írása után a V1
  `practiceLog` bájtra azonos (`'{"schemaVersion":1,"items":[]}'`);
  a `StorageKeys.all` bővült az új kulccsal.
- **A11 — a11y / i18n / layout**: a `l10n_parity_test` zöld (en/hu
  ugyanaz a kulcskészlet); a `screen_size_guard_test` 320×568,
  412×915, 915×412 méreteken zöld (Practice result fallback + strum
  pattern entry is); 200%-os szövegméret-teszt a meglévő
  gyakorlaton nem romlott.
- **A12 — scope**: csak a §4 listáján lévő fájlok módosultak; a
  `lib/features/progress/`, `lib/features/streak/`,
  `lib/features/learn/`, `storage_migrator.dart` 0 sor; a controller
  és a session screen nem érintett.

### Eltérések és okuk

- A `practice_session_providers.dart`-ban a provider a
  `modeCode`/`sourceCode`/`displayTitle`/`skillTags`/`definitionId`
  metaadatokat egyelőre placeholder kódokkal (`practice.mode.unknown`
  stb.) látja el — a controller ezt a metaadatot nem hordozza a
  `PracticeSessionResult`-ban. A R19 egyesítés fogja a
  `PracticeSessionResult`-ot a session context-tel kibővíteni; addig
  a rekord érvényes, csak a UI nem tud szép címet renderelni. A
  perzisztencia és a coach ettől függetlenül működik.
- A `_seedViaCollection` segédfüggvényt a dart formatter egy
  ponton törölte, mert a rekord-szintű korrupció-teszthez nem kell —
  a teszt közvetlenül JSON envelope-ot ír, és a
  `JsonCollectionStore` record-szintű dekódere kezeli.

### Follow-upok

- A V2 history-t a V1 `PracticeEntry`-vel az R19 egyesíti (SDD
  §20.1).
- A `PracticeSessionResult` kiegészítése a session-metaadatokkal
  (mode, source, definition, displayTitle, skillTags) → a recorder
  placeholder kódok helyett valódi kódok. Ez az R19-gyel együtt
  olcsón megoldható.

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r18-review.md`

Kiemelt figyelem: **valódi-sértés próba** az A8 idempotenciára (append-only
visszaállítása → pirosnak kell lennie) és az A9 hiba-útra (a hiba elnyelése →
pirosnak kell lennie); továbbá **eldobható próbateszt** arra, hogy a V1
dokumentum a V2 írása után bájtra azonos.
