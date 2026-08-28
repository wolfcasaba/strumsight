# E12-R10 — Idempotens integration dispatcher és outbox

- **Státusz:** READY (pre-flight elvégezve 2026-08-28, kód újramérve: `main @ 24874c58`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 10
- **Kör-azonosító:** `E12-R10`
- **Branch:** `sonnet-impl/e12-r10-idempotent-dispatcher-and-outbox`
- **Előfeltétel:** `E12-R09` merge-elve (a katalógus adja a mért esemény-listát és az idempotencia-kulcsokat)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`ADR 0469`](../adr/0469-outbox-idempotency-is-measured-on-the-ledger-effect.md) — a `tools/round-slots.py reserve-adr` foglalója adta (lásd §0.0 R1).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "idempotent event dispatcher outbox retry dead-letter duplicate XP streak"` → **`halts/round-status-E08-R24`** (a Practice↔Gamification integráció merge-elt köre) és **[ADR 0333](../adr/0333-activity-outbox-reliable-processing.md)** (Activity outbox: kapacitás, `maxAttempts`, karantén, ack csak sikeres ledger-hívás után). A dupla-XP elleni védelem MÁR él — ez a kör MÉRI és lefedi, nem újraírja.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/gamification/data/local_activity_outbox_repository.dart` és az `application/activity_event_ingestor.dart` MÉRT viselkedését (kapacitás-túlcsordulás → legrégebbi karanténba; `attemptCount == maxAttempts` → karantén; `appendIfAbsent` `false` = idempotens ismétlés, ack-elhető). A §6 cellái ezekre a MÉRT invariánsokra épülnek.

## 0.0 Pre-flight brief-revízió (Claude, 2026-08-28, `main @ 24874c58`)

A `brief-lint` (strict) **nem adott leletet**. Az alábbi hat revízió a §1 két mérési
szabályából (elérhetetlen cél-státusz · erőforrás-tulajdonlás a TÉNYLEGES hívási
láncon) született, mind kimért paranccsal.

**Visszakeresés (ADR 0312, szűkítve → teljes):** `lessons,halts,adr` →
[`ADR 0333`](../adr/0333-activity-outbox-reliable-processing.md) (a kapacitás/karantén/
`maxAttempts` szerződés), [`ADR 0301`](../adr/0301-reward-ledger-append-only-idempotency.md)
(append-only dedup), `halts/round-status-E08-R04` (a mai outbox merge-elt köre);
`lessons,halts` → **[L453](../LESSONS.md)** (egy csatorna-specifikus mock csak azt az
EGY csatornát bizonyítja — az invariánst nem), **[L441](../LESSONS.md)** (a bukó
`expect` UTÁNI állítások SOHA nem futnak le, tehát méretlenek), **[L368](../LESSONS.md)**
(a bizonyíték a TÉNYLEGESEN futtatott őré, nem egy általánosabbé).

