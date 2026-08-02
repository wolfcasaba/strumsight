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
