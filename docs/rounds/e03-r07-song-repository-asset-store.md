# E03-R07 — Fájlrendszeres Song repository és asset store

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 7; §18
- **Branch:** `codex/e03-r07-song-repository-asset-store`
- **Előfeltétel:** E03-R06 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/domain/repositories/song_repository.dart",
  "lib/features/song_trainer/domain/repositories/song_asset_repository.dart",
  "lib/features/song_trainer/data/local/file_song_repository.dart",
  "lib/features/song_trainer/data/local/file_song_asset_repository.dart",
  "lib/features/song_trainer/data/local/song_index_codec.dart",
  "lib/features/song_trainer/data/local/atomic_file_writer.dart",
  "lib/features/song_trainer/data/local/song_repository_recovery.dart",
  "lib/features/song_trainer/data/local/in_memory_song_repository.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "test/features/song_trainer/data/local/file_song_repository_test.dart",
  "test/features/song_trainer/data/local/file_song_asset_repository_test.dart",
  "test/features/song_trainer/data/local/song_repository_recovery_test.dart",
  "test/features/song_trainer/data/local/song_repository_wiring_test.dart",
  "docs/rounds/e03-r07-song-repository-asset-store.md",
]
gate_tests = [
  "test/features/song_trainer/data/local",
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

- A V2 codec R02-ben, validáció R05-ben, legacy adapter R06-ban kész.
- A planning baseline core storage KeyValueStore-ja nem alkalmas nagy SongDocument/asset tárolásra.
- Platform directory, clock és IO hibák injektálható boundaryt igényelnek.

A pre-flight az itt leírt tényeket újraméri. Ha bármelyik eltér, ebben a
szekcióban rögzíti a mért állapotot, a választott feloldást és annak indokát.
Üres vagy implicit revízióval a státusz nem válhat `PLANNING`-re.

## 1. Cél

Atomikus, revision-aware, recoverable dokumentum- és content-hash asset tárolás szállítása SharedPreferences nélkül.

## 2. Jelenlegi állapot

- A V2 codec R02-ben, validáció R05-ben, legacy adapter R06-ban kész.
- A planning baseline core storage KeyValueStore-ja nem alkalmas nagy SongDocument/asset tárolásra.
- Platform directory, clock és IO hibák injektálható boundaryt igényelnek.

## 3. Scope

**Benne:**

- SongRepository és SongAssetRepository contract
- file repository, index codec, atomic writer és recovery
- trash/restore/permanent delete, SHA-256 dedupe/integrity
- in-memory fake és production-wiring persistence test

**Kívül — ebben a körben TILOS:**

- legacy persistent migráció
- library UI és import controller
- SharedPreferences SongDocument vagy global singleton path

## 4. Engedélyezett fájlok

| Útvonal | Állapot a kör elején | Miért |
|---|---|---|
| `lib/features/song_trainer/domain/repositories/song_repository.dart` | ÚJ | repository contract |
| `lib/features/song_trainer/domain/repositories/song_asset_repository.dart` | ÚJ | asset contract |
| `lib/features/song_trainer/data/local/file_song_repository.dart` | ÚJ | file implementation |
| `lib/features/song_trainer/data/local/file_song_asset_repository.dart` | ÚJ | streamelt asset store |
| `lib/features/song_trainer/data/local/song_index_codec.dart` | ÚJ | summary index |
| `lib/features/song_trainer/data/local/atomic_file_writer.dart` | ÚJ | temp/flush/verify/rename |
| `lib/features/song_trainer/data/local/song_repository_recovery.dart` | ÚJ | startup scan |
| `lib/features/song_trainer/data/local/in_memory_song_repository.dart` | ÚJ | fake |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | ÚJ | production wiring |
| `test/features/song_trainer/data/local/file_song_repository_test.dart` | ÚJ | CRUD/crash/revision |
| `test/features/song_trainer/data/local/file_song_asset_repository_test.dart` | ÚJ | hash/dedupe/delete |
| `test/features/song_trainer/data/local/song_repository_recovery_test.dart` | ÚJ | recovery |
| `test/features/song_trainer/data/local/song_repository_wiring_test.dart` | ÚJ | real provider re-open |
| `docs/rounds/e03-r07-song-repository-asset-store.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, az RTM,
`.github/**`, nem felsorolt `lib/features/**`, más kör briefje és
`docs/adr/**`. ADR-fájl csak akkor kivétel, ha a pre-flight ütközésmentes
exact pathként hozzáadta ehhez a táblához, még a `PLANNING` commit előtt.
Új tesztfixture vagy helper is fájl: ha nincs tételesen a táblában, `stopped`.

## 5. Kötött architekturális döntések

1. Save sorrend: validate→temp serialize→flush→decode verify→atomic document rename→temp index→atomic index rename→success.
2. Expected revision mismatch stabil conflict; overwrite és retry-without-refresh tilos.
3. Asset streamelt SHA-256 alapján deduplikál; document platform pathot nem tárol.
4. Recovery nem töröl bizonyíték nélkül user contentet; korábbi jó verzió hiba után olvasható.

E döntések enyhítése nem elfogadható „zöldre javítás”. Valódi ellentmondásnál
brief-revízió vagy ADR szükséges.

## 6. Acceptance criteria

- [ ] Create/get/update/list, stale revision, trash/restore/delete stabil AppResult contracttal működik.
- [ ] Minden crash-pont után vagy régi jó vagy új teljes verzió olvasható; fél JSON nem válik currentté.
- [ ] Hash mismatch, missing/corrupt index/document, duplicate/orphan asset recoverable report.
- [ ] Production providerrel mentett adat friss repository instance-ból olvasható; valós IO/storage exception stabil failure code-dá alakul.
- [ ] SongDocument egyetlen SharedPreferences/key-value value-ban sem jelenik meg.

### Kötelező megkülönböztető mátrix

| Hibahely | Kötelező újraindítási eredmény |
|---|---|
| temp write előtt/közben | régi verzió |
| flush után, verify előtt | régi verzió + temp recovery |
| document rename után, index előtt | document/index reconcile |
| index temp/rename közben | documentből rebuildelhető index |
| asset hash mismatch | corrupt report, nincs néma playback |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással tesz pirossá; bemásolt zöld kimenet önmagában nem evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/data/local
```

Ez az egyetlen lokális záró gate; külön processzben futó format → analyze →
célzott testek → architecture lépéseit nem szabad `&&`-del, pipe-pal,
`tail`-lel vagy csonkítással helyettesíteni. A full suite + randomizált
property + APK CI-t az orchestrátor indítja, és exact branch `headSha`-t
ellenőriz.

## 8. Implementációs sorrend

1. Írd meg a contract-, crash-point- és provider-reopen RED teszteket temporary könyvtárral.
2. Implementáld az atomic writert és index codecet.
3. Implementáld a document repositoryt optimistic revisionnel.
4. Implementáld a streamelt asset store-t és trash/recoveryt.
5. Kösd be production providerrel, futtasd a gate-et és rögzítsd a disk reopen evidenciát.

Javasolt körcommit: `feat(song-storage): add atomic document and asset repositories`.

## 9. Kockázatok

- Filesystem rename atomicitása platformonként eltér; capability és fallback mérendő.
- Index/document kétfázisú írása split-brain állapotot okozhat; recovery fixture kötelező.
- Fake repository zöldje nem bizonyít perzisztenciát.

**STOP:** ha a kockázat csak listán kívüli módosítással, bizonyítatlan fallbackkel
vagy acceptance-gyengítéssel oldható fel, állj meg és kérj brief-revíziót.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult el; ezért nincs implementációs vagy tesztsiker-állítás.
A handoffba a végrehajtáskor fájlonkénti összefoglaló, tényleges parancs és
csonkítatlan eredmény, terveltérés, nem futtatott ellenőrzés és follow-up kerül.
Minden viselkedési állítást konkrét teszt vagy mérés bizonyít.

## 11. Review — a független reviewer tölti ki

Tervezett review-fájl:
`docs/reviews/e03-r07-song-repository-asset-store-review.md`.

Merge csak akkor engedett, ha az exact-SHA CI zöld, a diff a §4 listáján belül
marad, és nincs OPEN BLOCKER vagy MAJOR.
