# E03-R04 — Trackek, események és monophonic elemzés

- **Státusz:** **PLANNING** (2026-08-02, pre-flight baseline: `main` @ `00e273a`, tervezési baseline: `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 4; §11.1–11.7
- **Branch:** `codex/e03-r04-tracks-events-monophonic-analysis`
- **Előfeltétel:** E03-R03 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/song_trainer/domain/models/song_track.dart",
  "lib/features/song_trainer/domain/models/song_event.dart",
  "lib/features/song_trainer/domain/models/song_instrument.dart",
  "lib/features/song_trainer/domain/models/song_note_technique.dart",
  "lib/features/song_trainer/domain/models/backing_audio_track.dart",
  "lib/features/song_trainer/domain/models/song_document.dart",
  "lib/features/song_trainer/domain/services/note_track_analyzer.dart",
  "lib/features/song_trainer/data/local/song_document_codec.dart",
  "lib/features/song_trainer/domain/public.dart",
  "test/features/song_trainer/domain/song_track_codec_test.dart",
  "test/features/song_trainer/domain/note_track_analyzer_test.dart",
  "docs/rounds/e03-r04-tracks-events-monophonic-analysis.md",
]
gate_tests = [
  "test/features/song_trainer/domain/song_track_codec_test.dart",
  "test/features/song_trainer/domain/note_track_analyzer_test.dart",
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

- R03 után a document idő- és measure-szerkezete kész, de track/event listája nem hordoz tartalmat.
- Core chord/strum/tuning value objectek csak auditált core importtal használhatók.
- Backing platform path helyett kizárólag asset reference-t kaphat.

A pre-flight az itt leírt tényeket újraméri. Ha bármelyik eltér, ebben a
szekcióban rögzíti a mért állapotot, a választott feloldást és annak indokát.
Üres vagy implicit revízióval a státusz nem válhat `PLANNING`-re.

**Pre-flight mérés (2026-08-02, orchestrátor: Claude Sonnet 5, baseline
`main` @ `00e273a`, 51 commit-tal a brief eredeti `eeb4f6d` tervezési
baseline-ja után — E03-R02, E03-R03 és több self-heal kör; a kör-tartalmi
állítások alább mind érvényben maradtak):**

1. **Track/event tartalom hiánya — MEGERŐSÍTVE.**
   `lib/features/song_trainer/domain/models/song_document.dart` ma
   `sections`/`measures`/`tempoMap`/`meterMap`/`keyMap` mezőket hordoz
   (R03), de nincs `tracks`/`events` mező — a brief állítása pontos.
   `SongTrackId` és `SongEventId` már deklarált (R02,
   `song_id.dart:95-103`, kifejezetten „declared ahead of the track/event
   model (E03-R04)" kommenttel) — az `allowed_paths` listán szereplő új
   fájlok ezekre építhetnek módosítás nélkül.
2. **Core chord/strum/tuning auditált import — MEGERŐSÍTVE, egy ponton
   PONTOSÍTVA.** `test/features/song_trainer/domain/song_document_test.dart`
   `_forbiddenPatterns` scannere nem tiltja a `core/` importot (csak
   Flutter/Riverpod/Dio/SharedPreferences/l10n/felsorolt feature-öket) —
   `core/music/chord.dart` és `core/music/tuning.dart` már ma használatban
   van (`song_metadata.dart` `defaultTuning`, `song_document_codec.dart`).
   **Pontosítás:** `core/music/strum.dart` `StrumDirection` enumja csak
   `down`/`up` értéket hordoz, az SDD §11.3 viszont egy harmadik `unknown`
   állapotot is előír a `SongStrumEvent.direction`-höz, és a fájl NINCS az
   `allowed_paths` listán (bővítése tilos zóna, H3). Feloldás: [ADR
   0113](../adr/0113-song-track-event-model.md) — `SongStrumEvent.direction`
   típusa `StrumDirection?` (nullable core enum), `null` = `unknown`, nincs
   szükség core-fájl módosításra vagy párhuzamos enumra.
3. **Backing asset reference — MEGERŐSÍTVE.**
   `SongAssetReference` (R02) tipizált `SongAssetId`-t, SHA-256-ot,
   kiterjesztést és byte-hosszt tárol, platform path mezőt nem — az SDD
   §11.7 `BackingAudioTrack.assetId: SongAssetId` mintája közvetlenül erre
   épül, nincs ütközés.
4. **§9 kockázat 1 (tuning duplikáció) — feloldva.** Az egyetlen canonical
   tuning contract a core `Tuning`/`Tunings`; a bevezetendő
   `SongInstrument` ezt hordozza opcionális mezőként, nem definiál
   saját típust. Részletek: [ADR 0113](../adr/0113-song-track-event-model.md)
   Döntés 2.
5. **§9 kockázat 2 (ismeretlen sealed subtype) — feloldva.** A codec a
   már ma is használt fail-loud mintát követi (analóg
   `SongDocumentCodecErrorCode.sourceTypeUnknown`-nal): ismeretlen
   track/event altípus dekódoláskor stabil kóddal dobó kivétel, nem néma
   eldobás vagy alapértelmezett fallback. Részletek: [ADR
   0113](../adr/0113-song-track-event-model.md) Döntés 4.
6. **Chord symbol típus.** `SongChordEvent.symbol` a core `Chord`
   (validálatlan label-wrapper) típusát viseli — [ADR
   0113](../adr/0113-song-track-event-model.md) Döntés 1; a §11.2
   „unsupported chord megőrzi az eredeti display textet" a különálló
   `displayText` mezőn keresztül teljesül, nem a `Chord` validációján.
7. **Fájllista és scope — drift nélkül.** A §4 engedélyezett fájllista
   minden útvonala vagy ÚJ (nem létezik még), vagy a brief szerinti
   korábbi körből származik (`song_document.dart`, `song_document_codec.dart`,
   `public.dart` — mindhárom megerősítve létező, a leírt állapotban). Nincs
   listán kívüli szimbólum- vagy útvonal-igény.

Drift a fenti 6 tervezési tényállításban (§0.0 eredeti 3 sora + §9 2
kockázata) nem merült fel a track/event tartalmi kérdésekben; az egyetlen
mért eltérés (`StrumDirection` enum hiányzó `unknown` értéke) ADR 0113-mal
feloldva, fájllista-bővítés nélkül. A brief §3–§8 változatlanul érvényes.

## 1. Cél

A chord, strum, note, lyric, marker és backing tartalom immutable, verziózható domainmodellje és determinisztikus monophonic alkalmassági elemzője.

## 2. Jelenlegi állapot

- R03 után a document idő- és measure-szerkezete kész, de track/event listája nem hordoz tartalmat.
- Core chord/strum/tuning value objectek csak auditált core importtal használhatók.
- Backing platform path helyett kizárólag asset reference-t kaphat.

## 3. Scope

**Benne:**

- sealed SongTrack és event hierarchia
- instrument/tuning/technique/display versus scoring metadata
- NoteTrackAnalyzer overlap/tie/monophonic report
- codec és stable event ordering

**Kívül — ebben a körben TILOS:**

- normalizer által végzett tied-note merge
- capability resolver és scorer
- audio lejátszás, parser és UI

## 4. Engedélyezett fájlok

| Útvonal | Állapot a kör elején | Miért |
|---|---|---|
| `lib/features/song_trainer/domain/models/song_track.dart` | ÚJ | track hierarchia |
| `lib/features/song_trainer/domain/models/song_event.dart` | ÚJ | event hierarchia |
| `lib/features/song_trainer/domain/models/song_instrument.dart` | ÚJ | instrument value object |
| `lib/features/song_trainer/domain/models/song_note_technique.dart` | ÚJ | extensible technique |
| `lib/features/song_trainer/domain/models/backing_audio_track.dart` | ÚJ | asset-alapú backing |
| `lib/features/song_trainer/domain/models/song_document.dart` | R03-ból | track-lista bekötése |
| `lib/features/song_trainer/domain/services/note_track_analyzer.dart` | ÚJ | monophonic report |
| `lib/features/song_trainer/data/local/song_document_codec.dart` | R02-ből | track/event codec |
| `lib/features/song_trainer/domain/public.dart` | R03-ból | exportok |
| `test/features/song_trainer/domain/song_track_codec_test.dart` | ÚJ | minden subtype round-trip |
| `test/features/song_trainer/domain/note_track_analyzer_test.dart` | ÚJ | overlap/tie mátrix |
| `docs/rounds/e03-r04-tracks-events-monophonic-analysis.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, az RTM,
`.github/**`, nem felsorolt `lib/features/**`, más kör briefje és
`docs/adr/**`. ADR-fájl csak akkor kivétel, ha a pre-flight ütközésmentes
exact pathként hozzáadta ehhez a táblához, még a `PLANNING` commit előtt.
Új tesztfixture vagy helper is fájl: ha nincs tételesen a táblában, `stopped`.

## 5. Kötött architekturális döntések

1. Event canonical sorrend: start, track, stable ID; input collection nem mutálható.
2. Unsupported technique raw/display adatként megmarad, de nem bizonyít scoring capabilityt.
3. Lyric nem scoring capability; backing csak SongAssetId-t, nem platform pathot tárol.
4. Polyphonic overlap esetén az analyzer nem választ önkényesen egy hangot.

E döntések enyhítése nem elfogadható „zöldre javítás”. Valódi ellentmondásnál
brief-revízió vagy ADR szükséges.

## 6. Acceptance criteria

- [ ] Minden track/event subtype determinisztikusan round-tripel és immutable.
- [ ] Pitch/string/fret invalid érték stabil validation failure; unknown direction és technique adatvesztés nélkül megmarad.
- [ ] Az analyzer azonos inputra azonos reportot ad, tie és valódi overlap elkülönül.
- [ ] A document teljes tracklistát tárol platform- és parserfüggés nélkül.

### Kötelező megkülönböztető mátrix

| Note-helyzet | Várt report |
|---|---|
| egymás után, gap-pel | monophonic |
| end == next start | monophonic boundary |
| end > next start | polyphonic overlap |
| azonos pitch tie | merge-candidate, nem önkényes merge |
| eltérő pitch tie flag | warning/invalid a kötött policy szerint |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással tesz pirossá; bemásolt zöld kimenet önmagában nem evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/domain/song_track_codec_test.dart test/features/song_trainer/domain/note_track_analyzer_test.dart
```

Ez az egyetlen lokális záró gate; külön processzben futó format → analyze →
célzott testek → architecture lépéseit nem szabad `&&`-del, pipe-pal,
`tail`-lel vagy csonkítással helyettesíteni. A full suite + randomizált
property + APK CI-t az orchestrátor indítja, és exact branch `headSha`-t
ellenőriz.

## 8. Implementációs sorrend

1. Írd meg minden subtype codec RED tesztjét.
2. Írd meg az overlap/tie határmátrixot és futtasd RED-ként.
3. Implementáld a modelleket és codec-bővítést.
4. Implementáld az analyzert tiszta service-ként.
5. Futtasd a gate-et és import-audittal igazold a domain tisztaságát.

Javasolt körcommit: `feat(song-domain): add structured tracks events and note analysis`.

## 9. Kockázatok

- Core és Song Trainer tuning típus duplikálódhat; pre-flightban egyetlen canonical public contractot válassz.
- Sealed codec unknown subtype kezelése forward-compatibility döntést igényel; néma eldobás tilos.

**STOP:** ha a kockázat csak listán kívüli módosítással, bizonyítatlan fallbackkel
vagy acceptance-gyengítéssel oldható fel, állj meg és kérj brief-revíziót.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult el; ezért nincs implementációs vagy tesztsiker-állítás.
A handoffba a végrehajtáskor fájlonkénti összefoglaló, tényleges parancs és
csonkítatlan eredmény, terveltérés, nem futtatott ellenőrzés és follow-up kerül.
Minden viselkedési állítást konkrét teszt vagy mérés bizonyít.

## 11. Review — a független reviewer tölti ki

Tervezett review-fájl:
`docs/reviews/e03-r04-tracks-events-monophonic-analysis-review.md`.

Merge csak akkor engedett, ha az exact-SHA CI zöld, a diff a §4 listáján belül
marad, és nincs OPEN BLOCKER vagy MAJOR.
