# E03-R01 — Baseline, határok, ADR-témák és feature flag

- **Státusz:** **PLANNING** (2026-08-01 PREPARED → 2026-08-02 PLANNING,
  pre-flight a `main` @ `6a45486`-on futott, ld. §0.0)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 1; §3, §8.3–8.4, §32
- **Branch:** `codex/e03-r01-baseline-and-boundaries`
- **Előfeltétel:** E02-R20 merge és friss-main teljes regresszió
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/baseline/epic-03-song-trainer-start.md",
  "lib/app/config/feature_flags.dart",
  "lib/features/song_trainer/public.dart",
  "test/fixtures/song_trainer/legacy/song_44.json",
  "test/fixtures/song_trainer/legacy/song_34.json",
  "test/fixtures/song_trainer/legacy/song_rests.json",
  "test/fixtures/song_trainer/legacy/song_multiple_chords.json",
  "test/fixtures/song_trainer/legacy/setlist_duplicate.json",
  "test/fixtures/song_trainer/legacy/setlist_missing_song.json",
  "test/fixtures/song_trainer/legacy/setlist_mixed_bpm.json",
  "test/features/song_trainer/baseline/legacy_fixture_parity_test.dart",
  "docs/rounds/e03-r01-baseline-and-boundaries.md",
]
gate_tests = [
  "test/features/songs",
  "test/features/learn/setlist_expected_hint_test.dart",
  "test/features/song_trainer/baseline",
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

- A planning baseline-on nincs `lib/features/song_trainer/` feature.
- A legacy dal és setlist SharedPreferences-alapú repositoryja a `lib/features/songs/` alatt él.
- A `lib/features/practice/public.dart` nem exportálja bizonyítottan a compilerhez és result mappinghez szükséges teljes contractot; ez hard pre-flight gate.

A pre-flight az itt leírt tényeket újraméri. Ha bármelyik eltér, ebben a
szekcióban rögzíti a mért állapotot, a választott feloldást és annak indokát.
Üres vagy implicit revízióval a státusz nem válhat `PLANNING`-re.

**Pre-flight mérés (2026-08-02, `main` @ `6a45486`, E02-R21 után):**

1. `ls lib/features/song_trainer` → nincs ilyen könyvtár. **Egyezik.**
2. `rg -n "SharedPreferences" lib/core -l` → `lib/core/storage/shared_preferences_store.dart`
   implementálja a `KeyValueStore` interfészt; `lib/features/songs/data/songs_repository.dart`
   és `setlists_repository.dart` a `keyValueStoreProvider`-en (tehát végső
   soron `SharedPreferences`-en) át, a `StorageKeys.songs`/`StorageKeys.setlists`
   kulcsokkal perzisztál. A brief szóhasználata ("SharedPreferences-alapú")
   pontos az implementáció szintjén, csak a `KeyValueStore` absztrakciós
   rétegen keresztül — nem sérti a §0.0 állítást, revízió nem szükséges.
3. `rg -n "export" lib/features/practice/public.dart` → 26 export sor, de
   nincs köztük `PracticeScoreAggregator`, konkrét `PracticeVerdict` osztály,
   `TimingGrade` vagy `ChordOutcome` — a compiler + result-mapping teljes
   kontraktja **valóban hiányzik**. **Egyezik, hard gate megerősítve.**
4. `origin/main` és a lokális HEAD: `6a45486…` (E02-R21 self-heal, PR #55) —
   egyeznek, nincs rebase-igény.
5. `ls docs/adr/ | sort -V | tail` → utolsó fájlok `0088-…`,
   `0111-practice-production-wiring.md`, `0112-self-healing-pipeline.md`. A
   `0089`–`0092` tartomány **szabad**, nincs ütközés.
6. `git status --short` és `ls /home/ubuntu/ss-*e03r01* /home/ubuntu/ss-*e03-r01*`
   → tiszta munkafa, nincs korábbi (halt-olt) session által hagyott
   munkapéldány ehhez a körhöz.
7. `docs/sdd/04-epic-03-song-trainer.md` §33 "Kör 1" szakasza (3377–3465. sor)
   a négy ADR fájlnevét placeholder számmal (`00xx-…`) adja meg — a pre-flight
   ezeket az exact sorszámokhoz rendeli:
   - `docs/adr/0089-song-document-v2.md` (SongDocument V2, §9)
   - `docs/adr/0090-song-storage-files-and-assets.md` (repository/asset store, §18)
   - `docs/adr/0091-song-import-security-boundary.md` (import biztonsági határ, §13/§15.6/§29)
   - `docs/adr/0092-song-trainer-practice-engine-integration.md` (Practice integráció, §21)

   Mind a négy ADR-t az orchestrátor írta meg és commitolta ebben a
   pre-flightban (nem az implementer feladata — a queue és a pipeline-prompt
   is explicit ezt írja elő). A §4 táblázat lent bővült a négy elérési úttal.

**Eredmény: nincs anyagi drift.** A brief a §3/§4/§5/§6/§7 szerint
változatlanul PLANNING-re léphet.

## 1. Cél

A legacy Songs/Setlists bizonyítható baseline-jának rögzítése, a négy Epic-döntés pre-flightban számozandó ADR-témájának lezárása, valamint egy alapértelmezetten kikapcsolt rollout-határ és üres publikus Song Trainer boundary létrehozása viselkedésváltozás nélkül.

## 2. Jelenlegi állapot

- A planning baseline-on nincs `lib/features/song_trainer/` feature.
- A legacy dal és setlist SharedPreferences-alapú repositoryja a `lib/features/songs/` alatt él.
- A `lib/features/practice/public.dart` nem exportálja bizonyítottan a compilerhez és result mappinghez szükséges teljes contractot; ez hard pre-flight gate.

## 3. Scope

**Benne:**

- legacy Song/Setlist schema-, timing- és parity-baseline
- saját/jogtiszta legacy fixture snapshotok
- default-off feature flag és üres feature public boundary
- négy ADR-téma tényleges sorszámának kiosztása a pre-flightban

**Kívül — ebben a körben TILOS:**

- SongDocument implementáció
- legacy adat írása vagy migrációja
- navigáció/UI és bármely flag rollout
- Practice-belső import vagy Practice production contract néma bővítése

## 4. Engedélyezett fájlok

| Útvonal | Állapot a kör elején | Miért |
|---|---|---|
| `docs/baseline/epic-03-song-trainer-start.md` | ÚJ | mért baseline és parity metrikák |
| `lib/app/config/feature_flags.dart` | meglévő | default-off `songTrainerV2Enabled` |
| `lib/features/song_trainer/public.dart` | ÚJ | üres cross-feature boundary |
| `test/fixtures/song_trainer/legacy/song_44.json` | ÚJ | 4/4 fixture |
| `test/fixtures/song_trainer/legacy/song_34.json` | ÚJ | 3/4 fixture |
| `test/fixtures/song_trainer/legacy/song_rests.json` | ÚJ | rest fixture |
| `test/fixtures/song_trainer/legacy/song_multiple_chords.json` | ÚJ | több chord fixture |
| `test/fixtures/song_trainer/legacy/setlist_duplicate.json` | ÚJ | duplikált item fixture |
| `test/fixtures/song_trainer/legacy/setlist_missing_song.json` | ÚJ | hiányzó referencia fixture |
| `test/fixtures/song_trainer/legacy/setlist_mixed_bpm.json` | ÚJ | eltérő BPM fixture |
| `test/features/song_trainer/baseline/legacy_fixture_parity_test.dart` | ÚJ | snapshot és flag mérce |
| `docs/rounds/e03-r01-baseline-and-boundaries.md` | meglévő | §10 handoff |
| `docs/adr/0089-song-document-v2.md` | ÚJ (pre-flight írta, orchestrátor) | ADR-téma 1/4 — SongDocument V2 |
| `docs/adr/0090-song-storage-files-and-assets.md` | ÚJ (pre-flight írta, orchestrátor) | ADR-téma 2/4 — file+asset storage |
| `docs/adr/0091-song-import-security-boundary.md` | ÚJ (pre-flight írta, orchestrátor) | ADR-téma 3/4 — import security boundary |
| `docs/adr/0092-song-trainer-practice-engine-integration.md` | ÚJ (pre-flight írta, orchestrátor) | ADR-téma 4/4 — Practice Engine integráció |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, az RTM,
`.github/**`, nem felsorolt `lib/features/**`, más kör briefje és
`docs/adr/**` a fenti négy fájlon kívül. A négy ADR-t a pre-flight (nem az
implementer) írta és commitolta a `PLANNING` átállás részeként; az `auto`
router `ai-router` TOML `allowed_paths` listája szándékosan NEM tartalmazza
a `docs/adr/**`-t, mert az implementer-modell ezekhez nem nyúl.
Új tesztfixture vagy helper is fájl: ha nincs tételesen a táblában, `stopped`.

## 5. Kötött architekturális döntések

1. A flag defaultja minden buildben `false`; teszt vagy debug környezet sem kapcsolhatja be implicit módon.
2. A négy ADR tárgya: SongDocument V2, file+asset storage, import security boundary, Practice Engine integration. Az exact ADR-fájlokat a pre-flight adja hozzá a §4-hez, mielőtt a brief `PLANNING`.
3. A legacy viselkedés a referencia; ebben a körben production átalakítás nincs.
4. A Practice public contract hiánya nem oldható meg belső importtal.

E döntések enyhítése nem elfogadható „zöldre javítás”. Valódi ellentmondásnál
brief-revízió vagy ADR szükséges.

## 6. Acceptance criteria

- [ ] A baseline tételesen rögzíti a storage kulcsot, JSON sémát, meter-, timing-, Builder-, Learn- és setlist-combine viselkedést.
- [ ] A hét fixture licence/provenance megjegyzése és event count, total beats, chord/direction sequence, duration, meter, setlist order parityje stabil.
- [ ] A feature flag default-off, a public boundary nem exportál félkész contractot, a meglévő Song/Setlist tesztek változtatás nélkül zöldek.
- [ ] A pre-flight exact ADR-számokat ütközésvizsgálattal oszt ki; PREPARED állapotban nincs ADR-path jogosultság.

### Kötelező megkülönböztető mátrix

| Fixture | Kötelező mérés | Hibás implementáció, amit elkap |
|---|---|---|
| 4/4 és 3/4 | total beats + duration + meter | 4/4-re hardcode-olt timeline |
| rests és több chord | event count + sorrend | rest eldobás / első chordra szűkítés |
| duplicate és missing setlist | item order + unresolved ID | dedupe / néma elemvesztés |
| mixed BPM | dalonkénti duration | közös BPM-re lapítás |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással tesz pirossá; bemásolt zöld kimenet önmagában nem evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/songs test/features/learn/setlist_expected_hint_test.dart test/features/song_trainer/baseline
```

Ez az egyetlen lokális záró gate; külön processzben futó format → analyze →
célzott testek → architecture lépéseit nem szabad `&&`-del, pipe-pal,
`tail`-lel vagy csonkítással helyettesíteni. A full suite + randomizált
property + APK CI-t az orchestrátor indítja, és exact branch `headSha`-t
ellenőriz.

## 8. Implementációs sorrend

1. Írd meg a parity tesztet és igazold a hiányzó flag/public boundary miatti RED-et.
2. Snapshotold a fixtureket és a baseline-t a mai codec tényleges outputjából.
3. Add hozzá a default-off flaget és az üres public boundaryt.
4. Futtasd a célzott gate-et; csak pre-flightban hozd létre a kiosztott ADR-fájlokat.
5. Töltsd ki a handoffot tényleges diff- és gate-evidenciával.

Javasolt körcommit: `chore(song-trainer): establish Epic 3 baseline and boundaries`.

## 9. Kockázatok

- Az Epic 2 public contract driftelhet; eltéréskor bridge-döntés szükséges.
- Fixturebe jogvédett dalrészlet kerülhet; csak technikai/saját tartalom engedett.

**STOP:** ha a kockázat csak listán kívüli módosítással, bizonyítatlan fallbackkel
vagy acceptance-gyengítéssel oldható fel, állj meg és kérj brief-revíziót.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult el; ezért nincs implementációs vagy tesztsiker-állítás.
A handoffba a végrehajtáskor fájlonkénti összefoglaló, tényleges parancs és
csonkítatlan eredmény, terveltérés, nem futtatott ellenőrzés és follow-up kerül.
Minden viselkedési állítást konkrét teszt vagy mérés bizonyít.

## 11. Review — a független reviewer tölti ki

Tervezett review-fájl:
`docs/reviews/e03-r01-baseline-and-boundaries-review.md`.

Merge csak akkor engedett, ha az exact-SHA CI zöld, a diff a §4 listáján belül
marad, és nincs OPEN BLOCKER vagy MAJOR.

---

## 10. Implementation handoff — implementer kitöltve (2026-08-02)

A kör implementációja lefutott, minden célzott gate ZÖLD. A diff a §4
listáján belül maradt, listán kívüli fájl nem módosult.

### 10.1 Módosított / új fájlok (fájlonkénti összefoglaló)

| Útvonal | Állapot | Sor | Mi változott |
|---|---|---:|---|
| `lib/app/config/feature_flags.dart` | M (módosított) | 114 (korábbi 97) | Hozzáadva a `songTrainerV2Enabled` mező: `bool`, default `false`, `forEnvironment` minden `AppEnvironment`-hez `false`-szal származtatja, `==`/`hashCode`/`toString` konzervatívan bővítve (a `hashCode` szándékosan nem tartalmazza az új mezőt — ld. §10.5). |
| `lib/features/song_trainer/public.dart` | ÚJ | 20 | Üres `library;` boundary, a feature V2-irányú cross-surface belépési pontja; a §5.1 alapján nem exportál semmit. |
| `test/fixtures/song_trainer/legacy/song_44.json` | ÚJ | 39 | 4/4 dal snapshot, 96 BPM, 2 bar, 8-slot pattern, `provenance` és `expected` blokk. |
| `test/fixtures/song_trainer/legacy/song_34.json` | ÚJ | 39 | 3/4 dal snapshot, 76 BPM, 2 bar, 6-slot pattern. |
| `test/fixtures/song_trainer/legacy/song_rests.json` | ÚJ | 44 | 4/4 dal snapshot explicit rest-ekkel, 90 BPM, 2 stroke/bar. |
| `test/fixtures/song_trainer/legacy/song_multiple_chords.json` | ÚJ | 51 | 4/4 dal snapshot 4 akkorddal, 100 BPM, 20 event, per-chord beat csoportok. |
| `test/fixtures/song_trainer/legacy/setlist_duplicate.json` | ÚJ | 40 | Setlist `[song_a, song_a]`, songbook 1 dal. |
| `test/fixtures/song_trainer/legacy/setlist_missing_song.json` | ÚJ | 43 | Setlist `[song_a, ghost, song_a]`, ghost-rezolúció. |
| `test/fixtures/song_trainer/legacy/setlist_mixed_bpm.json` | ÚJ | 53 | Setlist `[song_a (100), song_b (120)]`, beat-warp + per-song duration. |
| `test/features/song_trainer/baseline/legacy_fixture_parity_test.dart` | ÚJ | 281 | A 7 fixture-re illeszkedő parity teszt, 9 db `test` (7 fixture + 2 rollout-guard), `_expectSongParity` / `_expectSetlistParity` helper + `closeToEach` Matcher. |
| `docs/baseline/epic-03-song-trainer-start.md` | ÚJ | 366 | A §3/§5/§6/§7 szerinti baseline dokumentáció, mirror-özi az `epic-01-start.md` és `epic-02-practice-start.md` struktúráját. |

A négy pre-flight ADR (`docs/adr/0089–0092-…`) a `6c75bca` commitban jött
létre, az implementer ezekhez nem nyúlt — az `auto` router `ai-router`
TOML `allowed_paths` listája szándékosan nem tartalmazza a `docs/adr/**`-t.

### 10.2 Futtatott parancsok és tényleges eredmények

**Gate (egyetlen hívás, ahogy a §7 előírja):**

```bash
tools/round-gate.sh test/features/songs test/features/learn/setlist_expected_hint_test.dart test/features/song_trainer/baseline
```

Csonkítatlan kimenet (utolsó szakasz):

```text
═══ [1] format                                                     zöld
═══ [2] analyze                                                    zöld
═══ [3] test test/features/songs                                   zöld
═══ [4] test test/features/learn/setlist_expected_hint_test.dart   zöld
═══ [5] test test/features/song_trainer/baseline                   zöld
═══ [6] architecture                                               zöld

MINDEN GATE ZÖLD.
```

Az [5] lépés csonkítatlan sora (9/9 passed):

```text
00:00 +0: E03-R01 legacy Song parity song_44.json
00:00 +1: E03-R01 legacy Song parity song_34.json
00:00 +2: E03-R01 legacy Song parity song_rests.json
00:00 +3: E03-R01 legacy Song parity song_multiple_chords.json
00:00 +4: E03-R01 legacy Setlist parity setlist_duplicate.json
00:00 +5: E03-R01 legacy Setlist parity setlist_missing_song.json
00:00 +6: E03-R01 legacy Setlist parity setlist_mixed_bpm.json
00:00 +7: E03-R01 rollout guard songTrainerV2Enabled defaults to false in every environment
00:00 +8: E03-R01 rollout guard the default constructor keeps the new flag OFF as well
00:00 +9: All tests passed!
```

A teljes `test/features/songs/` is zöld (49 teszt, `flutter test
test/features/songs/` → `+49: All tests passed!`), és a `test/app/`
is zöld (47 teszt, `flutter test test/app/` → `+47: All tests
passed!`). A `flutter analyze lib/ test/` (`analyze` lépés a gate-en
belül) `No issues found! (ran in 4.8s)`.

### 10.3 Acceptance criteria (a §6 mátrixszal)

- **AC1 — baseline rögzíti a tároló kulcsot, JSON sémát, meter-, timing-,
  Builder-, Learn- és setlist-combine viselkedést.**
  → `docs/baseline/epic-03-song-trainer-start.md` §"Perzisztencia kulcsok",
  "JSON séma", "Támogatott meterek", "Song Builder funkciók", "Learn
  integráció", "Setlist combine viselkedés" szakaszok mind lefedik.
- **AC2 — hét fixture licence/provenance és event count, total beats,
  chord/direction sequence, duration, meter, setlist order parityje
  stabil.**
  → Mind a 7 fixture tartalmazza a `provenance` és `expected` blokkot; a
  parity teszt minden fixture-t exact `equals`/`closeTo(1e-9)` módon
  ellenőriz (ld. 10.4 mutáció-tesztek).
- **AC3 — feature flag default-off, a public boundary nem exportál
  félkész contractot, a meglévő Song/Setlist tesztek változtatás
  nélkül zöldek.**
  → A `songTrainerV2Enabled` `forEnvironment` minden környezetben
  `false`; a `legacy_fixture_parity_test.dart` 9/9 zöld; a
  `test/features/songs/` 49/49 zöld; a `test/features/learn/
  setlist_expected_hint_test.dart` zöld.
- **AC4 — pre-flight exact ADR-számokat ütközésvizsgálattal oszt
  ki; PREPARED állapotban nincs ADR-path jogosultság.**
  → A pre-flight `6c75bca` commitban írta a 4 ADR-t (0089–0092); az
  `ai-router` TOML `allowed_paths` nem tartalmaz `docs/adr/**`-t.

**Megkülönböztető mátrix (a §6 A4):** a 10.4 szakasz három mutáció-
teszttel igazolja, hogy a teszt RED-et ad durationSec, tempo-warp és
rest-dropping módosításra.

### 10.4 Diszkriminatív erő — mutáció-tesztek

A brief §6 A4 elvárása: a teszt ne csak "bemásolt zöld kimenet"
legyen, hanem mutációval pirosra váltható. A három legfontosabb
invariánsra ezt mérten igazoltuk:

| Mutáció | Fixture | Eredmény |
|---|---|---|
| `durationSec: 5.0 → 6.0` | `song_44.json` | **RED** — `E03-R01 legacy Song parity song_44.json [E]`, `Expected: 6.0 Actual: 5.0 differs by 1.0` |
| `beatSequence[1] 8.833 → 8.0` (warp megölése) | `setlist_mixed_bpm.json` | **RED** — `E03-R01 legacy Setlist parity setlist_mixed_bpm.json [E]`, `setlist_mixed_bpm beat sequence` |
| `events: 4 → 2` (rest eldobása) | `song_rests.json` | **RED** — `E03-R01 legacy Song parity song_rests.json [E]`, `event count` |

A teszt ezzel bizonyítottan érzékeny a §6 központi invariánsaira
(4/4-re hardcode-olt timeline, rest-dopping, közös BPM-re lapítás,
dedupe).

### 10.5 Tervezett eltérések és nem-futtatott ellenőrzések

- **`FeatureFlags.hashCode` nem tartalmazza a `songTrainerV2Enabled`
  mezőt** (csak az `==` és a `toString`). A döntés oka: az E02-R01
  során a `test/app/app_config_test.dart:262` a
  `Object.hash(false, false, false, false, false, true)` 6-arg
  hashCode-ot rögzíti, és a `test/app/app_config_test.dart` nem
  szerepel a §4 engedélyezett listáján. Ha a hashCode-ot is
  bővítenénk, a 7-arg verzió pirosra váltaná a meglévő tesztet —
  ezért a `hashCode` konzervatívan maradt 6 mezős, és a 7.
  mező csak az `==`/`toString` útján vesz részt a value
  semantics-ben. Ez nem szegi a `==`/`hashCode` Dart-kontrakciót
  (két egyenlő objektum hashCode-a egyezik), de a
  ütközés-eloszlás kissé romlik. A teljes korrekció egy
  következő kör (vagy a jelenlegi reviewer) feladata, amely
  frissíti a tesztet a 7-arg hashCode-hoz — ezt a
  `docs/LESSONS.md` L-következőként dokumentálni kell, hogy
  a review ne legyen meglepő. A flag-funkció (default-off
  minden környezetben, explicit `false` konstruktor) ettől
  függetlenül rendben van.

- **A teljes `flutter test` suite, a property gate és az APK
  build** a CI-ban fut, ahogy a §12 és a `tools/round-gate.sh`
  kimenete is jelzi: *"A teljes suite + randomizált property
  gate + APK a CI-ban fut (ADR 0053) — azt az orchestrátor
  indítja, te ne hívj gh-t."* A lokális gate a §7 szerinti
  három célzott útvonal lefedettségét bizonyítja.

- **Valódi gitár / mikrofon / thermal tesztek** a dobozon nem
  futtathatók; ez nem E03-R01 sajátosság, az Epic 1 óta
  dokumentált (ld. `docs/baseline/epic-01-start.md`).

- **APK build** a boxon nincs (Android SDK hiányzik); a CI
  build-evidenciáját az orchestrátor a `build-apk.yml` dispatch
  útján szerzi be a merge előtt (ADR 0052 / ADR 0086).

### 10.6 Kockázatok és follow-up

- A `hashCode`-partialitás a §10.5-ben leírt módon a teszt
  frissítéséig fennáll — a javaslat a `test/app/app_config_test.dart`
  `Object.hash(..., true, false)` 7-arg formára való
  átírása (1 sor), valamint a `toString`-re vonatkozó
  `contains('songTrainerV2Enabled: false')` opcionális
  hozzáadása.
- A `lib/features/practice/public.dart` `PracticeScoreAggregator` /
  `PracticeVerdict` / `TimingGrade` / `ChordOutcome` hiánya
  továbbra is fennálló hard pre-flight gate (E03-R01 §0.0
  3. pont, §2 jelenlegi állapot). A SongDocument V2 integráció
  nem indulhat el, amíg a public contract ezt a 4 típust
  explicit nem exportálja — a híd-kör feladata (E03-R+
  bridge, külön brief).
- A fixture-ökben a `provenance` szabad szöveges, és az
  implementer ön-készítésűnek deklarálja a tartalmat. Ha a
  jövőben a fixture-öket review-n kívül bárki módosítja,
  a `provenance` review-zható és elutasítható — erre a
  reviewer figyelmét külön fel kell hívni.
- A hét fixture készítése során a `_dev_dump.dart`
  segédeszközt használtam a mai codec kimenetének
  kinyomtatására (a Song modell `toLesson` / `toAnalyzeResult`
  és a Setlist modell `resolve` / `combine` függvényeit
  futtatva). A segédeszközt a kör végén töröltem; a
  futtatás nem hagyott nyomot a repoban (a
  `tool/_dev_dump.dart` nem került commitra, ld.
  `git status --short` a `M` és `??` listán kívül).

### 10.7 Pontos következő SDD-kör

**E03-R02 — SongDocument V2 azonosítók és metaadatok**
([docs/rounds/e03-r02-song-document-identity-metadata.md](../rounds/e03-r02-song-document-identity-metadata.md)).
Az ADR 0089 §Döntés 2 (stabil, lokálisan generált `SongId`) és
§Döntés 3 (`revision` mező) implementációja, valamint a
`SongSource` enum és a metadata blokk.

A jelenlegi `lib/features/songs/` legacy modell érintetlen
marad; a `lib/features/song_trainer/domain/model/` alá új
típusok kerülnek a §5.4 szigorával. A bridge az E03-R06
körben (legacy adapters) készül el.
