# E03-R12 — Standard MIDI importer

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 12; §16
- **Branch:** `codex/e03-r12-midi-importer`
- **Előfeltétel:** E03-R11 merge
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
- event limit és cancellation

**Kívül — ebben a körben TILOS:**

- chord inference
- raw start nyolcadokra felülírása
- SMPTE trainer support
- MIDI playback vagy editor

## 4. Engedélyezett fájlok

| Útvonal | Állapot/ág | Miért |
|---|---|---|
| `pubspec.yaml` | meglévő | szükség esetén auditált MIDI dependency |
| `pubspec.lock` | meglévő | lock |
| `lib/features/song_trainer/data/importers/midi_importer.dart` | ÚJ | probe/import |
| `lib/features/song_trainer/data/importers/midi_parser_adapter.dart` | ÚJ | package/binary boundary |
| `lib/features/song_trainer/data/importers/midi_timeline_mapper.dart` | ÚJ | PPQ→beat |
| `lib/features/song_trainer/data/importers/midi_track_preview.dart` | ÚJ | preview/polyphony |
| `lib/features/song_trainer/data/importers/importer_registry.dart` | R11-ből | registration |
| `test/features/song_trainer/data/importers/midi_importer_test.dart` | ÚJ | format/timing fixture |
| `test/features/song_trainer/data/importers/midi_malformed_test.dart` | ÚJ | malformed/limit/cancel |
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
- [ ] Extreme PPQ, invalid chunk/header/status, event max+1 és cancel nem crash-el és nem commitol.
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

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r12-midi-importer-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
