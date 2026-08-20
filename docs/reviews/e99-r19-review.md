# E99-R19 — Review

Brief: `docs/rounds/e99-r19-gov-13-chain-hygiene.md`  
Diff: `f2d98204...cf368d2a`  
Reviewer: Codex (független, izolált `/tmp/review-e99-r19-cf368d2a` klón)  
Dátum: 2026-08-20  
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | D1 azonos / lemaradt / divergáló | ✅ | `test_chain_hygiene.py::MainSyncStrategyTest` és izolált git-fixtúrák |
| 2 | D1 piszkos fa változatlanul megáll | ❌ | F1: a jelen teszt nem a tényleges előfeltételt méri |
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
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` | ✅ izolált klónban 6/6 zöld |
| `python3 -m pytest tools/tests -q` | ✅ izolált klónban 640 passed, 2 skipped, 567 subtests passed |
| `python3 tools/brief-lint.py --open --level base` | ✅ nincs lelet |
| CI (full suite + property) | ⏳ dispatch-elve, exact-SHA eredményre vár |

## Merge-döntés

Az F1 MAJOR nyitott; merge tilos a javítás és az ismételt független review előtt.
