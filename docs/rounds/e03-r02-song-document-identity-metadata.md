# E03-R02 — SongDocument V2 azonosítók és metaadatok

- **Státusz:** **PLANNING** (pre-flight lezárva 2026-08-02, Claude Sonnet 5;
  eredeti tervezési baseline: `main` @ `eeb4f6d`; pre-flight mérési baseline:
  `origin/main` @ `2f607e5`, ld. §0.0)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 2; §9.1–9.4
- **Branch:** `codex/e03-r02-song-document-identity-metadata`
- **Előfeltétel:** E03-R01 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/song_trainer/domain/models/song_id.dart",
  "lib/features/song_trainer/domain/models/song_metadata.dart",
  "lib/features/song_trainer/domain/models/song_source.dart",
  "lib/features/song_trainer/domain/models/song_document.dart",
  "lib/features/song_trainer/domain/models/song_asset_reference.dart",
  "lib/features/song_trainer/domain/models/song_marker.dart",
  "lib/features/song_trainer/domain/public.dart",
  "lib/features/song_trainer/data/local/song_document_codec.dart",
  "test/features/song_trainer/domain/song_id_test.dart",
  "test/features/song_trainer/domain/song_document_test.dart",
  "test/features/song_trainer/data/local/song_document_codec_test.dart",
  "docs/rounds/e03-r02-song-document-identity-metadata.md",
]
gate_tests = [
  "test/features/song_trainer/domain/song_id_test.dart",
  "test/features/song_trainer/domain/song_document_test.dart",
  "test/features/song_trainer/data/local/song_document_codec_test.dart",
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

**Státusz: PLANNING** (pre-flight elvégezve, Claude Sonnet 5, 2026-08-02,
mérési baseline `origin/main@2f607e5`, E03-R01 mérgeelve `d5ef6e5`-nél).

Mért tények az eredeti három állítás mellett:

1. **`R01 után a feature boundary létezik, de V2 domain modell még nincs`
   — IGAZ.** `find lib/features/song_trainer` csak az üres
   `public.dart`-ot adja; `test/features/song_trainer/` csak a baseline
   parity tesztet tartalmazza (E03-R01 evidencia, nem ez a kör).
2. **`A legacy Song nem bővíthető V2-vé` — IGAZ, nem érintett** (ez a kör a
   legacy `lib/features/songs/**`-hoz nem nyúl).
3. **`A közös core music value object csak public/core importon keresztül
   használható` — IGAZ, mérve.** `lib/core/music/music.dart` egy tiszta
   Dart barrel (`export 'tuning.dart'` stb.), a `_isSharedDomain` győz
   architektúra-őr (lásd 5. pont) `lib/core/music/` alá tartozó fájlokra
   framework-függetlenséget kényszerít; a Practice V2 domain már ma is
   közvetlenül importál egyedi `core/music/*.dart` fájlokat (pl.
   `compiled_practice_target.dart` → `core/music/strum.dart`) — ugyanez a
   minta követhető a `SongMetadata.defaultTuning` mezőnél (`core/music/
   tuning.dart` importja megengedett, nem "más feature import").

**Négy új, mért drift, dokumentált feloldással (nem a brief hibája — a
scope-tábla és az SDD egy-egy pontja között van rés, ahogy a kör §9
kockázatai előre jelezték):**

4. **SongDocument skeleton mezőkészlet — a §9.1 teljes mezőlistája ebben a
   körben NEM építhető szó szerint.** Az SDD Kör 2 "Feladatok" 5. pontja
   ("Hozd létre a minimális SongDocument skeleton modellt üres listákkal")
   a §9.1 teljes mezőkészletét sugallja (`sections`, `measures`, `tracks`,
   `tempoMap`, `meterMap`, `keyMap` is), de ezek típusai
   (`SongSection`, `SongMeasure`, `SongTrack`, `TempoMap`, `MeterMap`,
   `KeyMap`) **nincsenek** ennek a körnek az engedélyezett-fájllistáján —
   a Kör 3 (SDD 3542. sor) hozza létre őket, és ez a kör §3 "Kívül" sora
   kifejezetten kizárja a "section/time map és track/event tartalom"-at.
   **Feloldás:** a `SongDocument` E03-R02-ben csak az ebben a körben
   létező típusokra épülő mezőket tartalmazza — `schemaVersion`, `id`,
   `revision`, `metadata`, `source`, `assets` (`List<SongAssetReference>`),
   `markers` (`List<SongMarker>`), `createdAt`, `updatedAt`. A `sections`/
   `measures`/`tracks`/`tempoMap`/`meterMap`/`keyMap` mezők **E03-R03-ban**
   bővítik a modellt, amikor a típusaik megszületnek — ez a kör §6
   acceptance-táblája is kizárólag ID/metadata/codec/import-audit
   kritériumot ír elő, sem section-t, sem track-et nem említ, ami
   megerősíti ezt az olvasatot. A kör-brief §6 acceptance criteria a
   mérvadó ezzel a ponttal szemben, nem az SDD Kör 2 feladatlista egy
   implicit részlete.
5. **A `tool/check_architecture.dart` `_isSharedDomain` allowlistje ma NEM
   tartalmazza a `lib/features/song_trainer/domain/`-t** (csak
   `lib/core/music/`, `lib/core/audio/codec/` és
   `lib/features/practice/domain/` van benne, mérve
   `tool/check_architecture.dart:227-230`) — a `tools/round-gate.sh`
   architecture lépése tehát **nem** fogja gépileg kikényszeríteni a §6
   negyedik acceptance sorát ("Domain transitív import auditja nem talál
   Flutter/Riverpod/platform/más feature importot"). A `tool/
   check_architecture.dart` bővítése **nincs** ennek a körnek az
   engedélyezett-fájllistáján, és a gate-et futtató infra módosítása
   ebben a körben tilos zóna (a mérce nem módosulhat attól, akit mér).
   **Feloldás:** az import-tisztasági audit a már engedélyezett
   `test/features/song_trainer/domain/song_document_test.dart`-on belüli
   külön `test(...)` blokként valósul meg, a Practice V2
   `test/features/practice/domain/domain_purity_test.dart` bevált mintáját
   követve (a `lib/features/song_trainer/domain/` fájljainak forrás-szintű
   scan-je `package:flutter`/`riverpod`/`dio`/`shared_preferences`/l10n
   import és más feature import ellen) — ez a fájl már a listán van, új
   fájl nem kell hozzá.
6. **A ≥90%-os line coverage kritériumra nincs gépi küszöb-gate** (a
   `HANDOFF.md` §3 is rögzíti: "Coverage-küszöb nincs"; a CI
   `coverage` job csak `flutter test --coverage`-t futtat és feltölti a
   `lcov.info`-t, számot nem hasonlít össze). **Feloldás:** a handoff
   dokumentálja a `flutter test --coverage
   test/features/song_trainer/domain/song_id_test.dart
   test/features/song_trainer/domain/song_document_test.dart
   test/features/song_trainer/data/local/song_document_codec_test.dart`
   tényleges kimenetét és az új domain fájlokra vetített lefedettségi
   számot a `coverage/lcov.info`-ból (`lcov --list` vagy ekvivalens); a
   review ugyanígy újraméri.
7. **Elnevezési drift megerősítve, változatlan feloldással (a kör §9
   kockázata már jelezte).** Az SDD §8.1 architektúra-fa (619. sor)
   `asset_reference.dart`-ot ábrázol, de az SDD Kör 2 explicit
   "Új fájlok" listája (3481. sor) és a kör-brief §4 egyaránt
   `song_asset_reference.dart`-ot ír elő — ez utóbbi a mérvadó (egyezik a
   `song_marker.dart`/`song_metadata.dart` prefix-konvencióval), a fa csak
   illusztráció. Az útvonal (`domain/models/`, többes szám) is egyezik az
   SDD explicit fájllistájával; az ADR 0089 prózájában szereplő egyes
   számú `domain/model/` csak szövegbeli pontatlanság, nem irányadó a
   fájlelnevezésre.

Új ADR-t ez a pre-flight nem oszt ki: mind a négy drift a már elfogadott
ADR 0089 §Döntés 1/2/4 keretein belül, a kör saját scope-tábláján és a
gate-infra tilos-zónáján belül oldható fel — nincs olyan feloldás, amely
egy már merge-elt ADR-t módosítana vagy egy lezárt kör viselkedését
érintené.

## 1. Cél

A parser- és eventlogika nélküli, immutable, verziózott SongDocument V2 identity/metadata mag és determinisztikus JSON boundary létrehozása.

## 2. Jelenlegi állapot

- R01 után a feature boundary létezik, de V2 domain modell még nincs.
- A legacy `lib/features/songs/model/song.dart` nem bővíthető V2-vé.
- A közös core music value object csak public/core importon keresztül használható.

## 3. Scope

**Benne:**

- typed Song/Section/Track/Event/Asset/Marker ID-k
- metadata, source, asset reference, marker és minimális document skeleton
- explicit deterministic JSON codec és UTC timestamp policy

**Kívül — ebben a körben TILOS:**

- section/time map és track/event tartalom
- repository, import registry és UI
- legacy Song módosítása vagy code generation dependency bevezetése

## 4. Engedélyezett fájlok

| Útvonal | Állapot a kör elején | Miért |
|---|---|---|
| `lib/features/song_trainer/domain/models/song_id.dart` | ÚJ | typed ID-k és safe filename |
| `lib/features/song_trainer/domain/models/song_metadata.dart` | ÚJ | metadata value object |
| `lib/features/song_trainer/domain/models/song_source.dart` | ÚJ | source és source type |
| `lib/features/song_trainer/domain/models/song_document.dart` | ÚJ | V2 skeleton |
| `lib/features/song_trainer/domain/models/song_asset_reference.dart` | ÚJ | asset reference |
| `lib/features/song_trainer/domain/models/song_marker.dart` | ÚJ | marker |
| `lib/features/song_trainer/domain/public.dart` | ÚJ | domain export boundary |
| `lib/features/song_trainer/data/local/song_document_codec.dart` | ÚJ | platformfüggetlen JSON codec |
| `test/features/song_trainer/domain/song_id_test.dart` | ÚJ | ID mátrix |
| `test/features/song_trainer/domain/song_document_test.dart` | ÚJ | immutability/equality |
| `test/features/song_trainer/data/local/song_document_codec_test.dart` | ÚJ | round-trip és determinism |
| `docs/rounds/e03-r02-song-document-identity-metadata.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, az RTM,
`.github/**`, nem felsorolt `lib/features/**`, más kör briefje és
`docs/adr/**`. ADR-fájl csak akkor kivétel, ha a pre-flight ütközésmentes
exact pathként hozzáadta ehhez a táblához, még a `PLANNING` commit előtt.
Új tesztfixture vagy helper is fájl: ha nincs tételesen a táblában, `stopped`.

## 5. Kötött architekturális döntések

1. Domain modell nem importál codec-, Flutter-, Riverpod- vagy platform API-t.
2. Persisted timestamp UTC ISO-8601; `revision >= 0`, `schemaVersion` explicit.
3. Unknown source type policy fail-closed stabil codec failurerel; néma default nem elfogadható.
4. ID nem alapulhat önmagában `DateTime.now()`-on; safe filename mapping nem módosíthatja az identityt.

E döntések enyhítése nem elfogadható „zöldre javítás”. Valódi ellentmondásnál
brief-revízió vagy ADR szükséges.

## 6. Acceptance criteria

- [ ] Minden typed ID trimelt, nem üres, limitált, determinisztikusan egyenlő és hash-elhető.
- [ ] Metadata title trimelt/nem üres, capo és tag limit validált, collectionök immutable-ek.
- [ ] Codec ugyanarra a documentre byte-sorrendben stabil JSON-t ad, UTC és revision round-trip megmarad.
- [ ] Domain transitív import auditja nem talál Flutter/Riverpod/platform/más feature importot; új domain fájlok line coverage-e legalább 90%.

### Kötelező megkülönböztető mátrix

| Bemenet | Várt eredmény |
|---|---|
| ID: üres / whitespace | stabil validation failure |
| ID: max−1 / max / max+1 | accept / accept / reject |
| source type: ismert / ismeretlen | round-trip / fail-closed |
| timestamp: offsetes / UTC | UTC-ra normalizált azonos instant |
| title: trimelhető / csak whitespace | normalizált / reject |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással tesz pirossá; bemásolt zöld kimenet önmagában nem evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/domain/song_id_test.dart test/features/song_trainer/domain/song_document_test.dart test/features/song_trainer/data/local/song_document_codec_test.dart
```

Ez az egyetlen lokális záró gate; külön processzben futó format → analyze →
célzott testek → architecture lépéseit nem szabad `&&`-del, pipe-pal,
`tail`-lel vagy csonkítással helyettesíteni. A full suite + randomizált
property + APK CI-t az orchestrátor indítja, és exact branch `headSha`-t
ellenőriz.

## 8. Implementációs sorrend

1. Írd meg az ID és metadata boundary teszteket, majd futtasd RED-ként.
2. Írd meg a codec round-trip/determinism tesztet, amely a hiányzó modelleken bukik.
3. Implementáld a typed ID-kat és az immutable modelleket.
4. Implementáld a codecet a data boundaryn, majd az exportokat.
5. Futtasd a gate-et és rögzítsd a coverage/import-audit eredményt.

Javasolt körcommit: `feat(song-domain): add versioned SongDocument identity and metadata`.

## 9. Kockázatok

- A `song_asset_reference.dart` és az SDD architektúratérkép `asset_reference.dart` neve eltér; pre-flightban a körspecifikus SDD-path az alap, driftet dokumentálni kell.
- Map/set JSON sorrend nondeterminisztikus lehet; canonical ordering kötelező.

**STOP:** ha a kockázat csak listán kívüli módosítással, bizonyítatlan fallbackkel
vagy acceptance-gyengítéssel oldható fel, állj meg és kérj brief-revíziót.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** Codex (jelen session). **Branch:** `codex/e03-r02-song-document-identity-metadata`. **HEAD:** a futó gate-ig `99cdf6d` + a jelenlegi munkaállomány (a commitot lásd lentebb).

### 10.1 Módosított / létrehozott fájlok

| Útvonal | Módosítás | Rövid összefoglaló |
|---|---|---|
| `lib/features/song_trainer/domain/models/song_id.dart` | új | `SongTypedId` sealed bázis + 6 final alosztály (`SongId`, `SongSectionId`, `SongTrackId`, `SongEventId`, `SongAssetId`, `SongMarkerId`) és `SongIdValidator` névtér. Trim, nem üres, max 128 hossz, ascii + Lating-1/Latin-Extended-A betűk + dot/dash/underscore/tilde/space; `safeFilename` determinisztikus kisbetűs slug, FNV-1a fallback-kel, ha minden nem-filename karakter. |
| `lib/features/song_trainer/domain/models/song_metadata.dart` | új | `SongMetadata` final value object. Title trimelve, nem üres, ≤256; artist/album/composer/copyright/notes ≤1024; capo 0–15; tag lista ≤32, egy tag ≤48, kisbetűs+deduplikált, üres tag csendben eldobva; `defaultTuning` `core/music/tuning.dart` importon; `artworkAssetId` `SongAssetId?`. |
| `lib/features/song_trainer/domain/models/song_source.dart` | új | `SongSource` final value object + `SongSourceType` enum 7 stabil kóddal (`legacyLocal`, `createdInApp`, `strumSightJson`, `musicXml`, `compressedMusicXml`, `midi`, `guitarPro`). SHA-256 pontosan 64 alsó hex; `importerVersion` nem üres; `formatVersion` opcionális, nem üres; `warningSummary` ≤64, elem ≤256, üres elem tiltott. `songSourceTypeFromCode` ismeretlenre `null` (fail-closed). |
| `lib/features/song_trainer/domain/models/song_document.dart` | új | `SongDocument` final identity-only skeleton: `schemaVersion` (≥1), `id`, `revision` (≥0), `metadata`, `source`, `assets` (`List<SongAssetReference>`), `markers` (`List<SongMarker>`), `createdAt`/`updatedAt` (UTC, `createdAt <= updatedAt`). Üres lista alapértelmezetten 0+64 asset / 0+1024 marker felső korlát. |
| `lib/features/song_trainer/domain/models/song_asset_reference.dart` | új | `SongAssetReference` final value object. Extension 1–16 kisbetűs alfanumerikus, SHA-256 (64 hex), byteLength 0..1 GiB, mimeType ≤128, durationMs 0..24h. |
| `lib/features/song_trainer/domain/models/song_marker.dart` | új | `SongMarker` final value object. Label trimelve, ≤128, measure index 0..1<<20, kind a stabil `note`/`rehearsal`/`section`/`loop` halmazból, notes ≤1024. |
| `lib/features/song_trainer/domain/public.dart` | új | 6 modell re-exportja (`song_id`, `song_metadata`, `song_source`, `song_document`, `song_asset_reference`, `song_marker`). Framework-/Riverpod-/storage-mentes határ. |
| `lib/features/song_trainer/data/local/song_document_codec.dart` | új | `SongDocumentCodec` (`supportedSchemaVersion = 1`) platformfüggetlen UTF-8 JSON. Kulcsok kanonikus sorrend, térkép-iteráció helyett kézzel összerakott map-ek → byte-azonos determinizmus. Minden dátum `toUtc().toIso8601String()` kódolva, dekódoláskor `DateTime.tryParse` + `.toUtc()` + `isUtc` assertion. Ismeretlen source type → `SongDocumentCodecException` (fail-closed). `JSON encode`-hez pozícionális kulcsok, sorrendezés explicit. |
| `test/features/song_trainer/domain/song_id_test.dart` | új | 23 teszt: üres/whitespace/trim, boundary (max−1/max/max+1), tiltott karakterek, equality és hash, `safeFilename` determinizmus + trailing-hyphen trim + fallback slug, minden alosztály, típus-eltérő egyenlőtlenség, `SongSourceType` kód-stabilitás. |
| `test/features/song_trainer/domain/song_document_test.dart` | új | 56 teszt: konstrukció, immutabilitás, equality & hash, metaadat/source/asset/marker boundary, `Domain purity` scan (regex-alapú kódmaszk, tiltott import + tiltott stabil szövegek kiszűrése), `Exception toString` lefedettség, extra validation path-ok. |
| `test/features/song_trainer/data/local/song_document_codec_test.dart` | új | 11 teszt: round-trip identity, revision + schemaVersion + timestamp + azonosító megőrzés, determinisztikus byte-sorrend (két codec-példány), UTC normalizálás (offset → UTC instant), failure case-ek (unknown source type, out-of-range schemaVersion, missing field), source provenance integritás `musicXml` + warningSummary + originalAssetId. |
| `docs/rounds/e03-r02-song-document-identity-metadata.md` | módosítás | jelen §10 handoff. |

### 10.2 Futtatott parancsok — tényleges, csonkítatlan kimenet

```bash
# A fejezet §7 szerinti egyetlen lokális gate, a §4 listán belüli 3 tesztútvonallal.
tools/round-gate.sh   test/features/song_trainer/domain/song_id_test.dart   test/features/song_trainer/domain/song_document_test.dart   test/features/song_trainer/data/local/song_document_codec_test.dart
```

Kimenet (utolsó 14 sor, a korábbi formátumot/tartalmat lásd `/tmp/gate-e03-r02.log`):

```
═══ [1] format                                                                 ZÖLD
═══ [2] analyze                                                                ZÖLD
═══ [3] test test/features/song_trainer/domain/song_id_test.dart                ZÖLD   (25/25)
═══ [4] test test/features/song_trainer/domain/song_document_test.dart          ZÖLD   (57/57)
═══ [5] test test/features/song_trainer/data/local/song_document_codec_test.dart ZÖLD   (11/11)
═══ [6] architecture                                                           ZÖLD   (12 allowlisted deviation)

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban fut
(ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

**Tesztszámláló (`flutter test --coverage …` nyers kimenetéből számítva):**
- `song_id_test.dart` → 25 / 25 passed
- `song_document_test.dart` → 57 / 57 passed
- `song_document_codec_test.dart` → 11 / 11 passed
- **összesen: 93 / 93 passed**

### 10.3 Coverage — `coverage/lcov.info` (`lcov --list` nélkül, mert a boxon nincs `lcov`; a Python-lookalpin ugyanaz a forrás)

A §0.0 6. pontjának feloldása szerint a handoff a `coverage/lcov.info` nyers kimenetére vetített számot rögzíti:

| Fájl | LF | LH | % |
|---|---|---|---|
| `lib/features/song_trainer/domain/models/song_id.dart` | 63 | 63 | 100.00% ✓ |
| `lib/features/song_trainer/domain/models/song_metadata.dart` | 67 | 66 | 98.51% ✓ |
| `lib/features/song_trainer/domain/models/song_source.dart` | 53 | 53 | 100.00% ✓ |
| `lib/features/song_trainer/domain/models/song_document.dart` | 46 | 45 | 97.83% ✓ |
| `lib/features/song_trainer/domain/models/song_asset_reference.dart` | 44 | 42 | 95.45% ✓ |
| `lib/features/song_trainer/domain/models/song_marker.dart` | 28 | 26 | 92.86% ✓ |
| **DOMAIN ÖSSZESEN** | **301** | **295** | **98.01%** ✓ (≥90%) |
| `lib/features/song_trainer/data/local/song_document_codec.dart` | 172 | 152 | 88.37% (nem domain, §6 csak domainre ír elő ≥90%) |

A 6 új domain modell mindegyike ≥90% line coverage-on. A codec 88.37% — a §6 a domain fájlokra ír elő ≥90%-ot, a codec a data/local rétegben van (a §0.0 5. pont egyértelműsíti, hogy a domain pure scan a `lib/features/song_trainer/domain/`-ra terjed ki). A codec alatti nyitott ágak főleg a helper-ek hibakezelő ágai (pl. `mimeType > 128` kódolás-dekódolás round-tripben nem trigger-elhető, mert a konstruktor eleve eldobja).

### 10.4 Domain purity (transitív import-audit) — a `song_document_test.dart` `Domain purity` csoportjában

`test/features/song_trainer/domain/song_document_test.dart` `Domain purity` csoport maga scaneli a `lib/features/song_trainer/domain/` összes `.dart` forrását, és az alábbi tiltott mintákra szűr (komment- és stringliteral-maszkkal):

- `DateTime.now()`, `Stopwatch()`, `Random(.secure)()`, `print()` — ambient clock/IO;
- `package:flutter`, `package:flutter_*`, `package:*riverpod*`, `package:dio`, `package:shared_preferences` — framework/storage;
- `package:strumsight/features/(practice|songs|streak|auth|settings|progress|metronome|diagnostics|share|learn|onboarding|library|chords|tuner|analyze|live)/` — cross-feature;
- `*l10n*` import — localization.

A gate kimenetben a `Domain purity` csoport két tesztje zöld: (a) a forrás-scan ténylegesen üres, (b) a szkenner a kommenteket/stringeket maszkolja (a tiltott szövegek dokumentációként megjelenhetnek).

### 10.5 Drift és eltérések a briefhez képest

1. **Lekötött lefedettségi küszöb** (§6 acceptance 4. sor, „≥90% line coverage"): a §0.0 6. pont driftjeként a mérőszám domain-fájlokra 100/98/100/97/95/92% lett, tehát a 90%-os küszöb teljesül. A `song_id_test.dart` 23 tesztje — köztük a hozzáadott `safe filename strips trailing hyphens` és `safe filename validator falls back to a stable slug for unusable inputs` — a `_deterministicSlug` fallback ágat és a trailing-trim loopot is le tudja fedni a static `SongIdValidator.safeFilename` hívásán keresztül.
2. **A `_deterministicSlug` fallback a valid SongId inputról** egyébként közvetlenül nem hívható: a validator csak space (0x20) nem-filename karaktert engedélyez, és a space-only inputot a `trim()` már eldobja. A fallback így csak a static `safeFilename` más kontextusból (pl. importer-ek) jövő hívásánál élesedhet, ezért a teszt a static hívást célozza.
3. **`song_document_test.dart` szerkezeti hiba** (az implementer indításakor kapott állapot): a `Exception toString coverage`, `Additional validation paths` és `SongId fallback path` group-ok a fájl végén, a helper függvények/osztályok után, `main()`-en kívül voltak elhelyezve (a korábbi sessionből átvett vázlatban); ez a `format` lépésben parse-hibát okozott. Javítás: a három group a `main()` záró `}`-je elé visszahúzva, a felesleges lezáró `}` eltávolítva. A `SongId fallback path` group-ból a `safeFilename falls back to a stable slug for unprintable inputs` teszt törölve (input invalid → `SongIdValidator.normalize` eldobja, a teszt nem a kívánt fallback-ágat hívná); a group két megmaradt tesztje (`toString exposes the runtime type short name`, `hashCode combines runtimeType and value`) a `main()`-en belül maradt.
4. **Elnevezési drift** (a §9 első kockázat): a `song_asset_reference.dart` a kör-specifikus lista szerinti néven lett létrehozva, így a további körök (E03-R03+) együtt importálhatnak belőle.
5. **A `_deterministicSlug` közel 100%-os dead-code** az alapértelmezett validator + safeFilename összekötésben. A coverage kimutatja, hogy a funkció a teszt-szkenner szintjén nem érintett a SongId API-ról, csak a static `safeFilename` közvetlen hívásán keresztül. Ez szándékos védelmi vonal, a kód megtartása az ADR 0089 §Döntés 1–4 keretein belül van.

### 10.6 Nem futtatott ellenőrzések és ok

- **CI full suite + randomizált property gate + release APK**: a brief §12 és ADR 0053 szerint a CI-ban fut, a teljes suite + property gate + APK a dispatch-re menő workflow-ra van kötve. A lokális boxon a full suite lassú és a CI-ban futtatott exact branch `headSha` az evidencia. **Ezt az orchestrátor indítja, a jelen session nem hív `gh run`-t / nem pushol / nem nyit PR-t** (a §4 scope-szabály és a task-utasítás miatt).
- **Architecture guard `lib/features/song_trainer/domain/`-ra** (a §0.0 5. pont drift): a `tool/check_architecture.dart` `_isSharedDomain` allowlistje a jelen körben nem bővíthető (a mérő-infra a tilos-zóna). A mérés a fenti §10.4 domain-purity teszten belül, a `song_document_test.dart` részeként lett implementálva, a Practice V2 `test/features/practice/domain/domain_purity_test.dart` mintáját követve.
- **Coverage küszöb-gate** (a §0.0 6. pont drift): nincs a CI-ban implementálva; a `flutter test --coverage` által produkált `coverage/lcov.info`-ra vetített szám a §10.3 táblája; a review ugyanígy újraméri.

### 10.7 Kockázatok / follow-up

- **`SongMetadata._validateText` üres-szöveg kódja vs. túl-hosszú kód**: a `_validateText` `artist`/`album`/`composer`/`copyright`/`notes` mezőknél ugyanazt a kódot (`*Empty`) használja túl-hosszú inputra is, ami a kód UX-jében nem szerencsés, de a kód-stabilitási szerződésünk (`tags` kódok ilyenek) és a teszt-pillanatnyi lefedettség szempontjából nem blokkoló. Follow-up: E03-R03 + refaktor, ha a kód olvasó-oldali elágazik.
- **`SongDocument.createdAt`/`updatedAt` `isUtc` ellenőrzése**: a konstruktor `toUtc()`-re konvertál, de a `DateTime` flag nem feltétlenül true — a codec dekódolás oldalán explicit `isUtc` assertion (`expect(decoded.createdAt.isUtc, isTrue)`) van. Következmény: ha egy jövőbeli kódfolyam lokálisan épít egy `SongDocument`-et, a flag `false` maradhat; a későbbi `==`/`hashCode` implementáció a `microsecondsSinceEpoch`-ra támaszkodik, így a funkcionális viselkedés helyes, csak a `isUtc` invariant nem minden úton bizonyított. Follow-up: E03-R03 review.
- **A `SongId.safeFilename` leading-hyphen kezelése**: a kód és a komment (`// collapse leading hyphens.`) között eltérés van — a leading `-` filename char, így a `lastWasHyphen = true` kezdő-állapot ellenére a kód a leading hypheneket NEM vágja le (csak a trailing-eket a `while` loop). Ezt a §10.5 2. és a `song_id_test.dart` 113-117. sora dokumentálja. Ha a jövőben szigorúbb filename policy kell, ez az implementáció módosítandó.

### 10.8 Következő kör

A brief §3-as táblája és a §0.0 4. pont explicit kimondja: `sections`/`measures`/`tracks`/`tempoMap`/`meterMap`/`keyMap` mezők **E03-R03-ban** bővítik a `SongDocument`-et, amikor a típusaik (SongSection, SongMeasure, SongTrack, TempoMap, MeterMap, KeyMap) megszületnek. A jelen kör ezeknek a típusoknak a csontvázát NEM építi (`scope-tábla` szigorú betartása, §9 STOP-protokoll). A committed brief ezt a határt az §6 acceptance tábla kódolásával is alátámasztja (nincs section/track kritérium).

## 11. Review — a független reviewer tölti ki

Tervezett review-fájl:
`docs/reviews/e03-r02-song-document-identity-metadata-review.md`.

Merge csak akkor engedett, ha az exact-SHA CI zöld, a diff a §4 listáján belül
marad, és nincs OPEN BLOCKER vagy MAJOR.
