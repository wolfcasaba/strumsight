# E99-R08 — Review

Brief: `docs/rounds/e99-r08-gov-07-per-round-orchestrator-rotation.md`  
Diff: `origin/main...8d44ae8d` (Terra, F1–F3 azonosítva) → `origin/main...f4b3afff` (F3 mechanikusan zárva, lásd lent)  
Reviewer: Codex / gpt-5.6-terra (a Sonnet implementertől független) · Dátum: 2026-08-13  
Verdikt: **APPROVED** (frissítve 2026-08-13, orchestrátor-session — F3 zárva, lásd §Merge-döntés)

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
- **Státusz:** FIXED — commit `9391108b` (rebase onto `origin/main@6228764f`
  után). A javítás pontosan a kért alakot követi: `_fake_claude_bin()` egy
  determinisztikus, `chmod 755` végrehajtható stub fájlt ír ki (`#!/bin/sh\nexit
  0\n`), és a fixture ezt adja át `CLAUDE_BIN` env-ként — a driver
  `claude_bin=${CLAUDE_BIN:-claude}` (`round-pipeline.sh:96`) miatt ezt olvassa
  a `command -v "$claude_bin"` előfeltételnél (`:1444`), a fake bináris
  utólag SOHA nem fut (a teszt elvárt kimenete a `die()` a `PIPELINE_STATE_DIR`
  ágon, ami a claude-hívás ELŐTT történik). Nincs valódi CLI, nincs hálózat.
  Mechanikus újra-ellenőrzés (AGENTS.md §15.7 — a Sonnet-5
  orchestrátor-session a Terra-review MÁR meglévő, független ítéletét
  certifikálja, nem ismétli meg saját véleményezéssel):
  - `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart`
    a rebase-elt `9391108b`-n: mind a hat lépés (format/analyze/test/
    architecture/secrets/l10n) ZÖLD.
  - `python3 -m pytest tools/tests -q` (`/tmp/rvenv`) ugyanazon a commiton:
    **407 passed, 394 subtests passed, 0 failed** — a korábbi egyetlen,
    e körön kívüli piros (`test_claude_harness_engines.py::WrapperModeTest::
    test_the_legacy_call_without_round_engine_stays_minimax`) a rebase által
    behozott H6 self-heal miatt szintén zöld.
  - Router CI exact `9391108b`-n: lásd a §Merge-döntés frissítését.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| scope-audit | zöld | ✅ izolált klónban (`8d44ae8d`), majd újra `f4b3afff`-n: `Legacy scope audit OK (origin/main..f4b3afff4d85, 8 changed path(s), 1 generated/ignored)` |
| format/analyze/célzott Dart gate | indítva az izolált klónban | ✅ `9391108b`-n mind a hat lépés ZÖLD (`round-gate.sh`) |
| `python3 -m pytest tools/tests -q` | zöldként állítva | ✅ `9391108b`-n: 407 passed, 394 subtests, 0 failed |
| Router CI | exact `f4b3afff` | ✅ [run 31690984653](https://github.com/wolfcasaba/strumsight/actions/runs/31690984653) |
| Full Gate (no APK) | exact `f4b3afff` | ✅ [run 31690998877](https://github.com/wolfcasaba/strumsight/actions/runs/31690998877) |

## Merge-döntés

Az ADR 0052 szerint a nyitott MAJOR és a piros exact-SHA Router CI miatt merge
tilos. A javítást ugyanazzal a `sonnet-impl` motorral kell végrehajtani, majd
friss izolált review és új CI-dispatch következik.

### Frissítés (2026-08-13, orchestrátor-session — mechanikus zárás)

F3 javítva `9391108b`-n (lásd fent), a branch `origin/main@6228764f`-re
rebase-elve (0 fájl-átfedés a H3/H6/H8 self-heal commitokkal — mérve
`git merge-base --is-ancestor origin/main HEAD`), pusholva
`tools/safe-force-push.sh`-sal (a kör SAJÁT D3-deliverable-je — remote-only
commit nem volt, tiszta lease-push). Mindkét helyi gate ZÖLD a pontos
`9391108b` SHA-n (lásd F3 §Státusz).

**Végső CI-bizonyíték a merge-jelölt exact SHA-n (`f4b3afff`):**

| Workflow | Run | Konklúzió |
|---|---|---|
| Router CI | [31690984653](https://github.com/wolfcasaba/strumsight/actions/runs/31690984653) | ✅ success |
| Full Gate (no APK) | [31690998877](https://github.com/wolfcasaba/strumsight/actions/runs/31690998877) | ✅ success (Coverage 11m35s + full-gate 8m21s) |

`origin/main` a dispatch (`6228764f`) és e két run befejezése között nem
mozdult (`git rev-parse origin/main` egyezik). A `tools/round-ci-plan.py`
`full-gate.yml`-t adott (`apk_required=false`, 0 natív útvonal) —
`router_ci_expected=true`, mindkettő lefutott és zöld. **Merge engedélyezve
(ADR 0052).**
