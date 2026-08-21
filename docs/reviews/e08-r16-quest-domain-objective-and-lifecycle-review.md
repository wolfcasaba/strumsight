# E08-R16 — Quest domain, objective és életciklus — Review

Brief: `docs/rounds/e08-r16-quest-domain-objective-and-lifecycle.md`
Diff: `eff75b3bd6a7..c7fb235edbb7`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-21
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 0 · NOTE: 1

A formai kapuk zöldek, a scope tiszta, és az aktív állapotból induló happy
path megfelel a briefnek. Két perzisztencia-/idempotencia-hiba azonban
eldobható negatív teszttel reprodukálható: az ismétlődő quest-példányok ledger
azonosítója ütközik, illetve a persisted completed rekord hamis receipt-ID-t
és lejárati határon létrejött completiont is elfogad.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1–A2 | Claim nélküli automatikus receipt | ⚠️ részben | A happy path zöld, de F1 miatt egy későbbi napi példány receiptje ütközik. |
| A3 | Expiry megőrzi a haladást/evidence-t | ✅ | `quest_model_test.dart` A3; `expire()` változatlanul viszi tovább a két mezőt. |
| A4–A5 | Zárt élek és reason code | ✅ | A4/A5 mátrix; undefined élek typed failure-t adnak. |
| A6 | Típusos, fail-closed objective | ✅ | A6; unknown sentinel a definitionben elutasított. |
| A7 | Schedule mezők round-tripje | ✅ | A7/A8 schedule round-trip. |
| A8 | Ismeretlen schemaVersion elutasítása | ⚠️ részben | A verzió elutasított, de F2 szerint a támogatott verzió szemantikai invariánsai nem fail-closedak. |
| A9 | Ismételt completion azonos receiptet ad | ⚠️ részben | Egy példányon belül zöld; F1 szerint két külön napi példány között tévesen ugyanaz. |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e08-r16-HovgGV/repo
--brief docs/rounds/e08-r16-quest-domain-objective-and-lifecycle.md --base
eff75b3bd6a761c9dfcbfefcc4c8686f1e557db8` → **OK**, 7 változott útvonal,
0 generated/ignored, 0 sértés.

## Megállapítások

### F1 — MAJOR — A napi/heti quest-példányok ledger identityje ütközik

- **Fájl:** `lib/features/gamification/domain/quests/quest_progress.dart:110`
  és `:225–240`
- **Probléma:** a ledger ID és a `sourceEventId` kizárólag a stabil
  `QuestDefinition.id` értékéből származik. Ugyanaz a katalógus-quest második
  napon/héten új schedule-lel ugyanazt a `quest:<id>:completion` receiptet
  állítja elő.
- **Hatás:** az R03 idempotens ledger a második quest-példányt duplikátumnak
  tekintheti; a felhasználó a későbbi napi/heti jutalmát elveszíti.
- **Bizonyíték:** eldobható review-teszt két `daily_rhythm` definíciót hozott
  létre `generationEpochDay = 20686` és `20687` értékkel. Mindkét completion
  ledger ID-ja `quest:daily_rhythm:completion`, a célzott teszt piros lett:
  `Expected: not 'quest:daily_rhythm:completion'`.
- **Kötelező javítás:** vezess be stabil quest-instance identityt, amely
  legalább a definíció ID-ját és az eredeti schedule naphatárát/cadence-ét
  tartalmazza, és ebből képezd mind a ledger ID-t, mind a source event ID-t.
  Ugyanazon instance retryja maradjon azonos, eltérő instance legyen eltérő.
- **Ellenőrzés:** két külön generation day/cadence → eltérő ID; ugyanazon
  instance ismételt completion → azonos ID.
- **Státusz:** OPEN

### F2 — MAJOR — A persisted completion megkerüli a receipt- és expiry-invariánst

- **Fájl:** `lib/features/gamification/domain/quests/quest_progress.dart:183–205`
  és `:244–279`
- **Probléma:** `_validate()` csak a completion/ledger null-párt ellenőrzi.
  Nem követeli meg, hogy a `rewardLedgerId` az adott quest instance
  determinisztikus ID-ja legyen, és azt sem, hogy `completionAt < expiresAt`.
- **Hatás:** támogatott schemaVersion alatt egy manipulált vagy sérült lokális
  rekord tetszőleges ledger identityvel, illetve már lejárt quest
  completionjeként tölthető be; az idempotencia és az exkluzív expiry-határ
  csak az élő `complete()` úton érvényes.
- **Bizonyíték:** két eldobható review-cella külön-külön `throwsArgumentError`
  elvárással futott. A `rewardLedgerId = attacker-controlled-receipt` és a
  `completionAt = expiresAt` rekord is sikeresen `QuestProgress` objektummá
  dekódolódott; mindkét teszt piros lett (`Actual: returned QuestProgress`).
- **Kötelező javítás:** a konstruktor/deszerializáló ugyanazokat a szemantikai
  invariánsokat validálja, mint az élő átmenet: pontos instance-derived ledger
  ID, UTC completion és szigorúan expiry előtti idő. Archivált completed
  rekordnál ugyanez maradjon kötelező.
- **Ellenőrzés:** a két fenti negatív cella, plusz valid completed és archived
  completed teljes JSON round-trip.
- **Státusz:** OPEN

### N1 — NOTE — A következő generátorkör előtt mérni kell az objective target-alakját

Az R16 brief csak a típusos hivatkozásokat kérte, ezért ez nem blokkoló lelet.
A jelenlegi objective-ek target/threshold nélküliek, miközben az R17 „rövid”
objective-et, az R18 pedig active-day, mode-diversity és improvement targetet
kér. Az R17 pre-flightban bizonyítani kell, hogy e szerződés bővítése nélkül
ezek végrehajthatóan reprezentálhatók; ellenkező esetben a prepared R17/R18
brief scope-ja H2-t okozna.

## Gate-bizonyíték ellenőrzése

| Gate | Eredmény | Ellenőrizve |
|---|---|---|
| Scope audit | 7 changed, 0 violation | ✅ |
| Format | 1757 fájl, 0 változás | ✅ |
| Analyze | No issues found | ✅ |
| Célzott teszt | 8/8 zöld az eredeti suite-ban | ✅ |
| Architecture | OK, 12 allowlisted deviation | ✅ |
| Secret | 3152 fájl, 0 lelet | ✅ |
| L10n | EN/HU 1532 message, zöld | ✅ |
| Review negatív próbák | 3/3 célzottan piros | ✅ |
| CI | még nem indult a javítás előtti SHA-ra | ⏳ |

A wrapper `gate_shape=VIOLATION` mezője hamis pozitív: a naplóba beillesztett
implementer-preambulum maga tartalmazza a tiltott `| tail`/`&&` példát. A
tényleges gate-hívások a logban mind önálló
`tools/round-gate.sh test/features/gamification/domain/quest_model_test.dart`
alakúak; az izolált reviewer-gate is ugyanezzel az exact alakkal zárt 6/6
zölden.

## Merge-döntés

Az ADR 0052 szerint merge tilos, amíg F1 és F2 OPEN. Egy Terra javítókör
következik ugyanazon a branchen, majd friss izolált re-review és exact-SHA CI.
