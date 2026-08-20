# E99-R20 — Biztonsági review

Reviewer: Codex Sol · Dátum: 2026-08-20 · Kockázat: high

## Verdikt

**APPROVED** a `475a9ab0` recovered HEAD re-review-ja alapján.
CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0.

Az argumentumok shell-szinten idézettek, a PR-szám és kör formátuma validált,
a konfliktus-allowlist ismeretlen útvonalon fail-closed. A két nyitott lelet
azonban a merge hitelességi határát sérti:

- **S1 / BLOCKER — FIXED (`1779de35`):** új rebase-HEAD esetén gate és safe
  push után nincs merge; új exact-SHA CI és változatlan második invokáció kell.
- **S2 / MAJOR — FIXED (`1779de35`):** a PR `baseRefName`, `headRefName` és
  `headRefOid` mezői minden git-művelet előtt egyeznek a mért lokális ággal.

Mindkét korábbi próbából állandó hermetikus regressziós cella lett. A célzott
suite `13 passed, 3 subtests`, a teljes tooling-suite `664 passed, 2 skipped,
574 subtests`; shell-injekciós vagy engedélytágító út nem maradt.

**S3 / NOTE — H8-SELFDUP őr:** a `93dabfb4` patch-id ellenőrzése kizárólag
fail-closed ágat ad: duplikált saját patch esetén a rebase, gate, push és merge
előtt blokkol. Az offender commitok csak idézett argumentumként kerülnek a
jelzésbe, nem eval- vagy parancshelyzetbe. A hívás ideiglenes kikapcsolása a
hermetikus reprodukciót RED-re vitte, visszaállítása GREEN-re; új jogosultsági
vagy shell-injekciós felületet nem találtam.
