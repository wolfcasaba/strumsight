# ADR 0469 — Az outbox idempotenciáját a ledger-HATÁS méri, nem a hívásszám

- **Státusz:** elfogadva
- **Dátum:** 2026-08-28
- **Kör:** `E12-R10` (Chapter 12, Kör 10)
- **Kapcsolódó:** [`0301`](0301-reward-ledger-append-only-idempotency.md),
  [`0329`](0329-canonical-activity-event-contracts.md),
  [`0333`](0333-activity-outbox-reliable-processing.md),
  [`0468`](0468-domain-event-catalog-and-schema-registry.md)

## Kontextus

Az SDD Chapter 12 Kör 10 feladata „idempotens dispatcher és outbox". A fán ez a
mechanizmus **már él**: az [ADR 0333](0333-activity-outbox-reliable-processing.md)
óta a `LocalActivityOutboxRepository` korlátos, perzisztált sort vezet
karanténnal és kísérlet-számlálóval, a dedup pedig a
`RewardLedgerRepository.appendIfAbsent` `sourceEventId`-szűrésén fut
([ADR 0301](0301-reward-ledger-append-only-idempotency.md)).

Ami MÉRHETŐEN hiányzott, az nem mechanizmus, hanem **mérce**: a repóban egyetlen
cella sem bizonyította, hogy sok ismétlés, folyamat-megszakítás vagy
sorrend-csere mellett sem keletkezik dupla hatás. A meglévő
`test/features/gamification/application/activity_ingestor_test.dart` A1–A8
cellái komponens-szinten mérnek (egy-két esemény, jelenlét/hiány), és a
`hasProcessedEvent` / `pendingRecords()` **állapot**át nézik — nem a
felhasználó által érzékelt **egyenleget**.

A pre-flightban három állítást mértünk ki, amelyek a döntést kikényszerítették:

1. Az outbox drain egyetlen downstream-je az `appendIfAbsent`
   (`local_activity_outbox_repository.dart:249`). A ledger egyetlen
   projekciója a `ProfileProjector.rebuild()` → `GamificationProfile.totalXp`
   (`profile_projector.dart:40`).
2. A `StreakService`-nek **NINCS hívója a `lib/` fán**
   (`grep -rn "StreakService(" lib/` → 0 találat). A streak-számítás tiszta,
   hívó-vezérelt szolgáltatás, amit az outbox soha nem érint — a „streak nem
   borul" állítás ezen az úton nem mérhető.
3. A kísérlet-számláló a ledger-hívás **ELŐTT** nő
   (`local_activity_outbox_repository.dart:243`), a karantén-feltétel pedig
   `record.attempts >= maxAttempts` (`:286`). A küszöb tehát a PERZISZTÁLT,
   drain előtti számlálón `maxAttempts - 1`, nem `maxAttempts`.

## Döntés

**D1 — Az idempotencia mércéje a ledger-egyenleg.** Minden idempotencia-cella a
`RewardLedgerRepository.readPage` lapjain összegzett `totalXp`-t méri, a ledger
tartalmával (bejegyzés-darabszám `sourceEventId`-nként) együtt. Mock
hívásszám-állítás (`verify(callCount == 1)`) NEM elfogadható bizonyíték: a dupla
hívást zárja ki, a dupla hatást nem. (Precedens:
[L453](../LESSONS.md) — egy csatorna-specifikus mock csak azt az egy csatornát
bizonyítja.)

> **D1 módosítva az 1. javító körben (2026-08-28).** Az eredeti D1 a
> `ProfileProjector.rebuild()` → `profile.totalXp` felületet írta elő. Az első
> implementer-futás és az orchestrátor FÜGGETLEN próbatesztje egyaránt kimérte,
> hogy a `rebuild()` egy **nem üres, egyetlen oldalra férő** ledgeren
> `StateError: ledger page cursor did not advance`-szel dob
> (`profile_projector.dart:48–49`) — az [L349](../LESSONS.md) reziduális fele: a
> korábbi fix csak az ÜRES ledger esetét zárta, a nem üres egyoldalasnál az
> első iteráció `cursor`-a és a helyes `nextCursor: null` ugyanúgy `null == null`.
> A projector a kör tilos zónájában van, javítása külön kör dolga; a mérce
> lényege (a HATÁS, sosem a hívásszám) változatlan, csak a felület került eggyel
> közelebb a ledgerhez. Részletek és a mért kimenet: a kör-brief §0.0.0 R7.

**D2 — A dedup-kulcs a `sourceEventId`, és ezt a mérce is annak méri.** Az
ismétlés-cella ugyanazt a `sourceEventId`-t **eltérő `ledgerId`-vel** ismétli —
ez a valódi újrapróbálkozás alakja, és pontosan ez az a bemenet, ami pirosra
váltja a tartalom-hasholó vagy `ledgerId`-kulcsolt hibás implementációt.

**D3 — A resume új példány a PERZISZTÁLT állapotból.** A megszakítás utáni cella
egy MÁSODIK `LocalActivityOutboxRepository`-t épít UGYANARRA a
`KeyValueStore`-ra. In-memory objektum újrahasználása nem modellezi a
folyamat-halált, ezért nem elfogadható resume-bizonyíték. A mechanizmus, amire
ez épül: a `_ensureLoaded()` lusta, első használatkori dokumentum-olvasás
(`local_activity_outbox_repository.dart:334`).

**D4 — A sorrend-függetlenség a ledger tartalmán és az egyenlegen mérendő, nem a
streaken.** A (2) mérés miatt az „out-of-order" acceptance a mért hívási láncon
azt jelenti: a fordított sorrendben feldolgozott két esemény UGYANAZT a
ledger-tartalmat és UGYANAZT a `totalXp`-t adja, mint a sorrendhelyes futás, és
minden `sourceEventId` pontosan egyszer szerepel. Az esemény nap-hovatartozása
(`epochDay`) az eseményen utazik, és a perzisztált pending rekord
oda-vissza-fordulóját változatlanul éli túl — ezt is cella méri.

**D5 — A küszöb a drain ELŐTTI, perzisztált számlálón értendő.** A
`maxAttempts` cellahármas bemenete a persistált `attempts` mező:
`maxAttempts - 2` → a drain után PENDING marad; `maxAttempts - 1` → a drain
KARANTÉNba teszi (`attemptLimitReached`); efölött ugyanarra a `sourceEventId`-re
adott újabb `enqueue` friss, `attempts = 0` rekordként áll be, és a sor tovább
dolgozik.

**D6 — Piros cella esetén a javítás a MEGLÉVŐ osztályban történik.** Párhuzamos,
„tisztább" dispatcher bevezetése tilos: két igazság drágább, mint egy javítás
(ADR 0333 kiterjesztése, nem felváltása).

## Következmények

- A Kör 10 `lib/**` diff nélkül is teljesíthető, ha minden cella zöld — a kör
  terméke a **bizonyíték**, nem egy második mechanizmus.
- A `docs/contracts/event-catalog.md` idempotencia-szakasza a Kör 9-ben
  dokumentált `eventId`-kulcs mellé megkapja a MÉRT outbox-invariánsokat, mind
  cellára hivatkozva.
- A mock-alapú hamis zöld hibaosztályát ez az ADR normatívan zárja: a
  gamification-oldalon minden jövőbeli idempotencia-állítás egyenleg-mérés.
- Amit ez az ADR NEM dönt el: a `lib/features/community/.../community_outbox.dart`
  külön sorának viselkedése (mérni szabad, módosítani külön kör dolga).
