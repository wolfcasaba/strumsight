# E08-R14 — Review

Brief: `docs/rounds/e08-r14-achievement-evaluator-and-projection.md`  
Diff: `77a0c11f...ae703918`
Reviewer: Codex / `gpt-5.6-sol` · Dátum: 2026-08-21  
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

A H4 self-heal az F7/S6 leletet tartós 9 999/10 000/10 001 nyers-backfill
regresszióval lezárta. Az exact `ae703918` commit független, eldobható klónban
futtatott scope-auditja zöld, a round-gate 6/6 zöld, és a nyers input őrének
eltávolítása az új A8 cellát célzottan pirosra váltja. F1–F7 és S1–S6 zárt;
új correctness lelet nincs.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Event replay idempotens progress | ✅ | célzott replay + conflicting-payload cellák zöldek |
| A2 | Restart és concurrency mellett egyszeri unlock | ✅ | exact-source `Future.wait` cella egy receiptet mér |
| A3 | Stabil event timestamp | ✅ | rendezett rebuild + future-exclusion cellák zöldek |
| A4 | Rebuild + catalog version | ✅ | `contentVersion=7` regressziós cella zöld |
| A5 | Event kind + metric/dimension index | ✅ | típusos metric/dimension index-cellák zöldek |
| A6 | Unknown objective fail-closed | ✅ | célzott A6 cella zöld |
| A7 | Hiteles, exact achievement receipt | ✅ | exact receipt + forged-prefix fail-closed cellák zöldek |
| A8 | Bounded backfill | ✅ | 9 999/10 000 lejárt nyers event elfogadott; 10 001 a dátumszűrés előtt `ArgumentError` |

## Scope-audit és jelzés

`python3 tools/scope-audit.py --repo . --brief
docs/rounds/e08-r14-achievement-evaluator-and-projection.md --base 89e38bdf` az
exact `ae703918` detached review-klónban:

```text
Legacy scope audit OK (89e38bdf...ae703918, 2 changed path(s), 0 generated/ignored)
```

A javító wrapper `status=done`, `continuations=0`, `scope_audit=ok`. A jelzett
`dirty_files=1` kivizsgálásakor a `git status --short` üres volt; minden
javítás a `11fb1ac2` és `6bec75b0` commitokban van. A `gate_shape=VIOLATION`
hamis pozitív: a log tényleges invokációja kétszer exact
`/bin/bash -lc 'tools/round-gate.sh test/features/gamification/application/achievement_evaluator_test.dart'`,
pipe és kézi lánc nélkül; a prompt/preambulum idézett tiltásaira illeszkedett.

## Megállapítások

### F1 — BLOCKER — A kompozit source ID konkurens dupla unlockot enged

- **Fájl:** `lib/features/gamification/application/achievement_evaluator.dart:223,237,304`
- **Probléma:** a lookup és append külön lépés; a dedup-kulcs tartalmazza a
  trigger event ID-t. Két párhuzamos trigger két külön kulccsal jut a
  repositoryhoz, ezért annak exact-source szerializációja mindkettőt elfogadja.
- **Bizonyíték:** eldobható `_DelayedLedger` + `Future.wait`; várt 1, tényleges
  2 `RewardLedgerEntry`.
- **Kötelező javítás:** exact `sourceEventId = achievement:<id>`, a trigger az
  egyedi `ledgerId`-ban maradjon; concurrency regressziós cella.
- **Státusz:** RESOLVED (`11fb1ac2`).

### F2 — BLOCKER — Prefix-egyező idegen ledger entry hamis completion

- **Fájl:** `lib/features/gamification/application/achievement_evaluator.dart:223-230,274-287`
- **Probléma:** `_receiptFor` bármely `achievement:<id>:` prefixű sort elfogad,
  reason, XP és ledger-ID integritás ellenőrzése nélkül, még a state threshold
  vizsgálata előtt.
- **Bizonyíték:** reviewer egy `baseExperience` reasonű prefix sort seedelt;
  várt valódi unlock, tényleges `unlocked=[]` és a hamis timestamp kötődött.
- **Kötelező javítás:** exact source ID + teljes receipt-shape validáció;
  ütközés typed fail-closed diagnostic, nem completion.
- **Státusz:** RESOLVED (`11fb1ac2`).

### F3 — MAJOR — Replay event felfújja a count és sequence progresszt

- **Fájl:** `lib/features/gamification/application/achievement_evaluator.dart:336-340,396-407`
- **Probléma:** a history nyers lista-előfordulást számol, stabil event ID
  szerint nem deduplikál.
- **Bizonyíték:** `[sameEvent, sameEvent]`, target 2 → várt 0.5 és nincs unlock,
  tényleges 1.0 és unlock.
- **Kötelező javítás:** exact replay dedup; azonos ID/eltérő payload fail-closed;
  count és repeated-kind sequence regressziós cella.
- **Státusz:** RESOLVED (`11fb1ac2`).

