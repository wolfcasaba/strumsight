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

A kör még nem indult el; ezért nincs implementációs vagy tesztsiker-állítás.
A handoffba a végrehajtáskor fájlonkénti összefoglaló, tényleges parancs és
csonkítatlan eredmény, terveltérés, nem futtatott ellenőrzés és follow-up kerül.
Minden viselkedési állítást konkrét teszt vagy mérés bizonyít.

## 11. Review — a független reviewer tölti ki

Tervezett review-fájl:
`docs/reviews/e03-r02-song-document-identity-metadata-review.md`.

Merge csak akkor engedett, ha az exact-SHA CI zöld, a diff a §4 listáján belül
marad, és nincs OPEN BLOCKER vagy MAJOR.
