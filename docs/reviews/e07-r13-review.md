# E07-R13 — Review

Brief: `docs/rounds/e07-r13-candidate-selector.md`  
Diff: `b5128132..b09cb737`  
Reviewer: Codex / gpt-5.6-terra, independent GitHub clone `/tmp/review-e07-r13-head`  
Dátum: 2026-08-16  
Verdikt: CHANGES REQUESTED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 0

Az immutable/fail-closed hard-filter és az elutasítási diagnosztika jó irány;
a teljes célzott review-gate is zöld. A selector viszont a briefben vállalt
soft-rangsor tényezőinek többségét nem implementálja, és egy publikált
policy-mező hatástalan, ezért a kör még nem merge-elhető.

## Scope és gate-bizonyíték

- `python3 tools/scope-audit.py --repo /tmp/review-e07-r13-head --brief docs/rounds/e07-r13-candidate-selector.md --base b5128132ebeb55cb2a7cb9bce493dcba4630dba6` → **OK**, 9 changed path, 0 generated/ignored.
- `tools/round-gate.sh test/features/practice_generator/candidates/candidate_selector_test.dart test/features/practice_generator/candidates/candidate_policy_test.dart` → **zöld**: format, analyze, 18 + 5 teszt, architecture, secrets, l10n.
- Valódi-sértés próba: a review-klónban a `candidate_selector.dart` hard filter `if (hardReason != null)` feltételét ideiglenesen `false &&`-ra módosítottam. Az A1 célzott teszt exit 1-gyel piros lett (a hard-avoided `practiceCatalog:rhythm.zzz` lett selected a várt `...aaa` helyett). A módosítást rögtön visszaállítottam; a review-klón tiszta.

## Acceptance criteria

| # | Állapot | Bizonyíték |
|---|---|---|
| A1 | ✅ | hard filter score előtt, review-sértés próba piros |
| A2 | ✅ | offline-unconfirmed selected/fallback kizárás; locked upstream catalog contract |
| A3 | ❌ | MAJOR R1: nincs candidate-szintű relevance modell |
| A4 | ✅ | seed alapján determinizmus, immutable output |
| A5 | ✅ | rendezett rejected list, reason/detail |
| A6 | ✅ | same-skill filter után képzett fallback |
| A7 | ✅ | recent-overuse faktor és kompozit büntetés |
| A8 | ✅ | score, majd lexical stable order; seed csak top bucket |

## Leletek

### MAJOR R1 — A selector nem teljesíti a vállalt relevance/difficulty/preference/measurability rangsort, és az `explorationWeight` hatástalan

Érintett: `lib/features/practice_generator/domain/service/candidate_selector.dart:171-180`, `:190-219`; `domain/policy/candidate_policy.dart:18-19, :57-63`.

A selector minden ugyanazt a skillt célzó candidate-nek ugyanazt a `priority.score` relevance értéket adja. A composite score egyetlen lehetséges candidate-specifikus tényezője a `recentOverusePenalty`; nincs difficulty, preference vagy measurability input/faktor, bár a brief §3 ezeket explicit scope-ként rendeli. Emiatt az A3 teszt sem eltérő relevanciát mér: `best`, `mid` és `weak` ugyanazt a priority score-t kapja, csak utóbbi kettő overuse büntetése más.

Ezen felül az `explorationWeight` konstruktorban/provenance-ban jelen van, de a selector semelyik útvonalon nem olvassa; a komment is „informational today” mezőnek nevezi. A policy értékének megváltoztatása ezért nem változtatja az explorationt, miközben a policy közvetlenül ezt ígéri.

**Javasolt irány:** az allowed model/policy/service/test útvonalakon vezess be explicit, typed candidate-szintű soft ranking inputot (difficulty, preference, measurability), dokumentált, versioned policy-súlyokkal. A `explorationWeight=0` kikapcsolt stable lexical viselkedést, pozitív érték pedig csak azonos/közeli relevance bucketben determinisztikus seed-hatást mutasson. A3 és A4 teszteknek ezt a két különböző hibás implementációt kell pirosra fogniuk.

## Merge-döntés

Nyitott MAJOR R1 miatt merge tilos. A következő javító kör ugyanazzal a MiniMax motorral fusson erre a branchre és zárja R1-et célzott tesztekkel; utána új, független review és új exact-SHA CI szükséges.
