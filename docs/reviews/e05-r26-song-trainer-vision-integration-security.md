# E05-R26 — Song Trainer vision integration — Security & Privacy Review

**Reviewer:** security-reviewer agent (independent, read-only, isolated clone `/tmp/security-review-e05-r26`)
**Branch:** `codex/e05-r26-song-trainer-vision-integration` @ `5308958`
**Base:** `33b958e` (pre-flight; docs-only over `origin/main`@`7c474fa`)
**Risk declared:** high · **Scope:** 12 changed files, all within `allowed_paths`
**Dátum:** 2026-08-08

> Megjegyzés (orchesztrátor): a review-ágens a leletlistát a válaszába ágyazva
> adta vissza ahelyett, hogy ezt a fájlt maga írta volna meg (egy saját,
> nem ellenőrizhető belső instrukcióra hivatkozva, ami ütközött az explicit
> feladat-prompttal). A tartalom érdemi, mért bizonyítékokkal (fájl:sor,
> reprodukált RED→GREEN próbák, parancskimenetek) alátámasztott, ezért az
> orchesztrátor ezt a fájlt a kapott szöveg alapján, változtatás nélkül
> rögzíti — a leletek felelőssége a jelentés tartalmáé, nem az írás módjáé.
> Follow-up: ez a viselkedésminta (ágens saját, ellenőrizhetetlen
> instrukcióra hivatkozva tér el az explicit feladattól) LESSONS-bejegyzést
> érdemel.

## Verdict: **PASS** — merge-clearable

0 CRITICAL · 0 BLOCKER · 0 MAJOR · 0 MINOR · 1 NOTE

The round's security-motivated centrepiece — the new narrow `vision/domain/integration/public.dart` barrel — is **real, not cosmetic**. Its 9 direct exports all target non-blocked directories, its full transitively-reachable field-type graph is free of camera frames / coordinates / provider stream types, the song_trainer consumers import only the narrow barrel, and the reviewer reproduced the boundary guard going RED on both a forbidden export and a wide-barrel import (GREEN after revert). Transport isolation is machine-proven bit-identical. No secret, network, persistence, permission, or supply-chain surface is introduced.

## Severity table

| # | Sev | File:line | One-line |
|---|-----|-----------|----------|
| 1 | NOTE | `lib/features/vision/domain/integration/public.dart:1-15` + `.../metrics/posture_metrics.dart:132` + `test/.../vision_integration_barrel_boundary_test.dart:12-28` | Boundary test checks only the barrel's *direct* export lines; `PoseLandmarkId` (a benign static catalog enum) remains transitively field-reachable — no raw-media boundary breached; systemic fix already deferred to a dedicated architecture round. |

---

## NOTE-1 — Barrel boundary guard is direct-export-only; one benign `domain/landmarks/` enum is transitively reachable

