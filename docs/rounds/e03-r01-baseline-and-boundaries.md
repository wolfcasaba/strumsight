# E03-R01 — Baseline, határok, ADR-témák és feature flag

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 1; §3, §8.3–8.4, §32
- **Branch:** `codex/e03-r01-baseline-and-boundaries`
- **Előfeltétel:** E02-R20 merge és friss-main teljes regresszió
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

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

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, az RTM,
`.github/**`, nem felsorolt `lib/features/**`, más kör briefje és
`docs/adr/**`. ADR-fájl csak akkor kivétel, ha a pre-flight ütközésmentes
exact pathként hozzáadta ehhez a táblához, még a `PLANNING` commit előtt.
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
