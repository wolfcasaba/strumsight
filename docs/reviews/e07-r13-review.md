# E07-R13 — Review

Brief: `docs/rounds/e07-r13-candidate-selector.md`
Initial diff: `b5128132..b09cb737`; corrective head: `13ed7325`
Reviewer: Codex / gpt-5.6-terra, independent GitHub clones
`/tmp/review-e07-r13-head` and `/tmp/review-e07-r13-fix`
Dátum: 2026-08-16
Verdikt: APPROVED after corrective re-review

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

Az immutable/fail-closed hard-filter és az elutasítási diagnosztika jó irány;
a teljes célzott review-gate is zöld. A selector viszont a briefben vállalt
soft-rangsor tényezőinek többségét nem implementálja, és egy publikált
policy-mező hatástalan volt. A `13ed7325` javító commit typed per-candidate
ranking profile-t, három policy-súlyt és aktív `explorationWeight`-et adott;
az ismételt review minden leletet lezárt.

## Scope és gate-bizonyíték

- `python3 tools/scope-audit.py --repo /tmp/review-e07-r13-head --brief docs/rounds/e07-r13-candidate-selector.md --base b5128132ebeb55cb2a7cb9bce493dcba4630dba6` → **OK**, 9 changed path, 0 generated/ignored.
- `tools/round-gate.sh test/features/practice_generator/candidates/candidate_selector_test.dart test/features/practice_generator/candidates/candidate_policy_test.dart` → **zöld**: format, analyze, 18 + 5 teszt, architecture, secrets, l10n.
- Valódi-sértés próba: a review-klónban a `candidate_selector.dart` hard filter `if (hardReason != null)` feltételét ideiglenesen `false &&`-ra módosítottam. Az A1 célzott teszt exit 1-gyel piros lett (a hard-avoided `practiceCatalog:rhythm.zzz` lett selected a várt `...aaa` helyett). A módosítást rögtön visszaállítottam; a review-klón tiszta.

## Acceptance criteria

| # | Állapot | Bizonyíték |
|---|---|---|
| A1 | ✅ | hard filter score előtt, review-sértés próba piros |
| A2 | ✅ | offline-unconfirmed selected/fallback kizárás; locked upstream catalog contract |
| A3 | ✅ | corrective A3 cella distinct candidate-level soft relevance-et mér |
| A4 | ✅ | seed alapján determinizmus, immutable output |
| A5 | ✅ | rendezett rejected list, reason/detail |
| A6 | ✅ | same-skill filter után képzett fallback |
| A7 | ✅ | recent-overuse faktor és kompozit büntetés |
| A8 | ✅ | score, majd lexical stable order; seed csak top bucket |

## Leletek

### MAJOR R1 — FIXED a `13ed7325` corrective commitban

Érintett: `lib/features/practice_generator/domain/service/candidate_selector.dart:171-180`, `:190-219`; `domain/policy/candidate_policy.dart:18-19, :57-63`.

A selector minden ugyanazt a skillt célzó candidate-nek ugyanazt a `priority.score` relevance értéket adja. A composite score egyetlen lehetséges candidate-specifikus tényezője a `recentOverusePenalty`; nincs difficulty, preference vagy measurability input/faktor, bár a brief §3 ezeket explicit scope-ként rendeli. Emiatt az A3 teszt sem eltérő relevanciát mér: `best`, `mid` és `weak` ugyanazt a priority score-t kapja, csak utóbbi kettő overuse büntetése más.

Ezen felül az `explorationWeight` konstruktorban/provenance-ban jelen van, de a selector semelyik útvonalon nem olvassa; a komment is „informational today” mezőnek nevezi. A policy értékének megváltoztatása ezért nem változtatja az explorationt, miközben a policy közvetlenül ezt ígéri.

**Lezárási bizonyíték:** `CandidateRankingProfile` typed difficulty, preference és measurability inputot ad; a versioned policy mindhárom súlyt alkalmazza és a decision factor-listája megmutatja a hozzájárulásukat. Az `explorationWeight=0` strict lexical választást ad, pozitív érték pedig csak a `diversityWindow` top bucketjén belül enged deterministic seed permutationt. Az izolált corrective review-gate 27 selector- és 6 policy-tesztje zöld; az A3/A4 regressziós cellák ezt külön falszifikálják.

## Merge-döntés

Nincs nyitott review-lelet. Merge kizárólag a jelenlegi, review-jelentést is tartalmazó exact SHA-n zöld Full Gate és Router CI után engedett.