**Location:**
- `lib/features/vision/domain/integration/public.dart:1-4` (docstring claims "This deliberately excludes landmark, geometry, provider and presentation types") and `:12` (`export '../metrics/posture_metrics.dart';`)
- `lib/features/vision/domain/metrics/posture_metrics.dart:38` (`import '../landmarks/pose_landmarks.dart';`), `:132` (`final Set<PoseLandmarkId> requiredPoseLandmarkIds;`), `:156` (static `postureMetricDefinitions`)
- `test/features/vision/domain/integration/vision_integration_barrel_boundary_test.dart:12-28` (regex over the barrel's own `export '...'` lines only)

**Failure scenario (reproducible, benign):** A future file that imports the narrow barrel can write

```dart
final ids = postureMetricDefinitions.first.requiredPoseLandmarkIds; // Set<PoseLandmarkId>
for (final id in ids) use(id.name); // "leftShoulder", "neckReference", ...
```

and reach the `PoseLandmarkId` enum — which ADR 0193 Döntés 5 itself lists as a blocked `domain/landmarks/` symbol — **without the boundary test firing**, because the test only inspects the barrel's own `export` lines (none of which point at `domain/landmarks/`), never the transitive field-type graph of the exported aggregates.

**Why this is only a NOTE (not a boundary breach):** `PoseLandmarkId` is a static body-part-*name* enum carrying **zero** coordinate / pixel / frame / per-session data; it is reachable only through a compile-time-fixed catalog (`postureMetricDefinitions`), and its type *name* is not even importable through the barrel (Dart re-exports only symbols the target *declares*, and `posture_metrics.dart` merely *imports* `PoseLandmarkId`) — only the *value* is reachable via inference. No raw audio/camera/landmark-coordinate data leaves any boundary. This is strictly weaker than the E05-R25 wide-barrel MINOR (which name+value-exposed `NormalizedPoint` coordinates and `RecordedHandLandmarkProvider` replay classes). The reviewer walked the entire reachable graph and this is the **only** blocked-list symbol that leaks, and it leaks no data.

**Rule:** ADR 0178 (raw-media-free vision result) / §5 #1,#3 — *not breached*; this is the known transitive-reachability gap of the directory-prefix guard (prior finding, `docs/LESSONS.md` L190).

**Fix direction (no merge block):** (a) tighten the barrel docstring — it excludes landmark *coordinate/provider* types, but a landmark-*id* enum stays field-reachable via the posture catalog; (b) systemic: the dedicated architecture round already deferred in ADR 0193 "Elutasított alternatívák" should extend the check to the transitive field-type graph, not just the barrel's direct export lines. Also note the test's second cell pins a hardcoded 2-file consumer list — correct for this round's two new consumers, but a future song_trainer vision-consumer would need adding (the shared `check_architecture.dart` cross-feature guard is the backstop meanwhile).

---

## Verified clean (evidence — the empty findings are themselves evidence)

**Crux: narrow barrel.** All 9 exports resolve to non-blocked dirs (`domain/integration/`, `application/`, `domain/metrics/`, `domain/quality/`, `domain/`); none of the 9 target files contains *any* `export` directive, so there is **no transitive symbol re-export** of a blocked file. Direct-export level is clean. Boundary test GREEN at baseline; reproduced RED on a `../geometry/geometry_confidence.dart` export **and** on a wide-barrel import, GREEN after `git checkout` revert.

**Reachable-graph deep read.** `VisionSessionResult` (barrel-exported) value-graph is raw-media-free: `session`→`VisionSessionId`(String)+`startedAt`(DateTime) with explicit "neither a camera frame nor a platform capture object"; `qualitySummary`→int+enums; `calibrationState`→a **bare enum** (not the machine, so its geometry/`GuitarCalibration` imports are unreachable); `sessionSummary`→`VisionInsight` (enum/String/`List<String>` evidence-ids/double). `VisionFrameQuality` exposes only aggregate scalars (meanLuminance/sharpness/cameraMotion — per-frame quality summaries, not pixels). None of `vision_session.dart`/`vision_quality_summary.dart`/`insight_code.dart`/`calibration_loss_machine.dart` is a direct barrel export.

**Token sweep.** New lib files: 0 hits for `HandLandmark|PoseLandmark|CameraImage|VisionImage|Frame|pixel|NormalizedPoint|NormalizedRect|camera_coordinate_space|dart:io|dart:ffi|MethodChannel|Platform.`. 0 wide-barrel (`features/vision/public.dart`) imports in any song_trainer file; both new consumers import only `.../integration/public.dart`.

**SongVisionSummary data flow.** Aggregate-only: `String` ids, `Duration sectionDuration`, `VisionMetricState quality` (enum), `double?` stroke/hand/posture. No coordinates, no images, no per-frame timeseries. Constructor validates finite/non-negative; `notObservable` is an explicit missing-quality marker; missing-quality loops are **kept and marked**, never dropped (proven by `song_vision_adapter_test.dart` + the parity test asserting `loops[1].quality == notObservable`).

**Transport isolation.** No transport file touched (diff-verified). `SongVisionAdapter` has no transport dependency. `VisionCadenceDecision.isError` and `.requiresTransportStop` are hardcoded `false`; `decide()` never throws (range validation lives in the `VisionThermalLoad` input constructor, off the transport path). `transport_timing_parity_test.dart` proves the event timeline **and** `MonophonicNoteScorer` result are **bit-identical** vision ON vs OFF, and that transport stays `playing`/`playing` with `pauseCalls == 0` across thermal 0/40/80. A vision exception cannot reach the transport by construction (no wiring this round). Independently re-ran: parity + cadence + adapter = 14/14 PASS.

**Standard checks.** No network (case-sensitive grep clean — the earlier `Dio` hits were the substring "dio" in "au**dio**"), no logging, no persistence, no permissions/platform channels. `tool/ci/check_secrets.dart`: **0 findings / 2042 files**; no secret-like patterns in new files. `pubspec.yaml` + `pubspec.lock` **byte-unchanged** — no new dependency, no supply-chain surface. ARB change is additive-only (one key `songVisionLoopQualityUnavailable`, both en+hu), and its wording ("Visual quality was unavailable… Audio scoring is unchanged") correctly signals absent confidence rather than a false claim — consistent with §5 #5 / ADR 0179.

**Scope audit.** All 12 changed files ∈ `allowed_paths`; wide `vision/public.dart` byte-unchanged vs `origin/main` (ADR 0193 Döntés 6); nothing outside `lib/features/{vision,song_trainer}` / `lib/l10n` / `test/features` / `docs/rounds`.

**Not applicable this round (with evidence):** AI-provider / prompt-injection (ADR 0131–0136) — no provider, no LLM, no tool-calling, no external content flows into any prompt. Importer / zip-bomb / path-traversal — no MusicXML/MIDI/GP/zip parsing in the diff; the only `File()`/`dart:io` use is in the boundary **test** reading source files, not production.

---

## Summary

**Verdict: PASS (merge-clearable).** Counts: **0 CRITICAL, 0 BLOCKER, 0 MAJOR, 0 MINOR, 1 NOTE.** The narrow-barrel fix is real (guard reproduced RED→GREEN), the full reachable graph is raw-media-free, transport isolation is bit-identical-proven, and there are no secret/network/persistence/permission/dependency changes. The single NOTE is the previously-anticipated transitive blind spot in the directory-prefix boundary test: `PoseLandmarkId` (a static, coordinate-free catalog enum) stays field-reachable through `PostureMetricDefinition.requiredPoseLandmarkIds` — no privacy boundary is breached, and the systemic guard upgrade is already deferred to a dedicated architecture round by ADR 0193 + LESSONS L190.
