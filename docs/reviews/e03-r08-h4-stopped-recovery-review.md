# E03-R08/H4 — STOPPED recovery review

Heal branch: `heal/E03-R08-H4-1b`  
Diff: `git diff origin/main...heal/E03-R08-H4-1b`  
Reviewer: Codex / GPT-5.6 Terra (orchestrator fallback; isolated clone)  
Date: 2026-08-02  
Verdict: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | STOPPED task csak zöld célzott gate után jut review-ra | ✅ | `recover_stopped_task_after_heal`, `RouterCliTest.test_heal_recovery_preserves_exhausted_attempts_after_a_green_gate` |
| 2 | Allowlisten kívüli diff fail-closed | ✅ | Izolált klón mutációja: `lib/allowed.dart` kikerült a fixture allowlistjéből → CLI exit 50, `healed worktree still fails scope audit: path outside allowed scope` |
| 3 | Korábbi M3/Terra ledger nem vész el | ✅ | A regressziós teszt `m3_attempts == 2`, `terra_calls == 1`, `terra_reservation` megőrzését ellenőrzi |
| 4 | Superseded terminális intent nem játszódik vissza | ✅ | A regressziós teszt mindkét `terra_terminal_*` mező eltűnését ellenőrzi, a reservation marad |

## Scope-audit

Az izolált klónban a diff pontosan négy engedélyezett self-heal fájlra
korlátozódott: `tools/model-router.py`, `tools/tests/test_router_cli.py`,
ADR 0112 jelölt módosítási blokk és `docs/LESSONS.md`. Nincs
`tools/round-gate.sh`, workflow, teszt-törlés vagy küszöblazítás.

## Próbateszt

A review-klónban ideiglenesen a teszt-fixture briefjének allowlistjéből
kivettem a módosított `lib/allowed.dart` utat. A recovery ezután `exit 50`-nel
állt meg scope-audit hibával. Az eredeti allowlist visszaállítása után a
célteszt ismét zöld volt; a review-klón tiszta.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| Python fordítás | ✅ `python3 -m py_compile tools/model-router.py` |
| Router tesztek | ✅ izolált klónban `/tmp/strumsight-heal-pytest/bin/python -m pytest tools/tests -q` |
| diff-integritás | ✅ `git diff --check` |
| Router CI | ✅ [run 30772138838](https://github.com/wolfcasaba/strumsight/actions/runs/30772138838), exact `ef7a4d1` headSha |
| APK / Flutter teljes suite | N/A — nincs Dart- vagy Android-változás; a router CI a releváns kötelező sáv |

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. A javítás nem resetel router-state-et és
nem gyengíti a mércét; squash-merge engedélyezett.