| # | Mért állítás | Revízió |
|---|---|---|
| **R1** | A brief `ADR 0451`-et írt elő; a kötelező foglaló (`tools/round-slots.py reserve-adr --round E12-R10`, ADR 0171 §1.0.1) **`0469`**-et adott (a fán a legmagasabb `0468`, a `0451` sosem került kiosztásra). | A kör ADR-je **0469**. A `0451` szám nem kerül felhasználásra. |
| **R2** | `local_activity_outbox_repository.dart:243` a kísérlet-számlálót a ledger-hívás **ELŐTT** növeli, a `:286` feltétel pedig `record.attempts >= maxAttempts`. Emiatt a `attemptCount = maxAttempts - 1` **perzisztált** állapot a következő drainben KARANTÉNBA kerül — a brief §6 „alatta" cellája (`maxAttempts - 1` → PENDING) **elérhetetlen**. | A küszöb-cellahármas a **drain ELŐTTI, perzisztált** `attempts` mezőn értendő; a §6 hármas újraírva (lásd lent). |
| **R3** | `grep -rn "StreakService(" lib/` → **0 találat**: a `StreakService` tiszta, hívó-vezérelt szolgáltatás, amit az outbox soha nem hív. Az outbox drain egyetlen downstream-je az `appendIfAbsent` (`:249`); a ledger egyetlen projekciója a `ProfileProjector.rebuild()` (`profile_projector.dart:40`). | Az **A3** nem mérhető „streak-számításként" ezen az úton. Újrafogalmazva a MÉRT láncon: sorrend-függetlenség a ledger-tartalmon és a projektált `totalXp`-n. |
| **R4** | Az effekt-mérés konkrét felülete megvan: `ProfileProjector(curve:…, ledger:…).rebuild()` → `.profile.totalXp`. A teszt-infra is: `test/support/preference_store.dart` exportálja az `InMemoryKeyValueStore`-t, és a `test/features/gamification/application/activity_ingestor_test.dart:521–608` `_Fixture` + `_FakeRewardLedger` mintája a VALÓDI `LocalRewardLedgerRepository`-t perzisztálja ugyanabba a store-ba. | Az új cellák EZT a mintát követik; új mock-ledger bevezetése tilos. |
| **R5** | `docs/contracts/event-catalog.md` idempotencia-**oszlopa MÁR kitöltött** (mind a hat soron `eventId`), és van „Idempotencia (ADR 0333)" szakasza — a Kör 9 leszállította. | Az **A6** nem „oszlop-kitöltés", hanem a meglévő szakasz kiegészítése a kör MÉRT outbox-invariánsaival, cellánkénti hivatkozással. |
| **R6** | `_ensureLoaded()` (`:334`) lusta, első használatkori dokumentum-olvasás; a konstruktor `KeyValueStore`-t kap. | Az **A2** resume-cellája elérhető: MÁSODIK `LocalActivityOutboxRepository` UGYANARRA az `InMemoryKeyValueStore`-ra. |

A kör kötött döntéseit az [`ADR 0469`](../adr/0469-outbox-idempotency-is-measured-on-the-ledger-effect.md)
rögzíti (D1–D6). A §5 alábbi pontjai annak a rövidítései.

## 0.0.1 A kör tárgya: HIÁNYZÓ MÉRCE, nem hiányzó mechanizmus

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

**Pre-flightban újramérve (2026-08-28, `main @ 24874c58`) — ezekre épülnek a §6 cellái:**

| Mért tény | Hol |
|---|---|
| A drain a kísérlet-számlálót a ledger-hívás **ELŐTT** növeli | `local_activity_outbox_repository.dart:242–245` |
| A karantén-feltétel `record.attempts >= maxAttempts` | `local_activity_outbox_repository.dart:286` |
| `appendIfAbsent == false` + `hasProcessedEvent == true` → ack (nincs dupla kifizetés) | `local_activity_outbox_repository.dart:276–282` |
| Ledger-kivétel a drainen belül elnyelve, a rekord PENDING marad | `local_activity_outbox_repository.dart:250–261`, `:308–312` |
| Már feldolgozott eseményre az `enqueue` `accepted == false` + `supersededByLedger` karantén | `local_activity_outbox_repository.dart:153–168` |
| A perzisztált állapot lustán, első használatkor töltődik (ez adja a resume-ot) | `local_activity_outbox_repository.dart:334` |
| Az egyetlen ledger-projekció: `ProfileProjector.rebuild()` → `profile.totalXp` | `profile_projector.dart:40`, `:57` |
| A `StreakService`-nek **nincs hívója** a `lib/` fán | `grep -rn "StreakService(" lib/` → 0 találat |
| Használható teszt-infra: `InMemoryKeyValueStore` + valódi `LocalRewardLedgerRepository` fölé húzott, kapcsolható `_FakeRewardLedger` | `test/support/preference_store.dart`, `test/features/gamification/application/activity_ingestor_test.dart:521–608` |
| A katalógus idempotencia-oszlopa MÁR kitöltött (`eventId`, hat sor) | `docs/contracts/event-catalog.md` |

## 3. Scope

