# E03-R03 — Songstruktúra és determinisztikus időmodell

- **Státusz:** **PLANNING** (pre-flight lezárva 2026-08-02, orchestrátor:
  Claude Sonnet 5; tervezési baseline: `main` @ `053376a`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 3; §9.5–10.6
- **Branch:** `codex/e03-r03-song-structure-and-time-map`
- **Előfeltétel:** E03-R02 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/song_trainer/domain/models/song_section.dart",
  "lib/features/song_trainer/domain/models/song_measure.dart",
  "lib/features/song_trainer/domain/models/tempo_map.dart",
  "lib/features/song_trainer/domain/models/meter_map.dart",
  "lib/features/song_trainer/domain/models/key_map.dart",
  "lib/features/song_trainer/domain/models/song_document.dart",
  "lib/features/song_trainer/domain/services/song_time_map.dart",
  "lib/features/song_trainer/domain/public.dart",
  "test/features/song_trainer/domain/song_structure_test.dart",
  "test/features/song_trainer/domain/song_time_map_test.dart",
  "test/property/song_time_map_property_test.dart",
  "docs/rounds/e03-r03-song-structure-and-time-map.md",
  "docs/adr/0093-song-trainer-local-time-primitives.md",
]
gate_tests = [
  "test/features/song_trainer/domain/song_structure_test.dart",
  "test/features/song_trainer/domain/song_time_map_test.dart",
  "test/property/song_time_map_property_test.dart",
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

**1. R02 document skeleton — megerősítve, nincs drift.** `lib/features/song_trainer/domain/models/song_document.dart`
(`main` @ `053376a`) csak `schemaVersion`/`id`/`revision`/`metadata`/`source`/
`assets`/`markers`/`createdAt`/`updatedAt` mezőket tartalmaz; nincs
`sections`/`measures`/`tracks`/`tempoMap`/`meterMap`/`keyMap`. `SongSectionId`
és `SongTrackId` viszont **már léteznek** `song_id.dart`-ban (R02, előre
deklarálva a jövőbeli modellekhez) — a section modell ezeket újrafelhasználja,
nem definiál új ID-t.

**2. Chapter 3 (`BeatPosition`/`Tempo`/`Meter`) publikus contract audit —
DRIFT, feloldva ADR 0093-ban.** A brief §10.1 idézete szerint az Epic 3 ezekre
a Practice Engine-beli (`lib/features/practice/domain/model/`) típusokra
„épít". Mérve: `test/features/song_trainer/domain/song_document_test.dart`
Domain purity scannere (`cross-feature import` minta) **kivétel nélkül**
tiltja a `package:strumsight/features/practice/` importot bármely
`lib/features/song_trainer/domain/**` fájlból — a `practice/public.dart`
határon át sem engedett, és ez a teszt NINCS az E03-R03 `allowed_paths`
listáján (tilos zóna, nem módosítható), de a teljes CI-suite futtatja, tehát
ténylegesen kikényszerített. ADR 0092 §1/§4 függetlenül megerősíti: a Song
Trainer ↔ Practice Engine kapcsolat csak egy jövőbeli, application-szintű
`SongPracticeCompiler` határon (E03-R19) él, nem domain-szintű
típusmegosztáson. **Feloldás — [ADR 0093](../adr/0093-song-trainer-local-time-primitives.md):**
a Song Trainer domain saját, lokális (nem Practice-ből importált) tick-alapú
pozíció- és BPM-alapú tempó-primitíveket definiál a már engedélyezett
`tempo_map.dart`/`song_time_map.dart` fájlokon belül — nincs szükség
`allowed_paths` bővítésre. A tervezési ELVEK (egész/racionális köztes
aritmetika, egyetlen kerekítési pont a mikroszekundum-konverzióban) öröklődnek
a Chapter 3 precedensből (ADR 0066/0072), a TÍPUSOK nem. `MeterChange` az SDD
§10.3 szerint measure-index kulcsú (`atMeasure: int`), ezért a meter maphez
nem kell pozíció-típus.

**3. Wall clock / UI frame nem lehet zenei időforrás — megerősítve, nincs
drift.** Nincs olyan meglévő song_trainer kód, ami ettől eltérne (a domain
réteg ma teljesen wall-clock-mentes); ez a kör-implementációra vonatkozó
kötött szabály marad (§5).

Fenti méréssel a brief az `allowed_paths`/`gate_tests` listát **változatlanul**
hagyja — a feloldás a meglévő fájlokon belül fér el.

## 1. Cél

Section, measure, tempo, meter, key és pontos beat↔time konverzió szállítása pickup-, map-change- és speed támogatással.

## 2. Jelenlegi állapot

- R02 document skeleton listái üresek és strukturális típusaik még nincsenek.
- Chapter 3 publikus BeatPosition/Tempo/Meter contractját pre-flightban újra kell auditálni.
- Wall clock vagy UI frame nem lehet zenei időforrás.

## 3. Scope

**Benne:**

- section/measure és map modellek
- SongTimeMap beat→duration és duration→beat
- pickup, tempo/meter change, seek/loop boundary reprezentáció

**Kívül — ebben a körben TILOS:**

- track/event és repeat expansion
- transport/backing player
- UI és scorer

## 4. Engedélyezett fájlok

| Útvonal | Állapot a kör elején | Miért |
|---|---|---|
| `lib/features/song_trainer/domain/models/song_section.dart` | ÚJ | section modell |
| `lib/features/song_trainer/domain/models/song_measure.dart` | ÚJ | measure/pickup |
| `lib/features/song_trainer/domain/models/tempo_map.dart` | ÚJ | tempo map |
| `lib/features/song_trainer/domain/models/meter_map.dart` | ÚJ | meter map |
| `lib/features/song_trainer/domain/models/key_map.dart` | ÚJ | locale-független key map |
| `lib/features/song_trainer/domain/models/song_document.dart` | R02-ből | strukturális mezők bekötése |
| `lib/features/song_trainer/domain/services/song_time_map.dart` | ÚJ | konverzió |
| `lib/features/song_trainer/domain/public.dart` | R02-ből | új publikus domain típusok |
| `test/features/song_trainer/domain/song_structure_test.dart` | ÚJ | modell invariánsok |
| `test/features/song_trainer/domain/song_time_map_test.dart` | ÚJ | határtesztek |
| `test/property/song_time_map_property_test.dart` | ÚJ | round-trip/monotonic property |
| `docs/rounds/e03-r03-song-structure-and-time-map.md` | meglévő | §10 handoff |
| `docs/adr/0093-song-trainer-local-time-primitives.md` | ÚJ (pre-flight commitolta) | ADR 0093 — lokális idő-primitívek, ld. §0.0 pont 2 |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, az RTM,
`.github/**`, nem felsorolt `lib/features/**`, más kör briefje és
`docs/adr/**`. ADR-fájl csak akkor kivétel, ha a pre-flight ütközésmentes
exact pathként hozzáadta ehhez a táblához, még a `PLANNING` commit előtt.
Új tesztfixture vagy helper is fájl: ha nincs tételesen a táblában, `stopped`.

## 5. Kötött architekturális döntések

1. Köztes aritmetika rational/integer; kontrollálatlan measure-enkénti double akkumuláció tilos.
2. Speed view-paraméter, nem módosítja a source mapet.
3. Tempo/meter change boundary bal/zárt policyje egyértelmű és minden irányban azonos.
4. Round-trip tolerancia konkrétan mérve és dokumentálva; monotonicitás nem gyengíthető csak rendezett fixturekre.
5. **Nincs Practice Engine import** ([ADR 0093](../adr/0093-song-trainer-local-time-primitives.md)):
   a `BeatPosition`/`Tempo`/`Meter` (`lib/features/practice/domain/model/`)
   sem közvetlenül, sem a `practice/public.dart`-on át nem importálható a
   song_trainer domainbe — a lokális idő-primitívek a §4 már engedélyezett
   fájljain belül készülnek. Ha ez lehetetlennek bizonyul: `stopped`, nem
   scope-tágítás.

E döntések enyhítése nem elfogadható „zöldre javítás”. Valódi ellentmondásnál
brief-revízió vagy ADR szükséges.

## 6. Acceptance criteria

- [ ] 3/4 és 4/4 teljesen, 6/8 reprezentációként támogatott; pickup explicit rövidebb lehet.
- [ ] Beat→time→beat property érvényes a dokumentált tolerancián belül és output monoton.
- [ ] Tempo/meter change előtt, pontosan rajta és utána folytonos, determinisztikus eredmény születik.
- [ ] Speed 0.5 kétszeres, 1.0 parity, 2.0 fele durationt ad source-mutáció nélkül.

### Kötelező megkülönböztető mátrix

| Map/pont | speed | Kötelező állítás |
|---|---:|---|
| állandó 120 BPM, beat 0/1/4 | 1.0 | 0/0.5/2.0 s |
| tempo change −ε / pontosan / +ε | 1.0 | monoton és boundary policy szerint |
| 3/4 pickup / normál measure | 0.5/1/2 | explicit duration skálázás |
| invalid duplicate/negative map | 1.0 | stabil failure, nincs partial map |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással tesz pirossá; bemásolt zöld kimenet önmagában nem evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/domain/song_structure_test.dart test/features/song_trainer/domain/song_time_map_test.dart test/property/song_time_map_property_test.dart
```

Ez az egyetlen lokális záró gate; külön processzben futó format → analyze →
célzott testek → architecture lépéseit nem szabad `&&`-del, pipe-pal,
`tail`-lel vagy csonkítással helyettesíteni. A full suite + randomizált
property + APK CI-t az orchestrátor indítja, és exact branch `headSha`-t
ellenőriz.

## 8. Implementációs sorrend

1. Írd meg a strukturális invalid/valid mátrixot és a property generátort.
2. Futtasd RED-ként a hiányzó modellek és time map miatt.
3. Implementáld a modelleket, majd a rational/integer mapet.
4. Kösd be a documentbe és ellenőrizd az immutabilityt.
5. Futtasd a gate-et több random seed-del; a CI property gate külön marad.

Javasolt körcommit: `feat(song-domain): add song structure and deterministic time maps`.

## 9. Kockázatok

- Chapter 3 public export driftje cross-feature belső import kísértést okozhat; ez STOP.
- Boundary eltolás csak egyirányú teszttel rejtve maradhat; mindkét konverzió kötelező.

**STOP:** ha a kockázat csak listán kívüli módosítással, bizonyítatlan fallbackkel
vagy acceptance-gyengítéssel oldható fel, állj meg és kérj brief-revíziót.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult el; ezért nincs implementációs vagy tesztsiker-állítás.
A handoffba a végrehajtáskor fájlonkénti összefoglaló, tényleges parancs és
csonkítatlan eredmény, terveltérés, nem futtatott ellenőrzés és follow-up kerül.
Minden viselkedési állítást konkrét teszt vagy mérés bizonyít.

## 11. Review — a független reviewer tölti ki

Tervezett review-fájl:
`docs/reviews/e03-r03-song-structure-and-time-map-review.md`.

Merge csak akkor engedett, ha az exact-SHA CI zöld, a diff a §4 listáján belül
marad, és nincs OPEN BLOCKER vagy MAJOR.
