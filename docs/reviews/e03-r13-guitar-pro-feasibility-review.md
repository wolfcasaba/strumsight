# E03-R13 — Guitar Pro feasibility — Review

Brief: `docs/rounds/e03-r13-guitar-pro-feasibility.md`
Diff: `origin/main...9de47d0`
Reviewer: Codex / GPT-5.6 Terra
Date: 2026-08-03
Verdict: **APPROVED** (the exact-review-head CI evidence is still required before merge).

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

The round keeps Guitar Pro parsing out of production code and makes the
release-safe C decision: an external, user-initiated conversion to the already
audited offline MusicXML/MXL or MIDI paths. The research evaluates the required
A/B/C candidates, the isolated alphaTab probe reproduces the stated fixture
matrix, and the ADR contains a concrete R14 activation contract.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Licence, GP versions, mobile/offline, size, fidelity, security, maintenance and effort comparison | ✅ | `docs/research/epic-03-guitar-pro-feasibility.md` candidate matrix; reviewer rechecked alphaTab’s official compatibility/importer documentation and TuxGuitar’s supported-format list on 2026-08-03. |
| 2 | Reproducible spike with all mandatory fidelity fields | ✅ | In isolated `/tmp/review-e03-r13.nRQVrg`: `npm pack @coderline/alphatab@1.8.4`, `dart pub get`, then `ALPHATAB_MODULE_PATH="$PWD/package" dart test test/gp_spike_test.dart` → 4 passed; the CLI output matched GP3, GP5 and GPX expected snapshots. |
| 3 | One A/B/C decision, rejection rationale and R14 contract | ✅ | `docs/adr/0122-guitar-pro-import-strategy.md` Decision 5 and Consequences; report “Döntés és R14 aktiválási szerződés”. |
| 4 | No production feature or registry modification; uncertain A/B excluded | ✅ | Scope audit: no `lib/**`, production `pubspec.yaml` or registry path changed; ADR selects C and makes A/B conditional. |

## Scope-audit

The implementation commit changes only the brief §4 human allowlist:

- research report and this round’s ADR;
- isolated `tool/guitar_pro_feasibility/` sources;
- provenance-documented GP3/GP5/GPX technical fixtures;
- the R13 brief handoff.

No production importer, registry, Flutter dependency, UI, network path or
protected pipeline path changed. This review report is the mandatory
reviewer-owned merge artefact, not an implementer change.

## Independent checks

- Fresh-clone prerequisite: the first gate reproduced the known ignored l10n
  and nested-tool package-cache precondition. After `flutter pub get`,
  `flutter gen-l10n`, and isolated-tool `dart pub get`, the mandatory gate was
  rerun in the same clone and passed.
- Mutation proof: changing `minimalGp3Expectation.firstFret` from `3` to `4`
  made the GP3 and GP5 fidelity tests fail; the mutation was reverted before
  this report. This proves the central preserved string/fret invariant is not
  a copied green result.
- The reviewed fixture SHA-256 values matched the provenance README.
- `git diff --check origin/main...9de47d0` passed.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| format | ✅ fresh-clone `tools/round-gate.sh` (0 files changed) |
| analyze | ✅ fresh-clone `tools/round-gate.sh` (no issues) |
| célzott importer tests | ✅ fresh-clone `tools/round-gate.sh` (45 passed) |
| architecture | ✅ fresh-clone `tools/round-gate.sh` (12 allowlisted deviations) |
| isolated alphaTab spike | ✅ 4/4 passed; documented CLI snapshots reproduced |
| full suite + randomized property + APK CI | ⏳ must run on this review-report commit’s exact SHA before merge |

## Merge-döntés

No open BLOCKER or MAJOR finding remains. Under ADR 0052, merge is permitted
only after the branch’s exact review-report SHA has a green full Flutter suite,
randomized property gate and development APK, and `origin/main` has not moved
since that dispatch.
