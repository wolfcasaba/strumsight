# ADR 0377 — Achievement evaluator: ledgerhez kötött projekció és korlátos backfill

- **Státusz:** elfogadva (E08-R14 pre-flight)
- **Dátum:** 2026-08-21
- **Kör:** `E08-R14` — Achievement evaluator és progress projection
- **Kapcsolódó:** [`0301`](0301-reward-ledger-append-only-idempotency.md),
  [`0329`](0329-canonical-activity-event-contracts.md),
  [`0350`](0350-legacy-practice-backfill-identity-zero-xp-and-checkpoint.md),
  [`0374`](0374-achievement-domain-and-catalog-contract.md)

> **Számozási megjegyzés:** az előre írt brief `0311`-et nevezett meg, de a
> repository és az atomi foglalások már ezen túl járnak. A kötelező
> `tools/round-slots.py reserve-adr --round E08-R14` futás `0377`-et adott;
> a foglaló mért eredménye az irányadó.

## Kontextus

Az R13 zárt objective-vokabulárt szállított (`count`, `threshold`, `distinct`,
`sequence`, `compound`, valamint fail-closed unknown), de nem értékeli azokat.
Az R02 kanonikus eventje stabil `eventId`, `occurredAt`, `duration`, `score` és
`source` mezőket hordoz; az R13 XP-metrikáihoz szükséges öt XP-komponens nem
része ennek a contractnak. Az R03 ledger atomikus `appendIfAbsent` művelettel
deduplikál `sourceEventId` szerint, miközben egy ledger entry önmagában nem
őrzi a count/distinct/threshold projekció összes bemenetét.

Az R13 katalógus achievement reward-összeget sem hordoz. Az R06 policy a
tanulási activity XP-jét számolja, nem achievement-specifikus balance-ot;
ugyanakkor a zárt `RewardReason` már tartalmazza az `achievementUnlocked`
kódot. A kör nem találhat ki rejtett XP-összeget és nem vehet át activity-
history storage tulajdonlást.

## Döntés

1. **Az evaluator bemenete immutable evaluation evidence.** A contract egy
   kanonikus `LearningActivityEvent`-et hordoz. Az event kind, duration,
   score és activity source ebből származik; XP-metrika csak caller-supplied,
   típusos, véges értékként használható. Hiányzó szükséges metrika explicit
   fail-closed diagnosztika, nem implicit nulla.

2. **Az index objective-referenciát ad event kind + metric kulcson.** A count
   objective `eventCount`, a threshold a saját metrikája, a distinct az event
   kind mellett `activitySource`, a sequence az összes benne szereplő event
   kind, a compound pedig rekurzívan a gyermekei kulcsain indexelődik. Egy
   event kiértékelése csak az index által visszaadott achievementeket érinti;
   a teljes katalógus eseményenkénti scan-je tilos.

3. **A progress projekció kanonikus event-historyból épül.** Incrementális
   feldolgozás és teljes rebuild ugyanazt a tiszta redukciót használja. A
   caller adja át a rendezett event-historyt; az evaluator nem nyit activity
   repositoryt és nem kér storage lease-et. A ledger az unlock receipt és a
   stabil completion timestamp igazságforrása, de nem helyettesíti az
   event-historyt.

4. **Az unlock receipt stabil és repository-szinten idempotens.** A receipt
   `sourceEventId` és `ledgerId` értéke
   `achievement:<achievementId>:<triggerEventId>`, `createdAt` értéke a
   kiváltó event `occurredAt` értéke. Az evaluator minden unlock-kísérletet a
   `RewardLedgerRepository.appendIfAbsent` műveleten vezet át; memóriabeli
   completed-set nem lehet dedup igazságforrás.

5. **Ez a kör nulla-XP achievement receiptet ír.** Mivel nincs elfogadott
   achievement-balance contract, a receipt `baseXp=0`, `bonusXp=0`,
   `totalXp=0`, reason kódja `achievementUnlocked`, policy verziója a jelenlegi
   achievement evaluator verzió. Pozitív XP vagy új reward-típus külön,
   explicit balance-döntést igényel; ennek csendes bevezetése tilos.

6. **Completion monoton és időbélyeg-stabil.** Egyszer beállított
   `completedAt` és `rewardLedgerEntryId` nem írható át későbbi eventtel vagy
   feldolgozási órával. Rebuild ugyanahhoz az első, objektívet teljesítő
   eventhez köt.

7. **Az ismeretlen vagy mérhetetlen objective fail-closed.** Nem hoz
   progresszt vagy receiptet, és típusos diagnosztikát ad. Compound objective
   bármely unknown/missing-metric gyermeke az egész achievementet
   fail-closed állapotba viszi.

8. **A backfill caller-anchored, inkluzív és korlátos.** Az alapablak 30 nap;
   az anchor explicit UTC időpont, nem `DateTime.now()`. A cutoffon lévő event
   még feldolgozható, a cutoffnál régebbi event kimarad és számlált
   diagnosztikát ad. A 29/30/31 napos mátrix kötelező. A bemeneti history
   caller-supplied snapshot; az evaluator nem pásztáz teljes tárolót app-
   indulásonként.

## Következmények

Az incremental és rebuild eredmény determinisztikus ugyanazon event-history és
ledger mellett; restart után sem dupláz receiptet, a completion timestamp nem
driftel. Az index teljes katalógus-scan nélkül skálázódik, a bounded backfill
pedig mérhetően kizárja a régi prefixet.

Az ár az, hogy az evaluator callerének explicit XP-evidence-et és history-
snapshotot kell adnia. Az achievement unlock ebben a körben auditálható, de
nem ad pozitív XP-t; a balance későbbi, külön szerződés. Perzisztált incremental
progress repository szintén későbbi kör feladata.

## Mérce

Az E08-R14 brief A1–A8 cellái és a 29/30/31 napos inkluzív backfill-mátrix.
Kötelező mutációs próba: a repository-alapú dedupot process-local completed
setre cserélve az app-restart A2 cella piros; restore után a teljes round-gate
zöld. A reviewer külön mutatja a timestamp stabilitását és az index scan-
számlálóját is.
