# E08-R06 — Review

Brief: `docs/rounds/e08-r06-xp-policy-engine-and-diminishing-returns.md`  
Diff: `origin/main...minimax/e08-r06-xp-policy-engine-and-diminishing-returns`  
Reviewer: Codex / gpt-5.6-terra  
Dátum: 2026-08-20  
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

Az F1 javítás után a history külön, tényleges `rewardedEventIds` készletet
hordoz. A gyermek-event újraküldését mérő A5 regressziós cella zöld, és a
mutált dedup-ág ezt bizonyíthatóan pirosra váltja.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Öt XP-komponens | ✅ | `experience_points.dart`, A1 tesztek |
| A2 | Kezdő, gyenge session base XP-t kap | ✅ | A2 teszt |
| A3 | Ismétlés csökken, receipt megmarad | ✅ | A3 tesztek |
| A4 | Daily-cap oka receiptben | ✅ | A4 küszöbhármas |
| A5 | Parent + child egyszeres jutalom | ✅ | A5 három cella + RED→GREEN mutáció |
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
- **Státusz:** FIXED (`3840cc00`)

## Javítás utáni független ellenőrzés

- Friss izolált klón: `/tmp/review-e08-r06-fix` a `3840cc00` fejen.
- Baseline: `flutter test … --plain-name 'replaying an already rewarded child event produces zero XP'` → zöld.
- Valódi-sértés próba: az `_dedup` `history.rewardedEventIds.contains(request.eventId)` kifejezése ideiglenesen `false`; ugyanaz a teszt → `Expected: <0>; Actual: <17>` (piros). Visszaállítva a klónban.
- A review-gate a friss klónban format, analyze, célzott 19/19 teszt, architecture és secret lépéseit zölden futtatta; a l10n-paritás külön, közvetlen ellenőrzése is zöld: `L10n parity OK (en → hu, 1405 message(s))`.

## Gate-bizonyíték

| Gate | Ellenőrizve |
|---|---|
| Scope-audit | ✅ |
| Izolált célzott A5 baseline | ✅ (zöld) |
| Teljes round-gate | implementer: 19/19 és mind a hat lépés zöld; reviewer: format/analyze/test/architecture/secrets + l10n újramérve |
| CI | dispatch-elendő exact SHA-n |

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. A merge továbbra is csak exact-SHA CI,
Router CI és a teljes zöld kapu után engedett.
