# E08-R19 — Review

Brief: docs/rounds/e08-r19-challenge-v2-and-legacy-migration.md
Diff: `git diff 44ed0a50...e5ebd025` (pre-flight base → implementer HEAD)
ADR: docs/adr/0387-challenge-v2-legacy-wrap-and-single-reward-instance.md
Reviewer: Claude Sonnet 5 (`--effort high`) · Dátum: 2026-08-21
Engine: minimax (MiniMax-M3)
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Ugyanaz az epoch-nap ugyanazt a pendítés-mintát adja | ✅ | `LegacyDailyChallengeAdapter.forDay` HÍVJA `DailyChallenge.forDay`-t (`legacy_daily_challenge_adapter.dart:22`), nem reprodukálja; `daily_challenge_service_test.dart` A1 cellák zöldek (own gate run) |
| A2 | `daily_challenge_test.dart` változatlanul zöld | ✅ | önálló gate-futás: `test test/features/streak` → ZÖLD, 20/20; a fájl diffje a pre-flight base óta üres |
| A3 | Újrajátszás szabad, jutalom egyszeres | ✅ | `DailyChallengeService.complete()` mindig frissíti `completedAt`-et, de `RewardLedgerRepository.appendIfAbsent` `sourceEventId=instanceId` alapján dedupol (`daily_challenge_service.dart:447-474`, `local_reward_ledger_repository.dart:77-81`); teszt: „the reward ledger sees exactly one entry per daily instance" ZÖLD |
| A4 | Teljesítés túléli az újraindítást | ✅ | `LocalDailyChallengeCompletionStore` a `JsonDocumentStore`-on át perzisztál; teszt: „a completion survives an app restart via a fresh store instance" ZÖLD |
| A5 | Katalógus-verzió váltás nem cseréli az aznapi kihívást | ✅ | `getOrGenerateInstance`: `if (stored != null && stored.epochDay == epochDay) return stored;` — a hívó-adta `catalogVersion` figyelmen kívül marad, amíg a nap nem vált (`daily_challenge_service.dart:419-422`); teszt ZÖLD |
| A6 | Csak elérhető tartalom-azonosító | ✅ | `DailyChallengeContentCatalogSnapshot.isAvailable` szűri a generálás bemenetét (`chordChange` ≥2 akkord, egyéb típusok nem-üres lista); `strumPattern` mindig elérhető fallback — offline sosem üres a választható halmaz; 4/4 A6 teszt ZÖLD |
| A7 | Mind a négy új típus támogatott | ✅ | `DailyChallengeType` (chordChange, rhythm, songSection, timing) + `strumPattern`; „every supported type is reachable" teszt ZÖLD |
| A8 | `lib/features/streak/**` érintetlen | ✅ | `git diff 44ed0a50..e5ebd025 -- lib/features/streak/ test/features/streak/` → üres kimenet (mérve, nem csak állítva) |
| §6.1 küszöb-hármas | alatt/rajta/fölött | ✅ | 3 önálló teszt ZÖLD: „below the threshold", „on the threshold" (az ÚJ nap aktív, inkluzív), „above the threshold" |

Valódi-sértés próba (A1 real-violation, §10.2): a teszt egy szándékosan
eltérő `_BadStrumPattern` konstanst állít, és `bad.pattern == legacy.pattern`
HAMIS eredményt vár — ez bizonyítja, hogy egy másolt-és-elcsúszott generátor
az A1 cellát ténylegesen pirosra vinné. A teszt a merge után is a suite-ban
marad (ez egy védő regressziós teszt, nem eldobható próba — a brief nem írta
elő a törlését).

## Scope-audit

Hiteles eszköz: `python3 tools/scope-audit.py --repo <izolált /tmp klón>
--brief docs/rounds/e08-r19-challenge-v2-and-legacy-migration.md --base
44ed0a506b216792a422a870bcd52c8b1c948a19` →
**„Legacy scope audit OK (44ed0a50..e5ebd025, 6 changed path(s), 0
generated/ignored)"**. A 6 megváltozott útvonal pontosan a brief §4
engedélyezett listája (5 fájl) + a brief saját fájlja
(`docs/rounds/e08-r19-...md`, amit a §4 explicit felsorol) — listán kívüli
fájl nincs.

