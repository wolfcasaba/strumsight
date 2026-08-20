# ADR 0333 — Activity outbox: megbízható, korlátos feldolgozás

- **Státusz:** elfogadva
- **Dátum:** 2026-08-19
- **Kör:** `E08-R04` (Chapter 9, Kör 4)
- **Kapcsolódó:** [`0301`](0301-reward-ledger-append-only-idempotency.md),
  [`0329`](0329-canonical-activity-event-contracts.md)

## Kontextus

Az R02 kanonikus eseménye stabil, hívó-adta `eventId`-t ad, az R03 pedig
`RewardLedgerRepository.appendIfAbsent(RewardLedgerEntry)` atomikus írását.
A kettő között nincs még policy: a `RewardLedgerEntry` kötelező XP-, policy- és
okmezői nem származtathatók az eseményből anélkül, hogy a Kör 5 reward
eligibility/policy döntését előrehoznánk. A session-eredménynek ugyanakkor
nem szabad egy hibás reward-írás miatt elvesznie.

## Döntés

1. **Az ingestor csak kész reward-műveletet továbbít.** Enqueue-kor a hívó egy
   `LearningActivityEvent`-et és egy kész `RewardLedgerEntry`-t ad. Az
   `entry.sourceEventId` pontosan az `event.eventId`; eltérés fail-fast
   argument error. Az ingestor nem állít elő XP-t, policy-verziót, okkódot,
   órát vagy azonosítót. A policy előállítója később az R05 lesz.

2. **A feature saját mentése megelőzi az API-hívást.** Az API neve és
   dokumentációja `recordSavedActivity`: ezt a feature csak a saját tartós
   session-eredményének sikeres mentése után hívhatja. E kör nem köt be
   feature-t, nem vezet be cross-feature tranzakciót és nem ad callbacket,
   amely a mentési sorrendet megfordíthatná.

3. **A pending rekord nyers esemény- és ledger-JSON-t tárol.** Drainkor mindkét
   oldalt dekódolja. Ismeretlen schema, hibás JSON vagy az ID-invariáns
   megsértése karanténba kerül az eredeti nyers adattal; a következő rekord
   feldolgozható marad. A karantén az `ActivityOutboxRepository`-n keresztül
   lekérdezhető, de ebben a körben nincs diagnostics UI/provider integráció.

4. **Ack csak sikeres ledger-hívás után.** Egy `appendIfAbsent` `true` vagy
   `false` eredménye sikeres feldolgozás: a `false` már feldolgozott,
   idempotens ismétlés. Kivétel esetén a pending rekord marad, a kísérletszám
   nő. A drain egy hibát nem dob tovább a sessionhez.

5. **A korlát és retry explicit konstruktorparaméter.** `capacity` és
   `maxAttempts` pozitív egész. A pending sor legfeljebb `capacity` rekordos;
   `capacity + 1`-edik enqueuekor a legrégebbi pending rekord karanténba kerül,
   az új rekord pedig pending marad. Amikor egy feldolgozási hiba után a
   `attemptCount` eléri a `maxAttempts` értéket, a rekord karanténba kerül.
   Nincs háttérciklus: app-start és explicit `drain()` a hívó által vezérelt.

6. **A lokális tárolás R03 mintáját követi.** Az implementáció explicit
   `KeyValueStore` és `AppLogger` függőséget kap és a `JsonDocumentStore`
   whole-document envelope-ját használja. Ez nem a ledger cap-nélkülisége:
   itt a pending sor tudatosan korlátos, de a kiszorított rekord megmarad a
   karanténban.

## Következmények

Az R04 megbízhatóan továbbít egy már definiált reward-műveletet, de nem válik
XP-policyvé. A feature-ek később csak a saját mentésük UTÁN hívhatják; a
ledger-írás hibája így nem módosítja a session sikerét. A repository queue- és
karantén-állapota diagnosztikailag lekérdezhető, miközben nincs új hálózati,
UI- vagy platform-erőforrás tulajdonlás.

## Mérce

Az E08-R04 brief A1–A8 cellái. A kötelező valódi-sértés próba ideiglenesen a
ledger-írás elé tett ack; A4-nek pirosra kell váltania, majd a visszaállítás
után a célzott gate zöld.
