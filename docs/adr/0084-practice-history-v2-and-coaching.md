# ADR 0084 — Practice History V2, PracticeCoach és a mode-specifikus result

**Státusz:** elfogadva (E02-R18 pre-flight, 2026-08-01).
Épít az [ADR 0068](0068-practice-domain-model-contracts.md) (`PracticeMetrics`,
`MetricValue`, coaching-kód-készlet), [ADR 0070](0070-builtin-practice-catalog-contract.md)
(`PracticeDefinition`, stabil `builtin.<slug>.v1` ID-k), [ADR 0076](0076-practice-scoring-dimensions.md)
(scorerek, `PracticeScoreAggregator`, `MetricNotApplicable`/`MetricInsufficientData`),
[ADR 0077](0077-practice-session-controller.md) (`PracticeSessionController`,
`PracticeSessionResult`, `PracticeSessionRecorder`, `NavigateToResult`/`ShowRecoverableError`
effektek), [ADR 0081](0081-chord-change-measurement.md) (chord-pair statisztika),
[ADR 0082](0082-free-practice-honest-summary.md) (`FreePracticeSummary`) és
[ADR 0083](0083-speed-builder-and-adaptive-policy.md) (`SpeedBuilderState`) döntéseire.
A verziózott perzisztenciát az Epic 1 [ADR 0054](0054-versioned-user-content-documents.md)
adja (`JsonDocumentStore`, `JsonCollectionStore`, karantén).
Kör: [`docs/rounds/e02-r18-result-coaching-history.md`](../rounds/e02-r18-result-coaching-history.md).
SDD: [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md)
§17, §20.1–20.2, §21.5, „Kör 18".

## Kontextus

A Practice Engine eddig **mért**, de nem **mutatott** és nem **tárolt** semmit
tartósan: a `PracticeSessionRecorder` egyetlen implementációja a
`NoopPracticeSessionRecorder`, a `NavigateToResult` effekt célja az R13-óta
placeholder, és a coaching csak event-szintű kódokként (`PracticeCoachingCode`,
öt kód) létezik — session-szintű, mérésből levezetett insight nincs.

Ez a kör három összetartozó dolgot ad: (1) **mode-specifikus result képernyő**,
csak az alkalmazható dimenziókkal; (2) **PracticeCoach** pure service, amely
kizárólag mérésből választ lokalizálható insight-**kódokat**; (3) **Practice
History V2** — verziózott, capelt, korrupció-izolált, **idempotens**
perzisztencia, a V1 `PracticeEntry` adatok érintetlenül hagyásával.

### Mért kiindulás (`main` @ `0e31bc6`, pre-flight 2026-08-01)

