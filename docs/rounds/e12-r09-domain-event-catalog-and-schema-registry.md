# E12-R09 — Domain event catalog és schema registry

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 9
- **Kör-azonosító:** `E12-R09`
- **Branch:** `<motor>/e12-r09-domain-event-catalog-and-schema-registry`
- **Előfeltétel:** `E12-R02` merge-elve (a fejezet-index adja a producer/consumer oszlop Chapter-hivatkozásait)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0450` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "domain event catalog envelope schema version idempotency cross-feature"` → **[ADR 0329](../adr/0329-canonical-activity-event-contracts.md)** (kanonikus tanulási esemény-szerződések: kötelező `schemaVersion`, hívó-adta stabil `eventId`, `type` discriminator, egyetlen `public.dart` belépő) és **[ADR 0176](../adr/0176-cross-feature-public-barrel-recognition.md)** (a cross-feature import audit a beágyazott barrelt is elfogadja). A kör ezekre ÉPÜL — nem tervez új envelope-ot melléjük.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/gamification/domain/activity/learning_activity_event.dart` MÉRT alakját (`sealed class`, `eventId`, `occurredAt`, `epochDay`, `source`, `trust`, `schemaVersion`, `duration`, `score`, `type` discriminator, **hat** altípus) és a `lib/features/community/application/outbox/community_outbox.dart` létét. Ha az E13/E14 sáv új eseményt vett fel, a katalógusnak azt is tartalmaznia kell.

## 0.0 A kör MÉRT kiindulópontja: az esemény-szerződés MÁR LÉTEZIK

A SDD Kör 9 „implementáld a `DomainEventEnvelope` core típust" feladata a fán RÉSZBEN teljesült: a `LearningActivityEvent` sealed hierarchia (ADR 0329) hat altípussal, verziózott sémával és stabil azonosítóval ÉL, a gamification feature `public.dart` barrelje mögött. Ami HIÁNYZIK: (a) a katalógus-DOKUMENTUM (producer, consumer, owner, schema-verzió, idempotencia-kulcs), (b) a fixture-készlet, (c) a séma-kompatibilitási teszt (ismeretlen mező tolerancia, additív bővítés). Ez a kör ezt a hármat szállítja, és **nem vezet be konkurens envelope-típust**.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/contracts/event-catalog.md",
  "test/fixtures/events/practice_session_completed_v1.json",
  "test/fixtures/events/song_session_completed_v1.json",
  "test/fixtures/events/analysis_completed_v1.json",
  "test/fixtures/events/plan_completed_v1.json",
  "test/fixtures/events/tutor_session_completed_v1.json",
  "test/fixtures/events/vision_session_completed_v1.json",
  "test/core/events/event_schema_compatibility_test.dart",
  "docs/rounds/e12-r09-domain-event-catalog-and-schema-registry.md",
]
gate_tests = [
  "test/core/events/event_schema_compatibility_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a katalógus egy MÉRT ellentmondást talál a kódban (pl. egy altípus `schemaVersion` kezelése eltér az ADR 0329-től), a kimenet a `stopped` jelzés és jelentés — a `lib/**` javítása ebben a körben TILOS.

## 1. Cél

A cross-feature események egyetlen, verziózott, tulajdonossal ellátott katalógusa és gépi kompatibilitás-mércéje — a meglévő `LearningActivityEvent` szerződés lecserélése nélkül.

## 2. Jelenlegi állapot — mért tények

- `lib/features/gamification/domain/activity/learning_activity_event.dart`: `sealed class LearningActivityEvent`, kötelező `schemaVersion`, hívó-adta `eventId`, `type` discriminator; altípusok: `PracticeActivityEvent`, `SongActivityEvent`, `AnalysisActivityEvent`, `PlanActivityEvent`, `TutorActivityEvent`, `VisionActivityEvent`.
- Kilenc feature-adapter termel eseményt (`gamification_{practice,song,analysis,plan,tutor,vision,lesson}_adapter.dart` és társaik) — a producer-oszlop ezekből MÉRHETŐ, nem feltételezhető.
- `lib/features/gamification/data/activity_outbox_repository.dart` + `local_activity_outbox_repository.dart` és `application/activity_event_ingestor.dart` MÁR megvalósítja az idempotens beemelést (ADR 0333).
- `lib/features/community/application/outbox/community_outbox.dart` (460 sor) külön, community-oldali outbox.
- `docs/contracts/` MA egyetlen fájlt tartalmaz (`community-share-artifacts.md`); `test/fixtures/events/` és `test/core/events/` **nem létezik**.

## 3. Scope

**Benne van:** `docs/contracts/event-catalog.md` — MINDEN cross-feature esemény: `type` kód, séma-verzió, PRODUCER (mért fájl), CONSUMER (mért fájl), idempotencia-kulcs, owner Chapter, kompatibilitási szabály · hat JSON fixture (altípusonként egy, a MÉRT mezőnevekkel) · `test/core/events/event_schema_compatibility_test.dart`: round-trip minden fixture-re, ISMERETLEN mező tolerálása (additív bővítés), ismeretlen `type` és hiányzó `schemaVersion` KONTROLLÁLT hibája, két azonos `eventId`-jű fixture idempotencia-kulcs-egyezése.

**NINCS benne (tilos):**

- Bármely `lib/**` fájl módosítása — beleértve új `lib/core/events/` könyvtár létrehozását (a szerződés a gamification barrel mögött él, ADR 0329/0176).
- Új esemény-altípus bevezetése.
- `docs/adr/**` — az ADR 0450-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/contracts/event-catalog.md` | ÚJ — a katalógus |
| `test/fixtures/events/*.json` (6 fájl) | ÚJ — altípusonként egy fixture |
| `test/core/events/event_schema_compatibility_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/adr/**` · `tools/**` · minden meglévő teszt

## 5. Kötött architekturális döntések (ADR 0450)

### 5.1 A katalógus a KÓDBÓL mért, nem a SDD-ből másolt

Minden sor producer/consumer oszlopa létező fájlra (és ahol értelmes, sorra) hivatkozik. **NEM elfogadható gyengítés:** a `docs/sdd/12-…` §14.1 „közös események" listájának átmásolása anélkül, hogy a fán megkeresnék a tényleges termelőt — a SDD terv, a kód a valóság.

### 5.2 Az ismeretlen MEZŐ tolerált, az ismeretlen TÍPUS nem

Additív séma-bővítés (új mező) nem törheti a régi olvasót; ismeretlen `type` vagy hiányzó `schemaVersion` viszont kontrollált hiba (ADR 0329 1. pont). **NEM elfogadható gyengítés:** „legyen 1 az alapértelmezés" a hiányzó verzióra.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a hat fixture round-trip-el (dekódolás → kódolás → dekódolás, mezőazonos) | `event_schema_compatibility_test.dart` |
| A2 | Ismeretlen EXTRA mezővel bővített fixture továbbra is dekódolható | ugyanaz a teszt |
| A3 | Hiányzó `schemaVersion` → kontrollált hiba (nem csendes default) | ugyanaz a teszt |
| A4 | Ismeretlen `type` → kontrollált hiba | ugyanaz a teszt |
| A5 | A katalógus MINDEN sora létező producer- és consumer-fájlra hivatkozik | ugyanaz a teszt (fájllét-cella) |
| A6 | Minden katalógus-sorhoz tartozik owner Chapter és idempotencia-kulcs | a katalógus + a teszt mező-cellája |

**Küszöb-cellahármas a séma-verzióra** (a fixture-ökben MÉRT legfrissebb támogatott verzió `V`; a határ INKLUZÍV): a küszöb **alatt** (`schemaVersion < V`, régi esemény) → dekódolható marad, a katalógus kompatibilitási szabálya szerint; **pontosan rajta** (`schemaVersion == V`) → dekódolható; a küszöb **fölött** (`schemaVersion > V`, jövőbeli verzió) → KONTROLLÁLT hiba, nem csendes elfogadás.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A teszt szigorúan tiltja az ismeretlen mezőt (nincs additív bővíthetőség) | A2 |
| A dekódoló hiányzó `schemaVersion`-re 1-et feltételez | A3 |
| A katalógus egy nem létező `lib/core/events/…` fájlra hivatkozik producerként | A5 |
| Egy fixture kézzel írt mezőnevet használ a MÉRT helyett (`occurred_at` vs `occurredAt`) | A1 |
| A dekódoló a jövőbeli (`> V`) séma-verziót csendben elfogadja | a küszöb-cellahármas „fölött" cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki az egyik fixture-ből a `schemaVersion` mezőt, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/events/event_schema_compatibility_test.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: producer/consumer hívóhelyek kigyűjtése a `lib/features/**` fából.
2. A hat fixture a MÉRT mezőnevekkel.
3. `event_schema_compatibility_test.dart` (RED-ből indulva).
4. `docs/contracts/event-catalog.md`.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Párhuzamos envelope bevezetése.** A legdrágább hiba: egy új `lib/core/events/` típus a meglévő ADR 0329 szerződés mellé — kettős igazság (tilos zóna).
- **A katalógus terv-alapú kitöltése.** A SDD listája nem egyezik a fa MÉRT állapotával (A5).
- **A fixture-ek elavulása.** Ha egy altípus mezőt kap, a fixture néma marad — ezért méri az A1 a MEZŐAZONOS round-tripet.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