**Benne van:** `test/core/events/idempotency_test.dart` — ugyanaz a `sourceEventId` **100** ismétléssel (eltérő `ledgerId`-kkel) pontosan EGY ledger-hatást ad; a hatás mérése a projektált egyenlegen (`ProfileProjector.rebuild().profile.totalXp`) történik, nem a hívásszámon · `test/core/events/outbox_resume_test.dart` — a drain közepén megszakított folyamat (MÁSODIK repository-példány UGYANARRA a store-ra) folytatja, duplázás nélkül; out-of-order beérkezés (a később keletkezett esemény drainelődik előbb) ugyanazt a ledger-tartalmat és egyenleget adja, mint a sorrendhelyes futás (§5.2.1) · szükség esetén PONTOSAN annyi javítás a két engedélyezett `lib/` fájlban, amennyit egy MÉRT piros cella indokol · a `docs/contracts/event-catalog.md` „Idempotencia" szakaszának bővítése a kör MÉRT outbox-invariánsaival (a Kör 9 már kitöltötte az oszlopot — pre-flight R5).

**NINCS benne (tilos):**

- ÚJ dispatcher/outbox osztály vagy `lib/core/sync/outbox/` könyvtár létrehozása.
- A community outbox átírása (mérni szabad, módosítani nem).
- Meglévő teszt gyengítése vagy törlése.
- `docs/adr/**` — az [ADR 0469](../adr/0469-outbox-idempotency-is-measured-on-the-ledger-effect.md)-et a Claude MÁR megírta a pre-flightban; hozzányúlni tilos.
- A `StreakService` közvetlen hívása „streak-bizonyítékként" (§5.2.1 — nincs a mért láncon).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/activity_event_ingestor.dart` | csak MÉRT piros cellára adott javítás |
| `lib/features/gamification/data/local_activity_outbox_repository.dart` | csak MÉRT piros cellára adott javítás |
| `test/core/events/idempotency_test.dart` | ÚJ — az ismétlés-invariáns |
| `test/core/events/outbox_resume_test.dart` | ÚJ — resume és out-of-order |
| `docs/contracts/event-catalog.md` | az idempotencia-oszlop kitöltése |

**Tilos zóna:** `lib/features/community/**` · `lib/features/gamification/` egyéb fájljai · `lib/core/**` · `backend/**` · `docs/adr/**` · `.github/**`

## 5. Kötött architekturális döntések ([ADR 0469](../adr/0469-outbox-idempotency-is-measured-on-the-ledger-effect.md))

### 5.1 Az idempotencia mércéje a HATÁS, nem a hívásszám (ADR 0469 D1–D2)

A teszt a **projektált egyenleget** méri:
`ProfileProjector(curve: …, ledger: …).rebuild()` → `.profile.totalXp`
(`lib/features/gamification/application/profile_projector.dart:40`), nem azt,
hányszor hívódott egy metódus. **NEM elfogadható gyengítés:**
`verify(callCount == 1)` jellegű mock-állítás — az a dupla hatást nem zárja ki,
csak a dupla hívást ([L453](../LESSONS.md)).

Az ismétlés a VALÓDI újrapróbálkozás alakjában megy: ugyanaz a `sourceEventId`,
**eltérő `ledgerId`** (ADR 0469 D2).

### 5.2 A megszakítás UTÁNI példány a perzisztált állapotból indul (ADR 0469 D3)

A resume-cella MÁSODIK `LocalActivityOutboxRepository`-t épít UGYANARRA az
`InMemoryKeyValueStore`-ra, nem ugyanazt az objektumot folytatja; a
`_ensureLoaded()` (`local_activity_outbox_repository.dart:334`) lusta olvasása
adja a folytatást. **NEM elfogadható gyengítés:** in-memory objektum
„újrahasználása" resume-ként — az a folyamat-halált nem modellezi.

### 5.2.1 A sorrend-függetlenség a ledgeren mérendő, nem a streaken (ADR 0469 D4)

**MÉRT (pre-flight R3):** a `StreakService`-nek nincs hívója a `lib/` fán, és az
outbox soha nem hívja. Az out-of-order cella ezért azt méri, hogy a fordított
sorrendben feldolgozott két esemény UGYANAZT a ledger-tartalmat és UGYANAZT a
`totalXp`-t adja, mint a sorrendhelyes futás, minden `sourceEventId` pontosan
egyszer. **NEM elfogadható gyengítés:** a `StreakService` közvetlen, outboxtól
független hívása „streak-bizonyítékként" — az nem ezen a láncon mér.

### 5.3 Piros cella esetén a javítás a MEGLÉVŐ osztályban történik (ADR 0469 D6)

**NEM elfogadható gyengítés:** párhuzamos, „tisztább" dispatcher bevezetése a hiba megkerülésére — a repó mért tanulsága szerint két igazság drágább, mint egy javítás.