1. **Recorder-határ:** `lib/features/practice/domain/repository/practice_session_recorder.dart`
   — `abstract interface class PracticeSessionRecorder { Future<AppResult<void>>
   record(PracticeSessionResult) }` + `NoopPracticeSessionRecorder` (a doc szerint
   „NEM nyeli el a hibát try/catch-csel"). A production provider a `Noop`-ot köti
   (`practice_session_providers.dart:58-59`).
2. **A finish-út és a hiba-effekt MÁR be van kötve a controllerben** (mért:
   `practice_session_controller.dart:493` `await recorder.record(result)`, `:500`
   `_effectsController.add(ShowRecoverableError(error))`). A controller
   **single-flight**-et tart (`_navigateToResultEffects` őr, `:177`), és ugyanazt
   a `result` objektumot adja minden FinishPractice attemptre. **Következmény:**
   az A9 „a hívó `ShowRecoverableError`-t kap" garanciát a **controller** adja,
   ami **nincs** az engedélyezett-fájllistán → R18 nem is nyúl hozzá; az új
   repository dolga csak az, hogy a hibát `AppResult` **failure**-ként adja
   vissza (soha nem néma `catch`). Az idempotencia a **repository** szintjén
   (sessionId-kulcs) külön garancia, a controller single-flightjától függetlenül.
3. **`PracticeSessionResult`** (`practice_session_result.dart:38`): `id`,
   `activeDuration`, `pausedDuration`, `attempts` (`List<PracticeAttemptResult>`),
   `finishReason` (`PracticeFinishReason`, stabil `code`), `highestStableTempo`
   (`Tempo?`), `coachingSummary` (`List<String>`). A V2 history-entry ebből és a
   `PracticeMetrics`/összegzőkből épül; a `PracticeSessionResult` **nem** változik.
4. **Metrika-állapotok** (`practice_metrics.dart:7-93`): `MetricValue` sealed,
   altípusok `MetricAvailable(double ∈ [0,1])`, `MetricNotApplicable()`,
   `MetricInsufficientData(reasonCode)`. A `PracticeScoreAggregator` a mód szerint
   ad `MetricNotApplicable`-t (`:59`, `:80`) — ez a result **láthatósági
   mátrixának** (A1) egyetlen igazságforrása, nem a képernyő heurisztikája.
5. **Coaching-kódok:** `PracticeCoachingCode` **`abstract final class`** String
   konstansokkal (`practice.coach.early/late/wrong_direction/chord_not_stable/no_signal`)
   és zárt `values` halmazzal (`practice_verdict.dart:42`); a
   `PracticeVerdict.validate()` elutasítja a nem kanonikus kódot. **Session-szintű**
   insight-kódkészlet ma nincs — ezt a kör adja (`practice_insight.dart`).
6. **Storage-minta:** `library_repository.dart` — `JsonCollectionStore<T>`,
   `maxItems: maxSessions = 100`, karantén a dekódolhatatlan bájtoknak
   (`StorageKeys.quarantineOf`). `StorageKeys.all` (`storage_keys.dart:84`) guard-teszt
   alatt (egyediség, `ss.` névtér). **Új kulcs csak a listával együtt.**
7. **V1 practice log:** `KeyValuePracticeLogRepository`,
   `StorageKeys.practiceLog = 'ss.progress.practice_log'`, `maxEntries = 400` —
   **tilos zóna** ebben a körben (`lib/features/progress/**`).
8. **Flag:** `AppConfig.flags.practiceDetailedHistoryEnabled` (feature_flags.dart:17,
   non-prod ON), az `app_config.dart:119-123` validálja, hogy csak
   `practiceEngineV2Enabled` mellett lehet igaz.

## Döntés — kötött, nem tárgyalható (a kör-brief §5 tükre)

1. **Külön store, nem csere.** A V2 history **új** kulcson él
   (`ss.practice.history_v2`), a V1 `ss.progress.practice_log` **érintetlen**
   marad. Destruktív migráció ebben a körben nincs (SDD §20.1). A két forrás
   egyesítése az R19 dolga.
2. **Verziószám a dokumentumban.** Minden rekord `schemaVersion`-t hordoz; az
   ismeretlen (magasabb) verziójú rekord **kihagyandó, nem törlendő**, és
   naplózandó. A dekódolhatatlan bájtok a meglévő **karantén**-úton
   (`StorageKeys.quarantineOf`) izolálódnak, a többi rekord betölt.
3. **Cap és eviction.** A V2 session-summary capelt (`maxSessions = 200`), a
   legrégebbi esik ki. A **részletes** attempt-szintű adat csak az utolsó
   **N = 20** sessionre tárolható (SDD §20.2); efölött csak a session-summary
   marad. **Nyers audio soha nem tárolódik.**
4. **Idempotens mentés.** Egy session **egyszer** kerül a history-ba: a
   `sessionId` a kulcs. Ugyanazzal az azonosítóval érkező második (és harmadik)
   mentés **nem** hoz létre új rekordot és nem duplikál — a meglévőt a legutolsó
   mentés tartalmára frissíti. Az append-only implementáció **hibás**.
5. **A mentés hibája nem nyelhető el.** A repository `AppResult`-ot ad; a
   `try/catch`-be nyelt, majd „mentve"-ként jelzett hiba **tilos** (a projekt
   mért néma-no-op osztálya). A hibát a **már meglévő controller-út**
   (`ShowRecoverableError`, §Kontextus 2) jeleníti meg; a session attól még
   **sikeres** marad.
