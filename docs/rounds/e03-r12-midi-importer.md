# E03-R12 — Standard MIDI importer

- **Státusz:** **PLANNING** (2026-08-03, pre-flight baseline: `main` @ `99d3adc`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 12; §16
- **Branch:** `codex/e03-r12-midi-importer`
- **Előfeltétel:** E03-R11 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/data/importers/import_limits.dart",
  "lib/features/song_trainer/data/importers/midi_importer.dart",
  "lib/features/song_trainer/data/importers/midi_parser_adapter.dart",
  "lib/features/song_trainer/data/importers/midi_timeline_mapper.dart",
  "lib/features/song_trainer/data/importers/midi_track_preview.dart",
  "lib/features/song_trainer/data/importers/song_importer.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "test/features/song_trainer/data/importers/midi_importer_test.dart",
  "test/features/song_trainer/data/importers/midi_malformed_test.dart",
  "test/features/song_trainer/application/song_trainer_providers_test.dart",
  "test/fixtures/song_trainer/midi/format0.mid",
  "test/fixtures/song_trainer/midi/format1_multitrack.mid",
  "test/fixtures/song_trainer/midi/tempo_meter_marker.mid",
  "test/fixtures/song_trainer/midi/running_velocity0.mid",
  "test/fixtures/song_trainer/midi/polyphonic_drum.mid",
  "test/fixtures/song_trainer/midi/malformed_chunks.mid",
  "docs/rounds/e03-r12-midi-importer.md",
]
gate_tests = [
  "test/features/song_trainer/data/importers/midi_importer_test.dart",
  "test/features/song_trainer/data/importers/midi_malformed_test.dart",
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

- **Mért baseline (2026-08-03):** E03-R11 merge-e a `main` `99d3adc`
  commitján van; nincs nyitott PR vagy E03-R12 worktree/branch/review. A
  production `ImporterRegistry` listát nem `importer_registry.dart`, hanem a
  `songImporterRegistryProvider` állítja össze a
  `lib/features/song_trainer/application/song_trainer_providers.dart:140–148`
  soron. Ezért az előkészített registry-pathot eltávolítottuk, és a tényleges
  production owner, valamint a közvetlen provider-teszt felkerült az
  engedélyezett listára.
- **Mért preview-contract drift:** `ImportPartPreview`
  (`data/importers/song_importer.dart:65–110`) jelenleg csak id/name/program,
  noteCount, pitch range és polyphony adatot hordoz; nincs MIDI channel,
  duration vagy suspected-drum mező. A §6 preview-acceptance ezeket kötelezővé
  teszi, ezért a szerződés exact ownerét hozzáadtuk. A mezők opcionálisak
  maradnak, így a korábbi JSON/MusicXML/MXL preview-k érték- és equality
  contractja nem változik.
- **Mért erőforrás-owner:** a közös event-limit az
  `ImportLimits.maxEventCount` (`data/importers/import_limits.dart:16–34`),
  és az `ImporterRegistry.import` érvényesíti
  (`data/importers/importer_registry.dart:67–79`). Az R12 nem vezet be
  privát MIDI-limitet és nem módosítja ezt a már merge-elt policyt; a
  max−1/max/max+1 esetet a MIDI teszt azonos `ImporterRegistry`-n keresztül
  méri.
- **Parser/licence audit:** a vizsgált `dart_midi_pro` 1.0.4+2 pure-Dart,
  MIT-licencű, de unverified publisherrel, alacsony használattal és a
  nyilvános csomagoldal szerint kb. 20 hónapja publikált utolsó kiadással
  rendelkezik. A csomag nem ad auditálható, eseményenkénti cancellation- és
  limit-határt; ezért az R12 kis, saját, csak SMF 0/1 + PPQ subset byte
  decoderét használja, új csomag és `pubspec`-változás nélkül. A döntést az
  új ADR 0121 rögzíti.
- **Kötött feloldás:** az ADR 0091/0119 közös security- és registry-határait
  nem módosítjuk. A MIDI adapter minden header/chunk/running-status hibát
  typed failureként ad vissza; a MIDI parser típusa nem lép ki a data
  rétegből. SMPTE marad explicit unsupported warning/failure, chord inference
  nem része a körnek.

### Módosítás (ADR 0112 önjavító kör, 2026-08-03)

- **Mért H3 gyökérok:** az R12 review eldobható invariáns-próbája szerint a
  parser a header `trackCount` értékét korlát nélkül dolgozza fel. Ez sérti az
  ADR 0091 §3 MIDI track-count kötelezettségét. Az egyetlen közös,
  konfigurálható limit- és stabil-failure-code owner a
  `data/importers/import_limits.dart:1-34`, amely hiányzott a prepared brief
  emberi scope-táblájából és az `ai-router` `allowed_paths` listájából.
- **Feloldás:** a scope kizárólag ezt az exact shared-policy ownert nyitja meg.
  Az R12 a `ImportLimits.maxMidiTrackCount` és
  `ImportLimitFailureCode.midiTrackCountExceeded` közös contractját használja;
  a parser a track-loop előtt fail-closed ellenőriz, nem vezet be privát
  MIDI-limitet. A már engedélyezett `midi_malformed_test.dart` a track-count
  max−1/max/max+1 mátrixot méri. Az ADR 0091 korlátkövetelménye és a gate nem
  változik.
- **Regressziós őr:**
  `Epic3BriefMetadataTest.test_r12_scope_includes_measured_midi_track_limit_owner`
  először RED volt e path hiányával; ezután csak e scope-revízióval GREEN.

### Módosítás (ADR 0112 önjavító kör, 2026-08-03, H6)

- **Mért gyökérok:** a H3-scope merge-konfliktusának R12-oldali feloldása az
  `docs/adr/0121-midi-import-boundary.md` pre-flight dokumentumot is
  visszaírta az implementer `ai-router.allowed_paths` listájába. Ez sérti az
  ADR 0088 tulajdonosi határát: az ADR a §4 emberi scope-táblájában marad,
  de az implementer nem szerkesztheti. A `Router CI` ezt a
  `Epic3BriefMetadataTest.test_all_twenty_two_briefs_match_their_committed_scope_and_gate`
  valódi hibájával mérte.
- **Feloldás:** az `allowed_paths` ismét csak a modell által módosítható
  implementation/test/fixture/brief fájlokat tartalmazza; a §4-table
  `docs/adr/0121-midi-import-boundary.md` sora változatlan marad. Ez nem
  szűkíti az emberi pre-flight scope-ot, csak visszaállítja a router
  szerződését. A rebase-baseline csak e javított, zöld scope-audit után
  frissítheti a perzisztált brief-hash-et.

- R10 importer pipeline és R05 NoteTrackAnalyzer használható.
- Parser dependency csak licence/maintenance audit után kerülhet be.
- Chord inference és SMPTE timing nem kötelező az első verzióban.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

SMF format 0/1, PPQ timing, meta- és note-event import stabil track previewval, raw timing megőrzéssel és malformed/cancel védelemmel.

## 2. Jelenlegi állapot

- R10 importer pipeline és R05 NoteTrackAnalyzer használható.
- Parser dependency csak licence/maintenance audit után kerülhet be.
- Chord inference és SMPTE timing nem kötelező az első verzióban.

## 3. Scope

**Benne:**

- MIDI parser adapter, header/chunk/running-status validáció
- PPQ tempo/meter/key/marker/lyric mapping
- note-on/off pairing, preview, drum/polyphony report
- event- és MIDI track-count limit, cancellation

**Kívül — ebben a körben TILOS:**

- chord inference
- raw start nyolcadokra felülírása
- SMPTE trainer support
- MIDI playback vagy editor

## 4. Engedélyezett fájlok

| Útvonal | Állapot/ág | Miért |
|---|---|---|
| `docs/adr/0121-midi-import-boundary.md` | új, R12 pre-flight | auditált saját SMF subset döntése |
| `lib/features/song_trainer/data/importers/import_limits.dart` | R10-ből | ADR 0091 közös, konfigurálható MIDI track-count limitje és stabil failure code-ja |
| `lib/features/song_trainer/data/importers/midi_importer.dart` | ÚJ | probe/import |
| `lib/features/song_trainer/data/importers/midi_parser_adapter.dart` | ÚJ | package/binary boundary |
| `lib/features/song_trainer/data/importers/midi_timeline_mapper.dart` | ÚJ | PPQ→beat |
| `lib/features/song_trainer/data/importers/midi_track_preview.dart` | ÚJ | preview/polyphony |
| `lib/features/song_trainer/data/importers/song_importer.dart` | R10-ből | MIDI-specifikus nullable preview contract |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | R10-ből | tényleges production registry owner |
| `test/features/song_trainer/data/importers/midi_importer_test.dart` | ÚJ | format/timing fixture |
| `test/features/song_trainer/data/importers/midi_malformed_test.dart` | ÚJ | malformed/limit/cancel |
| `test/features/song_trainer/application/song_trainer_providers_test.dart` | R10-ből | production registry wiring |
| `test/fixtures/song_trainer/midi/format0.mid` | ÚJ | SMF0 |
| `test/fixtures/song_trainer/midi/format1_multitrack.mid` | ÚJ | SMF1 |
| `test/fixtures/song_trainer/midi/tempo_meter_marker.mid` | ÚJ | meta events |
| `test/fixtures/song_trainer/midi/running_velocity0.mid` | ÚJ | encoding edges |
| `test/fixtures/song_trainer/midi/polyphonic_drum.mid` | ÚJ | preview flags |
| `test/fixtures/song_trainer/midi/malformed_chunks.mid` | ÚJ | failure |
| `docs/rounds/e03-r12-midi-importer.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, RTM,
nem felsorolt `.github/**`, más feature belső fájlja és más kör briefje.
`docs/adr/**` csak akkor engedett, ha a pre-flight ütközésmentes exact pathként
hozzáadta a táblához. Új fixture/helper is fájl; listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. Raw PPQ timing megmarad; quantization csak explicit preview option és reversibilis.
2. Velocity-0 note-on note-off; dangling note warninggal lezárható a dokumentált boundaryn.
3. Channel 10/suspected drum nem default trainer track; polyphony csak warning/capability, nem hangválasztás.
4. Malformed/overflow/tempo-0 kontrollált failure vagy warning a stabil code policy szerint.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Format 0/1, több track, tempo/meter/key/marker/lyric/program és note duration snapshot stabil.
- [ ] Running status és velocity-0 helyes; dangling/overlap determinisztikus report.
- [ ] Extreme PPQ, invalid chunk/header/status, event- és MIDI track-count max+1, valamint cancel nem crash-el és nem commitol.
- [ ] Preview track/channel/instrument/note count/pitch range/polyphony/duration/drum adatot ad.
- [ ] Timing nincs implicit nyolcadokra quantizálva; monophonic track felismerhető.

### Kötelező megkülönböztető mátrix

| Eset | Várt |
|---|---|
| format 0 / 1 | accept / accept |
| SMPTE division | documented unsupported warning/failure |
| PPQ min / normál / extrém valid | pontos rational mapping |
| note-on velocity 0 | note-off |
| dangling note EOF-nál | warning + bounded duration policy |
| event count max−1/max/max+1 | accept/accept/reject |
| MIDI track count max−1/max/max+1 | accept/accept/reject (`ImportLimitFailureCode.midiTrackCountExceeded`) |
| cancel trackek között | cancelled, 0 commit |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/data/importers/midi_importer_test.dart test/features/song_trainer/data/importers/midi_malformed_test.dart
```

A brief pre-flightja a feltételes szöveget egyetlen futtatható
`tools/round-gate.sh ...` parancsra cseréli, ha a kör döntési ágas. A gate
format → analyze → célzott test → architecture külön processzekben fut; nincs
`&&`, pipe, `tail` vagy csonkítás. Full suite + property + APK CI-t az
orchestrátor indít exact `headSha`-ra.

## 8. Implementációs sorrend

1. Auditáld a dependencyt és készíts minimális jogtiszta MIDI fixtureket.
2. Írd meg a normal és malformed RED teszteket.
3. Implementáld a parser boundaryt, PPQ mappert és note pairinget.
4. Implementáld a previewt és registry bekötést.
5. Futtasd a gate-et, raw timing snapshotot külön review-zd.

Javasolt commit: `feat(song-import): add Standard MIDI song import`.

## 9. Kockázatok

- Binary fixture kézi hibája a parser helyett a tesztet tesztelheti; független dump/reference szükséges.
- Tick overflow vagy rendezetlenség CPU/memória DoS-t okozhat.

**STOP:** listán kívüli javítás, bizonyítatlan fallback vagy gyengített mérce
helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

### Implementáció (2026-08-03)

- `midi_parser_adapter.dart`: saját, pure-Dart SMF 0/1 + PPQ byte-decoder;
  header/chunk, VLQ, channel running status, SysEx és a használt meta-eventek
  kontrollált typed failurerel térnek vissza. SMPTE explicit unsupported.
- `midi_importer.dart`, `midi_timeline_mapper.dart`, `midi_track_preview.dart`:
  note-on/off párosítás (velocity-0 = off), tempóalapú duration, metadata,
  marker és lyric mapping, track preview/program/channel/drum/polyphony és
  bounded dangling-note warning. A parser csomag nélküli maradt.
- `song_importer.dart` és `song_trainer_providers.dart`: a MIDI-specifikus
  nullable preview mezők és a production `MidiImporter` registry-wiring.
- A hat binary fixture lefedi a format 0/1, meta-, running-status, drum- és
  malformed eseteket; a két új importer teszt és provider teszt a szerződést
  méri.

### Ellenőrzés

- RED: `flutter test test/features/song_trainer/data/importers/midi_importer_test.dart test/features/song_trainer/data/importers/midi_malformed_test.dart test/features/song_trainer/application/song_trainer_providers_test.dart`
  a hiányzó `MidiImporter` importtal elvárt compilation failuret adott.
- GREEN: ugyanez a három tesztfájl 8 teszttel zöld.
- `flutter analyze` — `No issues found!`.
- `tools/round-gate.sh test/features/song_trainer/data/importers/midi_importer_test.dart test/features/song_trainer/data/importers/midi_malformed_test.dart`
  — format, analyze, mindkét célzott teszt és architecture zöld.

Nem futott: teljes Flutter suite, random property gate és APK CI; ezeket az
orchestrátor indítja. Commit, push, PR és router-signal nem történt.

### Review-javítás (2026-08-03)

- A review F1–F4 leleteit az engedélyezett shared limit ownerrel együtt
  javította a router: format 0 pontosan egy MTrk-t követel, az azonos pitchű
  átfedések megőrződnek és warningot adnak, a meter/key változások teljes
  timeline-ja megmarad, a MIDI track budget pedig `ImportLimits`-ben,
  track-parse előtt érvényesül.
- A router célzottan mindkét MIDI tesztfájlt lefuttatta: 7, illetve 6 teszt
  zöld; `git diff --check` zöld. A teljes round-gate, a független review és a
  CI evidence az orchestrátor következő lépése.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r12-midi-importer-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
