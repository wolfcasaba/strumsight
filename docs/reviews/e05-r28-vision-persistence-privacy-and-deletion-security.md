# E05-R28 — Dedicated security/privacy review

Brief: docs/rounds/e05-r28-vision-persistence-privacy-and-deletion.md
Diff: `git diff 1bbcc97..ee154cc` (14 files, all within `allowed_paths`)
Reviewer: security-reviewer agent (dedicated, mandatory for `risk = "high"`) · Dátum: 2026-08-08
Worktree/branch: `/home/ubuntu/ss-terra-e05-r28` · `codex/e05-r28-vision-persistence-privacy-and-deletion`
Method: independent field-by-field trace of the persistence/export path to its domain source; did not rely on the implementer's §10 self-report.

## Verdikt: PASS

No CRITICAL, no BLOCKER, no MAJOR from the security/privacy lens. The
non-negotiable boundaries (ADR 0178, ADR 0183 Döntés 1, AGENTS.md §5 #1–#5)
hold with reproducible evidence. Two MINOR and three NOTE items below.

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| BLOCKER | 0 |
| MAJOR | 0 |
| MINOR | 2 |
| NOTE | 3 |

MINOR-1 below (missing model-version) is a cross-domain ADR-compliance gap,
not a privacy/security breach — omitting data is privacy-neutral-to-positive.
The main independent review (`e05-r28-vision-persistence-privacy-and-deletion-review.md`)
re-classifies the SAME underlying fact as **F1 — MAJOR** from the
architecture/contract-compliance lens (ADR 0183 Döntés 2 explicitly rejects
omitting it), and routes it through a fix round. Both reports describe one
fact; the severity differs by lens, which is expected and not a
contradiction.

## Requested-verification results

**1. No raw media, ever — VERIFIED (clean).**
Every field in the persisted/exported JSON (`vision_session_codec.dart:183-214`)
was traced back to its source type:
- `sessionId` ← `VisionSessionId.value`; production generator is a counter
  `'vision-session-${sequence++}'` (`vision_session_controller.dart:28`) — an
  identifier, no media.
- `startedAt`/`endedAt` ← `DateTime`; `endReason`/`calibrationState`/
  `quality.*`/`insights.code`/`direction`/`capability` ← bare enums (`.name`
  serialized).
- `quality.frameCount`, `observedFrameCount` ← int **counts**
  (`frames.length`), not coordinates.
- `insights.confidence` ← double [0,1] (gated), `priority` ← int,
  `policyVersion` ← `"e05-r23-v1"` string.
- `insights.evidenceIds` ← `evidence.map((e) => e.id)`
  (`feedback_policy_engine.dart:98`); `VisionEvidence.id` is by convention the
  FNV-1a `deterministicId` = `'vision-evidence-<16-hex>'`
  (`vision_evidence.dart:48-62`), a one-way hash of `metric.key:startUs:endUs`.
  **Opaque; not a coordinate/value/landmark.**

The sibling-round failure class (E05-R26 F1/NOTE-1: a re-exported type
carrying a hidden raw field) does **not** recur. The one candidate that could
smuggle a raw value under a sanctioned name — `evidenceIds` — resolves to
hashes. Critically, the codec copies `insight.evidenceIds` (the ID strings)
and **not** the `VisionEvidence` objects, so the raw `VisionEvidence.value`
(double?) and `provenance.window` (startUs/endUs) never reach disk. No
pixel/frame/landmark/image-URI/raw-per-frame measurement is persisted.

**2. Deletion is real, not soft — VERIFIED.**
`deleteAllVisionData()` (`vision_session_repository.dart:60-65`) issues raw
`_store.remove(key)` + `_store.remove(quarantineOf(key))` for every key in
`StorageKeys.visionData` — no read-filter. `deleteSession()` rewrites the
collection without the record. The tests read the **raw** store:
`vision_session_repository_test.dart:89-96` (deleteSession) and `:112-121`
(delete-all) both `jsonDecode(store.readString(...))` and assert the bytes
are gone, including pre-seeded `.corrupt` shadows (`:103-110`). Not a logical
delete.

**3. `StorageKeys.visionData` exhaustive for this round — VERIFIED (no BLOCKER).**
The only **new** persisted key introduced in the diff is `visionSessionHistory`
(`storage_keys.dart:67`), and it **is** in `visionData` (`:74-77`). No new
vision key is omitted. The only storage write target in the new code is
`visionSessionHistory` via `_sessions.write`; delete-all also covers
`.corrupt` shadows. The pre-existing `visionSetupProfile`/`visionCamera` are
excluded — see NOTE-2.

**4. Zero network, structurally and behaviorally — VERIFIED.**
`VisionSessionRepository`, `VisionExport`, `VisionSessionCodec` constructors
take only `KeyValueStore` + codec; none imports `dio`/`HttpClient`.
`offline_network_guard_test.dart:277-304` boots the full app
(`AppBootstrap.run` + `StrumSightApp`), navigates to `AppRoutes.visionSession`,
then actually runs `repository.save(...)` + `VisionExport(...).exportJson()`
against the container's store and asserts `_expectNoNetwork`.
`_expectNoNetwork` (`:215-225`) is meaningful:
`[accountFactoryCreations, requests.length] == [0, 0]` plus null
`diagnosticsApiClient`/`diagnosticsUploader.client`.

**5. Destructive confirm-dialog gate — VERIFIED.**
`_confirmDeleteAll` (`vision_privacy_screen.dart:29-55`) `showDialog<bool>`
and calls `deleteAllVisionData()` only on `confirmed == true` (`:48`). Test
(`vision_privacy_screen_test.dart:37-40`) taps Cancel and asserts
**`store.writeLog isEmpty`** — and `InMemoryKeyValueStore` logs `remove` too
(`in_memory_key_value_store.dart:62`), so this genuinely proves zero writes
**and** zero removes — plus data still present. The confirm path (`:44-47`)
then asserts the keys are null.

**6. Export parity — VERIFIED (genuine set comparison).**
`vision_export_privacy_test.dart` pins a fixed 24-path key set
(`_expectedPaths`, `:33-58`) and asserts it against **both** the on-disk item
and the export entry, then compares the two:
`expect(_paths(stored), _expectedPaths)` /
`expect(_paths(exportedEntry), _expectedPaths)` /
`expect(_paths(stored), _paths(exportedEntry))` (`:26-29`). This is the AC
"key evidence" test and it is real, not eyeballed. (Limitation → NOTE-1.)

**7. Quarantine boundary — VERIFIED; and the E05-R10 escape-class does NOT recur here.**
`JsonCollectionStore.read()` decodes record-by-record inside
`try { … } on JsonRecordException { skip } catch (e) { skip }`
(`json_document_store.dart:213-233`). The trailing **bare `catch (e)`**
(`:226`) catches `Error` subtypes too. So a single corrupt record that makes
a value-constructor throw `ArgumentError` — e.g. `VisionInsightSnapshot` on
empty `evidenceIds` (`vision_session_codec.dart:86-92`),
`VisionSessionHistoryEntry` on empty `sessionId` (`:35-39`), an unknown enum,
or a future item `schemaVersion` (`:176-180`) — is skipped, and the rest stay
readable. `vision_session_repository_test.dart:51-77` proves it. This is
exactly the E05-R10 class (`ArgumentError` is an `Error`, escapes
`on Exception`), but R28 is safe because it decodes through the bare-catch
`JsonCollectionStore`, unlike R10's custom
`VisionCalibrationRepository.read()` which uses `on Exception catch`
(`vision_calibration_repository.dart:63`). Also: these DTO checks use
`throw ArgumentError`, not `assert`, so the fail-closed behavior is identical
in a release APK (no assert-stripping divergence).

**8. General posture — VERIFIED.**
Secrets: none in the diff (grep for secret/token/password/api-key/signing/
bearer → NONE). Logging: the repository wires `NoopAppLogger`
(`vision_session_repository.dart:23`), so record-skip/corruption events
aren't logged at all; `JsonRecordException`/store log-fields never carry
values by design (`json_validation.dart:8-9`) — no raw vision value can reach
a log. `ai_tutor/` is untouched by the diff. No LLM/tool-calling/
prompt-injection surface in this round's files.

**ADR reference correction (§0.0 R1) — CONFIRMED, with one deviation (→ F1 in the main review).**
`docs/adr/0161*`/`0166*` do not exist; the E05-R01 +17 shift maps
`0166 → 0183`, which exists. ADR 0183 **Döntés 1** ("raw kép és teljes
landmark-idősor alapértelmezetten nem tárolható") is faithfully implemented.
ADR 0183 **Döntés 2** (model-version provenance) is **not** — see MINOR-1
below and F1 in the main review.

## Megállapítások

### MINOR-1 — ADR 0183 Döntés 2 (model-version provenance) not implemented; §10 self-report inaccurate

- **Fájl:** `vision_session_codec.dart:183-214` (persisted DTO has no
  model-version key); `vision_session_result.dart:40-46` (the
  `VisionSessionResult` aggregate itself carries no model-version field).
- **Szabály:** ADR 0183 Döntés 2 + Elutasított alternatívák ("Model-verzió
  elhagyása a helytakarékosságért. **Elvetve**"). Brief §3 also lists
  "model-verzió" in "mentendő adatkör".
- **Hatás:** after a vision model upgrade, a persisted/exported session
  cannot be attributed to the model that produced it (SDD §30 manifest-chain)
  — the exact interpretability loss the ADR rejects. `policyVersion` is the
  *feedback-policy* version, not the ML model version; the actual
  `modelVersion` lives on `EvidenceProvenance.modelVersion`, which the codec
  drops (it only copies evidence **IDs**, not full evidence objects).
- **Miért security-semleges:** storing *less* is privacy-neutral-to-positive
  — this does not affect the security/privacy verdict.
- **Sorsa:** promoted to **F1 — MAJOR** in the main independent review
  (architecture/contract lens) and routed through a fix round. Status:
  **OPEN**, see main review for the fix direction.

### MINOR-2 — `vision_privacy_screen.dart` consumes the wide `vision/public.dart` barrel (transitively re-exports raw landmark/pose/geometry types)

- **Fájl:** `vision_privacy_screen.dart:12` imports `../../vision/public.dart`.
  That barrel re-exports raw types: `hand_landmarks.dart`/`pose_landmarks.dart`/
  `geometry/*` (`public.dart:24-34`), `NormalizedPoint`/`NormalizedRect`
  (`:65-66`), landmark providers (`:59-64`). The three persistence types this
  round adds (`:56-58`) are aggregate-only and safe; the issue is the *only*
  channel to reach them is the wide barrel.
- **Szabály:** ADR 0178 / AGENTS.md §5 #1,#3 privacy boundary; consistent
  with the latent barrel gap documented across E05-R25/R26 (both machine
  guards are symbol-blind: `check_architecture.dart` `_isFeaturePublicBarrel`
  only checks `endsWith('/public.dart')`; `domain_purity` only regexes
  framework packages).
- **Hatás (látens, ma nem valósul meg):** a future edit to this settings
  screen could reference `HandLandmarks`/`NormalizedPoint` (raw coords) with
  no new import, and both guards stay green — a latent path for raw data to
  enter the settings layer.
- **Miért MINOR (nem MAJOR), verdikt változatlan:** the round's own code uses
  only aggregate types (grep of the new files for
  `landmark|geometry|CameraImage|Frame|pixel` = 0), the screen is currently
  **dormant** (not wired to any route), and no in-round AC is defeated.
  Latent-but-reproducible, same bar as prior rounds → PASS. Matches the main
  review's N1 (same fact, same non-blocking conclusion).
- **Javasolt irány (follow-up, nem e kör):** add the persistence exports to
  a narrow nested barrel (as R26 did with `domain/integration/public.dart`)
  so `settings` can consume the aggregate persistence API without pulling
  raw landmark types into scope; land it before the screen is route-wired.
- **Státusz:** NOTE-level follow-up, nem blokkol.

### NOTE-1 — Privacy-snapshot test is a shape guard, not a value guard

`vision_export_privacy_test.dart` `_paths` compares **key paths**, and for
lists recurses only `value.first` (`:69`). It reliably catches a *new field*
(the AC's "valódi-sértés próba" — adding `landmarkSeries` goes red, confirmed
independently by both the implementer and the main review). It would **not**
catch a raw value smuggled inside an already-allowlisted field (e.g. if
`evidenceIds` ever carried non-hash strings, or a base64 blob in `sessionId`).
No leak exists today (values are hashes/scalars/enums by construction), so
this is defense-in-depth only. Optional hardening (future round, not this
one): assert `evidenceIds` match the `vision-evidence-` prefix and pin
value-level invariants.

### NOTE-2 — `visionData` excludes `visionSetupProfile`/`visionCamera`

Delete-all covers `visionSessionHistory` + `visionCalibration` (+
`.corrupt`), but not `visionSetupProfile` (a `VisionSetupProfile` framing
enum) or `visionCamera` (a `VisionCameraPreference` back/front enum). These
are non-sensitive UI preferences (no landmarks/coordinates/session data), out
of the brief §3 panel scope, and the UI does not overclaim: the scope list is
rendered directly from `StorageKeys.visionData`
(`vision_privacy_screen.dart:110-113`) and the ARB body enumerates exactly
"session summaries, calibration, and recovery copies." Informational only.

### NOTE-3 — `NoopAppLogger` suppresses all persistence diagnostics (privacy-positive trade-off)

Wiring `NoopAppLogger` (`vision_session_repository.dart:23`) means
per-record skip/corruption warnings are not emitted even to the app's normal
sink. This is privacy-conservative (nothing to leak) and safe (the fields
never carried values anyway), at the cost of silent skips being
undiagnosable from logs. Observation, not a defect.

## Files examined

`vision_session_codec.dart`, `vision_session_repository.dart`,
`vision_export.dart`, `vision_privacy_control.dart`, `vision/public.dart`,
`core/storage/storage_keys.dart`, `settings/screens/vision_privacy_screen.dart`,
`app_en.arb`; domain sources `vision_session_result.dart`, `vision_session.dart`,
`quality/vision_quality_summary.dart`, `feedback/insight_code.dart`,
`feedback/feedback_policy.dart`, `evidence/vision_evidence.dart`,
`evidence/evidence_provenance.dart`, `application/feedback_policy_engine.dart`,
`application/calibration_loss_machine.dart`, `vision_setup_profile.dart`;
infra `core/storage/json_document_store.dart`, `core/foundation/json_validation.dart`,
`vision_calibration_repository.dart`; all four test files +
`in_memory_key_value_store.dart`; ADR 0178, ADR 0183, and the round brief.

## Merge-döntés (security lens)

Security gate: **PASS**, 0 open CRITICAL/BLOCKER/MAJOR from this lens.
MINOR-1's underlying fact is tracked as F1 (MAJOR) in the main review and
must close before merge per that review's architecture/contract-compliance
verdict — the security review does not independently block merge, but does
not waive the main review's blocking finding either.
