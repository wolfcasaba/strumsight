# E03-R02 — SongDocument V2 azonosítók és metaadatok

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
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

- R01 után a feature boundary létezik, de V2 domain modell még nincs.
- A legacy `lib/features/songs/model/song.dart` nem bővíthető V2-vé.
- A közös core music value object csak public/core importon keresztül használható.

A pre-flight az itt leírt tényeket újraméri. Ha bármelyik eltér, ebben a
szekcióban rögzíti a mért állapotot, a választott feloldást és annak indokát.
Üres vagy implicit revízióval a státusz nem válhat `PLANNING`-re.

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
