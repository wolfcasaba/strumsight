# E99-R08 — Review

Brief: `docs/rounds/e99-r08-gov-07-per-round-orchestrator-rotation.md`  
Diff: `origin/main...8d44ae8d`  
Reviewer: Codex / gpt-5.6-terra (a Sonnet implementertől független) · Dátum: 2026-08-13  
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 0

Az F1 és F2 javításai a diffben jelen vannak, és a kör megengedett hét
útvonalát érinti. A Router CI azonban a pontos `8d44ae8d` SHA-n piros, mert
az F1 hermetikus regressziós tesztje CI-ben a `claude` bináris hiányáig jut,
mielőtt az ágvédelmi fail-closed ágat mérhetné. Ez a kötelező Router CI-gate
és az F1 bizonyítékát is érvényteleníti.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Körönként rögzített orchestrátor, új körre léptetéssel | ✅ | `tools/tests/test_orchestrator_rotation.py`, `tools/tests/test_round_resume_independence.py` |
| 2 | Folytatáskor mért implementer-identitás és független, elérhető orchestrátor | ✅ | `tools/round-pipeline.sh`, F2 `8d44ae8d` tesztjei |
| 3 | Remote-only commitot megtagadó explicit-lease push | ✅ | `tools/safe-force-push.sh`, `tools/tests/test_safe_force_push.py` |
| 4 | H8 operátori protokoll dokumentált | ✅ | `docs/execution/pipeline-orchestrator-prompt.md` |
| 5 | Hermetikus test-mode munkafaőrzés CI-ben is mér | ❌ | F3; Router CI #31685750107 |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e99-r08-8d44ae8d --brief docs/rounds/e99-r08-gov-07-per-round-orchestrator-rotation.md --base 37d5024a`

Eredmény: `Legacy scope audit OK (37d5024a..8d44ae8da136, 7 changed path(s), 0 generated/ignored)`.

## Megállapítások

### F3 — MAJOR — A hermetikus regressziós teszt CI-ben nem a védelmi ágat méri

- **Fájl:** `tools/tests/test_round_resume_independence.py:190-200`
- **Probléma:** a fixture csak egy bare `origin`-t állít be, majd a teljes
  `round-pipeline.sh`-t indítja. A GitHub-hosted runneren nincs `claude` CLI,
  ezért a script előbb `HIBA: nincs claude CLI: claude` hibával áll meg, mint
  hogy az `PIPELINE_STATE_DIR` miatti fail-closed munkafaőrzéshez érne.
- **Hatás:** a teszt lokálisan zöld lehet egy telepített Claude CLI miatt, de
  a Router CI pontos SHA-n piros; a teszt nem bizonyítja a megcélzott F1
  viselkedést CI-ben.
- **Kötelező javítás:** a fixture/teszt környezetét egészítsd ki olyan
  determinisztikus minimális CLI-fake-kel vagy más izolált előfeltétellel,
  amely biztosítja, hogy a driver a `PIPELINE_STATE_DIR`-őrig jusson; az
  assertion maradjon a várt fail-closed üzenetre és az eredeti branchre.
  Ne kerüljön valódi CLI vagy hálózat a tesztbe.
- **Ellenőrzés:** `python3 -m pytest tools/tests -q`, majd Router CI exact
  `headSha` zöld a javító commiton.
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| scope-audit | zöld | ✅ izolált klónban |
| format/analyze/célzott Dart gate | indítva az izolált klónban | ⏳ a futás befejező kimenete nem állt rendelkezésre ebben a review-iterációban |
| `python3 -m pytest tools/tests -q` | zöldként állítva | ❌ Router CI: 1 failed, 405 passed |
| Router CI | exact `8d44ae8d` | ❌ [run 31685750107](https://github.com/wolfcasaba/strumsight/actions/runs/31685750107) |

## Merge-döntés

Az ADR 0052 szerint a nyitott MAJOR és a piros exact-SHA Router CI miatt merge
tilos. A javítást ugyanazzal a `sonnet-impl` motorral kell végrehajtani, majd
friss izolált review és új CI-dispatch következik.
