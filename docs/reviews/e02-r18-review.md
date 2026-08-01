# E02-R18 Review — Result, coaching és Practice History V2

- **Kör:** E02-R18 · branch `codex/e02-r18-result-coaching-history` · HEAD `6414993`
- **Implementer:** MiniMax M3 · **Reviewer:** Claude (Opus 4.8), read-only
- **Review-dátum:** 2026-08-01
- **Gate (reviewer, izolált `/tmp/review-e02r18` klón):** `GATE_EXIT=0`
  (format → analyze → test ×4 → architecture, `flutter gen-l10n` után).
- **CI:** [run 30688117567](https://github.com/wolfcasaba/strumsight/actions/runs/30688117567)
  **success** a `6414993` HEAD-en (teljes suite + randomizált property + APK).
- **Verdikt (1. kör):** **CHANGES REQUESTED** — 2 BLOCKER + 4 MAJOR nyitva.
- **Verdikt (fix#1 után):** **✅ APPROVED** — minden lelet zárva (lásd §Fix#1 lezárás).

> A zöld gate NEM bizonyíték (ADR 0052 / L21). Mindkét BLOCKER zöld CI **és** zöld
> reviewer-gate mellett csúszott át; eldobható próbatesztek fogták meg őket az
> izolált `/tmp/review-e02r18-probe` klónban. A próbatesztek a klónban maradnak,
> a branchre nem kerülnek.

## Súlyossági összefoglaló

| # | Súly | Terület | Egy sor |
|---|---|---|---|
| B1 | **BLOCKER** | A9 / perzisztencia | Reális írás-hiba (`StorageException`) elnyelődik → `Success`, néma adatvesztés |
| B2 | **BLOCKER** | Produkciós recorder | A recorder `unknown` mode/source kóddal ír → a szerializáló olvasáskor **eldobja** minden rekordot (write-then-drop) |
| M1 | **MAJOR** | Scope | 3 új fájl a §4 listán kívül (jóváhagyható §0.0 revízióval) |
| M2 | **MAJOR** | A7 / detail-window | Az „utolsó N=20 session tart részletet" szabály nincs implementálva (a két cap összekeverve) |
| M3 | **MAJOR** | Timing chart | A bias-címke a `snapshot`-ot figyelmen kívül hagyja → mindig „balanced" |
| M4 | **MAJOR** | A4 coach-teszt | Két kötelező A4-cella (pozitív chord-pair; completion↔direction holtverseny) teszteletlen |
| m1 | MINOR | score_breakdown | `NotApplicable` „Not scored" sorként renderel (ADR §10: `findsNothing`) — két igazságforrás |
| m2 | MINOR | A1-teszt | Hardkódolt `'Chord'`/`'Direction'` literál az l10n-címke helyett |
| m3 | MINOR | result screen | Speed Builder sor holt kód (`speedBuilder.isApplicableTo` mindig false) |
| n1 | NOTE | result screen | Free Practice „strum count" tile az `attemptsCount`-ot mutatja (R19 metadata-followup) |

## BLOCKER B1 — A9 néma no-op: a reális írás-hiba `Success`-t ad

**Fájl:** `lib/features/practice/data/local_practice_history_repository.dart` (`save()`
`await store.write(next)`) + `lib/core/storage/json_document_store.dart:103-129`.

A `KeyValueStore` szerződése (`key_value_store.dart:19-21`): „Writes never fail
silently. A platform-level write failure completes the future with a
`StorageException`." A `JsonDocumentStore.write()` viszont `} on StorageException
catch (…) { logger.error(…) }` — **elnyeli és NEM dobja tovább**. Így a repository
`save()`-je a reális platform-írás-hibára is `Success`-t ad, miközben semmi nem
íródott ki. **Ez pontosan a kör által megcélzott mért néma-adatvesztés osztály**
(ADR 0084 §5, brief §8).

A **szállított** A9-teszt (`practice_history_repository_test.dart:326-347`)
szándékosan **`StateError`-t** (nem `StorageException`) dob, és a saját kommentje
kimondja: „so the JsonDocumentStore catch does NOT swallow it" — azaz a teszt a
reális hibatípus **köré** van írva. A garancia nem valódi.

**Próba (RED):** `review_probe_test.dart` → egy `StorageException`-t dobó store
mellett `record()` → `PROBE_A9_RESULT: Success<void>`.

**Irány:** a repository a `StorageException` írás-hibát `AppResult` **failure**-ként
kell felszínre hozza. A `JsonDocumentStore.write` a `core/storage` (tilos) zónában
elnyel — ezért az allowed `local_practice_history_repository.dart`-on belül kell
propagáló írás-utat adni: pl. **írás utáni visszaolvasás-ellenőrzés** (a
`JsonCollectionStore` állapotmentes, diszkről olvas — ha az írás elnyelt hibával
elmaradt, a visszaolvasás nem találja az új rekordot → `failure`), vagy a
`KeyValueStore` közvetlen használata a rekord-írásra (az propagálja a
`StorageException`-t). **Nem** kell a `core/storage`-hoz nyúlni.

## BLOCKER B2 — a produkciós recorder eldobásra ítélt rekordokat ír (write-then-drop)

**Fájl:** `lib/features/practice/application/practice_session_providers.dart:76-78`.

A `practiceSessionRecorderProvider` a mappert **hardkódolt** `modeCode:
'practice.mode.unknown'`, `sourceCode: 'practice.source.unknown'`,
`definitionId: 'practice.definition.unknown'` értékekkel köti. A szerializáló
**olvasáskor** elutasítja az ismeretlen mode/source kódot
(`practice_history_serializer.dart:77-86`: `practiceModeFromCode(code)==null →
throw JsonRecordException`), amit a `JsonCollectionStore.read` rekordonként
kihagy. **Így minden produkciósan rögzített session íródik, majd betöltéskor
eldobásra kerül.**

**Próba (RED):** a produkciós wiringgel mentve `PROBE_PROD_SAVE: Success`, de
`PROBE_PROD_LOADED_LEN: 0` — nulla betölthető rekord. Az A6/A8/A10 tesztek csak
azért zöldek, mert **valós kódokat injektálnak közvetlenül**, megkerülve a
szállított wiringet. A handoff §Eltérések „a rekord érvényes" állítása téves.

**Gyökérok (mért):** a `recorder.record(result)` csak `PracticeSessionResult`-ot
kap, amely **nem hordoz** mode/source/definitionId mezőt (a modell R10-ből
zárt). A valós metaadat a `PracticeSessionConfig`-ban él, amit csak a **controller**
ismer — az viszont a §4 tilos zóna, és nincs provider, amely a futó session
configját kiadná (`practice_session_providers.dart:133-137`: a
`practiceSessionControllerProvider` **még nincs is definiálva**).

**Irány (a javító körnek):** a kör NEM szállíthat write-then-drop utat („no demos
— real functionality"). Két elfogadható, **in-scope** kimenet:
1. a recorder ne írjon olyan rekordot, amit garantáltan eldob — a live rögzítés
   **valós metaadatig (R19) dokumentáltan halasztva**, a `providers`-fájlban, egy
   teszttel, amely bizonyítja, hogy **nem** keletkezik betölthetetlen rekord; VAGY
2. ha a valós mode/source in-scope megszerezhető (allowed provideren át), azzal írjon.

**Halt-figyelmeztetés:** ha a valós metaadat bekötése **kizárólag** zárt körök
fájljainak módosításával lehetséges (`practice_session_result.dart` R10,
`practice_session_recorder.dart` interfész R11, vagy a controller), akkor az
**H2/H3** — a javító kör NE tegye meg, hanem `stopped`-dal jelezze, és az
orchestrátor halttal embert vár.

## MAJOR M1 — scope: 3 új fájl a §4 engedélyezett listán kívül

`data/practice_history_recorder.dart`, `data/practice_session_result_history_mapper.dart`,
`domain/model/practice_metric_snapshot.dart`. Egyik sem tilos zónában van; mind
jóindulatú, feature-en belüli dekompozíció (a recorder+mapper a repositoryból
kiemelve; a snapshot a szerializáló/screen által igényelt sealed modell). A brief
szigorú szabálya szerint („új fájl a listán kívül = scope-sértés") ez legalább
MAJOR. **Feloldás:** az orchestrátor **§0.0 brief-revízióval elfogadja** a három
fájlt (a dekompozíció tiszta és teszthetőbb) — a fold-back felesleges diff-hízlalás
volna. A **valódi** tilos zónák (progress/streak/learn, meglévő `domain/service`
fájlok, `storage_migrator.dart`, más ADR-ek, `.github`) **0 sor** (A12 tilos-zóna
rész zöld).

## MAJOR M2 — A7 detail-window (utolsó N=20 session) nincs implementálva

**Fájl:** `practice_session_result_history_mapper.dart:58-68` +
`local_practice_history_repository.dart` `save()`.

ADR 0084 §Döntés 3 / SDD §20.2: csak a legújabb **20 session** tart per-attempt
részletet; a régebbiek csak summaryt. A kód a `practiceHistoryDetailLimit=20`-at
**csak egy session-en belüli attempt-index capként** alkalmazza (mapper:61), és
mentéskor **soha nem foszt meg** régebbi sessiont a részletétől — mind a max. 200
megtartott session tartja a részletét. Ez a brief §8 „két korlát összekeverése"
kockázata. Az A7 negyedik cellája („részletes adat > N session → csak summary")
sem implementálva, sem tesztelve. **Irány:** mentéskor csak a legújabb
`practiceHistoryDetailLimit` session tartsa a részletet, a többiről strippelni;
+A7-teszt.

## MAJOR M3 — a timing chart mindig „balanced"

**Fájl:** `lib/features/practice/presentation/widgets/timing_bias_chart.dart:46-48`.

A `_biasDirectionLabel` a `snapshot` argumentumát figyelmen kívül hagyja, és
feltétel nélkül `l10n.practiceResultTimingBalanced`-t ad. Az előjeles
`timingBias` sosem olvasódik. Erősen késői/korai sessionre is „kiegyensúlyozott"
timinget jelent — félrevezető tartalom, amit a gate átenged (nincs teszt a
bias-tükrözésre; A11 „a jelentés nem csak szín"). **Irány:** a címkét a
`timingBias`-ból (early/late/balanced küszöbökkel) származtatni + teszt késői
biasú fixture-rel.

## MAJOR M4 — A4 coach-mátrix hiányos

**Fájl:** `test/features/practice/domain/practice_coach_test.dart`.

Két A4-cella teszteletlen: (a) a `chordPairProblem` **pozitív** eset („chord 40%,
`G→D` pár mediánja legrosszabb → chord-pair probléma") — csak a negatív egy-páros
eset van (A5:156-178); (b) a prioritás-holtverseny („egyszerre alacsony
completion ÉS direction-hiba → completion nyer") — a lowCompletion-teszt
(25-36) `direction`-t NotApplicable-re hagyja, tehát nem gyakorolja a holtversenyt.
A coach-**kód** mindkettőt helyesen valósítja meg, de az acceptance csak
prózában/handoffban állítva. **Irány:** a két cella pótlása.

## MINOR

- **m1** `score_breakdown.dart:57`: az `applicable-but-NotApplicable` dimenzió
  „Not scored" sorként renderelne, holott az ADR §Döntés 10 `findsNothing`-et ír.
  Ma maszkolva, mert a mode-mátrix és az aggregátor egyezik — két igazságforrás,
  ami elcsúszhat.
- **m2** `practice_result_screen_test.dart:42,48`: hardkódolt `'Chord'`/`'Direction'`
  literál az l10n-címke helyett — törékeny az ARB-copy változására.
- **m3** `practice_result_screen.dart:283-306,121-129`: a Speed Builder blokk holt
  kód (`speedBuilder.isApplicableTo(mode)` mindig false), az A1 „Speed Builder
  aktív → ✓" ezen a képernyőn elérhetetlen.

## NOTE

- **n1** `practice_result_screen.dart:161-164`: a Free Practice „strum count" tile
  az `attemptsCount`-ot mutatja (attempt-szám, nem pengetésszám) — a valós
  sessionök beérkezésekor rosszul olvas (R19 metadata-followup, B2-hez kötve).
- A handoff (§10) teljes, csonkítatlan, `status=done`, a gate-tábla mind a hét
  lépést zöldnek mutatja; az egyetlen érdemi téves állítás a §Eltérések „a rekord
  érvényes", amit B2 cáfol.

## Zöld keresztellenőrzések (bizonyítékkal)

- A8 idempotencia **valódi** (`save()` azonos id-t szűr, elé fűz) — próba GREEN.
- A1/A2/A3 widget-tesztek GREEN; az A2 helyesen bizonyítja `InsufficientData →
  lokalizált szöveg, `%` nélkül`.
- A10 V1-érintetlenség: külön kulcs, V1 bájtok változatlanok — teszt GREEN.
- Szerializáló: ismeretlen kód → `JsonRecordException` (fallback nélkül), Duration
  µs-pontosság, jövőbeli `schemaVersion` kihagyva, sérült rekord karanténba — mind
  lefedve. `StorageKeys.practiceHistoryV2` felvéve a `StorageKeys.all`-ba (guard ép).

## Következő lépés

Javító kör **MiniMax M3**-mal (a lánc normál útja), a fenti B1/B2/M2/M3/M4 + m1–m3
leletlistával; az M1 scope-ot az orchestrátor §0.0 revízióval elfogadja. A B2
halt-figyelmeztetés kötelező eleme a javító-promptnak.

---

## Fix#1 lezárás — 2026-08-01, commit `30b8b1d` (MiniMax M3)

**Reviewer-gate (friss `/tmp/review-e02r18-fix` klón, HEAD `30b8b1d`):** `GATE_EXIT=0`
(format → analyze → test ×4 → architecture). **CI:**
[run 30689227628](https://github.com/wolfcasaba/strumsight/actions/runs/30689227628)
**success** a `30b8b1d` HEAD-en (teljes suite + randomizált property + APK).
**Scope-audit:** a fix diff **0** tilos-zóna fájlt érint (nincs controller /
recorder-interfész / `practice_session_result.dart` / `core/storage` /
progress/streak/learn / `.github`).

| # | Zárás | Bizonyíték (a hibát PIROSRA fogó teszt a szállított suite-ban) |
|---|---|---|
| **B1** | ✅ | A repository közvetlenül a `KeyValueStore.writeString`-gel ír (propagálja a `StorageException`-t), és `Failure(StorageFailure(storageWrite))`-ot ad; a régi `JsonDocumentStore.write` elnyelő útját elkerüli. Új teszt `_RejectingKeyValueStore`-ral (`practice_history_repository_test.dart:235-254`): a `StorageException` írás-hiba **failure**-ként buborékol, a cause megőrzött. |
| **B2** | ✅ | Honest deferral: a provider `NoopPracticeSessionRecorder`-t ad, amíg a mode/source/definition placeholder — **nincs** write-then-drop. `practice_history_recorder_test.dart` (B2 group): a produkciós wiring `record()`-ja `Success` **írás nélkül**, és a load **0** rekordot ad (nincs eldobható bájt). A valós metaadat-plumbing dokumentáltan **R19**. |
| **M1** | ✅ | A 3 dekompozíciós fájl a brief §0.0 R1 revíziójával elfogadva. |
| **M2** | ✅ | Detail-window implementálva: `practice_history_repository_test.dart:147-193` — `N+5` session mentése után a legújabb 20 tartja a `detailAttempts`-ot, a régebbiek summaryre strippelve (a summary megmarad). |
| **M3** | ✅ | `timing_bias_chart_test.dart` (M3 group): +30 ms → „late", −25 ms → „early", ±15 ms és 0 → „balanced". |
| **M4** | ✅ | `practice_coach_test.dart`: pozitív `chordPairProblem` cella (`G→D` median-worst, ≥3 mérés) + completion↔direction holtverseny valós `MetricAvailable` directionnel → completion nyer. |
| **m1** | ✅ | `NotApplicable` már nem „Not scored" sorként renderel. |
| **m2** | ✅ | Az A1-teszt l10n-címkéket használ. |
| **m3** | ✅ | A Speed Builder holt ág kezelve. |

**Merge-döntés:** a zöld kapu (ADR 0052) minden eleme zöld a kör-branch **exact
HEAD**-jén (`30b8b1d`): format + analyze + architecture + teljes CI-suite +
randomizált property + APK. **Squash-merge engedélyezve.**
