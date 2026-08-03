# E03-R13/H6 — Nested Dart cache self-heal review

Halt: `H6` — router scope audit rejected generated nested Dart cache files.
Diff: `origin/main...heal/E03-R13-H6-1`
Reviewer: Codex / Terra (isolated clone)
Dátum: 2026-08-03
Reviewed head: `315362f`
Verdikt: **APPROVED**

## Összegzés

**BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0**

Az E03-R13 tényleges router-haltja a `dart pub get` által az engedélyezett
Guitar Pro feasibility spike alá létrehozott
`tool/guitar_pro_feasibility/.dart_tool/**` artefaktumokat sorolta a
modell-diffhez. A javítás csak a `.dart_tool` path-komponenst ismeri fel Dart
generált cache-ként; a testvér source- és egyéb ignorált utak továbbra is a
normál allowlist/protected-path audit alatt maradnak.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | A mért R13 nested `.dart_tool` útvonalak nem blokkolják a scope auditot | ✅ | `RouterArtifactScopeTest.test_nested_dart_tool_artifacts_are_generated_ignored` |
| 2 | A guard nem kapcsol ki és a termék-utak scope-ellenőrzése megmarad | ✅ | `audit_scope()` változatlan protected/allowlist ágai; a változás kizárólag `_is_generated_ignored()` ismert generált cache kategóriája |
| 3 | A javítás regressziós teszttel lefedett | ✅ | a teszt a javítás előtt RED, utána GREEN |

## Scope-audit

Engedélyezett infrastruktúra- és review-fájlokon kívüli változás: nincs.

## Független ellenőrzés

| Ellenőrzés | Eredmény |
|---|---|
| Izolált clone | PASS — `/tmp/review-e03-r13-h6-rJ48OD` |
| `git diff --check origin/main...HEAD` | PASS |
| Célzott regressziós teszt | PASS — 4 passed |
| Teljes routerteszt-sáv | PASS — `/tmp/rvenv-e03-r13-h6/bin/python -m pytest tools/tests -q` |
| Valódi-sértés próba | PASS — az `or ".dart_tool" in parts` ideiglenes eltávolítása után 1 failed / 3 passed, a konkrét nested cache paths scope-sértésével; visszaállítva |
| Router CI | PASS az első implementation headen: [30837253488](https://github.com/wolfcasaba/strumsight/actions/runs/30837253488); a review-commit után exact-head újrafutás kötelező |

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. A squash merge az exact-head Router CI
sikeres lefutása után engedélyezett; Dart termékkód nem változott, ezért
APK-dispatch nem alkalmazható.