6. **A perzisztencia nem tárol lokalizált szöveget** (SDD §8.3). A history
   **kódokat** tárol (mód, forrás, coaching-kód, skill-tag, indokkód), a szöveg
   a UI-ban képződik ARB-ből.
7. **A coach pure, és minden insight mögött mérés áll.** Bemenet: metrikák,
   verdict-összegzés, chord-pair statisztika, timing-hisztogram/bias, attempt-
   történet, config. Kimenet: **primary insight**, opcionális **secondary**,
   **ajánlott következő lépés**. Minden insight-szabályhoz **minimális
   bizonyíték-küszöb** tartozik; bizonyíték nélküli insight **tilos**.
8. **Insight-prioritás rögzített** (SDD §17.3): nincs elég jel → alacsony
   completion → domináns early/late bias → direction-hiba → chord-hiba → konkrét
   chord-pair probléma → túl magas tempó → pozitív megerősítés → következő
   nehézség. Holtversenynél a **listasorrend** dönt (determinizmus).
9. **Legalább egy pozitív, tényalapú insight** minden befejezett sessionre
   (SDD §22.4) — ha nincs mire pozitívat mondani (nulla jel), a „nincs elég jel"
   insight az egyetlen, és **nem** pótoljuk üres dicsérettel.
10. **El nem érhető dimenzió nem jelenik meg 0%-ként** — sem a képernyőn, sem a
    history-ban. `MetricNotApplicable` → a blokk **nincs a fában**
    (`findsNothing`); `MetricInsufficientData` → lokalizált „nincs elég adat"
    (nem százalék).
11. **A Free Practice result külön layout:** időtartam, pengetésszám, átlagos
    detektált BPM, tempó-stabilitás, akkord-összegzés, le/fel eloszlás — **nincs**
    overall accuracy, **nincs** pass/fail, **nincs** combo (forrás- és
    ARB-szintű állítás).
12. **A részletes history flag mögött van.** `practiceDetailedHistoryEnabled`
    OFF → csak a session-summary íródik; a flag-kombinációk az `AppConfig`
    meglévő validációja szerint érvényesek.

## Következmények

- **Pozitív:** a Practice Engine először válik láthatóvá és tartóssá; a coaching
  auditálható (kód + bizonyíték-küszöb), a perzisztencia a bevált Epic-1 storage
  mintáit követi (karantén, cap, verzió), a V1 adat védve marad.
- **Ár:** két párhuzamos practice-log-forrás (V1 progress + V2 practice) az R19
  egyesítéséig; a coach szabálykészlete és a bizonyíték-küszöbök tesztelt, de
  konzervatív — a jövőben finomítható (ADR-módosítással).
- **Kockázat:** a mért néma-adatvesztés osztály (elnyelt tárolási hiba) — az A9
  és a §5 tiltja; a V1 megsértése (tilos zóna, A10/A12 méri); a `PracticeSource`
  név-ütközés a `progress` és a `practice` feature között (import-csapda).

## Alternatívák, amelyeket elvetettünk

- **V1 azonnali destruktív lecserélése** — felhasználói adatvesztés kockázata;
  az SDD §20.1 explicit tiltja. Elvetve a külön-store + későbbi egyesítés javára.
- **Szabad-szöveges coaching** — nem auditálható, „bizonyíték nélküli mondat"
  kockázat. Elvetve a kód + minimális-bizonyíték modell javára.
- **Append-only history** — a finish-újrapróbálkozás duplikálná a rekordot
  (A8 pirosra fogja). Elvetve az sessionId-idempotencia javára.
