# E99-R20 — Biztonsági review

Reviewer: Codex Sol · Dátum: 2026-08-20 · Kockázat: high

## Verdikt

**APPROVED** a `1779de35` javítás és a `d0c25079` re-review alapján.
CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0.

Az argumentumok shell-szinten idézettek, a PR-szám és kör formátuma validált,
a konfliktus-allowlist ismeretlen útvonalon fail-closed. A két nyitott lelet
azonban a merge hitelességi határát sérti:

- **S1 / BLOCKER — FIXED (`1779de35`):** új rebase-HEAD esetén gate és safe
  push után nincs merge; új exact-SHA CI és változatlan második invokáció kell.
- **S2 / MAJOR — FIXED (`1779de35`):** a PR `baseRefName`, `headRefName` és
  `headRefOid` mezői minden git-művelet előtt egyeznek a mért lokális ággal.

Mindkét korábbi próbából állandó hermetikus regressziós cella lett. A célzott
suite `11 passed, 3 subtests`, a teljes tooling-suite `662 passed, 2 skipped,
574 subtests`; shell-injekciós vagy engedélytágító út nem maradt.
