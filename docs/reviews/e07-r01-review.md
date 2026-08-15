# E07-R01 — Review

Brief: `docs/rounds/e07-r01-planner-baseline-adrs-and-flags.md`
Diff: `fc4b10e4..e2e3aeff` (`terra/e07-r01-planner-baseline-adrs-and-flags`)
Reviewer: Claude (Sonnet 5, orchestrátor) · független a `terra` implementertől · Dátum: 2026-08-15
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

Tiszta, minimális kör: két opcionális, alapból `false` feature flag
(`practiceGeneratorEnabled`, `plannerAssistEnabled`) a konstruktor + a
`forEnvironment` gyár + a `toString()` mindhárom helyén, a `nonProd` minta
tudatos elkerülésével, plusz az architektúra-őr kétirányú bővítése a jövőbeli
`practice_generator` feature-re. Nulla alkalmazáslogika, nulla módosított
meglévő sor (csak hozzáadás).

## Acceptance criteria

| # | Teljesült | Bizonyíték |
|---|---|---|
| A1 | ✅ | `feature_flags.dart`: mindkét flag a konstruktorban (:22-23), a gyárban (:75-76) és a `toString()`-ben; `feature_flags_test.dart` 1. cella `toString()`-et is méri |
| A2 | ✅ | `feature_flags_test.dart` production+non-production cellák zöldek; **saját, független valódi-sértés próba** (`plannerAssistEnabled: false` → `nonProd`) a non-production cellát `Expected: false / Actual: <true>` hibával PIROSRA váltotta, majd visszaállítva — a diff `git diff --check` + `diff` bájt-azonosan tiszta |
| A3 | ✅ | izolált gate: `flutter analyze` „No issues found”; a teljes célzott teszt-suite zöld — az 51 meglévő `FeatureFlags(...)` hívóhely (a két flag opcionális, default `false`) nem törik |
| A4 | ✅ | `architecture_dependency_test.dart` új esete (`blocks Practice Generator feature internals in both directions`) valódi, temp-fájlba írt import mindkét irányban, `checkArchitecture` a report `unexpectedViolations`-ában mindkét kulcsot visszaadja |
| A5 | ✅ | diff — `dio`/`http` import nem érintett, a 4 fájl egyike sem hálózati kód |
| A6 | ✅ | `find lib/features -maxdepth 1 -iname '*practice_generator*'` — nulla találat |
| A7 | ✅ | `git diff --stat fc4b10e4..HEAD` — mind a 4 fájl **csak hozzáadás** (125 insertions, 0 deletions); egyetlen meglévő flag-sor sem módosult |

## Scope-audit

```
python3 tools/scope-audit.py --repo /tmp/review-e07-r01 \
  --brief docs/rounds/e07-r01-planner-baseline-adrs-and-flags.md \
  --base fc4b10e476579ea2ea2b990b37c39b92cbb10a74
```

`Legacy scope audit OK (fc4b10e47657..e2e3aeff8d60, 4 changed path(s), 0
generated/ignored)` — pontosan a brief §4 négy engedélyezett fájlja.

## Gate-bizonyíték

Izolált, `origin`-ről klónozott példány (`/tmp/review-e07-r01`, NEM a közös
munkapéldány), `tools/round-gate.sh test/app/config/feature_flags_test.dart
test/core/architecture_dependency_test.dart`:

| Gate | Eredmény |
|---|---|
| format | zöld — `Formatted 1495 files (0 changed)` |
| analyze | zöld — `No issues found!` |
| test `feature_flags_test.dart` | zöld — 3/3 |
| test `architecture_dependency_test.dart` | zöld — 17/17 |
| architecture | zöld — `12 allowlisted deviation(s)` (változatlan a baseline-hoz képest) |
| secrets | zöld — `2539 file(s) scanned, 0 finding(s)` |
| l10n | zöld — `en → hu, 1276 message(s)` |

A teljes suite + randomizált property + APK a CI-ban fut (ADR 0053) — exact-SHA
dispatch a merge előtt, ennek a jelentésnek nem tárgya.

## Megállapítások

Nincs nyitott lelet.

## Merge-döntés

Nincs nyitott BLOCKER/MAJOR/MINOR. `risk = "normal"` (a brief `ai-router`
blokkja) és a diff nem érint `.ai/router.toml` `high_risk_path_fragments`
egyezést (`auth`, `authorization`, `credential`, `crypto`, `encryption`,
`migration`, `payment`, `secret`) — dedikált security review nem kötelező
ehhez a körhöz. Az exact-SHA CI (Full Gate/build-apk + Router CI) még külön
merge-feltétel (ADR 0052).
