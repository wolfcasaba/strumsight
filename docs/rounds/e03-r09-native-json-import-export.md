# E03-R09 — Natív StrumSight JSON import és export

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 9; §13–14
- **Branch:** `codex/e03-r09-native-json-import-export`
- **Előfeltétel:** E03-R08 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/data/importers/song_importer.dart",
  "lib/features/song_trainer/data/importers/native_json_importer.dart",
  "lib/features/song_trainer/data/importers/native_json_exporter.dart",
  "lib/features/song_trainer/data/importers/export_filename_sanitizer.dart",
  "lib/features/song_trainer/data/local/song_document_codec.dart",
  "test/features/song_trainer/data/importers/native_json_importer_test.dart",
  "test/features/song_trainer/data/importers/native_json_exporter_test.dart",
  "test/fixtures/song_trainer/native/full_song.strumsight-song.json",
  "test/fixtures/song_trainer/native/newer_version.strumsight-song.json",
  "test/fixtures/song_trainer/native/corrupt.strumsight-song.json",
  "docs/rounds/e03-r09-native-json-import-export.md",
]
gate_tests = [
  "test/features/song_trainer/data/importers/native_json_importer_test.dart",
  "test/features/song_trainer/data/importers/native_json_exporter_test.dart",
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

- A SongDocument codec és file repository rendelkezésre áll.
- Formátumfüggetlen importer contract alapját ebben a körben kell a natív adapterhez létrehozni.
- Import controller és UI csak R10/R15-ben készül.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

Teljes hűségű, offline, verziózott natív csereformátum probe/import/export contracttal, determinisztikus outputtal és privacy scrubbal.

## 2. Jelenlegi állapot

- A SongDocument codec és file repository rendelkezésre áll.
- Formátumfüggetlen importer contract alapját ebben a körben kell a natív adapterhez létrehozni.
- Import controller és UI csak R10/R15-ben készül.

## 3. Scope

**Benne:**

- SongImporter alapcontract és natív JSON adapter
- native exporter, probe, format/version/size/cancel policy
- deterministic codec snapshot és privacy scrub
- export filename sanitization

**Kívül — ebben a körben TILOS:**

- file picker és UI state machine
- MusicXML/MIDI/GP
- nagy source bytes Riverpod state-ben
- félig commitolt library rekord

## 4. Engedélyezett fájlok

| Útvonal | Állapot/ág | Miért |
|---|---|---|
| `lib/features/song_trainer/data/importers/song_importer.dart` | ÚJ | import contractok |
| `lib/features/song_trainer/data/importers/native_json_importer.dart` | ÚJ | probe/import |
| `lib/features/song_trainer/data/importers/native_json_exporter.dart` | ÚJ | export |
| `lib/features/song_trainer/data/importers/export_filename_sanitizer.dart` | ÚJ | safe név |
| `lib/features/song_trainer/data/local/song_document_codec.dart` | R02-ből | canonical root/codec |
| `test/features/song_trainer/data/importers/native_json_importer_test.dart` | ÚJ | probe/import matrix |
| `test/features/song_trainer/data/importers/native_json_exporter_test.dart` | ÚJ | round-trip/privacy |
| `test/fixtures/song_trainer/native/full_song.strumsight-song.json` | ÚJ | canonical snapshot |
| `test/fixtures/song_trainer/native/newer_version.strumsight-song.json` | ÚJ | forward-version failure |
| `test/fixtures/song_trainer/native/corrupt.strumsight-song.json` | ÚJ | malformed fixture |
| `docs/rounds/e03-r09-native-json-import-export.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, RTM,
nem felsorolt `.github/**`, más feature belső fájlja és más kör briefje.
`docs/adr/**` csak akkor engedett, ha a pre-flight ütközésmentes exact pathként
hozzáadta a táblához. Új fixture/helper is fájl; listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. Root `format` és `formatVersion` kötelező; newer schema fail-closed érthető failure.
2. Ugyanaz a normalizált document canonical JSON bytes/hash outputot ad.
3. Exportból abszolút path, temporary path és privacy-sensitive import metadata hiányzik.
4. Duplicate source hash warning, nem automatikus identity összevonás.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Full metadata/section/map/track/event/asset manifest round-trip adatvesztés nélkül működik.
- [ ] Invalid root, corrupt JSON, duplicate ID, max size és max+1, newer version és cancel stabil eredmény.
- [ ] Export filename minden platformon safe és nem változtatja a SongId-t.
- [ ] Export bytes/hash determinisztikus; privacy tiltott mezők snapshotban sincsenek.
- [ ] Import failure nem ír repositoryt; cancellation biztonságos ponton megszakít.

### Kötelező megkülönböztető mátrix

| Input | Várt probe/import |
|---|---|
| valid magic+extension | recognized / success |
| valid content, rossz extension | recognized + mismatch warning |
| rossz root vagy corrupt | stable failure |
| formatVersion current/current+1 | success/fail-closed |
| size max−1/max/max+1 | accept/accept/reject |
| cancel parse előtt/közben | cancelled, 0 commit |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/data/importers/native_json_importer_test.dart test/features/song_trainer/data/importers/native_json_exporter_test.dart
```

A brief pre-flightja a feltételes szöveget egyetlen futtatható
`tools/round-gate.sh ...` parancsra cseréli, ha a kör döntési ágas. A gate
format → analyze → célzott test → architecture külön processzekben fut; nincs
`&&`, pipe, `tail` vagy csonkítás. Full suite + property + APK CI-t az
orchestrátor indít exact `headSha`-ra.

## 8. Implementációs sorrend

1. Írd meg a root/version/limit/cancel RED teszteket és canonical fixturet.
2. Írd meg az export privacy/deterministic round-trip tesztet.
3. Implementáld az importer contractot, probe-ot és natív adaptert.
4. Implementáld az exportert és filename sanitizert.
5. Futtasd a gate-et, a fixture hash-változást review-ban indokold.

Javasolt commit: `feat(song-import): add native StrumSight song import and export`.

## 9. Kockázatok

- A domain codec és exchange-format összekeverése privacy mezőt exportálhat.
- Canonical map ordering platformonként driftelhet.

**STOP:** listán kívüli javítás, bizonyítatlan fallback vagy gyengített mérce
helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r09-native-json-import-export-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
