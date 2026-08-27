# E12-R10 — Idempotens integration dispatcher és outbox

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 10
- **Kör-azonosító:** `E12-R10`
- **Branch:** `<motor>/e12-r10-idempotent-dispatcher-and-outbox`
- **Előfeltétel:** `E12-R09` merge-elve (a katalógus adja a mért esemény-listát és az idempotencia-kulcsokat)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0451` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "idempotent event dispatcher outbox retry dead-letter duplicate XP streak"` → **`halts/round-status-E08-R24`** (a Practice↔Gamification integráció merge-elt köre) és **[ADR 0333](../adr/0333-activity-outbox-reliable-processing.md)** (Activity outbox: kapacitás, `maxAttempts`, karantén, ack csak sikeres ledger-hívás után). A dupla-XP elleni védelem MÁR él — ez a kör MÉRI és lefedi, nem újraírja.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/gamification/data/local_activity_outbox_repository.dart` és az `application/activity_event_ingestor.dart` MÉRT viselkedését (kapacitás-túlcsordulás → legrégebbi karanténba; `attemptCount == maxAttempts` → karantén; `appendIfAbsent` `false` = idempotens ismétlés, ack-elhető). A §6 cellái ezekre a MÉRT invariánsokra épülnek.

## 0.0 A kör tárgya: HIÁNYZÓ MÉRCE, nem hiányzó mechanizmus

A SDD Kör 10 „implementálj dispatchert és outboxot" feladata a fán RÉSZBEN teljesült (ADR 0333). Ami MÉRHETŐEN hiányzik: (a) a **100-szoros ismétlés** invariáns-teszt, (b) a **process-kill utáni resume** bizonyítéka, (c) az **out-of-order** esemény kezelésének cellája, (d) a community-oldali outbox és a gamification-outbox EGYÜTTES viselkedésének mérése. A kör ezt a négyet szállítja, és csak akkor módosít `lib/**` kódot, ha valamelyik cella MÉRT hibát talál — a javítás ekkor a MEGLÉVŐ osztályban történik, új párhuzamos dispatcher NEM jön létre.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/gamification/application/activity_event_ingestor.dart",
  "lib/features/gamification/data/local_activity_outbox_repository.dart",
  "test/core/events/idempotency_test.dart",
  "test/core/events/outbox_resume_test.dart",
  "docs/contracts/event-catalog.md",
  "docs/rounds/e12-r10-idempotent-dispatcher-and-outbox.md",
]
gate_tests = [
  "test/core/events/idempotency_test.dart",
  "test/core/events/outbox_resume_test.dart",
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

**STOP-protokoll:** ha egy cella MÉRT hibát talál, ami a `lib/features/gamification/` §4-en KÍVÜLI fájljában él (pl. a `RewardLedger`-ben), a kimenet a `stopped` jelzés és jelentés — a lista tágítása TILOS.

## 1. Cél

Bizonyítani — nem feltételezni —, hogy ismétlés, folyamat-megszakítás és sorrend-csere mellett sem keletkezik dupla XP, streak, challenge-eredmény vagy poszt.

## 2. Jelenlegi állapot — mért tények

- `lib/features/gamification/data/activity_outbox_repository.dart` + `local_activity_outbox_repository.dart`: pending/karantén sor, `capacity`, `maxAttempts` (ADR 0333 5. pont).
- `lib/features/gamification/application/activity_event_ingestor.dart`: az `entry.sourceEventId == event.eventId` invariáns fail-fast; `appendIfAbsent` `false` értéke SIKERES, idempotens ismétlés.
- `lib/features/community/application/outbox/community_outbox.dart` (460 sor): külön, community-oldali sor a poszt/reakció írásokhoz.
- `test/features/gamification/` alatt van `application`, `data`, `domain`, `integration` teszt-könyvtár — a mai cellák a KOMPONENS szintjén mérnek; **100-szoros ismétlés, kill-resume és out-of-order cella nincs**.
- `test/core/events/` a Kör 9 után létezik (séma-kompatibilitási teszttel).

## 3. Scope

**Benne van:** `test/core/events/idempotency_test.dart` — ugyanaz az esemény **100** ismétléssel pontosan EGY ledger-hatást ad; a hatás mérése a ledger-egyenlegen történik, nem a hívásszámon · `test/core/events/outbox_resume_test.dart` — a drain közepén megszakított folyamat (perzisztált állapotból új példány) folytatja, duplázás nélkül; out-of-order beérkezés (később keletkezett esemény előbb) nem borítja a napi/streak számítást · szükség esetén PONTOSAN annyi javítás a két engedélyezett `lib/` fájlban, amennyit egy MÉRT piros cella indokol · a `docs/contracts/event-catalog.md` idempotencia-oszlopának kitöltése a MÉRT viselkedéssel.

**NINCS benne (tilos):**

- ÚJ dispatcher/outbox osztály vagy `lib/core/sync/outbox/` könyvtár létrehozása.
- A community outbox átírása (mérni szabad, módosítani nem).
- Meglévő teszt gyengítése vagy törlése.
- `docs/adr/**` — az ADR 0451-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/activity_event_ingestor.dart` | csak MÉRT piros cellára adott javítás |
| `lib/features/gamification/data/local_activity_outbox_repository.dart` | csak MÉRT piros cellára adott javítás |
| `test/core/events/idempotency_test.dart` | ÚJ — az ismétlés-invariáns |
| `test/core/events/outbox_resume_test.dart` | ÚJ — resume és out-of-order |
| `docs/contracts/event-catalog.md` | az idempotencia-oszlop kitöltése |

**Tilos zóna:** `lib/features/community/**` · `lib/features/gamification/` egyéb fájljai · `lib/core/**` · `backend/**` · `docs/adr/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0451)

### 5.1 Az idempotencia mércéje a HATÁS, nem a hívásszám

A teszt a ledger-egyenleget (XP, streak-nap, jutalom) méri, nem azt, hányszor hívódott egy metódus. **NEM elfogadható gyengítés:** `verify(callCount == 1)` jellegű mock-állítás — az a dupla hatást nem zárja ki, csak a dupla hívást.

### 5.2 A megszakítás UTÁNI példány a perzisztált állapotból indul

A resume-cella új repository-példányt épít ugyanarra a tárolóra, nem ugyanazt az objektumot folytatja. **NEM elfogadható gyengítés:** in-memory objektum „újrahasználása" resume-ként — az a folyamat-halált nem modellezi.

### 5.3 Piros cella esetén a javítás a MEGLÉVŐ osztályban történik

**NEM elfogadható gyengítés:** párhuzamos, „tisztább" dispatcher bevezetése a hiba megkerülésére — a repó mért tanulsága szerint két igazság drágább, mint egy javítás.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | 100 ismétlés → pontosan egy ledger-hatás (egyenleg-mérés) | `idempotency_test.dart` |
| A2 | Drain közepén megszakított folyamat után új példány folytatja, duplázás nélkül | `outbox_resume_test.dart` |
| A3 | Out-of-order beérkezés nem duplázza és nem veszíti el a napi/streak hatást | `outbox_resume_test.dart` |
| A4 | Sikertelen online mellékhatás NEM blokkolja a lokális állapotot (a lokális mentés megmarad) | `outbox_resume_test.dart` |
| A5 | A `maxAttempts` elérése után a rekord karanténba kerül, és a sor tovább dolgozik | `outbox_resume_test.dart` |
| A6 | Az esemény-katalógus minden sorának idempotencia-kulcsa a MÉRT viselkedést írja le | `docs/contracts/event-catalog.md` + a §7 gate |

**Küszöb-cellahármas a `maxAttempts`-ra** (a határ INKLUZÍV: az utolsó megengedett kísérlet MÉG lefut): a küszöb **alatt** (`attemptCount = maxAttempts - 1`) → a rekord PENDING marad; **pontosan rajta** (`attemptCount == maxAttempts`) → KARANTÉN; a küszöb **fölött** (további enqueue ugyanarra) → a sor változatlanul dolgozik, új karantén-bejegyzés nem keletkezik.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az idempotencia-kulcs az esemény TARTALMÁBÓL hasholódik `eventId` helyett (két azonos tartalmú, külön esemény összeolvad) | A1 |
| A resume in-memory állapotból indul, a perzisztált sor nem olvasódik vissza | A2 |
| A hálózati hiba visszagörgeti a lokális mentést | A4 |
| A karantén a teljes sort megállítja | A5 |
| A `maxAttempts` ellenőrzés `>` helyett `>=`-t használ egy kísérlettel korábban | a küszöb-cellahármas „alatt" cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cseréld az `appendIfAbsent` idempotens ágát feltétlen `append`-re, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/events/idempotency_test.dart test/core/events/outbox_resume_test.dart test/core/events/event_schema_compatibility_test.dart
```

A gamification meglévő cellái regresszió-őrként (külön hívás, nem lánc):

```bash
tools/round-gate.sh test/features/gamification/
```

## 8. Implementációs sorrend

1. `idempotency_test.dart` — a 100-szoros ismétlés, egyenleg-méréssel (RED vagy zöld: MÉRÉS).
2. `outbox_resume_test.dart` — resume, out-of-order, karantén, küszöb-cellahármas.
3. Csak MÉRT piros cellára: javítás a két engedélyezett `lib/` fájlban.
4. A katalógus idempotencia-oszlopa.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Mock-alapú hamis zöld.** A hívásszám-mérés a valódi dupla hatást nem zárja ki (§5.1).
- **Párhuzamos implementáció.** Egy új `lib/core/sync/outbox/` a meglévő ADR 0333 mellé kettős igazságot teremtene (tilos zóna).
- **A community-outbox érintése.** Mérni szabad, módosítani nem — a két sor viselkedése együtt is vizsgálandó, de a javítása külön kör.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
