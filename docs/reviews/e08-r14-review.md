# E08-R14 — Review

Brief: `docs/rounds/e08-r14-achievement-evaluator-and-projection.md`  
Diff: `e5669f20...997a52a0`  
Reviewer: Codex / `gpt-5.6-sol` · Dátum: 2026-08-21  
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 2 · MAJOR: 4 · MINOR: 0 · NOTE: 1

A merge tilos. A célzott implementer-suite és a független round-gate zöld,
de négy eldobható reviewer-cella 4/4 piros lett: konkurens dupla receipt,
idegen prefix receiptből hamis unlock, replay eventtel felfújt count és hibás
catalog-version. A külön security review ugyanazt a két BLOCKER-t találta.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Event replay idempotens progress | ❌ | reviewer-cella: ugyanaz az `eventId` kétszer → várt 0.5, tényleges 1.0 |
| A2 | Restart és concurrency mellett egyszeri unlock | ❌ | reviewer `Future.wait`: 2 külön trigger → 2 receipt |
| A3 | Stabil event timestamp | ⚠️ | normál rebuild-cella zöld; unsorted/future history nincs őrizve |
| A4 | Rebuild + catalog version | ❌ | `contentVersion=7`, tényleges progress version 1 |
| A5 | Event kind + metric/dimension index | ❌ | `AchievementIndex` csak event-kind mapet hordoz |
| A6 | Unknown objective fail-closed | ✅ | célzott A6 cella zöld |
| A7 | Hiteles, exact achievement receipt | ❌ | idegen prefix entry completionnek számít |
| A8 | Bounded backfill | ❌ | régi event kizárt; future, darabszám és lineáris munka nincs őrizve |

## Scope-audit és jelzés

`python3 tools/scope-audit.py --repo /home/ubuntu/ss-terra-e08-r14 --brief
docs/rounds/e08-r14-achievement-evaluator-and-projection.md --base e5669f20`:

```text
Legacy scope audit OK (e5669f2055f3..997a52a0176d, 5 changed path(s), 0 generated/ignored)
```

A wrapper `status=done`, `continuations=0`, `scope_audit=ok`. A jelzett
`dirty_files=1` kivizsgálásakor a `git status --short` üres volt; minden
implementációs változás a `997a52a0` commitban van. A `gate_shape=VIOLATION`
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
- **Státusz:** OPEN.

### F2 — BLOCKER — Prefix-egyező idegen ledger entry hamis completion

- **Fájl:** `lib/features/gamification/application/achievement_evaluator.dart:223-230,274-287`
- **Probléma:** `_receiptFor` bármely `achievement:<id>:` prefixű sort elfogad,
  reason, XP és ledger-ID integritás ellenőrzése nélkül, még a state threshold
  vizsgálata előtt.
- **Bizonyíték:** reviewer egy `baseExperience` reasonű prefix sort seedelt;
  várt valódi unlock, tényleges `unlocked=[]` és a hamis timestamp kötődött.
- **Kötelező javítás:** exact source ID + teljes receipt-shape validáció;
  ütközés typed fail-closed diagnostic, nem completion.
- **Státusz:** OPEN.

### F3 — MAJOR — Replay event felfújja a count és sequence progresszt

- **Fájl:** `lib/features/gamification/application/achievement_evaluator.dart:336-340,396-407`
- **Probléma:** a history nyers lista-előfordulást számol, stabil event ID
  szerint nem deduplikál.
- **Bizonyíték:** `[sameEvent, sameEvent]`, target 2 → várt 0.5 és nincs unlock,
  tényleges 1.0 és unlock.
- **Kötelező javítás:** exact replay dedup; azonos ID/eltérő payload fail-closed;
  count és repeated-kind sequence regressziós cella.
- **Státusz:** OPEN.

### F4 — MAJOR — A progress definícióverziót ír catalog-version helyett

- **Fájl:** `lib/features/gamification/application/achievement_evaluator.dart:291-302`
- **Probléma:** `_progress` a `definition.version` értéket adja a név szerint
  `catalogVersion` mezőnek.
- **Bizonyíték:** catalog contentVersion 7 + definition version 1 → tényleges 1.
- **Kötelező javítás:** minden incremental/rebuild progress a catalog
  `contentVersion` értékét hordozza; különböző verziós cella.
- **Státusz:** OPEN.

### F5 — MAJOR — A bounded backfill csak alsó időhatárt őriz

- **Fájl:** `lib/features/gamification/application/achievement_evaluator.dart:127-200`
- **Probléma:** anchor utáni event átjut; a caller-sorrend határozza meg az
  első completiont; nincs darabszám-hard-cap. A rebuild növekvő prefixeket
  másol és újraértékel, majd objective-enként újra végiglapozza a ledgert.
- **Kötelező javítás:** future event kizárás/diagnosztika, determinisztikus
  időrend, 10 000-es hard cap (9 999/10 000/10 001), lineáris history pass és
  egyszeri receipt-index.
- **Státusz:** OPEN.

### F6 — MAJOR — Az index nem teljesíti az event kind + metric szerződést

- **Fájl:** `lib/features/gamification/application/achievement_index.dart:14-41`
- **Probléma:** csak `Map<AchievementEventKind,...>` épül; metric/dimension
  kulcs vagy objective-ref nincs, miközben ADR 0377 D2 ezt kötötten előírja.
- **Kötelező javítás:** típusos event-kind + metric/dimension kulcs és olyan
  regressziós cella, amely azonos event kind mellett két eltérő metric útját
  külön méri.
- **Státusz:** OPEN.

### N1 — NOTE — Az első reviewer-gate rossz CWD-ből indult

Az abszolút review-scriptet először a közös repo CWD-jéből hívtam, ezért ott
kereste a nem merge-elt tesztet és `Does not exist` hibát adott. Az izolált
klón CWD-jéből megismételt exact gate 6/6 zöld; az első hívás orchestrátor-
invokációs hiba, nem köri kódhiba és nem CI-attempt.

## Gate-bizonyíték

Izolált klón: `/tmp/review-e08-r14-sol-b4Wsif`.

| Gate | Eredmény |
|---|---|
| scope-audit | OK, 5/5 allowed |
| format | 1735 fájl, 0 változás |
| analyze | No issues found |
| célzott teszt | 9/9 zöld |
| architecture | OK, 12 allowlisted deviation |
| secrets | 3114 fájl, 0 finding |
| l10n | 1503 message parity |
| reviewer próbák | 4/4 szándékosan piros a fenti eltérésekkel |

## Merge-döntés

Az ADR 0052 szerint merge tilos: két BLOCKER és négy MAJOR nyitott. Ugyanaz a
Terra motor kap egy javító kört a fenti exact leletlistával; utána friss,
izolált re-review és security re-review kötelező.
