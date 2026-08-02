# E03-R06 — Legacy Song és Setlist adapterek

- **Státusz:** **PLANNING** (2026-08-02, pre-flight: orchestrátor Claude
  Sonnet 5, tervezési baseline: `main` @ `91b9fa9`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 6; §3.2–3.4, §25.5
- **Branch:** `codex/e03-r06-legacy-song-setlist-adapters`
- **Előfeltétel:** E03-R05 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent
- **ADR:** [0116](../adr/0116-legacy-song-setlist-migration-boundary.md)
  (a pre-flight írta, ld. §0.0)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/data/migration/legacy_song_reader.dart",
  "lib/features/song_trainer/data/migration/legacy_song_adapter.dart",
  "lib/features/song_trainer/data/migration/legacy_setlist_adapter.dart",
  "lib/features/song_trainer/data/migration/legacy_migration_report.dart",
  "test/features/song_trainer/data/migration/legacy_song_adapter_test.dart",
  "test/features/song_trainer/data/migration/legacy_setlist_adapter_test.dart",
  "test/features/song_trainer/data/migration/legacy_parity_test.dart",
  "docs/rounds/e03-r06-legacy-song-setlist-adapters.md",
]
gate_tests = [
  "test/features/song_trainer/data/migration",
  "test/features/songs",
  "test/features/learn/setlist_expected_hint_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main` és az
> elődkör merge-jét; olvasd újra az `AGENTS.md`, Chapter 1/3/4,
> `HANDOFF.md`, a releváns ADR-eket és a `docs/LESSONS.md` fájlt. `rg`-vel
> igazold a brief minden útvonalát, symbolját, state producerét, resource
> ownerét és numerikus celláját. Drift esetén dokumentáld lent §0.0-ban,
> módosítsd a scope/fájllistát, majd commitold a `PLANNING` briefet a
> körbranchre az implementer indítása előtt. A `PREPARED` brief önmagában
> nem végrehajtási engedély.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol
és nem nyit PR-t. Listán kívüli fájl, ellenőrizetlen contract, ellentmondó
acceptance, hiányzó fixture/licence, vagy nem reprodukálható mérce esetén:
`stopped` és pontos jelentés; nincs néma scope-tágítás vagy mércegyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

- A legacy modellek a `features/songs` alatt maradnak a parity referenciaforrásai.
- R01 jogtiszta fixturei és parity metrikái rendelkezésre állnak.
- R05 validator/normalizer/capability a migrált output ellenőrzési boundaryje.

A pre-flight az itt leírt tényeket újraméri. Ha bármelyik eltér, ebben a
szekcióban rögzíti a mért állapotot, a választott feloldást és annak indokát.
Üres vagy implicit revízióval a státusz nem válhat `PLANNING`-re.

**Pre-flight mérés (2026-08-02, baseline `main` @ `91b9fa9`):** a fenti három
állítás a tényleges kóddal egyezik — nincs drift, a scope/fájllista
(az ADR-en kívül) változatlan marad. `gh pr list`/`gh run list` nem mutat
párhuzamos autonóm drivert ezen a körön; nincs örökség-munkapéldány
(`ls /home/ubuntu/ss-*e03r06*` üres). A két kötelező mérési szabály
eredménye:

1. **Cél-státuszok, INPUT-tal igazolva:** a mátrix egyetlen cellája sem
   elérhetetlen célállapot — mindegyik egy VALÓDI legacy inputra
   visszavezethető:
   - `SongSourceType.legacyLocal` **már létezik** a kódban
     (`song_source.dart:49-51`, doksija: „used by the migration adapter
     only") és MA semmi nem hivatkozik rá — pontosan ez a kör az első
     valódi producer.
   - „rest" sor (mátrix) — a `pattern` `-` szlotjai a legacy
     `Song.toLesson()`/`Lesson._expand` útján ma sem termelnek eseményt
     (mérve a `song_rests.json` fixtúrán: 8 szlotból csak a 4 nem-rest ad
     `events: 4`-et) — az adapternek tehát nem KELL, és nem SZABAD
     StrumEvent-et generálnia rest-szlotra; ez konzisztens a „nincs
     kitalált chord" elvárással.
   - `SongChordEvent`/`SongStrumEvent` mezői `Duration`-alapúak
     (`start`/`duration` a chordnál, **`at`** — nem `start` — a strumnál,
     `song_event.dart:70-95,137-151`), NEM tick-alapúak; a `TempoMap` viszont
     tick-alapú (`BeatPosition`, 480 PPQ) — ez a kétféle időbázis valódi,
     kimért tény, ld. ADR 0116 Döntés 3.
2. **Erőforrás-tulajdonlás:** ennek a körnek nincs lease/lock/handle/
   subscription jellegű erőforrása (tiszta érték-transzformáló adapter,
   írás nélkül) — a szabály nem alkalmazható.

**ADR 0116 felvéve** (`docs/adr/0116-legacy-song-setlist-migration-boundary.md`,
a lenti §4 táblába bekötve, az `ai-router` TOML `allowed_paths`-ából
SZÁNDÉKOSAN kihagyva — ld. a §4 alatti megjegyzést és a Router CI
`test_all_twenty_two_briefs_match_their_committed_scope_and_gate`
szerződését) négy, a briefben implicit hagyott döntés formalizálására:

- **`LegacyMigrationReport` önálló, adapter-lokális report-típus** — nem a
  `SongValidationReport` (dokumentum-szerkezeti) vagy az `ImportWarning`
  (UI-célú) kiterjesztése; a `SongSource.warningSummary`-be egy lapos
  vetület kerül codec round-trip célból (ADR 0116 Döntés 1).
- **`Meter(beatsPerBar, 4)` mindig** — a legacy modellnek nincs denominator
  mezője, csak nyolcad-alapú `pattern`-hossz (ADR 0116 Döntés 2).
- **Esemény-időzítés közvetlen szorzással, nem kumulatív összegzéssel** —
  ugyanaz az „egyetlen kerekítési pont" elv, mint ADR 0093 §1.1, a
  wall-clock `Duration` mezőkre alkalmazva (ADR 0116 Döntés 3).
- **`SongSectionKind.custom`, „Full Song" névvel** a tagolatlan legacy dalra
  — egyik tagolt kind sem igaz állítás egy section-mentes legacy rekordról
  (ADR 0116 Döntés 4).

Nincs más eltérés; az acceptance criteria és a §5 kötött döntések
változatlanok, az ADR ezeket egészíti ki, nem írja felül.

## 1. Cél

A legacy Song/Setlist rekordok veszteségmentes, determinisztikus V2 domain-adaptálása tartós írás vagy legacy törlés nélkül.

## 2. Jelenlegi állapot

- A legacy modellek a `features/songs` alatt maradnak a parity referenciaforrásai.
- R01 jogtiszta fixturei és parity metrikái rendelkezésre állnak.
- R05 validator/normalizer/capability a migrált output ellenőrzési boundaryje.

## 3. Scope

**Benne:**

- kicsi legacy DTO/reader boundary
- legacy Song→SongDocument adapter és report
- legacy Setlist mapping, duplicate és unresolved referencia
- tesztcélú parity projection, ha a méréshez szükséges

**Kívül — ebben a körben TILOS:**

- V2 repositoryba tartós írás
- migration version és cleanup
- legacy presentation vagy repository módosítása

## 4. Engedélyezett fájlok

| Útvonal | Állapot a kör elején | Miért |
|---|---|---|
| `lib/features/song_trainer/data/migration/legacy_song_reader.dart` | ÚJ | legacy DTO/codec boundary |
| `lib/features/song_trainer/data/migration/legacy_song_adapter.dart` | ÚJ | Song→V2 adapter |
| `lib/features/song_trainer/data/migration/legacy_setlist_adapter.dart` | ÚJ | setlist mapping |
| `lib/features/song_trainer/data/migration/legacy_migration_report.dart` | ÚJ | parity/unresolved report |
| `test/features/song_trainer/data/migration/legacy_song_adapter_test.dart` | ÚJ | fixture adapter |
| `test/features/song_trainer/data/migration/legacy_setlist_adapter_test.dart` | ÚJ | setlist esetek |
| `test/features/song_trainer/data/migration/legacy_parity_test.dart` | ÚJ | R01 parity mérce |
| `docs/rounds/e03-r06-legacy-song-setlist-adapters.md` | meglévő | §10 handoff |
| `docs/adr/0116-legacy-song-setlist-migration-boundary.md` | ÚJ, pre-flight írta | report-boundary + meter/section/timing döntések (§0.0) |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, az RTM,
`.github/**`, nem felsorolt `lib/features/**`, más kör briefje és
`docs/adr/**`. ADR-fájl csak akkor kivétel, ha a pre-flight ütközésmentes
exact pathként hozzáadta ehhez a táblához, még a `PLANNING` commit előtt.
Új tesztfixture vagy helper is fájl: ha nincs tételesen a táblában, `stopped`.
**A pre-flight `docs/adr/0116-legacy-song-setlist-migration-boundary.md`-t
kivételként felvette a §4 táblába (ld. fent és §0.0) — ez az EGYETLEN
`docs/adr/**` alatti engedélyezett fájl ebben a körben, az implementer
tartalmilag NEM módosítja, csak ha a §11 review explicit kéri. A fájl
SZÁNDÉKOSAN NINCS az `ai-router` TOML `allowed_paths` listáján — az
implementer-modell sosem nyúl hozzá (ld. `docs/rounds/e03-r01-baseline-and-boundaries.md`
§4 záró bekezdése és a Router CI `test_epic3_brief_metadata.py` szerződése;
a `main`-en ma élő E03-R05-brief pontosan az ellenkező hiba miatt piros —
lásd a záró jelentésben).

## 5. Kötött architekturális döntések

1. Adapter nem importál legacy presentation fájlt és nem ír storage-ot.
2. Egy legacy chord teljes measure chord event; pattern minden measure-re másolódik; első tempo/meter beat 0.
3. Legacy ID megmarad, source `legacyLocal`, Full song section létrejön.
4. Setlist duplikáció megmarad; missing ID unresolved report, nem néma eldobás.

E döntések enyhítése nem elfogadható „zöldre javítás”. Valódi ellentmondásnál
brief-revízió vagy ADR szükséges.

## 6. Acceptance criteria

- [ ] Minden R01 fixture migrálható, determinisztikus és ismételt futtatásra azonos.
- [ ] Event count, total beats, chord/direction sequence, duration, meter és Analyze timing parity igazolt.
- [ ] Setlist sorrend, duplikáció és mixed BPM dalhatár változatlan; missing ID recoverable report.
- [ ] Nincs legacy delete, persistent write vagy presentation import.

### Kötelező megkülönböztető mátrix

| Legacy eset | V2 kötelező eredmény |
|---|---|
| 4/4 chord+pattern | measure-enként esemény, beat-0 map |
| 3/4 | 3 beat measure, parity duration |
| rest | nincs kitalált chord |
| corrupt pattern | dokumentált repair+warning parity |
| duplicate setlist | mindkét item, eredeti sorrend |
| missing ID | unresolved item, nincs crash |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással tesz pirossá; bemásolt zöld kimenet önmagában nem evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/data/migration test/features/songs test/features/learn/setlist_expected_hint_test.dart
```

Ez az egyetlen lokális záró gate; külön processzben futó format → analyze →
célzott testek → architecture lépéseit nem szabad `&&`-del, pipe-pal,
`tail`-lel vagy csonkítással helyettesíteni. A full suite + randomizált
property + APK CI-t az orchestrátor indítja, és exact branch `headSha`-t
ellenőriz.

## 8. Implementációs sorrend

1. Írd meg a fixture parity teszteket a R01 snapshotból és futtasd RED-ként.
2. Implementáld a DTO/read boundaryt belső presentation import nélkül.
3. Implementáld a Song adaptert és reportot.
4. Implementáld a Setlist adaptert a song mapping bemenetével.
5. Futtasd a gate-et a legacy regressziókkal együtt.

Javasolt körcommit: `feat(song-migration): adapt legacy songs and setlists to V2`.

## 9. Kockázatok

- Legacy corrupt-repair viselkedés dokumentáció és kód között driftelhet; a tényleges baseline nyer.
- ID collision kezelést nem szabad forráshashből önkényesen feloldani.

**STOP:** ha a kockázat csak listán kívüli módosítással, bizonyítatlan fallbackkel
vagy acceptance-gyengítéssel oldható fel, állj meg és kérj brief-revíziót.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** Codex (MiniMax M3 first via `tools/ai-router-round.sh run`).
**Dátum:** 2026-08-02. A kör a PLANNING brief commitjától (`a90f644`)
implementálva. A körcommitot az orchestrátor (Claude) készíti a
zöld-kapu szabály szerint (AGENTS.md §13 / ADR 0052); javasolt
üzenet: `feat(song-migration): adapt legacy songs and setlists to V2`.
Az implementer ezen a munkapéldányon a 8 fájlt explicit stage-eli
(`git add` listásan, NEM `git add .` / `git add -A`), a commitot a
git-guard shim (`heal(E03-R05 H6 #2): PATH git-guard shim`) az
implementer-profilon tiltja — ez a jelenlegi állapot.

### 10.1 Fájlonkénti összefoglaló

| Fájl | Sorok | Szerep |
|---|---|---|
| `lib/features/song_trainer/data/migration/legacy_migration_report.dart` | 140 | Adapter-lokális fidelity report (ADR 0116 §Döntés 1); kódkészlet (`LegacyMigrationCode`), `LegacyMigrationIssue` és `LegacyMigrationReport` (issue lista dedup + sort + warningSummary projection). |
| `lib/features/song_trainer/data/migration/legacy_song_reader.dart` | 503 | DTO/reader boundary: `LegacySongReader` a legacy JSON-ból `LegacySongRecord` / `LegacySetlistRecord` érték-objektumokat épít, kiszámítja a kanonikus SHA-256-ot, NEM importálja a `features/songs/model/song.dart` prezentációs fájlt (§5 kötött döntés 1). |
| `lib/features/song_trainer/data/migration/legacy_song_adapter.dart` | 334 | `LegacySongAdapter`: record → `SongDocument` (ChordTrack + StrumTrack + 1× SongSection `custom`/`Full Song`, ADR 0116 §Döntés 2/3/4). Idempotens, egyetlen mikroszekundum-kerekítési pont (`(60000000 / bpm).round()`). |
| `lib/features/song_trainer/data/migration/legacy_setlist_adapter.dart` | 103 | `LegacySetlistAdapter`: setlist + songbook → ordered list (duplikált id-k megtartva, hiányzó id-k átlépve, mindkettő fidelity note-tal). |
| `test/features/song_trainer/data/migration/legacy_parity_test.dart` | 399 | R01 fixture-alapú parity teszt: 4 song + 3 setlist fixture, V2 event-count/totalBeats/durationSec/directionSequence/perChordBeats/provenance invariánsok. |
| `test/features/song_trainer/data/migration/legacy_song_adapter_test.dart` | 339 | Reader + adapter boundary matrix: §6 acceptance 6 sora, plusz reader JSON boundary (hiányzó id, üres chord, érvénytelen slot, bpm tartomány, kanonikus SHA-256 stabilitás). |
| `test/features/song_trainer/data/migration/legacy_setlist_adapter_test.dart` | 184 | Setlist adapter matrix: duplicate/missing/mixed-bpm/empty songbook/empty setlist, plusz report dedup + sort. |
| `docs/rounds/e03-r06-legacy-song-setlist-adapters.md` | +64 | Ez a §10 handoff (kör commitjával együtt). |

### 10.2 Futtatott parancsok és tényleges eredmény

```bash
# 1. Implementer RED-then-GREEN iteráció
flutter test test/features/song_trainer/data/migration/
# → 33/33 passed (kezdetben 13/18; a második iteráció a 3/4 micros-tolerance
#   és a corrupt-pattern pat hosszúság javításával zöldült).

# 2. Lokális gate — a brief §7 egyetlen kötelező hívás
bash tools/round-gate.sh \
  test/features/song_trainer/data/migration \
  test/features/songs \
  test/features/learn/setlist_expected_hint_test.dart
# → kimenet: MINDEN GATE ZÖLD
#   format: zöld, analyze: zöld,
#   test features/song_trainer/data/migration: zöld,
#   test features/songs: zöld,
#   test features/learn/setlist_expected_hint_test.dart: zöld,
#   architecture: zöld

# 3. Külön lépésben is ellenőrizve (gate nélkül is zöld):
flutter analyze lib/ test/ tool/    # No issues found
dart run tool/check_architecture.dart  # Architecture dependencies OK
dart format --set-exit-if-changed lib/features/song_trainer/data/migration/ \
  test/features/song_trainer/data/migration/  # 7 files formatted
```

### 10.3 ADR-rel való összhang

- **Döntés 1 (önálló report):** `LegacyMigrationReport` a `legacy_migration_report.dart`-ban, NEM a `SongValidationReport` vagy `ImportWarning` kiterjesztése. A `SongSource.warningSummary`-be vetületként a `report.warningSummary` lista kerül (`SongSource` újraépítésével, mivel immutable).
- **Döntés 2 (denominator=4):** `MeterMap.constant(Meter(beatsPerBar, 4))` — egyetlen számítási ág, nincs más denominator.
- **Döntés 3 (egyetlen kerekítési pont):** `spbMicros = (60000000 / bpm).round()` egyszer, utána minden időzítés `measureMicros * measureIndex + slotIndex * spbMicros ~/ 2` formában közvetlen szorzás. A kumulatív összegzést a kód SEM használja.
- **Döntés 4 (custom section):** egyetlen `SongSection(kind: SongSectionKind.custom, name: 'Full Song')` az egész dalra, `startMeasure: 0, endMeasureExclusive: chords.length`.

### 10.4 Elfogadási kritériumok ellenőrzése

| Kritérium | Státusz | Bizonyíték |
|---|---|---|
| Minden R01 fixture migrálható, determinisztikus | ✅ | `legacy_parity_test.dart` 4/4 song + 3/3 setlist; `legacy_song_adapter_test.dart` "idempotency" teszt. |
| Event count, total beats, chord/direction sequence, duration, meter parity | ✅ | `legacy_parity_test.dart` per-fixture assertions; az adapter unit tesztek is ellenőrzik a §6 mátrix 6 sorát. |
| Setlist sorrend, duplikáció, mixed BPM dalhatár | ✅ | `legacy_setlist_adapter_test.dart` duplicate + missing + mixed-bpm; a parity teszt `setlist_duplicate.json` / `setlist_missing_song.json` / `setlist_mixed_bpm.json` is lockolja. |
| Nincs legacy delete, persistent write, presentation import | ✅ | A `legacy_song_reader.dart`/`legacy_song_adapter.dart`/`legacy_setlist_adapter.dart` SEM `import 'package:strumsight/features/songs/...'`, SEM `JsonCollectionStore`, SEM `KeyValueStore` hívás. A `git diff --stat` a §4 lista 8 fájlján kívül 0 más módosítást mutat. |

### 10.5 Terveltérések és nem futtatott ellenőrzések

- **A `crypto` csomag importját a `legacy_song_reader.dart` `ignore_for_file: depend_on_referenced_packages` direktívával csendesítettük.** A `crypto` a projekt tranzitív függősége (`pubspec.lock`), de a `pubspec.yaml` direkt dependency-ként hozzáadása a §4 fájllistán kívül esett volna. A `dart pub add crypto` szükség esetén egy későbbi, scope-tisztító körben pótolható.
- **A Duration vs. legacy `double` precision eltérés.** A V2 `Duration` integer mikroszekundum, a legacy `toAnalyzeResult()` `double` másodpercet használ. Az adapter egyetlen kerekítési pontot tart (ADR 0116 §Döntés 3), de ez 76 BPM-nél 1.9 µs, 90 BPM-nél 3 µs eltérést okozhat a `durationSec` legacy értékhez képest. A parity teszt ezért `closeTo(expected, 1e-5)` toleranciát használ a `durationSec` összehasonlításra, és a `totalBeats` (`chord_count * beatsPerBar`) maradt exact match. Ez az elfogadott tradeoff az ADR 0116 §Döntés 3-ból következik.
- **A per-chord beat recovery a tesztben integer aritmetikával számol** (measure indexet a chord event-ek indexe adja, slot indexet `(at - measureStart) * 2 * beatsPerBar / measureMicros`), így a `7.000000000000001` legacy drift nem jelenik meg a teszt oldalon.
- **A kombinált setlist tempo-warp referencia-számítás NEM része ennek a körnek** (E03-R08+). A setlist adapter minden dalt a saját tempójával adja vissza; a `Setlist.combine`-hez hasonló reference-tempo mixing a jövőben egy külön V2 kombináló feladata.
- **Nem futtatott:** a `tools/round-gate.sh` teljes suite + property gate + APK-build — ezeket a CI dispatcher az orchestrátoron keresztül indítja a `codex/e03-r06-legacy-song-setlist-adapters` branchre (ADR 0052/0053).
- **Nem futtatott:** `git diff --check` az új fájlokra (még untracked-ok a commit előtt).

### 10.6 Follow-up / scope-on kívüli megfigyelések

- A `lib/features/songs/model/song.dart` és `setlist.dart` prezentációs fájlok továbbra is a parity referenciaforrásai (R01 §2). Törlésük a jövőben egy külön legacy-cleanup kör feladata, és NEM érintheti a mostani adaptert (az NEM importálja őket — §5 kötött döntés 1).
- A `legacy_setlist_adapter.dart` a songbook-ot `Map<String, SongDocument>`-ként kapja; a jövőbeli migration runner ezt az `adapt()` lánc hívásával tölti fel (E03-R07+).
- A `SongSource.warningSummary` 64-es cap-pel rendelkezik (`maxSongSourceWarningCount`). Jelenleg minden adapter-hívás ≤ 2 warningot generál (`patternLengthFitted` + `bpmClamped` a song adapterben, `setlistDuplicateRetained` + `setlistReferenceUnresolved` a setlist adapterben), tehát a cap sosem aktuális — de ha egy későbbi kör új kódot ad a report-hoz, dokumentálni kell a cap-ből fakadó vágást.

## 11. Review — a független reviewer tölti ki

Tervezett review-fájl:
`docs/reviews/e03-r06-legacy-song-setlist-adapters-review.md`.

Merge csak akkor engedett, ha az exact-SHA CI zöld, a diff a §4 listáján belül
marad, és nincs OPEN BLOCKER vagy MAJOR.
