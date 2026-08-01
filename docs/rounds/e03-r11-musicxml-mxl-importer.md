# E03-R11 — MusicXML és MXL importer

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 11; §15
- **Branch:** `codex/e03-r11-musicxml-mxl-importer`
- **Előfeltétel:** E03-R10 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

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

- Az R10 registry/workspace/limit/cancel pipeline formátumfüggetlenül kész.
- Parser dependency csak pre-flight licence/maintenance/security audit után választható.
- External entity, archive traversal és korlátlan repeat expansion hard security tiltás.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

A dokumentált MusicXML subset és MXL container biztonságos, rational timingú, fixture-snapshotolt importja.

## 2. Jelenlegi állapot

- Az R10 registry/workspace/limit/cancel pipeline formátumfüggetlenül kész.
- Parser dependency csak pre-flight licence/maintenance/security audit után választható.
- External entity, archive traversal és korlátlan repeat expansion hard security tiltás.

## 3. Scope

**Benne:**

- XML parser adapter, probe, mapper és part preview
- divisions/tie/repeat rational konverzió
- MXL secure extraction és container validation
- teljes §15.7 fixture és malicious suite

**Kívül — ebben a körben TILOS:**

- teljes engraving/notation támogatás
- komplex D.C./D.S./Coda vagy bizonytalan nested repeat trainerként
- parser package type domain/application rétegben
- jogvédett kereskedelmi score fixture

## 4. Engedélyezett fájlok

| Útvonal | Állapot/ág | Miért |
|---|---|---|
| `pubspec.yaml` | meglévő | auditált parser/archive dependency |
| `pubspec.lock` | meglévő | lock |
| `lib/features/song_trainer/data/importers/musicxml_importer.dart` | ÚJ | probe/import adapter |
| `lib/features/song_trainer/data/importers/musicxml_parser_adapter.dart` | ÚJ | package boundary |
| `lib/features/song_trainer/data/importers/musicxml_mapper.dart` | ÚJ | domain mapping |
| `lib/features/song_trainer/data/importers/musicxml_repeat_expander.dart` | ÚJ | bounded linearization |
| `lib/features/song_trainer/data/importers/mxl_importer.dart` | ÚJ | container adapter |
| `lib/features/song_trainer/data/importers/mxl_archive_reader.dart` | ÚJ | secure extraction |
| `lib/features/song_trainer/data/importers/importer_registry.dart` | R10-ből | registration |
| `test/features/song_trainer/data/importers/musicxml_importer_test.dart` | ÚJ | subset snapshot |
| `test/features/song_trainer/data/importers/mxl_security_test.dart` | ÚJ | archive/XML security |
| `test/fixtures/song_trainer/musicxml/chord_chart_44.musicxml` | ÚJ | 4/4 chord |
| `test/fixtures/song_trainer/musicxml/waltz_34.musicxml` | ÚJ | 3/4 |
| `test/fixtures/song_trainer/musicxml/meter_68.musicxml` | ÚJ | 6/8 |
| `test/fixtures/song_trainer/musicxml/tempo_meter_pickup.musicxml` | ÚJ | map+pickup |
| `test/fixtures/song_trainer/musicxml/two_chords.musicxml` | ÚJ | két chord/measure |
| `test/fixtures/song_trainer/musicxml/monophonic_tie_rest.musicxml` | ÚJ | note/tie/rest |
| `test/fixtures/song_trainer/musicxml/multipart_polyphonic.musicxml` | ÚJ | part preview/polyphony |
| `test/fixtures/song_trainer/musicxml/markers_lyrics_repeat.musicxml` | ÚJ | marker/lyrics/repeat |
| `test/fixtures/song_trainer/musicxml/corrupt.musicxml` | ÚJ | malformed XML |
| `test/fixtures/song_trainer/mxl/malicious_path.mxl` | ÚJ | traversal |
| `test/fixtures/song_trainer/mxl/extracted_limit.mxl` | ÚJ | zip expansion limit |
| `docs/rounds/e03-r11-musicxml-mxl-importer.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, RTM,
nem felsorolt `.github/**`, más feature belső fájlja és más kör briefje.
`docs/adr/**` csak akkor engedett, ha a pre-flight ütközésmentes exact pathként
hozzáadta a táblához. Új fixture/helper is fájl; listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. XML external entity és entity expansion tiltott; parser defaultját teszt igazolja.
2. Divisions rational/integer, max denominator és kontrollált quantization warninggal.
3. Repeat expansion measure/nesting limittel; bizonytalan navigáció display-only warning.
4. MXL entry path canonicalizált, absolute/symlink/duplicate/nested archive policy fail-closed.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Title/creator/part/measure/divisions/meter/key/tempo/harmony/note/rest/tie/marker/lyrics/string/fret subset megmarad.
- [ ] 3/4, 4/4, 6/8, pickup, tempo/meter change és két chord snapshot stabil.
- [ ] Part preview note count/pitch range/polyphony/tab információt ad.
- [ ] XXE, traversal, excessive entries/extracted bytes, corrupt container/root és nested archive nem ír workspace-en kívül.
- [ ] Unsupported, de biztonságosan megőrizhető elem stabil warning, nem néma loss vagy fatal.

### Kötelező megkülönböztető mátrix

| Security/input boundary | max−1 / max / max+1 |
|---|---|
| archive entry count | accept / accept / reject |
| extracted bytes | accept / accept / reject |
| repeat expanded measures | accept / accept / display-only failure/warning |
| divisions denominator | exact / exact / controlled quantization warning |

| Path | Várt |
|---|---|
| `score.xml` | accept |
| `../score.xml`, `/score.xml`, symlink | reject |
| duplicate canonical path | reject |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/data/importers/musicxml_importer_test.dart test/features/song_trainer/data/importers/mxl_security_test.dart
```

A brief pre-flightja a feltételes szöveget egyetlen futtatható
`tools/round-gate.sh ...` parancsra cseréli, ha a kör döntési ágas. A gate
format → analyze → célzott test → architecture külön processzekben fut; nincs
`&&`, pipe, `tail` vagy csonkítás. Full suite + property + APK CI-t az
orchestrátor indít exact `headSha`-ra.

## 8. Implementációs sorrend

1. Auditáld és dokumentáld a dependency licence/security állapotát.
2. Írd meg a normál subset snapshot és malicious RED teszteket.
3. Implementáld az XML adaptert és rational mappert.
4. Implementáld a bounded repeatet és secure MXL readert.
5. Regisztráld az importert, futtasd a gate-et és review-zd a fixture provenance-et.

Javasolt commit: `feat(song-import): add secure MusicXML and MXL import`.

## 9. Kockázatok

- Parser lazy entity behavior rejtve maradhat; célzott XXE fixture kötelező.
- Binary MXL fixture mérete és licencelése review tárgy; minimális technikai fájl kell.
- Repeat expansion exponenciális lehet, ha csak output végén limitál.

**STOP:** listán kívüli javítás, bizonyítatlan fallback vagy gyengített mérce
helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r11-musicxml-mxl-importer-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
