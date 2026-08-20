# E08-R06 — Review

Brief: `docs/rounds/e08-r06-xp-policy-engine-and-diminishing-returns.md`  
Diff: `origin/main...minimax/e08-r06-xp-policy-engine-and-diminishing-returns`  
Reviewer: Codex / gpt-5.6-terra  
Dátum: 2026-08-20  
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 0

Az implementáció scope-a gépileg rendben van, és az A5 jelenlegi két sorrendi
tesztje zöld. Az event-ID alapú újraküldés azonban nem deduplikálódik: a
history a gyermek parent ID-ját, nem a gyermek saját event ID-ját tárolja,
miközben a policy ezt event-ID készletként olvassa.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Öt XP-komponens | ✅ | `experience_points.dart`, A1 tesztek |
| A2 | Kezdő, gyenge session base XP-t kap | ✅ | A2 teszt |
| A3 | Ismétlés csökken, receipt megmarad | ✅ | A3 tesztek |
| A4 | Daily-cap oka receiptben | ✅ | A4 küszöbhármas |
| A5 | Parent + child egyszeres jutalom | ❌ | F1 eldobható regressziós próba |
| A6 | Determinizmus | ✅ | A6 100 futás |
| A7 | Policy-verzió | ✅ | A7 teszt |
| A8 | Egy konfiguráció | ✅ | A8 tesztek |

## Scope-audit

`python3 tools/scope-audit.py --repo /home/ubuntu/ss-minimax-e08-r06 --brief docs/rounds/e08-r06-xp-policy-engine-and-diminishing-returns.md --base 923d75ef…` → `Legacy scope audit OK` (6 változott útvonal, 0 kivétel).

## Megállapítások

### F1 — MAJOR — Gyermek event újraküldése ismét XP-t kap

- **Fájl:** `lib/features/gamification/application/reward_policy_engine.dart:168-171`, `lib/features/gamification/infrastructure/default_reward_policy.dart:282-298`
- **Probléma:** `rewardedEventIds` a `rewardedParentIds` és a `rewardedChildParentIds` uniója. A második készlet a gyermek `parentEventId`-it tartja, ezért egy korábban jutalmazott `child-1` event ID nincs benne. Ugyanazzal a `child-1` és `parentEventId: session-summary-1` bemenettel a `_dedup` újra jutalmat ad.
- **Hatás:** idempotens újraküldés farmolható, megsérti az explicit event-ID szerinti dupla-jutalom tiltását és A5-öt.
- **Bizonyíték:** az izolált `/tmp/review-e08-r06` klónban ideiglenesen hozzáadott `replaying an already rewarded child event produces zero XP` A5 teszt: `Expected: <0>; Actual: <5>`.
- **Kötelező javítás:** a history contract külön, ténylegesen jutalmazott `eventId` készletet kapjon, és a dedup azzal vizsgálja a request event ID-ját. Bővítsd az A5 tesztet a gyermek-event újraküldésével; a javítás után a fenti próba zöld legyen. A parent/child kétirányú sorrendi tesztek maradjanak zöldek.
- **Státusz:** OPEN

## Gate-bizonyíték

| Gate | Ellenőrizve |
|---|---|
| Scope-audit | ✅ |
| Izolált célzott A5 baseline | ✅ (zöld) |
| Teljes round-gate | a javítás után újrafuttatandó |
| CI | javítás és review után dispatch-elendő |

## Merge-döntés

Az F1 MAJOR nyitott, ezért merge tilos. Ugyanazzal a MiniMax motorral egy
javító kör szükséges.
