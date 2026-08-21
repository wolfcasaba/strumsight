# E08-R16 — Security review

Brief: `docs/rounds/e08-r16-quest-domain-objective-and-lifecycle.md`
Reviewed commit: `c7fb235edbb7`
Reviewer: independent Codex Sol security reviewer · Dátum: 2026-08-21
Verdikt: **CHANGES REQUESTED**

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 2 · MINOR: 0 · NOTE: 0

A review nem talált secret-, privacy-, hálózati vagy tiltott import problémát.
A persisted quest progress trust boundary azonban két, a correctness review F2
leletével egyező MAJOR hibát tartalmaz.

## Megállapítások

### S1 — MAJOR — Manipulált persisted ledger ID újra-kibocsátható

- **Fájl:** `lib/features/gamification/domain/quests/quest_progress.dart:183–205`,
  `:225–240`
- **Bizonyíték:** eldobható probe
  `rewardLedgerId = attacker-controlled-ledger-id` értékkel sikeresen
  dekódolta a completed rekordot; a későbbi idempotens `complete()` ugyanazzal
  a manipulált ID-val adott receiptet.
- **Hatás:** a lokális persisted rekord sérülése/manipulációja megkerüli a
  determinisztikus receipt identityt és hibás ledger-bejegyzést állíthat elő.
- **Kötelező javítás:** completed és completed eredetű archived rekordnál a
  dekódolt ID pontosan egyezzen az instance-derived determinisztikus ID-val;
  eltérés fail-closed.
- **Státusz:** OPEN

### S2 — MAJOR — Lejárat utáni persisted completion receiptet ad

- **Fájl:** `lib/features/gamification/domain/quests/quest_progress.dart:87–104`,
  `:183–205`
- **Bizonyíték:** `completionAt = expiresAt + 1s` értékű completed rekord
  dekódolódott, majd egy nappal későbbi `complete()` a completed short-circuit
  ágon sikeres receiptet adott.
- **Hatás:** a persisted input megkerüli az exkluzív expiry-határt, így lejárt
  quest rewardja hitelesnek látszhat.
- **Kötelező javítás:** completed és completed eredetű archived rekord csak
  `completionAt < schedule.expiresAt` mellett érvényes; határon és utána
  `ArgumentError`.
- **Státusz:** OPEN

## Ellenőrzések

- Izolált reviewer-klónban round-gate: **6/6 zöld**.
- Scope audit: **OK**, 7 változott útvonal, 0 sértés.
- Secret scan: **0 lelet**.
- Import boundary: tiszta. Eldobható Flutter-import mutációt az
  `architecture_dependency_test.dart` pirosra vitt; restore után zöld.

## Merge-döntés

S1 és S2 zárásáig merge tilos. A correctness review F1 ismétlődő-instance
identity ütközését ugyanabban a Terra javítókörben kell rendezni.