## 6. Acceptance criteria

Minden cella az **egyenleget** méri (§5.1), és minden `expect` ELŐTT álljon a
kritikus állítás — a bukó `expect` utáni sorok soha nem futnak le
([L441](../LESSONS.md)).

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ugyanaz a `sourceEventId` **100** ismétléssel (eltérő `ledgerId`-kkel) → `ProfileProjector.rebuild().profile.totalXp` pontosan EGY bejegyzés `totalXp`-je | `idempotency_test.dart` |
| A1b | Ugyanez a 100 ismétlés **enqueue→drain** párokban (nem egy batch drainben) → ugyanaz az egyenleg; a második ismétléstől az `enqueue` `accepted == false`, `supersededByLedger` karanténnal | `idempotency_test.dart` |
| A2 | Drain közepén megszakított folyamat után **MÁSODIK** `LocalActivityOutboxRepository` UGYANARRA a store-ra folytatja: a pending rekord előkerül, a drain befejezi, és az egyenleg egyszeres | `outbox_resume_test.dart` |
| A3 | Out-of-order beérkezés (a KÉSŐBBI `epochDay`/`occurredAt` esemény drainelődik ELŐBB) ugyanazt a ledger-tartalmat és ugyanazt a `totalXp`-t adja, mint a sorrendhelyes futás; minden `sourceEventId` pontosan egyszer szerepel, és mindkét esemény `epochDay`-e változatlanul éli túl a perzisztált fordulót | `outbox_resume_test.dart` |
| A4 | Sikertelen ledger-hívás (dobó `appendIfAbsent`) NEM dob át a drain határán, és NEM görgeti vissza a lokális állapotot: a rekord PENDING marad, a következő, egészséges drain befejezi — az egyenleg ekkor is egyszeres | `outbox_resume_test.dart` |
| A5 | A `maxAttempts` elérésekor a rekord karanténba kerül (`attemptLimitReached`), és a sor **tovább dolgozik**: egy mögötte álló, egészséges rekord UGYANABBAN a drain-passzban ack-elődik | `outbox_resume_test.dart` |
| A6 | `docs/contracts/event-catalog.md` „Idempotencia" szakasza a kör MÉRT outbox-invariánsaival bővül, invariánsonként a mérő cella nevével | `docs/contracts/event-catalog.md` + a §7 gate |

**Küszöb-cellahármas a `maxAttempts`-ra — a DRAIN ELŐTTI, PERZISZTÁLT `attempts`
mezőn** (MÉRT, pre-flight R2: a számláló a ledger-hívás ELŐTT nő,
`local_activity_outbox_repository.dart:243`, a feltétel `>= maxAttempts`, `:286`).
A cellák `maxAttempts = 3`-mal, `python3 -c` számolással:

| Cella | Perzisztált `attempts` a drain előtt | A drain utáni számláló | Elvárt kimenet |
|---|---|---|---|
| **alatta** | `maxAttempts - 2 = 1` | `2` (`2 < 3`) | a rekord PENDING marad, az id a `report.dropped` listán van, `report.quarantined` üres |
| **rajta** | `maxAttempts - 1 = 2` | `3` (`3 >= 3`) | KARANTÉN `ActivityOutboxOutcome.attemptLimitReached`-csel, a rekord kikerül a pendingből |
| **fölötte** | ugyanarra a `sourceEventId`-re adott ÚJABB `enqueue` a karantén után (a ledger továbbra sem ismeri: `hasProcessedEvent == false`, `:153`) | a friss rekord `attempts = 0` | `accepted == true`, a sor tovább dolgozik, ez az `enqueue` NEM termel új karantén-bejegyzést |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az idempotencia-kulcs az esemény TARTALMÁBÓL vagy a `ledgerId`-ből hasholódik `sourceEventId` helyett | **A1** (ezért ismétel eltérő `ledgerId`-vel) |
| A drain csak a hívásszámot védi, a hatást nem (dupla `append` ugyanarra az eseményre) | **A1**, **A1b** (egyenleg-mérés) |
| A resume in-memory állapotból indul, a perzisztált sor nem olvasódik vissza | **A2** |
| A feldolgozás sorrend-függő (a későbbi esemény felülírja vagy elnyeli a korábbit) | **A3** |
| A ledger-kivétel átdob a drain határán, vagy visszagörgeti a pending rekordot | **A4** |
| A karantén a teljes sort megállítja (a mögötte álló rekord nem ack-elődik) | **A5** |
| A `maxAttempts` feltétel `>=` helyett `>` (egy kísérlettel későbbi karantén) | a küszöb-hármas **„rajta"** cellája |
| A számláló a ledger-hívás UTÁN nő (egy kísérlettel későbbi karantén) | a küszöb-hármas **„rajta"** cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** a
`local_activity_outbox_repository.dart:249` `appendIfAbsent` hívása helyett hívd
a ledger feltétel nélküli append-jét (vagy töröld a `:276` `hasProcessedEvent`
ack-ágát úgy, hogy a duplikátum újra appendelődjön), futtasd a §7 gate-et → az
**A1** cellának PIROSNAK kell lennie a MÉRT egyenleg miatt → állítsd vissza, és
a §10-ben idézd a piros kimenet sorát.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/events/idempotency_test.dart test/core/events/outbox_resume_test.dart test/core/events/event_schema_compatibility_test.dart
```

A gamification meglévő cellái regresszió-őrként (külön hívás, nem lánc):

```bash
tools/round-gate.sh test/features/gamification/
```

## 8. Implementációs sorrend

1. `idempotency_test.dart` — A1 (batch) és A1b (enqueue→drain párok), egyenleg-méréssel (RED vagy zöld: MÉRÉS). A `_Fixture`/`_FakeRewardLedger` mintát a `test/features/gamification/application/activity_ingestor_test.dart:521–608`-ból vedd át; új mock-ledger tilos.
2. `outbox_resume_test.dart` — A2 resume (MÁSODIK repository-példány), A3 out-of-order, A4 hibatűrés, A5 karantén-továbbdolgozás, és a küszöb-cellahármas (`maxAttempts = 3`).
3. Csak MÉRT piros cellára: javítás a két engedélyezett `lib/` fájlban, a MEGLÉVŐ osztályban (§5.3).
4. A katalógus „Idempotencia" szakaszának bővítése a MÉRT invariánsokkal, invariánsonként a mérő cella nevével.
5. A valódi-sértés próba a §10-be, a piros kimenet idézett sorával.

**A brief §8 a terved — nincs külön task-lista.** Doc-commentben csak tesztben
bizonyított állítás szerepeljen (`const`, `immutable`). A munkádat **commitold a
branchre**.

## 9. Kockázatok

- **Mock-alapú hamis zöld.** A hívásszám-mérés a valódi dupla hatást nem zárja ki (§5.1).
- **Párhuzamos implementáció.** Egy új `lib/core/sync/outbox/` a meglévő ADR 0333 mellé kettős igazságot teremtene (tilos zóna).
- **A community-outbox érintése.** Mérni szabad, módosítani nem — a két sor viselkedése együtt is vizsgálandó, de a javítása külön kör.

## 10. Implementation handoff — az implementer tölti ki

**Státusz: STOPPED (§0 STOP-protokoll) — §4-en KÍVÜLI fájlban élő, ezt a kört
blokkoló MÉRT hiba.**

### Amit leszállítottam

- `test/core/events/idempotency_test.dart` — **A1** (100 ismétlés egy batch
  drainben, eltérő `ledgerId`-kkel) és **A1b** (100 × enqueue→drain pár, a
  második ismétléstől `accepted == false` + `supersededByLedger`) — a §4/§8
  szerinti `_Fixture`/`_FakeRewardLedger` mintával (a
  `activity_ingestor_test.dart:521–608` mintáját véve át), KIZÁRÓLAG az ADR
  0469 D1 mérce-felületén (`ProfileProjector(...).rebuild().profile.totalXp`)
  mérve.
- `test/core/events/outbox_resume_test.dart` — **A2** (MÁSODIK
  `LocalActivityOutboxRepository` UGYANARRA az `InMemoryKeyValueStore`-ra,
  ADR 0469 D3), **A3** (a KÉSŐBBI esemény drainelődik ELŐBB — enqueue-sorrend
  fordítva —, `epochDay` túléli a perzisztált resume-fordulót, ADR 0469 D4),
  **A4** (kétszer hibázó drain nem dob át és nem görget vissza, a harmadik,
  egészséges drain zárja egyszeres egyenleggel), **A5** (a `maxAttempts`-ot
  elérő rekord karanténba kerül, a mögötte álló egészséges rekord UGYANABBAN a
  drain-passzban ack-elődik — ehhez egy `throwForSourceEventIds`
  szelektív-hiba kiegészítés kellett a `_FakeRewardLedger`-en, mert az eredeti
  `alwaysThrow` folyamat-szintű kapcsoló nem tudja EGYIDEJŰLEG megbuktatni az
  egyik és átengedni a másik rekordot ugyanabban a drain-hívásban), és a
  **küszöb-cellahármas** (`maxAttempts = 3`, a DRAIN ELŐTTI, perzisztált
  `attempts` mezőn — `alatta`/`rajta`/`fölötte`, mind a §6 táblázat szerinti
  bemenettel és elvárt kimenettel).

Mind a hét cella (A1, A1b, A2, A3, A4, A5, küszöb-hármas × 3 teszt) a brief
§5.1/§5.2/§5.2.1 kötött mérési szabályait követi: nincs `verify(callCount)`
jellegű mock-állítás, a resume MÁSODIK repository-példánnyal történik, az
out-of-order cella a ledger-tartalmon és a `totalXp`-n mér, nem a
`StreakService`-en (amelynek — újramérve — továbbra sincs hívója a `lib/`
fán: `grep -rn "StreakService(" lib/` → 0 találat).

### A blokkoló mért hiba

**`tools/round-gate.sh test/core/events/idempotency_test.dart
test/core/events/outbox_resume_test.dart
test/core/events/event_schema_compatibility_test.dart`** — `format`: ZÖLD,
`analyze`: ZÖLD, `test test/core/events/idempotency_test.dart`: **PIROS**
(kilépési kód 1), a gate itt megállt (a fennmaradó két teszt-célra emiatt már
nem futott le újra ezen a hívási sorozaton — lásd lent, ugyanaz a hiba
mindhármat blokkolja).

A tényleges piros kimenet (csonkítatlan, a fenti gate-hívásból):

```
00:00 +0 -1: A1 — 100 repeats of one sourceEventId, single batch drain the projected balance reflects exactly one ledger effect even though every repeat carries a distinct ledgerId [E]
  Bad state: ledger page cursor did not advance
  package:strumsight/features/gamification/application/profile_projector.dart 49:9  ProfileProjector.rebuild
  test/core/events/idempotency_test.dart 106:5                                      _totalXp
  test/core/events/idempotency_test.dart 44:29                                      main.<fn>.<fn>

