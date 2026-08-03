# E03-R12 — Review

Brief: `docs/rounds/e03-r12-midi-importer.md`  
Diff: `git diff origin/main...codex/e03-r12-midi-importer`  
Reviewer: Codex / Terra  
Dátum: 2026-08-03  
Verdikt: **CHANGES REQUIRED**

## Összegzés

**BLOCKER: 0 · MAJOR: 4 · MINOR: 0 · NOTE: 0**

Az adapter saját célzott gate-je zöld, de három eldobható, független
invariáns-próba megmutatta, hogy az SMF format-validáció, a note-pairing és a
meta-map teljesítése nem felel meg a brief/SDD szerződésnek. A negyedik lelet
egy H3 scope-ütközés: az ADR 0091 által megkövetelt MIDI track-count policy
owner nincs az R12 allowlisten, ezért ezen a körön nem adható ki jogszerű
javító prompt.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Format 0/1, meta és note snapshot | ❌ | F1, F3 |
| 2 | Running status, velocity-0, dangling/overlap determinisztikus | ❌ | F2 |
| 3 | Malformed, limit, cancel kontrollált | ❌ | F4: MIDI track countnak nincs közös konfigurálható policy-je |
| 4 | Preview MIDI-adatok | ✅ | `midi_importer_test.dart`, `midi_track_preview.dart` |
| 5 | Raw timing, monophonic felismerés | részben | meglevő teszt zöld, de F2 miatt a bemeneti note-sor nem mindig őrződik meg |

## Scope-audit

Az implementációs diff az elfogadott, 2026-08-03-as pre-flight `allowed_paths`
listáján belül van. Ez a review-jelentés a kötelező független review artefaktum.

## Megállapítások

### F1 — MAJOR — Format 0 több MTrk chunkkal is elfogadható

- **Fájl:** `lib/features/song_trainer/data/importers/midi_parser_adapter.dart:38–43`
- **Probléma:** a decoder csak `format > 1` és `count == 0` esetén hibázik;
  a Standard MIDI File format 0 kötött, pontosan egy trackes formátum, de két
  `MTrk` chunkot sikeresen parse-ol.
- **Hatás:** hibás header/format kombináció kap `SongDocument`-et ahelyett,
  hogy kontrollált failure lenne.
- **Bizonyíték:** a review ideiglenes `review_midi_invariants_test.dart`
  formátum-0 + két EOT track próbája a várt
  `songImport.midi.unsupportedFormat` helyett sikeres parse-ot adott.
- **Kötelező javítás:** format 0-nál `count == 1` validáció, és annak saját
  regressziós tesztje.
- **Státusz:** OPEN.

### F2 — MAJOR — Azonos pitchű átfedő note-on esemény felülírja az elsőt

- **Fájl:** `lib/features/song_trainer/data/importers/midi_importer.dart:115–122`
- **Probléma:** az aktív note-ok mapje egyetlen
  `channel-pitch` kulcsot használ. Egy második, még nyitott azonos pitchű
  note-on felülírja az elsőt; a két note-offból végül csak egy `SongNoteEvent`
  keletkezik, warning nélkül.
- **Hatás:** valós MIDI performance-adat némán elvész, a preview noteCount és
  monophony eredmény hibás lehet.
- **Bizonyíték:** a review-ben két azonos, átfedő pitchű note-on + két note-off
  fixture a várt két event helyett egyet adott (`hasLength(2)` → tényleges 1).
- **Kötelező javítás:** kulcsonként determinisztikus aktív-note sor/stack és
  explicit overlap report, lefedve saját teszttel.
- **Státusz:** OPEN.

### F3 — MAJOR — Csak az első meter és key meta event kerül a dokumentumba

- **Fájl:** `lib/features/song_trainer/data/importers/midi_importer.dart:261–287`
- **Probléma:** `_meter` és `_key` `.firstOrNull`-t használ, majd egyetlen
  `MeterChange`/`KeyChange`-et épít. A későbbi meta események némán elvesznek.
- **Hatás:** tempo map változhat, de a meter/key timeline hamis marad; sérti
  a brief §6 és SDD Chapter 4 §16 "mapping" követelményét.
- **Bizonyíték:** a review egy 3/4→4/4, C→G, teljes ütemhatáron váltó SMF-je
  mindkét mapben várt két változás helyett egyet adott.
- **Kötelező javítás:** minden érvényes változást determinisztikusan map-pelj,
  és csak a domain által reprezentálhatatlan, nem measure-boundary meter
  váltást jelezd explicit warning/failureként; bővítsd a tesztet.
- **Státusz:** OPEN.

### F4 — MAJOR / H3 — A kötelező MIDI track-count limitnek nincs engedélyezett ownera

- **Fájl:** `lib/features/song_trainer/data/importers/import_limits.dart:15–34`
- **Probléma:** ADR 0091 §3 és SDD Chapter 4 §13.6 explicit MIDI track-count
  limitet ír elő. A közös `ImportLimits` csak source/event/workspace/archive/
  wall-time mezőket ad; a decoder korlát nélkül a header `count` értékét
  követi. Az R12 allowlist ezt a shared policy fájlt nem engedi módosítani.
- **Hatás:** a szabályos javítás `maxMidiTrackCount` + stable failure code és
  parser/registry tesztet igényelne, ami jelen körben scope-sértés lenne.
- **Bizonyíték:** `ImportLimits` konstruktor és a parser track-loopja; a
  pre-flight mérés korábban csak event-policyt azonosított, a track-count
  kötelezettség ownerát nem fedte fel.
- **Kötelező javítás:** önjavító/pre-flight körben egészítsd ki az R12 brief
  engedélyezett fájljait az exact shared-policy ownerrel, majd állítsd be a
  konfigurálható, fail-closed track limitet és max−1/max/max+1 tesztet.
- **Státusz:** OPEN — **H3**.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Független ellenőrzés |
|---|---|---|
| format | zöld | a friss klónban zöld (`dart format --output=none --set-exit-if-changed lib test tool`) |
| analyze | zöld | zöld: `flutter analyze lib/ test/ tool/` |
| célzott tesztek | zöld | 4 + 5 teszt zöld a két megadott fájlban |
| architecture | zöld | zöld: `dart run tool/check_architecture.dart` → `Architecture dependencies OK (12 allowlisted deviation(s)).` |
| review invariáns-próba | nincs | 3/3 piros; a review ideiglenes tesztfájl merge előtt törlendő |
| CI (full suite + property + APK) | fut | Build Android APK 30821506436, exact head `833f0b7`, review idején queued/running |

## Merge-döntés

Az ADR 0052 alapján merge **tilos**: négy nyitott MAJOR lelet van, ebből F4
H3 scope-ütközés. A router `resume` javító kör nem indítható az exact
`ImportLimits` owner pre-flight feloldása nélkül.
