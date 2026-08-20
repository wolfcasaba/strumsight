# E08-R04 — Security and product-boundary review

Brief: `docs/rounds/e08-r04-activity-outbox-and-reliable-processing.md`  
Reviewed implementation: `cb0f967b`  
Reviewer: independent security reviewer · Dátum: 2026-08-20  
Verdikt: CHANGES REQUIRED

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 3 · MINOR: 0 · NOTE: 0

Nem került a diffbe hálózati hívás, nyers audio- vagy kameraadat, illetve
érzékeny payloadot kiíró log. A scope-audit tiszta. A megbízható feldolgozás
termékhatárát viszont három tárolási/configurációs hiba sérti.

## Megállapítások

### S1 — MAJOR — Karantén restart után nem tartós

- **Fájl:** `lib/features/gamification/data/local_activity_outbox_repository.dart:330-416,432-452` (`cb0f967b`)
- **Probléma:** a betöltés nem olvasta az `activityOutboxQuarantineKey`-t,
  ezért a következő mentés felülírhatta a korábbi memórián kívüli karantént.
- **Státusz:** a MiniMax F1 javítás (`1a429d72`) `_loadQuarantine` ágat és
  restart-regressziós tesztet adott; a végső re-review ezt külön ellenőrzi.

### S2 — MAJOR — Pendingből karanténba átmozgatás közben crash adatvesztést okoz

- **Fájl:** `lib/features/gamification/data/local_activity_outbox_repository.dart:164-189,215-234,281-301` (`cb0f967b`)
- **Probléma:** a rekord előbb kikerül a pending listából, majd a pending
  snapshot külön `await`-tal íródik ki; a karantén csak egy második írásban
  mentődik. A két await közti crash után a rekord egyik tartós állapotban sincs.
- **Hatás:** sérül az "never deleted / no data loss" és az A2/A5/A7/A8
  szerződés.
- **Kötelező javítás:** pending és quarantine atomikus, ugyanazon
  crash-safe document-snapshotba kerüljön, vagy egy explicit recovery
  protokoll garantálja, hogy az átmenet bármely pontján az egyik példány
  megmarad. Adj crash-interleaving regressziós tesztet.
- **Státusz:** OPEN

### S3 — MAJOR — A kapacitás és retry-limit runtime validációja release-ben hiányzik

- **Fájl:** `lib/features/gamification/data/local_activity_outbox_repository.dart:43-54,164-166` (`cb0f967b`)
- **Probléma:** a pozitivitást csak Dart `assert` őrzi, amely release-ben nem
  fut. `capacity=0` első enqueuekor üres listán `removeAt(0)`-hoz vezet;
  `maxAttempts=0` a retry-szerződést teszi érvénytelenné.
- **Kötelező javítás:** konstruktorban runtime `ArgumentError.value`, és
  regressziós teszt assertion-mentes szemantikára.
- **Státusz:** OPEN

## Merge-döntés

S2 és S3 nyitott MAJOR, ezért a merge tilos. Az első MiniMax javító kör már
lefutott; a következő javítást a motor-eszkaláció szerint Codex/Terra végzi.
