# E03-R11/H6 — Router metadata recovery review

Brief: `docs/execution/pipeline-selfheal-prompt.md` (E03-R11/H6)
Diff: `git diff origin/main...heal/E03-R11-H6-1`
Reviewer: Codex/Terra, isolated `/tmp` clone · Dátum: 2026-08-03
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | A mért H6 reprodukálható, majd megszűnik | ✅ | `RouterCliTest.test_rebase_baseline_preserves_a_scoped_model_diff_after_preflight_commit`: RED állapotban `resume` exit 40, javítva `READY_FOR_REVIEW` |
| 2 | A baseline- és allowlist-scope audit megmarad | ✅ | `tools/model-router.py:109-119` a hash-frissítés előtt fut; a teszt tiltott `lib/forbidden.dart` diffre exit 50-at vár |
| 3 | Kísérletek és Terra-auditnyomok nem vesznek el | ✅ | ugyanaz a teszt ellenőrzi a meglévő reservationt, a javítás nem resetel állapotot |
| 4 | A javításnak regressziós tesztje van | ✅ | izolált klónban a `brief_hash`-sor eldobása után a teszt RED (`resume` exit 40), visszaállítva GREEN |

## Scope-audit

A `git diff --name-only origin/main...HEAD` kizárólag a self-heal számára
engedett `tools/**`, `tools/tests/**`, `docs/adr/**`, `docs/LESSONS.md`,
`HANDOFF.md` és ez a review-jelentés útvonalait érinti. A mérce-artefaktumok
(`tools/round-gate.sh`, `.github/workflows/**`) érintetlenek. `git diff --check`
zöld.

## Megállapítások

Nincs nyitott megállapítás. A recovery kizárólag sikeres, az aktuális brief
allowlistjével végzett scope-audit után írja át a metadata hash-et; emiatt a
következő `resume` nem kerüli meg a scope- vagy baseline-őrt.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| célzott router regresszió | 1 passed | ✅ izolált klónban |
| teljes router tesztcsomag | `tools/tests` zöld | ✅ izolált klónban (`pytest -q -rA`) |
| valós mutáció | a hash-frissítés eldobása pirosra vált | ✅ izolált klónban |
| Flutter format/analyze/APK | nem érintett Python/router self-heal | N/A |
| CI teljes suite/property | PR után, exact head SHA | függőben |

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. A review jóváhagyja a diffet; a squash-merge
csak a PR exact-head CI teljes suite- és property-evidenciája után engedélyezett.
