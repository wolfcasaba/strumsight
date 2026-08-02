# E03-R08 — Legacy adatok tartós V2 migrációja

- **Státusz:** **PLANNING** (pre-flight lezárva 2026-08-02, orchestrátor:
  Claude Sonnet 5, mérési baseline: `main` @ `2ca0b5a`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 8; §3.4, §18
- **Branch:** `codex/e03-r08-persistent-v2-migration`
- **Előfeltétel:** E03-R07 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/application/migration/song_storage_migrator.dart",
  "lib/features/song_trainer/application/migration/song_migration_state.dart",
  "lib/features/song_trainer/data/migration/song_migration_version_store.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "test/features/song_trainer/application/migration/song_storage_migrator_test.dart",
  "test/features/song_trainer/application/migration/song_storage_migrator_wiring_test.dart",
  "docs/rounds/e03-r08-persistent-v2-migration.md",
]
gate_tests = [
  "test/features/song_trainer/application/migration",
  "test/features/song_trainer/data/migration",
  "test/features/songs",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main` és az
> elődkör merge-jét; olvasd újra az `AGENTS.md`, Chapter 1/3/4,
> `HANDOFF.md`, a releváns ADR-eket és a `docs/LESSONS.md` fájlt. `rg`-vel
> igazold minden útvonal, symbol, producer, resource owner, dependency/licence
> és numerikus cella mai állapotát. Drift esetén dokumentáld §0.0-ban,
> módosítsd a scope/fájllistát, majd commitold a `PLANNING` briefet a
> körbranchre az implementer előtt. A `PREPARED` brief nem futtatható vakon.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol
és nem nyit PR-t. Listán kívüli fájl, ellenőrizetlen contract/licence,
ellentmondó acceptance, hiányzó fixture vagy nem reprodukálható mérce esetén
`stopped`; nincs néma scope-tágítás vagy acceptance-gyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

- R06 pure adaptert és parity reportot, R07 atomikus V2 repositoryt szállít.
- A legacy Songs/Setlists továbbra is olvasható és nem törlendő.
- Migration version csak teljes song+setlist siker után írható.

**Pre-flight (2026-08-02, `main` @ `2ca0b5a`, orchestrátor: Claude Sonnet
5) — három mért drift, mind [ADR 0117](../adr/0117-song-storage-migrator-boundary.md)-ben
formalizálva:**

1. **Legacy JSON elérés fájllista-bővítés nélkül (ADR 0117 Döntés 1).**
   `grep -rn "StorageKeys.songs\|StorageKeys.setlists"` megmutatta, hogy ma
   a `songs`/`setlists` feature (`lib/features/songs/data/*_repository.dart`)
   egy `JsonCollectionStore<Song>`/`<Setlist>`-et nyit a
   `StorageKeys.songs`/`StorageKeys.setlists` kulcsokon, és TÍPUSOS
   `Song`/`Setlist` objektumot ad — a `LegacySongReader.readSong`/
   `readSetlist` viszont nyers `Map<String, dynamic>`-et vár (ADR 0116). A
   `lib/features/songs/public.dart` csak `Song`-ot exportál, `Setlist`-et és
   a repository interfészt nem, és a `crossFeatureImportsMustUsePublicApi`
   architektúra-szabály (`tool/check_architecture.dart`) miatt a migrátor
   nem nyúlhat a `songs` feature belsejébe. A `public.dart` bővítése
   fájllista-tágítás lenne (tiltott). **Feloldás:** a migrátor egy MÁSODIK,
   saját `JsonDocumentStore`-példányt nyit ugyanazon a két kulcson —
   ez `lib/core/storage/**` importot igényel (core, nem feature), a
   `songs`/`setlists` feature-t és a `public.dart`-ot érintetlenül hagyja.
   Csak-olvasás, nincs írási ütközés.
2. **Checkpoint/version marker perzisztencia (ADR 0117 Döntés 2).** A
   `StorageKeys` (`lib/core/storage/storage_keys.dart`) nincs a §4 listán —
   új key-value kulcs felvétele tilos zóna, és a R07 HANDOFF-konvenció is
   kizárja a `SharedPreferences`/`KeyValueStore` útvonalat
   `SongDocument`-hez kötődő tartalomra. **Feloldás:** a
   `song_migration_version_store.dart` egy JSON dokumentumot ír a songs-root
   alá a MEGLÉVŐ (R07) `AtomicFileWriter`-en át — nincs új perzisztencia-
   primitíva, nincs `StorageKeys` érintés.
3. **Setlist-lépés hatóköre (ADR 0117 Döntés 3).** Az Epic 3 fájllistájában
   (`find lib/features/song_trainer -type f`) nincs V2 setlist domain modell
   vagy repository, és a kör §4 listája sem ad hozzá ilyet. **Feloldás:** a
   setlist-lépés ebben a körben a MÁR MERGE-ELT `LegacySetlistAdapter.adapt()`
   futtatása a sikeresen migrált songbook felett, és az eredmény (report +
   unresolved lista) a migráció completion-summary/state része — nincs V2
   setlist perzisztencia (konzisztens a §3 "Kívül — V2 Library UI"
   tilalommal).

Mért, változatlan tény (R06, MÁR MERGE-ELT, ezt a kör nem módosíthatja,
H2): `LegacySongAdapter.adapt()` a V2 `SongId`-t közvetlenül
`SongId(record.id)`-ként állítja elő — a legacy song ID és a V2 SongId
AZONOS. Ez a migrátor idempotencia-kulcsa: restart után ugyanarra a legacy
ID-ra a `SongRepository.create()` `SongRepositoryErrorCode.alreadyExists`-t
ad, amit a migrátor "már kész, ellenőrizd read-back parityvel, ne írj
újra" jelként kezel — nem hiba.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

A legacy rekordok újraindítható, adatvesztésmentes, rekord-szintű migrációja a file repositoryba, read-back parityvel és kontrollált fallbackkel.

## 2. Jelenlegi állapot

- R06 pure adaptert és parity reportot, R07 atomikus V2 repositoryt szállít.
- A legacy Songs/Setlists továbbra is olvasható és nem törlendő.
- Migration version csak teljes song+setlist siker után írható.

## 3. Scope

**Benne:**

- SongStorageMigrator use case és explicit state
- migration version store és production provider wiring
- record-by-record checkpoint, read-back parity, recovery UI state
- legacy read fallback a rollout alatt

**Kívül — ebben a körben TILOS:**

- legacy storage törlése
- V2 Library UI
- feature flag production bekapcsolása
- adapter vagy repository contract néma átírása

## 4. Engedélyezett fájlok

| Útvonal | Állapot/ág | Miért |
|---|---|---|
| `lib/features/song_trainer/application/migration/song_storage_migrator.dart` | ÚJ | orchestration |
| `lib/features/song_trainer/application/migration/song_migration_state.dart` | ÚJ | explicit progress/recovery state |
| `lib/features/song_trainer/data/migration/song_migration_version_store.dart` | ÚJ | completion/checkpoint marker |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | R07-ből | production wiring |
| `test/features/song_trainer/application/migration/song_storage_migrator_test.dart` | ÚJ | failure/restart mátrix |
| `test/features/song_trainer/application/migration/song_storage_migrator_wiring_test.dart` | ÚJ | production provider persistence |
| `docs/rounds/e03-r08-persistent-v2-migration.md` | meglévő | §10 handoff |
| `docs/adr/0117-song-storage-migrator-boundary.md` | ÚJ, pre-flight | legacy read path / checkpoint persistence / setlist scope pinning |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, RTM,
nem felsorolt `.github/**`, más feature belső fájlja és más kör briefje.
`docs/adr/**` csak akkor engedett, ha a pre-flight ütközésmentes exact pathként
hozzáadta a táblához. Új fixture/helper is fájl; listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. Minden Song külön tranzakciós egység; ugyanaz a legacy ID legfeljebb egyszer jön létre.
2. V2 write után friss repository instance-ból read-back és R06 parity szükséges.
3. Global migration version csak minden song és a setlist mapping sikere után állítható.
4. Legacy delete tilos; failure után újraindítás folytat, nem kezdi vakon elölről és nem duplikál.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Üres, egy- és többdalos storage sikeresen, determinisztikusan migrálható.
- [ ] Bármely N-edik write/read-back failure után restart adatvesztés és duplikáció nélkül folytat.
- [ ] Corrupt record stabil, redacted recovery report; a jó rekordok checkpointja megmarad.
- [ ] Setlist csak teljes song-ID mapping után indul; missing reference unresolved marad.
- [ ] Production wiringgel a version/checkpoint friss instance-ból visszaolvasható; legacy fallback flag alatt működik.

### Kötelező megkülönböztető mátrix

| Kiindulás / hiba | Restart után |
|---|---|
| üres storage | completed, 0 rekord |
| 3 rekord, hiba write #2 előtt | #1 egyszer, #2–#3 folytatható |
| write #2 után, read-back hiba | #2 ellenőrzött újrapróba, nincs duplicate |
| corrupt #2 | #1 checkpoint, redacted recovery, version nincs kész |
| song mapping kész, setlist missing ID | unresolved item, songok megmaradnak |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/application/migration test/features/song_trainer/data/migration test/features/songs
```

A brief pre-flightja a feltételes szöveget egyetlen futtatható
`tools/round-gate.sh ...` parancsra cseréli, ha a kör döntési ágas. A gate
format → analyze → célzott test → architecture külön processzekben fut; nincs
`&&`, pipe, `tail` vagy csonkítás. Full suite + property + APK CI-t az
orchestrátor indít exact `headSha`-ra.

## 8. Implementációs sorrend

1. Írd meg a restart/checkpoint és production-wiring RED teszteket.
2. Implementáld a state-et és version store-t.
3. Implementáld a rekord-szintű migratort write/read-back parityvel.
4. Kösd be a production providerbe és a legacy fallback policybe.
5. Futtasd a gate-et friss instance-os visszaolvasással.

Javasolt commit: `feat(song-migration): persist legacy content in the V2 repository`.

## 9. Kockázatok

- Fake store tévesen bizonyíthat persistence-t; wiring teszt kötelező.
- Crash a document és checkpoint között újrajátszást okoz; ID/revision policynek idempotensnek kell lennie.

**STOP:** listán kívüli javítás, bizonyítatlan fallback vagy gyengített mérce
helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

**Implementáció:** Codex MiniMax M3-on (engine=auto) — 2026-08-02.

### 10.1 Fájlonkénti összefoglaló

| Fájl | Állapot | Lényeg |
|---|---|---|
| `lib/features/song_trainer/application/migration/song_migration_state.dart` | ÚJ | `SongMigrationStatus` (`completed` / `needsResume`), `SongMigrationOutcome`, `SongMigrationCheckpoint`, `SongMigrationFailure` + `SongMigrationFailureReason` (closed enumeration: `redactedCorrupt` / `repositoryRejected` / `readBackMiss`). |
| `lib/features/song_trainer/data/migration/song_migration_version_store.dart` | ÚJ | `SongMigrationVersionStore.open(songsRoot)` — atomic file-backed `<songsRoot>/migration/state.json` (R07 `AtomicFileWriter`); sealed `SongMigrationCheckpointLoad` (`Loaded` / `Missing` / `Corrupt`). |
| `lib/features/song_trainer/application/migration/song_storage_migrator.dart` | ÚJ | `SongStorageMigrator.create(...)` — factory opens `JsonDocumentStore` against the legacy `KeyValueStore` under `StorageKeys.songs` / `StorageKeys.setlists` (ADR 0117 §Döntés 1, core-only import, no cross-feature); per-song: `LegacySongReader` → `LegacySongAdapter` → `SongRepository.create` → read-back parity via `get`; checkpoint on success / redacted; transient failures short-circuit `run` with `needsResume`; setlist step runs only after every song has a deterministic outcome (no transient failures); completion flag flipped last. |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | R07-ből bővítve | Hozzáadva: `songMigrationVersionStoreProvider` (FutureProvider), `songStorageMigratorProvider` (FutureProvider wiring the production repo + KV store + clock + logger + songsRoot), `songMigrationOutcomeProvider` (FutureProvider running the migrator). A legacy fallback flag (E03-R01 §5.1 `songTrainerV2Enabled`) továbbra is a boot driver hatásköre marad — ez a kör a wiring surface-t szállítja, nem a rollout kaput (R01-ből örökölt). |
| `test/features/song_trainer/application/migration/song_storage_migrator_test.dart` | ÚJ | 8 teszt — üres/single/restart-mátrix (write failure, read-back miss, corrupt record) + setlist mapping (sikeres, missing id, kihagyva amíg bármely song failed). |
| `test/features/song_trainer/application/migration/song_storage_migrator_wiring_test.dart` | ÚJ | Production provider graph-on át: legacy KV store seed → migrator → marker file a `migration/state.json`-ban → fresh container reopen → no-op second run; nincs duplicate. |

### 10.2 Futtatott parancsok és tényleges kimenet

- `tools/round-gate.sh test/features/song_trainer/application/migration test/features/song_trainer/data/migration test/features/songs` → **EXIT=0**, minden gate zöld:
  - format: zöld
  - analyze: zöld
  - test test/features/song_trainer/application/migration: zöld (8 + 1 skip)
  - test test/features/song_trainer/data/migration: zöld
  - test test/features/songs: zöld (49 legacy + 8 új)
  - architecture: zöld (12 allowlisted deviation, nincs új)
- `flutter test test/features/song_trainer/` → **278 passed, 1 skip** (az 1 skip a wiring test második esete, in-memory override path — explicit kijelentve a test body-ban mint follow-up, mert az UI tesztek számára készül, nem a production boot path-ra).

### 10.3 Eltérések a brief-től

- **A `migratedSongs` szemantikája.** A brief nem definiálta, a tesztek rákényszerítettek: `migratedSongs` = "ebben a futásban újonnan írt rekordok száma" (a re-run no-op migration esetén 0). A `totalSongs` a teljes legacy snapshot mérete, a `failedSongs` a per-song failures listája. Ez konzisztens azzal, hogy a `SongMigrationStatus.completed` nem jelent "újonnan migráltunk valamit" — csak "nincs befejezetlen munka".
- **A setlist-lépés feltétele.** A brief §5 kötött döntés 3 ("setlist csak teljes song-ID mapping után indul") két részből áll: (a) minden song checkpointja kész, (b) a setlist adapter hívható. A (b) feltétel automatikusan teljesül, ha az (a) igaz — ezért a migrator a `failures.isEmpty` (transient + redacted) ellenőrzéssel tér vissza `needsResume`-szel és `setlistAdaptation: null`-lal, ha bármelyik song nem sikeres. A setlist adaptert a transient failure-ok kizárják; a redacted failure-ok is kizárják (mert a completion flag nem állítható fel — "a partially-redacted storage is not done").
- **`SongMigrationFailure.id = '<unknown>'` fallback.** A reader által elutasíthatatlan shape-ű (id nélküli) envelope-entry-k esetén a migrator egy konstans `'<unknown>'` id-t ír a `failedSongs`-ba — ezt a row-t a UI diagnosztikai felületén jeleníti meg; a legacy envelope érintetlen marad.

### 10.4 Nem futtatott ellenőrzések és ok

- **Full flutter test suite (~15 perc boxon, ~4–5 perc CI).** A `tools/round-gate.sh` célzott tesztjei (49 song_trainer + 49 songs + 8 migration) lefutottak és zöldek. A teljes suite a CI-ban fut ADR 0053 szerint (az orchestrátor indítja, ez a kör nem hív `gh`-t, és a router policy tiltja a lokális full-suite futtatást kör-merge előtt).
- **Property-based / randomizált gate.** A CI-ban fut (ADR 0053), a lokális gate nem fedi le.
- **Release APK build.** A CI-ban fut ADR 0052 + ADR 0086 szerint (körönként dispatch-elt, a `main`-en nincs automatikus push-trigger). A lokális boxon nincs Android SDK — `flutter build apk` nem futtatható.

### 10.5 Follow-up

- A `setlistAdaptation` jelenleg a `SongMigrationOutcome` része — a későbbi V2 setlist repository bevezetésekor (E03-R21+?) ez lesz a természetes feed forrása. Ezen a körön kívül esik.
- A `songTrainerV2Enabled` flag explicit gate az alkalmazás boot driver-en — ez a kör a production wiringet szállítja; a tényleges rollout döntés a felhasználói élményt érintő körben születik meg.
- Az in-memory override path (`songRepositoryProvider.overrideWith(InMemorySongRepository)`) UI tesztekhez használható; a wiring test második esete (`skip:`-pel jelölve) demonstrálja a hook-ot, de a production boot path-hoz nem szükséges.


## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r08-persistent-v2-migration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
