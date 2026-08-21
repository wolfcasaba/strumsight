# E08-R16 — Quest domain, objective és életciklus — Review

Brief: `docs/rounds/e08-r16-quest-domain-objective-and-lifecycle.md`
Diff: `eff75b3bd6a7..8085a3b00846`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-21
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

A Terra javító commit (`8085a3b0`) lezárta mindkét MAJOR leletet. Az instance
identity cadence + generation epoch day + stabil definition ID összetételű;
a deszerializálás ugyanazt a receipt-ID- és expiry-invariánst ellenőrzi, mint
az élő completion. A friss izolált re-review scope-ja tiszta, a gate 6/6, a
célzott suite 10/10 zöld, és mindkét őr valódi visszarontásra piros lett.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1–A2 | Claim nélküli automatikus receipt | ✅ | A1/A2 + F1 instance-identity cella. |
| A3 | Expiry megőrzi a haladást/evidence-t | ✅ | `quest_model_test.dart` A3; `expire()` változatlanul viszi tovább a két mezőt. |
| A4–A5 | Zárt élek és reason code | ✅ | A4/A5 mátrix; undefined élek typed failure-t adnak. |
| A6 | Típusos, fail-closed objective | ✅ | A6; unknown sentinel a definitionben elutasított. |
| A7 | Schedule mezők round-tripje | ✅ | A7/A8 schedule round-trip. |
| A8 | Ismeretlen schemaVersion elutasítása | ✅ | A8 + F2 támogatott-verziós szemantikai negatív cellák. |
| A9 | Ismételt completion azonos receiptet ad | ✅ | Ugyanazon instance retry azonos; más nap/cadence eltérő. |

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
- **Státusz:** FIXED (`8085a3b0`) — két generation day és daily/weekly eltérő,
  azonos instance retry változatlan; a visszarontott identity-cella piros.

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
- **Státusz:** FIXED (`8085a3b0`) — completed és archived-completed valid
  round-trip; hamis ID és `completionAt >= expiresAt` elutasított. A validáció
  eldobható kikapcsolása az F2 cellát pirosra vitte.

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
| Célzott teszt | 10/10 zöld a javított suite-ban | ✅ |
| Architecture | OK, 12 allowlisted deviation | ✅ |
| Secret | 3152 fájl, 0 lelet | ✅ |
| L10n | EN/HU 1532 message, zöld | ✅ |
| Review negatív próbák | eredetileg 3/3 piros; javítás után F1 és F2 visszarontása külön piros | ✅ |
| CI | még nem indult a javítás előtti SHA-ra | ⏳ |

A wrapper `gate_shape=VIOLATION` mezője hamis pozitív: a naplóba beillesztett
implementer-preambulum maga tartalmazza a tiltott `| tail`/`&&` példát. A
tényleges gate-hívások a logban mind önálló
`tools/round-gate.sh test/features/gamification/domain/quest_model_test.dart`
alakúak; az izolált reviewer-gate is ugyanezzel az exact alakkal zárt 6/6
zölden.

## Merge-döntés

Correctness szempontból **APPROVED**. Az ADR 0052 szerinti merge csak a friss
review/security report commitot is tartalmazó exact-SHA Full Gate és Router CI
success után engedett.

## Re-review megjegyzés

A friss klón első gate-je az analyzer alatt 38, már generált
achievement-l10n metódust átmenetileg nem látott, miközben a generált Dart
fájlok közvetlen ellenőrzése már tartalmazta őket. Ugyanabban a tiszta klónban,
tracked módosítás nélkül megismételt exact gate 6/6 zöld lett. Ez generált
előfeltétel/analyzer cache verseny, nem a kör diffjének piros kódútja.