00:00 +0 -2: A1b — 100 repeats as enqueue -> drain pairs from the second repeat, enqueue is rejected as superseded-by-ledger and the projected balance never grows past the first effect [E]
  Bad state: ledger page cursor did not advance
  package:strumsight/features/gamification/application/profile_projector.dart 49:9  ProfileProjector.rebuild
  test/core/events/idempotency_test.dart 106:5                                      _totalXp
  test/core/events/idempotency_test.dart 91:31                                      main.<fn>.<fn>
```

**Gyökér-ok (`lib/features/gamification/application/profile_projector.dart:48–49`,
NEM az engedélyezett két lib-fájl egyikében):**

```dart
if (page.entries.isNotEmpty && page.nextCursor == cursor) {
  throw StateError('ledger page cursor did not advance');
}
```

Ez a stall-guard MÁR volt egyszer hibás — [`docs/LESSONS.md` L349](../LESSONS.md)
(E08-R07, review F1, javítás `be823c74`) pontosan ezt a `do { … } while
(cursor != null)` mintát írja le: az ELSŐ hívásnál `cursor == null`, és egy
olyan oldalnál, ami maga a lapozás UTOLSÓ (egyben egyetlen) oldala,
`page.nextCursor` is `null` lesz — a guard ezt tévesen "a lapozás nem
haladt" hibaként azonosítja, holott ez a normál, egy-oldalas befejezés jele.
Az L349 fixe (`page.entries.isEmpty` ághoz `page.entries.isNotEmpty &&`
feltételt adott) **csak az ÜRES ledger esetét zárta le** — a `rebuild()`
most már nem dob egy vadonatúj, 0 bejegyzésű ledgeren. A jelenlegi kör
pre-flightjában és brief §5.1-ében mért/elvárt eset viszont egy **1–2
bejegyzésű, NEM üres** ledger (pontosan az idempotencia-cellák elvárt
végállapota — egyetlen ledger-hatás sok ismétlés után), és erre a guard
VÁLTOZATLANUL hibásan dob, mert `page.entries.isNotEmpty` igaz ÉS
`page.nextCursor (null) == cursor (null)` is igaz az ELSŐ (és egyetlen)
lapozó híváson, ha a teljes ledger-tartalom befér egy oldalba (ami
`pageSize`-tól függetlenül MINDIG így van egyetlen bejegyzésnél — lásd lent).

**Miért nem kerülhető meg a §4 engedélyezett fájljain belül:** a hiba
kizárólag attól függ, hogy a ledger teljes tartalma befér-e EGY oldalba —
ez `pageSize`-tól függetlenül mindig igaz egyetlen bejegyzésnél (pl.
`pageSize: 1` esetén is: az egyetlen bejegyzés lapja egyszerre az első ÉS az
utolsó oldal, a bemenő `cursor` és a kimenő `nextCursor` is `null` marad).
A kör MINDEN acceptance-cellája (A1, A1b, A2, A4, A5, a küszöb-hármas) egy
1 bejegyzésű ledgerrel zár, az A3 pedig 2 bejegyzésűvel — mindegyik egyetlen,
alapértelmezett (`pageSize: 100`) oldalba fér. A mérce-felület
(`ProfileProjector.rebuild().profile.totalXp`) ADR 0469 D1 szerint KÖTELEZŐ —
egy másik mérési út bevezetése tiltott gyengítés lenne. A hibás sor
(`profile_projector.dart:49`) a §4 engedélyezett listáján kívül él (a lista
csak `activity_event_ingestor.dart`-ot és
`local_activity_outbox_repository.dart`-ot engedi) — ez pontosan a §0
STOP-protokoll által megnevezett eset ("MÉRT hiba, ami a §4-en KÍVÜLI
fájlban él").

### Amit emiatt NEM végeztem el

- A §8.3 lépést (javítás a két engedélyezett `lib/` fájlban) — a mért piros
  cellák egyike sem az `activity_event_ingestor.dart` vagy a
  `local_activity_outbox_repository.dart` hibájára vezethető vissza; mindkét
  fájl viselkedése a blokkoló hibáig pontosan a pre-flight §2 táblázatában
  mért módon fut (ez a `_totalXp` helper hívási láncából is látszik: a hiba a
  `ProfileProjector.rebuild()`-ben dob, az outbox/ingestor már lezajlott,
  hiba nélkül).
- A §8.4 lépést (`docs/contracts/event-catalog.md` „Idempotencia" szakaszának
  bővítése) — a brief kifejezetten "a kör MÉRT outbox-invariánsaival,
  invariánsonként a mérő cella nevével" kéri; mérő cella nélkül (mind piros)
  ez a szakasz bizonyítatlan állítást tartalmazna, ami a projekt saját
  doc-comment szabályát sértené ("csak tesztben bizonyított állítás").
- A §7 "gamification meglévő cellái regresszió-őrként" külön gate-hívást és a
  §6.1 kötelező valódi-sértés próbát — mindkettő csak egy már zöld
  alapállapot felett értelmezhető; a próba a MÁR piros A1 cellát nem tudja
  új információval szolgálni.

### Javaslat a következő körnek

A guard javítása (`profile_projector.dart:48`) minimálisan: a stall csak
akkor valódi hiba, ha egy KORÁBBAN MÁR NEM NULL cursor nem haladt —
`if (cursor != null && page.entries.isNotEmpty && page.nextCursor == cursor)`.
Ez a fix a §4 listáján kívül esik, tehát egy másik SDD-kör (vagy ennek a
körnek egy bővített allowed-files-szal újraindított változata) feladata. A
két itt leszállított teszt-fájl változtatás nélkül újrafuttatható a fix után
— ezek MÁR a teljes, brief §6 szerinti cellakészletet implementálják.

## 11. Review — a Claude tölti ki
