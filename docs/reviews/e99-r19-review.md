# E99-R19 — Review

Brief: `docs/rounds/e99-r19-gov-13-chain-hygiene.md`
Diff: `8fb5beb5...334c5fef`
Reviewer: Codex (független, izolált `/tmp/review-e99-r19-2aba1acb` klón)
Dátum: 2026-08-20
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | D1 azonos / lemaradt / divergáló | ✅ | `test_chain_hygiene.py::MainSyncStrategyTest` és izolált git-fixtúrák |
| 2 | D1 piszkos fa változatlanul megáll | ✅ | `halt:dirty-tree`, lemaradt+piszkos izolált fixtúra |
| 3 | D2 done → nincs plusz commit; pending → fail-safe | ✅ | `PendingDoneFailSafeTest` cellák és idempotencia-próba |
| 4 | D3 S7 strict, base változatlan | ✅ | `test_brief_risk_justification.py`; izolált CLI-cella |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e99-r19-cf368d2a --brief docs/rounds/e99-r19-gov-13-chain-hygiene.md --base f62dcd41` → OK, 6 engedélyezett út, 0 generált/ignorált eltérés.

## Megállapítások

### F1 — MAJOR — A piszkos-fás D1-cella nem falszifikálja a tényleges őrt

- **Fájl:** `tools/tests/test_chain_hygiene.py:222`
- **Probléma:** `test_dirty_tree_is_stopped_above_the_main_sync_check` a
  `--main-sync-ff-merge` teszthorgot futtatja olyan fán, ahol `HEAD ==
  origin/main`. Ez a horog piszkos-fát nem vizsgál, de már az azonos HEAD
  miatt `1`-gyel tér vissza. Így a `assertNotEqual(returncode, 0)` akkor is
  zöld maradna, ha a production `git status --porcelain` előfeltétel eltűnne
  vagy a main-sync elé/után hibásan kerülne.
- **Hatás:** a brief §4 „main lemaradt, fa piszkos → megáll” elfogadási
  cellája csak deklarált, nem mért; egy későbbi regresszió tiszta-fára
  korlátozott ff-merge helyett piszkos fán is továbbléphetne.
- **Kötelező javítás:** teremts valódi lemaradt (`HEAD` az origin/main őse)
  + piszkos fás fixtúrát, és a driver/teszthorog tényleges tisztasági
  előfeltételét mérd úgy, hogy a várható hibát kifejezetten a piszkosság
  okozza. A tesztnek pirosra kell váltania, ha ez az őr kikerül.
- **Ellenőrzés:** célzott `python3 -m pytest tools/tests/test_chain_hygiene.py -q`,
  majd a teljes tooling-suite és a round gate.
- **Státusz:** FIXED (`bf497480`): a `--main-sync-ff-merge` teszthorog
  explicit piszkosfa-őrt és `halt:dirty-tree` kimenetet kapott; a javított
  fixtúra valódi lemaradást hoz létre. A reviewer ugyanazt a cellát célzottan
  újrafuttatta (`10 passed`).

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` | ✅ friss izolált klónban 6/6 zöld |
| `python3 -m pytest tools/tests -q` | ✅ friss izolált klónban 645 passed, 2 skipped, 571 subtests passed |
| `python3 tools/brief-lint.py --open --level base` | ✅ nincs lelet |
| CI (full suite + property) | ⏳ a review-záró commit exact SHA-jára dispatch-elendő |

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. Merge kizárólag a review-záró SHA exact CI
és Router CI zöld eredménye után engedett.