### F4 — MAJOR — A progress definícióverziót ír catalog-version helyett

- **Fájl:** `lib/features/gamification/application/achievement_evaluator.dart:291-302`
- **Probléma:** `_progress` a `definition.version` értéket adja a név szerint
  `catalogVersion` mezőnek.
- **Bizonyíték:** catalog contentVersion 7 + definition version 1 → tényleges 1.
- **Kötelező javítás:** minden incremental/rebuild progress a catalog
  `contentVersion` értékét hordozza; különböző verziós cella.
- **Státusz:** RESOLVED (`11fb1ac2`).

### F5 — MAJOR — A bounded backfill csak alsó időhatárt őriz

- **Fájl:** `lib/features/gamification/application/achievement_evaluator.dart:127-200`
- **Probléma:** anchor utáni event átjut; a caller-sorrend határozza meg az
  első completiont; nincs darabszám-hard-cap. A rebuild növekvő prefixeket
  másol és újraértékel, majd objective-enként újra végiglapozza a ledgert.
- **Kötelező javítás:** future event kizárás/diagnosztika, determinisztikus
  időrend, 10 000-es hard cap (9 999/10 000/10 001), lineáris history pass és
  egyszeri receipt-index.
- **Státusz:** RESOLVED (`11fb1ac2`).

### F6 — MAJOR — Az index nem teljesíti az event kind + metric szerződést

- **Fájl:** `lib/features/gamification/application/achievement_index.dart:14-41`
- **Probléma:** csak `Map<AchievementEventKind,...>` épül; metric/dimension
  kulcs vagy objective-ref nincs, miközben ADR 0377 D2 ezt kötötten előírja.
- **Kötelező javítás:** típusos event-kind + metric/dimension kulcs és olyan
  regressziós cella, amely azonos event kind mellett két eltérő metric útját
  külön méri.
- **Státusz:** RESOLVED (`11fb1ac2`).

### F7 — MAJOR — A backfill cap csak a dátumszűrés utáni listát védi

- **Fájl:** `lib/features/gamification/application/achievement_evaluator.dart:193-211,487-497`
- **Probléma:** a `backfill` előbb végigszűri a teljes caller-historyt, majd a
  `rebuild(retained)` útvonalon futtatja a 10 000-es limitet. Így tetszőleges
  méretű, ablakon kívüli nyers input átjut, noha ADR 0377 D5 és a brief A8 a
  caller snapshotot köti 10 000 elemhez.
- **Bizonyíték:** eldobható cella 10 001 egyedi, lejárt eventtel; várt
  `ArgumentError`, tényleges sikeres `AchievementEvaluationResult`.
- **Reprodukció:** a reviewer-cella neve
  `review: backfill rejects 10001 raw events before date filtering`; a célzott
  futás `Expected: throws ArgumentError`, `Actual: emitted AchievementEvaluationResult`.
- **Kötelező javítás:** a nyers `history` méretét a dátumszűrés előtt, egyszer
  és legfeljebb 10 001 elem materializálásával/őrzött iterációval ellenőrizni;
  a 9 999/10 000/10 001 hármast a `backfill` API-ra is rögzíteni.
- **Státusz:** RESOLVED (`ae703918`). A nyers iteráció számlálója a
  dátumszűrés előtt, a 10 001. elemnél áll meg. A tartós A8 cella 9 999 és
  10 000 lejárt eseményt elfogad, 10 001-et elutasít; az őr eldobható
  eltávolítása ugyanezt a cellát pirosra váltotta.

### N1 — NOTE — Az első reviewer-gate rossz CWD-ből indult

Az abszolút review-scriptet először a közös repo CWD-jéből hívtam, ezért ott
kereste a nem merge-elt tesztet és `Does not exist` hibát adott. Az izolált
klón CWD-jéből megismételt exact gate 6/6 zöld; az első hívás orchestrátor-
invokációs hiba, nem köri kódhiba és nem CI-attempt.

## Gate-bizonyíték

Izolált H4 re-review klón: `/tmp/review-e08-r14-h4-OSZvDe`, exact
`ae70391862557f06dd4264214ec74d3ad8c3620f`.

| Gate | Eredmény |
|---|---|
| scope-audit | OK, 2/2 H4 paths allowed |
| format | 1735 fájl, 0 változás |
| analyze | No issues found |
| célzott teszt | 11/11 zöld |
| architecture | OK, 12 allowlisted deviation |
| secrets | 3116 fájl, 0 finding |
| l10n | 1503 message parity |
| H4 mutációs próba | a nyers input őr eltávolításakor az új A8 cella piros; restore után 1/1 zöld és tiszta klón |

## Merge-döntés

Az F7/S6 H4 akadály lezárult, a kör branch tartalmilag review-kész. Az L304 és
L358 mért mintája szerint a fix közvetlenül a még nem merge-elt E08-R14 ágra
kerül; a következő friss kör-session feladata a szokásos PR, exact-SHA CI és
ADR 0052 szerinti zöld-kapus merge.
