# E99-R20 — Független review

Brief: `docs/rounds/e99-r20-gov-14-round-landing-automation.md`
Diff: `d8552204..f7fec35a`
Reviewer: Codex Sol · Dátum: 2026-08-20
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 1 · MAJOR: 1 · MINOR: 0 · NOTE: 0

Az engedélyezett diff, a deklarált kör-gate és a teljes tooling-suite zöld,
de két eldobható próbateszt bizonyította, hogy a landoló nem köti össze
fail-closed módon a mért lokális HEAD-et a ténylegesen merge-elt PR-rel.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Merge-záron belüli fetch/rebase/gate/push/merge | ⚠️ | `tools/round-land.sh:65-180`; F1 nyitva |
| 2 | Mechanikus konfliktusok szűk allowlistje | ✅ | 8-cellás hermetikus suite; fail-closed mutáció RED |
| 3 | Kombinált-HEAD kapu | ⚠️ | a lokális kapu fut, de F1 miatt az exact-SHA CI bizonyítéka elavulhat |
| 4 | Orchestrátor a landolót hívja | ✅ | `pipeline-orchestrator-prompt.md:484-497` |
| 5 | Router-CI útvonal-lefedettség | ✅ | meglévő `tools/**` trigger; scope nem módosít workflow-t |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e99-r20-sol.wJ7qq9 --brief
docs/rounds/e99-r20-gov-14-round-landing-automation.md --base d8552204`:
**OK**, 4 változott útvonal, 0 generated/ignored. Scope-on kívüli
implementációs változás nincs.

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
- **Státusz:** OPEN

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
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Eredmény | Ellenőrizve |
|---|---|---|
| scope-audit | 4 útvonal, OK | ✅ |
| format/analyze/architecture/secrets/l10n | `MINDEN GATE ZÖLD` | ✅, friss izolált klón |
| célzott Flutter-teszt | 1 passed | ✅ |
| tooling pytest | 658 passed, 2 skipped, 571 subtests | ✅, 319.01 s |
| review próbák | 2 failed | ❌, a két nyitott lelet reprodukciója |
| CI | még nincs végső exact-SHA run | ⏳ javítás után kötelező |

## Merge-döntés

Az ADR 0052 szerint a merge tilos, amíg F1/F2 nyitva van. Javítás után friss
izolált re-review, exact-SHA Full Gate/Router CI és csak utána landolás.

