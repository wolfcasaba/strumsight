# E08-R16 — Security review

Brief: `docs/rounds/e08-r16-quest-domain-objective-and-lifecycle.md`
Reviewed commit: `8085a3b00846`
Reviewer: independent Codex Sol security reviewer · Dátum: 2026-08-21
Verdikt: **PASS**

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

A review nem talált secret-, privacy-, hálózati vagy tiltott import problémát.
A Terra `8085a3b0` javítása lezárta a persisted quest progress két trust-boundary
leletét és az instance identity ütközését.

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
- **Státusz:** FIXED (`8085a3b0`) — exact instance-derived ID ellenőrzés és
  hamis persisted ID negatív cella.

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
- **Státusz:** FIXED (`8085a3b0`) — `completionAt < expiresAt` validáció
  completed és archived-completed rekordokra, határ/utána negatív cellával.

## Ellenőrzések

- Izolált reviewer-klónban round-gate: **6/6 zöld**.
- Scope audit: **OK**, 7 változott útvonal, 0 sértés.
- Secret scan: **0 lelet**.
- Import boundary: tiszta. Eldobható Flutter-import mutációt az
  `architecture_dependency_test.dart` pirosra vitt; restore után zöld.

## Merge-döntés

Security/privacy szempontból **PASS**. Merge csak a correctness approval és a
friss exact-SHA CI-k után engedett.