## Megállapítások

### F1 — NOTE — `RewardReason.questCompleted` mint legközelebbi illeszkedés

- **Fájl:** `lib/features/gamification/application/daily_challenge_service.dart:466`
- **Megfigyelés:** a `RewardReason` enum nem tartalmaz `dailyChallenge`
  értéket; a szolgáltatás a legközelebbi meglévőt (`questCompleted`) használja
  (a brief §10.4 pont 5 ezt dokumentálja). `reward_reason.dart` NINCS a §4
  engedélyezett listán, tehát egy új enum-érték hozzáadása scope-sértés
  (H3) lett volna — a döntés helyes ezen a körön belül.
- **Hatás:** egyetlen felhasználó-látható különbség sincs (a reward-réteg
  kvóta-kezelése nem különbözteti a reason code-ot); egy jövőbeli kör, ami a
  gamification analytics/riportolást bővíti, érdemben profitálna egy
  dedikált `dailyChallengeCompleted` reason code-ból.
- **Kötelező javítás:** nincs — nem blokkol.
- **Ellenőrzés:** —
- **Státusz:** OPEN (follow-up jelölt, nem ezen a körön)

Nincs BLOCKER/MAJOR/MINOR lelet. A generálási logika mérten a legacy
generátort HÍVJA (nem másolja), a jutalom-idempotencia és a
katalógus-verzió-pin mérten a tárolt állapoton dől el (nem csak
dokumentáció), és a `lib/features/streak/**` diffje mérten üres.

## Gate-bizonyíték ellenőrzése

Mindet ÖNÁLLÓAN futtattam, izolált klónban (`/tmp/review-e08-r19`, GitHub
originból klónozva a valódi HEAD-re, `bash tools/prepare-flutter-generated.sh`
után), NEM az implementer állítására hagyatkozva:

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | ZÖLD (1777 files, 0 changed) | ✅ saját futás |
| analyze | ZÖLD (No issues found) | ✅ saját futás |
| test daily_challenge_service_test.dart | ZÖLD (18/18) | ✅ saját futás |
| test streak | ZÖLD (20/20) | ✅ saját futás |
| architecture | ZÖLD (12 allowlisted deviation — a meglévő alapszám, nem nőtt) | ✅ saját futás |
| secrets | ZÖLD (3191 file, 0 finding) | ✅ saját futás |
| l10n | ZÖLD (en↔hu parity) | ✅ saját futás |
| CI (teljes suite + property + APK) | — | ⏳ a review UTÁN dispatch-elve (`tools/round-ci-plan.py` dönti a workflow-t) |

**Mért incidens a review során (orchestrátor-oldali, nem az implementer
hibája):** az implementer a saját munkapéldányában (`/home/ubuntu/ss-mm-
e08-r19`) commitolt, de a kör-branch csak a pre-flight commitig
(`44ed0a50`) volt push-olva `origin`-re — az implementer 5 commitja
(`ef9b5143`..`e5ebd025`) csak lokálisan létezett. Az első review-klón emiatt
a stale branch-et látta (a teszt-fájl `Does not exist`-tel bukott). A
javítás: `git push origin minimax/e08-r19-challenge-v2-and-legacy-migration`
az implementer munkapéldányából, majd újraklónozás közvetlenül
`https://github.com/wolfcasaba/strumsight.git`-ról (nem a helyi
`/home/ubuntu/music-theory`-ból, aminek volt egy elavult lokális branch-ága
ugyanezen a néven). A fenti gate-eredmények mind a PUSH UTÁNI, valódi
`e5ebd025` HEAD-en futottak.

## Merge-döntés

ADR 0052 szerint: minden önállóan futtatott gate ZÖLD, scope-audit OK, nincs
nyitott BLOCKER/MAJOR → **merge engedélyezett**, a CI-dispatch (teljes suite +
randomizált property + APK) zöldje után.
