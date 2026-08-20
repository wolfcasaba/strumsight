# E99-R20 — Független review

Brief: `docs/rounds/e99-r20-gov-14-round-landing-automation.md`
Diff: `9e18c68d..d0c25079` (javító commit: `1779de35`)
Reviewer: Codex Sol · Dátum: 2026-08-20
Verdikt: **CHANGES REQUIRED** (landolási próbán újranyitva)

## Összegzés

BLOCKER: 1 · MAJOR: 0 · MINOR: 0 · NOTE: 0

Az első review két fail-closed rést talált. A `1779de35` javító commit mindkét
próbát állandó regressziós cellává tette; a friss upstreamet tartalmazó
`d0c25079` HEAD-en a scope-audit, a round-gate és a teljes tooling-suite zöld.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Merge-záron belüli fetch/rebase/gate/push/merge | ❌ | F3: a script git-módja `100644`, közvetlenül nem indítható |
| 2 | Mechanikus konfliktusok szűk allowlistje | ✅ | 8-cellás hermetikus suite; fail-closed mutáció RED |
| 3 | Kombinált-HEAD kapu | ✅ | rebase után gate+safe push, majd merge helyett új exact-SHA CI-kérés |
| 4 | Orchestrátor a landolót hívja | ✅ | `pipeline-orchestrator-prompt.md:484-497` |
| 5 | Router-CI útvonal-lefedettség | ✅ | meglévő `tools/**` trigger; scope nem módosít workflow-t |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e99-r20-sol-final.mE5SU4
--brief docs/rounds/e99-r20-gov-14-round-landing-automation.md --base
9e18c68d`: **OK**, 6 változott útvonal, ebből 2 generated/ignored review-
artefaktum. Scope-on kívüli implementációs változás nincs.

## Megállapítások

### F1 — BLOCKER — A rebase után a korábbi exact-SHA CI már nem a merge-elt HEAD-et méri

- **Fájl:** `tools/round-land.sh:153-180`,
  `docs/execution/pipeline-orchestrator-prompt.md:484-493`
- **Probléma:** a prompt szerint az exact-SHA CI igazolása a landoló előtt
  történik. Ha közben a `main` mozdult, a landoló új commit-SHA-t képez
  rebase-szel, helyi gate-et futtat, pushol, majd azonnal `gh pr merge`-et
  hív. A korábbi workflow-run így nem az új SHA bizonyítéka. Külső GitHub
  branch-protectionre nem támaszkodhatunk: a tokennel a classic protection
  nem auditálható (`403`), a rulesets API üres listát adott.
- **Bizonyíték:** az eldobható
  `test_review_probe_rebase_invalidates_previously_measured_exact_sha` egy
  valódi upstream commit után eltérő `measured_head`/`landed_head` SHA-t
  mért, a script mégis 0-val tért vissza és kiadta a merge-hívást. Eredmény:
  `FAILED`.
- **Hatás:** zöldnek jelenthető és merge-elhető olyan kombinált állapot,
  amelyen a teljes suite/property/workflow nem futott; ez hamis zöld
  bizonyíték.
- **Kötelező javítás:** ha a landoló rebase miatt új SHA-t képez, a lokális
  gate és safe push után merge nélkül álljon meg, és kérjen új exact-SHA
  workflow-dispatchet. A következő invokáció csak változatlan, már igazolt
  HEAD-en merge-elhet. A prompt és a brief §0.0/§4 dokumentálja a kétfázisú
  ágat.
- **Ellenőrzés:** a fenti próba legyen GREEN; rebase esetén nincs
  `gh pr merge`, változatlan friss HEAD esetén a meglévő tiszta-cellában
  továbbra is van merge.
- **Javítás:** a `1779de35` commit rebase után safe pushig jut, majd blocked
  jelzéssel új exact-SHA CI-t kér; csak változatlan következő invokáció
  merge-elhet. A regressziós cella zöld.
- **Státusz:** FIXED (`1779de35`)

### F2 — MAJOR — A `--pr` nincs a mért branchhez kötve

- **Fájl:** `tools/round-land.sh:94-101`, `tools/round-land.sh:178`
- **Probléma:** a script a lokális current branch-et rebase-eli/gate-eli és
  pusholja, de a kapott PR-számot közvetlenül átadja a `gh pr merge`-nek.
  Nincs `gh pr view`-alapú ellenőrzés, hogy a PR base-e `main`, head branch-e
  a lokális branch, és head SHA-ja az induló lokális HEAD.
- **Bizonyíték:** az eldobható
  `test_review_probe_does_not_merge_a_different_pr_than_the_measured_branch`
  a `--pr 99` értéket adta egy másik lokális branch méréséhez; a script 0-val
  tért vissza és `gh pr merge 99`-et hívott. Eredmény: `FAILED`.
- **Hatás:** operátori tévesztésnél A ág gate-je után B PR merge-elhető.
- **Kötelező javítás:** minden git-művelet előtt kérdezd le a PR
  `baseRefName`, `headRefName` és `headRefOid` mezőit; eltérésnél fail-closed
  blocked, push és merge nélkül. A hermetikus `gh` stub modellezze a helyes
  és eltérő PR-metaadatot.
- **Ellenőrzés:** a fenti próba legyen GREEN, és legyen pozitív cella a
  helyes PR/head kötésre.
- **Javítás:** a `1779de35` commit minden git-művelet előtt egyezteti a PR
  base/head/headOid mezőit; mindhárom eltérési alteszt push/gate/merge előtt
  fail-closed. A pozitív út is zöld.
- **Státusz:** FIXED (`1779de35`)

### F3 — BLOCKER — A landoló nem futtatható fájl

- **Fájl:** `tools/round-land.sh` git mode
- **Probléma:** a Definition of Done futtatható scriptet kér, a prompt pedig
  közvetlen `tools/round-land.sh ...` hívást ír elő, de a git index módja
  `100644` (`stat`: `-rw-rw-r--`, 664).
- **Bizonyíték:** a valódi merge-próba `tools/round-land.sh --pr 358 ...`
  parancsa azonnal `/bin/bash: ... Permission denied` hibával állt meg; merge
  nem történt. A suite azért maradt zöld, mert a fixture és a tesztek
  `bash tools/round-land.sh` formában kerülték meg az execute bitet.
- **Hatás:** a dokumentált és kötelező landolási út egyetlen körben sem
  indítható el.
- **Kötelező javítás:** gitben állítsd a fájlt `100755` módra, és adj olyan
  regressziós tesztet, amely a repository-beli `LAND` execute bitjét méri.
- **Ellenőrzés:** `git ls-files -s tools/round-land.sh` első mezője `100755`,
  `test -x tools/round-land.sh`, célzott suite és round-gate zöld.
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Eredmény | Ellenőrizve |
|---|---|---|
| scope-audit | 6 útvonal, 2 generated/ignored, OK | ✅ |
| format/analyze/architecture/secrets/l10n | `MINDEN GATE ZÖLD` | ✅, friss izolált klón |
| célzott Flutter-teszt | 1 passed | ✅ |
| tooling pytest | 662 passed, 2 skipped, 574 subtests | ✅, 341.69 s |
| landoló regressziós suite | 11 passed, 3 subtests | ✅, F1/F2 lezárva |
| CI | még nincs végső exact-SHA run | ⏳ javítás után kötelező |

## Merge-döntés

F3 nyitva, ezért merge tilos. Javítás után friss re-review és az új exact-SHA
Full Gate + Router CI kötelező; csak mindkettő zöldjén landolhat.
