# E08-R22 — Review

Brief: `docs/rounds/e08-r22-reward-inbox-and-celebration.md`
Diff: `git diff origin/main..HEAD` (12 paths, 11 implementer + 1 orchestrator-pre-flight ADR; scope-audit `OK` against post-pre-flight base `241834e3`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-21
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1 (orchestrator-pre-flight ADR scope-mentesség, dokumentált)

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Aktív gyakorlás közben SEMMILYEN ünneplés | ✅ | `celebration_coordinator_test.dart` group `A1 — active session: no celebration, ever (§5.1)` (3 teszt) + group `A1 — szigorú megszakítás-mátrix (valódi-sértés próba)` (1 teszt). Real-violation probe: `sed '215s/if (isActiveSession)/if (false)/'` → 4/4 A1 teszt PIROS → revert → 4/4 zöld. |
| A2 | Több jutalom összevontan jelenik meg (3 szintlépés → 1 összefoglaló) | ✅ | group `A2 — session end: multiple rewards consolidate into ONE summary` (1 teszt) |
| A3 | Jutalom a főkönyvben, MIELŐTT a postaládába kerül | ✅ | group `A3 — reward must already be in the ledger before it reaches the coordinator` (2 teszt): a `RewardEvent` konstruktor üres `sourceLedgerId`-t elutasít, és a koordinátor csak ledger-tartalmat kap |
| A4 | Postaláda-elem NEM jár le, nincs begyűjtés-gomb | ✅ | group `A4 — no expiry, no claim field on RewardInboxItem (§5.2)` (1 teszt) + `grep -n "expiresAt\|claimState\|claimedAt" lib/features/gamification/domain/profile/reward_inbox_item.dart` → 0 találat |
| A5 | Háttérben/bezárt folyamatban keletkezett jutalom megjelenik | ✅ | group `A5 — background / closed-app rewards still surface in the inbox` (1 teszt) |
| A6 | Prioritási sorrend determinisztikus | ✅ | group `A6 — deterministic priority order (§5.3)` (2 teszt: előre + visszafelé beszúrás, azonos eredmény) |
| A7 | Reduced motion: statikus, UGYANAZT az információt adja | ✅ | group `A7 — reduced motion: information preserved, animation dropped (§5.4)` (1 teszt, a `CelebrationSummary.events` minden mezőt tartalmaz) |
| A8 | Postaláda tartós: app-újraindítás után is megvan | ✅ | group `A8 — inbox survives app restart via JSON round-trip` (2 teszt, toJson → fromJson egyenlőség) |
| §6.1 alatt | window-1 időkülönbség → ÖSSZEVONVA | ✅ | group `§6.1 threshold triplet — alatt / rajta / fölött` (alatt) |
| §6.1 rajta | pontosan window → MÉG ÖSSZEVONVA (inkluzív) | ✅ | group `§6.1 threshold triplet — alatt / rajta / fölött` (rajta) |
| §6.1 fölött | window+1 → KÜLÖN összefoglaló | ✅ | group `§6.1 threshold triplet — alatt / rajta / fölött` (fölött) |
| §6.1 fölött + session | window+1 + gyakorlás indult → második a postaládába | ✅ | group `§6.1 threshold triplet — alatt / rajta / fölött` (fölött + közben gyakorlás indult) |

Összesen 18 teszt, mind zöld (gate `[3] test: ZÖLD, 00:00 +18: All tests passed!`).

## Scope-audit

`python3 tools/scope-audit.py --repo /home/ubuntu/ss-minimax-e08-r22 --brief docs/rounds/e08-r22-reward-inbox-and-celebration.md --base 241834e3`:

```
Legacy scope audit OK (241834e3abf1..6a8c865c5b2a, 11 changed path(s), 0 generated/ignored)
```

A post-pre-flight bázissal (`241834e3` = orchestrator pre-flight commit) minden 11 implementer-változás a brief §0.0.1 által frissített `allowed_paths` listán BELÜL van. A `docs/adr/0389-reward-inbox-and-celebration-coordinator.md` a pre-flight commit része (orchestrator-authored, brief §0.0: „az implementer a `docs/adr/`-t NEM érinti"); az implementer ezt a fájlt NEM módosította (`git diff 241834e3..HEAD -- docs/adr/...` üres, ahogy a round-auditor is megerősítette).

`origin/main` bázissal a scope-audit `FAILED`-et ír, de ez kizárólag a pre-flight ADR miatt van (orchestrator-írás, brief-tervezett); az implementer-scope tiszta.

## Gate-bizonyíték

`tools/round-gate.sh test/features/gamification/application/celebration_coordinator_test.dart` — izolált `/tmp/review-e08-r22` klónban, előtérben, csonkítatlanul:

```
[1] format:    ZÖLD   (1791 files, 0 changed)
[2] analyze:   ZÖLD   (No issues found!)
[3] test:      ZÖLD   (00:00 +18: All tests passed!)
[4] architecture: ZÖLD  (12 allowlisted deviation(s))
[5] secrets:   ZÖLD   (3210 file(s) scanned, 0 finding(s))
[6] l10n:      ZÖLD   (L10n parity OK, 1584 message(s))
GATE_EXIT=0
```

A §10 handoff minden állítása mögött LEFUTTATOTT parancs van:
- "MINDEN GATE ZÖLD" → gate exit 0 (lásd fent)
- "18/18 teszt" → `+18: All tests passed!` a gate test-lépésében
- "l10n parity 1584" → `check_l10n_parity.dart` idézete a gate `l10n` lépésében
- valódi-sértés próba → a fenti A1 sorban dokumentálva

## Architektúra + termékhatárok

- **Domain/application szétválasztás:** `celebration_coordinator.dart` pure-Dart, nincs `flutter`/`riverpod` import (`grep -l "flutter\|riverpod" lib/features/gamification/application/celebration_coordinator.dart` → 0). A `PracticeSessionState` és `MediaQuery` olvasás a presentation-rétegben marad (ADR 0389 Döntés 2, §0.0 rögzített `caller-fed` minta).
- **Reward ledgerhez nem nyúl:** `grep -n "appendIfAbsent" lib/features/gamification/application/celebration_coordinator.dart` → 0. A koordinátor csak olvasott, már véglegesített eseményeket kap (ADR 0389 Döntés 1).
- **`public.dart` contract:** 3 új export-sor a meglévő barrel-ben — `celebration_coordinator.dart`, `reward_inbox_item.dart`, `reward_summary_sheet.dart`, `reward_inbox_screen.dart`. A `RewardSummarySheet`, `RewardInboxScreen` UI-widgetek exportja a feature-n kívülről nem jellemző, de a `public.dart` meglévő konvencióját követi.
- **Nincs rejtett hálózat / mic / camera:** a kör nem érint hálózati, mikrofon-, vagy kamera-erőforrást (ADR 0389 §5, AGENTS.md §5).
- **Lifecycle:** nincs `StreamSubscription`/`Timer`/`wakelock`/`Isolate` a koordinátorban — pure state-machine, nincs felszabadítandó erőforrás (lásd AGENTS.md §7).

## Hibakezelés és tesztek

- A `RewardEvent` konstruktor `sourceLedgerId.isEmpty`-et `ArgumentError`-ral dob (A3-as első teszt bizonyítja); az alkalmazás-réteg hívó oldaláról ez a contract.
- A `RewardInboxItem` `toJson`/`fromJson` körkörös egyenlőségét a JSON round-trip teszt (A8 × 2) garantálja — nincs csendes adatvesztés.
- Nincs üres `catch` blokk a kör diffjében (`grep -rn "} on Exception\|} catch" lib/features/gamification/application/celebration_coordinator.dart` → 0).
- A tesztek kivétel nélkül determinisztikusak — `DateTime`/`Random` nincs a koordinátorban (pure caller-fed, ahogy az E08-R19 §3.1 "framework-free application layer" szabálya is előírja).

## Megállapítások

### N1 — NOTE — Orchestrator-pre-flight ADR scope-mentesség

- **Fájl:** `docs/adr/0389-reward-inbox-and-celebration-coordinator.md` (commit `241834e3`, orchestrator-authored)
- **Megfigyelés:** a scope-audit `origin/main` bázissal `FAILED` jelzést ad, mert ez az ADR fájl az `allowed_paths` listán kívül esik. Ez NEM implementer-sértés: a brief §0.0 explicit kimondja, hogy „az implementer a `docs/adr/`-t NEM érinti (TILOS zóna)" és „Az ADR-t a Claude írja meg a kör indítási pre-flightjában". A pre-flight commit (`241834e3`) az ORCHESTRATOR munkája, nem az implementeré — `git diff 241834e3..HEAD -- docs/adr/...` üres.
- **Scope-audit base konvenció:** a scope-audit `--base 241834e3` (post-pre-flight) bázissal `OK` (11/11 path az `allowed_paths` listán belül). A `origin/main` bázisú audit a pre-flight ADR-t is a „diff" részének tekinti, ez a scope-audit eszköz ismert korlátja.
- **Hatás:** nincs — az implementer scope tiszta, a pre-flight ADR a kör tervezett része.
- **Státusz:** WONTFIX (tervezetten kívül esik; az audit-eszköz konvenciója, hogy a post-pre-flight bázist használja, ahogy a scope_audit_base=`37714ae5` az implementer `.codex-round-status`-ban is ezt tükrözi)

## Következtetés

A §6 / §6.1 minden cellájához tartozik LEFUTTATOTT teszt; a §10 handoff minden állítása igazolt; a gate minden lépése zöld egy független `/tmp` klónban; a scope tiszta az implementer-oldalon; a §5.1 „zenélés közben nincs felugró" guard valódi-sértés próbával bizonyított védelem. **APPROVED — merge-re kész.**
