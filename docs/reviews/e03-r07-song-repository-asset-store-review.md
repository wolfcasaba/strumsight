# E03-R07 — Review

Brief: `docs/rounds/e03-r07-song-repository-asset-store.md`
Diff: `git diff main...codex/e03-r07-song-repository-asset-store` (merged as PR #66, squash `b8b7e4e`)
Reviewer: Claude Sonnet 5 (three independent passes, isolated `/tmp` clones each time) · Dátum: 2026-08-02
Verdikt: **APPROVED** (final pass, commit `652fdf6`)

## Összegzés

Three independent review passes were required across two fix rounds before merge. Green gate was never accepted as evidence on its own — each pass wrote its own throwaway adversarial probe tests against the shipped code.

- **Pass 1** (against `e8555b6`): BLOCKER 1, MAJOR 6, MINOR 5, NOTE 2 — CHANGES REQUESTED.
- **Fix round #1** (MiniMax M3, `resume` with findings): closed all 7 BLOCKER/MAJOR + 3 cheap items.
- **Pass 2** (against `468dae4`): found fix round #1's own MAJOR-7 fix (streamed SHA-256) had introduced a NEW BLOCKER (`writeFromSync` length/end-index confusion) — CHANGES REQUESTED, 1 fresh BLOCKER.
- **Fix round #2** (orchestrator-authored, one line + one regression test — implementer side genuinely unavailable, see round brief §10.6): closed the new BLOCKER.
- **Pass 3 / final** (against `652fdf6`): independently re-verified the fix with a differently-sized probe, swept every other index/length call site in the diff, confirmed no regression on the earlier 7 findings, confirmed scope — **APPROVED**.

## Acceptance criteria (brief §6)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Create/get/update/list, stale revision, trash/restore/delete stabil `AppResult` contracttal | ✅ | `file_song_repository_test.dart` teljes csoport-készlete, 67/67 zöld a végső gate-ben |
| 2 | Minden crash-pont után régi jó vagy új teljes verzió olvasható; fél JSON nem válik currentté | ✅ (fix round #1 után) | `AtomicFileWriter` direkt `renameSync` pre-delete nélkül (BLOCKER 6 zárva); `song_repository_recovery_test.dart` reopen→recovery integrációs teszt |
| 3 | Hash mismatch, missing/corrupt index/document, duplicate/orphan asset recoverable report | ✅ (fix round #1 után) | `get()` re-hash → `corruptAsset` (MAJOR 2); sidecar decode-hiba → `corruptSidecar` (MAJOR 3); `SongIndexCodec` corruption-mátrix |
| 4 | Production providerrel mentett adat friss repository instance-ból olvasható; valós IO/storage exception stabil failure code-dá alakul | ✅ | `song_repository_wiring_test.dart` reopen-ciklus; minden repository-oldali catch stabil kódra képez |
| 5 | `SongDocument` egyetlen SharedPreferences/key-value value-ban sem jelenik meg | ✅ | grep nulla találat `shared_preferences`/`KeyValueStore`-ra az új fájlokban (mindhárom review pass megerősítette) |

### Kötelező megkülönböztető mátrix (brief §6 táblázat)

| Hibahely | Kötelező eredmény | Teljesült |
|---|---|---|
| temp write előtt/közben | régi verzió | ✅ — staging a `temp/` alatt (BLOCKER/MAJOR 5 fix után), a rename előtti hiba nem érinti a targetet |
| flush után, verify előtt | régi verzió + temp recovery | ✅ — verifier-false eset teszttel fedve |
| document rename után, index előtt | document/index reconcile | ✅ — `song_repository_recovery_test.dart` "Integration: FileSongRepository reopen → recovery" |
| index temp/rename közben | documentből rebuildelhető index | ✅ — `rebuildIndex` teszt |
| asset hash mismatch | corrupt report, nincs néma playback | ✅ (fix round #1 után, MAJOR 2) |

## Scope-audit

Mindhárom review pass (izolált klónban, `git diff --stat`) megerősítette: a diff a brief §4 táblájának **pontosan** 14 fájlját érinti — 9 `lib/features/song_trainer/**` fájl, 4 `test/features/song_trainer/data/local/**` fájl, a kör-brief maga. Nincs `pubspec.yaml`, `HANDOFF.md`, `docs/adr/**` vagy `.github/**` érintés, nincs listán kívüli új fájl.

**Folyamat-megjegyzés a diffhez:** M3 első próbája két, a listán KÍVÜLI teszt-fájlt hozott létre (`atomic_file_writer_test.dart`, `song_index_codec_test.dart`); az orchestrátor mechanikusan (fájllista-bővítés nélkül) áthelyezte mind a 11 tesztesetet a már engedélyezett fájlokba — részletek a kör-brief §10.3-ban.

## Megállapítások (lezárt lista, mind FIXED)

### F1 — BLOCKER — hiányzó validáció mentés előtt

- **Fájl:** `lib/features/song_trainer/data/local/file_song_repository.dart:202,228` (pass 1 idején)
- **Probléma:** `create`/`update` sosem hívta a `SongValidator`/`SongCapabilityResolver`-t; `fatal` validációs hibájú dokumentum sikeresen perzisztálódott.
- **Kötelező javítás:** validáció a diszk-írás előtt, `canPersist=false` → refuse.
- **Ellenőrzés:** "BLOCKER 1 — refuses a fatal validation issue before touching disk" (create + update), fatal-triggerű `SongDocument`-tel.
- **Státusz:** FIXED (`468dae4`)

### F2 — MAJOR — asset-olvasás integritás-ellenőrzés nélkül

- **Fájl:** `file_song_asset_repository.dart:156` (pass 1 idején)
- **Probléma:** `get()` a lemezes bájtokat SHA-256 újraellenőrzés nélkül adta vissza; egy sérült asset `Success`-ként ment volna vissza.
- **Kötelező javítás:** újra-hash olvasáskor, `corruptAsset` eltérésnél.
- **Ellenőrzés:** on-disk bájt-korrupció után `get()` → `Failure(corruptAsset)`.
- **Státusz:** FIXED (`468dae4`)

### F3 — MAJOR — uncaught `FormatException` sérült sidecaron

- **Fájl:** `file_song_asset_repository.dart` `_readSummary`/`_readRefs`
- **Probléma:** `jsonDecode` védtelen; csak `FileSystemException`-t kapott el a hívó.
- **Kötelező javítás:** decode-hiba → stabil `corruptSidecar` kód.
- **Ellenőrzés:** kézzel sérült `.summary.json`/`.refs.json` → `Failure`, nincs uncaught throw.
- **Státusz:** FIXED (`468dae4`)

### F4 — MAJOR — nem-atomikus asset-írás

- **Fájl:** `file_song_asset_repository.dart` `_writeAtomic`
- **Probléma:** bare `deleteSync` + `writeAsBytesSync`, nincs temp/rename/verify.
- **Kötelező javítás:** ugyanaz az `AtomicFileWriter` path, mint a dokumentumoknál.
- **Ellenőrzés:** "MAJOR 4 — asset bytes & sidecar writes route through the AtomicFileWriter".
- **Státusz:** FIXED (`468dae4`)

### F5 — BLOCKER/MAJOR — rossz staging könyvtár

- **Fájl:** `atomic_file_writer.dart`
- **Probléma:** a temp fájl a target melletti könyvtárban stage-elt, sosem az ADR-előírt `temp/` alatt — a recovery scanner soha nem látott valódi crash-residue-t.
- **Kötelező javítás:** opcionális `stagingDirectory` paraméter; mindkét repository a songs-root `temp/`-jét adja át.
- **Ellenőrzés:** "BLOCKER 5/MAJOR 5 — staged temp file lives in the stagingDirectory".
- **Státusz:** FIXED (`468dae4`)

### F6 — BLOCKER — delete-then-rename törte az atomicitást

- **Fájl:** `atomic_file_writer.dart`
- **Probléma:** a target előzetes törlése a rename előtt valódi crash-ablakot nyitott (sem a régi, sem az új dokumentum nem lett volna olvasható).
- **Kötelező javítás:** közvetlen `renameSync`, előzetes törlés nélkül (POSIX `rename(2)` már atomikusan felülír).
- **Ellenőrzés:** kódszemle + a meglévő write-teszt-mátrix zöld marad.
- **Státusz:** FIXED (`468dae4`)

### F7 — MAJOR → (fix round #1 után) BLOCKER regresszió → FIXED

- **Fájl:** `atomic_file_writer.dart` `writeStream`
- **Probléma (eredeti, pass 1):** a streamelt SHA-256 (ADR 0090 §5 / brief §3) nem volt implementálva, a teljes payload egyszerre memóriába töltve hash-elődött.
- **Fix round #1 hibája (pass 2 találta):** a bevezetett `writeStream` `raf.writeFromSync(bytes, offset, length)`-t hívott, holott a harmadik argumentum kizáró VÉG-index, nem hossz — egy chunknál (64 KiB) nagyobb payload `RangeError`-ral halt volna el éles használatban; a leszállított 66 teszt mind sub-chunk fixture volt, ezért a gate zöld maradt.
- **Kötelező javítás:** `writeFromSync(bytes, offset, end)`.
- **Ellenőrzés:** két független review pass írt saját, eltérő méretű (200 KiB, illetve 3×64 KiB+partial) próbatesztet, mindkettő byte-azonos round-trip + helyes hash mellett zöld a javítás után.
- **Státusz:** FIXED (`652fdf6`, orchestrátor-írt — ld. kör-brief §10.6 az indoklásért: M3 kerete kimerült, Terra napi automatikus kerete mérve kimerült ugyanarra az UTC napra)

### Cheap fixes (mind FIXED, `468dae4`)

- Vacuous `.tmp` reziduum-szűrő → valós `\.tmp-\d+-\d+$` regexre cserélve.
- Hibás JSON-fixture (törte a saját tesztje célját) → valós, csak a `revision` mezőt hiányoló bemenetre javítva.
- Halott `Directory.flush()` kód → eltávolítva, őszinte doc-comment a platform-korlátról; `pid` sentinel dokumentálva.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (mindhárom review pass + orchestrátor, izolált klónokban) |
| analyze | zöld | ✅ |
| `test test/features/song_trainer/data/local` | 67/67 zöld | ✅ |
| architecture | zöld (12 allowlisted deviation) | ✅ |
| CI (teljes suite + property + APK) | [run 30750669625](https://github.com/wolfcasaba/strumsight/actions/runs/30750669625) | ✅ — a merge-elt `headSha` (`652fdf6`) exact-matchel |
| post-merge független gate `main`-en | zöld | ✅ (orchestrátor, izolált klón, `b8b7e4e`) |

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge. Teljesült — squash-merge [PR #66](https://github.com/wolfcasaba/strumsight/pull/66) → `b8b7e4e`.
