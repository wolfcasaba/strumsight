# E05-R08 — Security & Privacy Review

Brief: `docs/rounds/e05-r08-vision-setup-wizard.md`
Branch: `codex/e05-r08-vision-setup-wizard` @ `b20ff23`
Base: `origin/main` @ `78ac3ce`
Reviewer: security-reviewer agent (read-only) · Dátum: 2026-08-06
Trigger: brief `ai-router` block declares `risk = "high"` (camera permission + privacy-sensitive UI) → dedicated security review mechanically required.
Method: full read of the 15-file diff + the core camera/storage contracts it consumes (`lib/core/camera/*`, `lib/core/storage/*`); import/danger-grep of the new feature; single-call-site tracing of `.request()`/`.start()`/`.acquire()`; ARB↔code symbol cross-reference; storage-key value-uniqueness check; verification that the two test files actually *gate* each safety boundary rather than merely pass; recursive real-router reachability check.

**Verdikt: PASS** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR. 2 NOTE (correctness cross-refs, non-blocking) + 1 NOTE (pre-existing context).

## Severity table

| # | Severity | File:line | One-line |
|---|---|---|---|
| 1 | NOTE (correctness, not security) | `vision_setup_controller.dart:117-123,157-160` | If `_openCameraSession()` fails *after* `selectCamera` already closed the prior session (e.g. another owner grabbed the camera mid-restart), `step` stays `ready` while `cameraSessionActive=false`. No leak, no privacy impact — UI/state-consistency matter for the correctness reviewer. |
| 2 | NOTE (privacy-positive / UX) | `vision_setup_screen.dart:252-268`, `vision_setup_controller.dart:157-195` | The `ready` step starts a real `CameraCapture` session but renders only text — it **never subscribes to `capture.frames`**. Zero frame exposure (good), but the camera hardware/indicator is active with no visible preview. Flag OFF; behind explicit grant. UX note for correctness reviewer. |
| 3 | NOTE (pre-existing, out of scope) | `android/app/src/main/AndroidManifest.xml:5` | `android.permission.CAMERA` is declared in the manifest. **Not introduced by this round** (no manifest change in the diff) and inert while the feature is dark — noted only for store-listing posture tracking. |

No finding rises to MINOR: every non-negotiable boundary and every one of the 9 requested checks verified clean with reproducible evidence below.

## Non-negotiable product boundaries (AGENTS.md §5 / brief §5) — all honored

- **Raw camera frame never leaves the device / never persisted (§5.1, ADR 0183):** The controller creates a capture and calls `start()` (`vision_setup_controller.dart:183`) but **never reads `capture.frames`** anywhere; `CameraFrame` is not imported by the feature. Only two enum-name strings are ever written (`persistSelections`, lines 103-113). Danger-grep for `dart:io|http|dio|Socket|WebSocket|package:web` across `lib/features/vision/` → **empty**. No network surface exists to exfiltrate a frame even in principle.
- **Logged-out / diagnostics-off → no hidden network (§5.2):** Zero network/IO added; feature is dark (`feature_flags.dart:21-22,66-67` both default `false`).
- **No secret/token/frame in logs, signals, errors, commits (§5.3):** The controller emits no logs. The coordinator logs only closed-enum names (`CameraOwner`, `CameraSessionRevocationReason`), `leaseId`, and a timestamp (`camera_session_coordinator.dart:100-127`) — the revocation-reason enum exists specifically to keep arbitrary text out of the structured log (`camera_session_lease.dart:8-12`). No secrets in the diff.
- **Cloud/community must not degrade the offline base (§5.4):** Skip → audio-only is reachable from every step (`vision_setup_screen.dart:45-51`, `skip()` at controller `152-155`); privacy copy states core features remain without camera (`visionSetupAudioOnlyBody`).
- **Weak confidence not shown as certain (§5.5):** N/A (no inference); the privacy disclosure ("processed on this device… not recorded" / "nem készül felvétel") is truthful given the code.

## The 9 required checks — evidence

1. **Permission requested only on explicit press.** Exactly one `.request()` call site: `vision_setup_controller.dart:146` inside `requestCameraPermission()`, wired only to the `denied`-state button (`camera_permission_panel.dart:39-44`, key `vision-permission-request` → `vision_setup_screen.dart:73-74`). `build()` (controller `63-85`) requests nothing. `initState` (`vision_setup_screen.dart:26-33`) calls `refreshPermissionState()` → `gateway.currentState()`, which is contractually dialog-free (`camera_permission.dart:90-91`; prod impl uses `Permission.camera.status`, `:69-70`). Test asserts `requestCalls==0` after refresh, `==1` after the explicit action (`vision_setup_controller_test.dart:122-141`). **Clean.**
2. **No raw frame / image byte persisted.** Only `store.writeString` of `selectedProfile.storageValue` and `selectedCamera.storageValue` (controller `104-112`). The persistence test asserts **exact map equality** `{visionSetupProfile: 'fullUpperBody', visionCamera: 'front'}` — any stray key fails it (`..._controller_test.dart:116-119`). **Clean.**
3. **No implicit camera start; Skip never starts.** Single `.start()` at controller `183` inside `_openCameraSession()`, reachable only from `requestCameraPermission` (after `permission.isGranted`, `:148`) or from `selectCamera` **only when a session was already active** (`:119-122`). `skip()` calls `_closeCameraSession()` only. Test asserts `captures isEmpty` after skip (`..._controller_test.dart:175-192`). **Clean.**
4. **≤1 active lease; no leak on any failure path.** Single `.acquire()` at controller `163`. Cleanup verified on: acquire-`Failure` (`:175-177` close capture, return), `start()` failure (`:184-190` close + release + null), provider dispose (`_disposeCameraSession`, `:209-216`), and lifecycle revoke (`onRevoke`, `:165-172`). Exclusivity backstop: the coordinator's check-and-take is synchronous before its first `await` (`camera_session_coordinator.dart:39-62`), so concurrent opens cannot both win. `selectCamera` is strictly close→open (`:120-122`); the switch test proves the old capture's `closeCalls==1` before the new capture's `startCalls==1` (`..._controller_test.dart:143-173`). **Clean.**
5. **No hardcoded user-facing strings.** All 28 `l10n.visionSetup*` symbols used in the widgets/screen resolve to ARB keys (cross-ref: 0 missing); en/hu key sets identical. The only string interpolations are widget keys (`vision-setup-guide-${profile.name}`) and log fields — never user-facing text. **Clean.**
6. **`permanentlyDenied`/`restricted` → Settings CTA, no dead retry; `unavailable` ≠ `denied`.** `camera_permission_panel.dart:46-58`: both `permanentlyDenied` and `restricted` route to `_settingsPanel` (Open-Settings button, **no** request button); `unavailable` renders an explanatory panel with **no** request and **no** settings button and distinct copy. Five matrix widget tests assert exactly this, including `find(...request) findsNothing` for each terminal state (`vision_setup_screen_test.dart:92-186`). **Clean.**
7. **Route unreachable unless both flags true.** Hard `if (visionEnabled && visionSetupEnabled) ...[GoRoute(...)]` around the *registration* (`app_router.dart:228-233`) — not a UI conditional. `VisionSetupScreen` and `AppRoutes.visionSetup` each have exactly one consumer (that GoRoute); no other push/deep-link exists. Both flags default `false`. The flag test reads the **real `routerProvider`** and recursively confirms the route is absent when either flag is off (`vision_setup_screen_test.dart:233-261`). **Clean.**
8. **`storage_keys.dart` purely additive.** Diff adds two `static const String` + two `all`-list entries; no existing key renamed/removed/reassigned. Both values (`ss.vision.setup_profile`, `ss.vision.camera`) are unique (no duplicate `ss.*` literal) and absent on base (`git show 78ac3ce` → 0 hits). **Clean.**
9. **Prompt-injection-adjacent.** N/A (no AI/LLM/tool-calling code). Adjacent robustness: stored profile/camera values are read via `firstWhere(... orElse: default)` (`vision_setup_profile.dart:14-18,36-40`; controller `87-96`), so a tampered preference **fails safe to a default enum**, never to executable/instruction content. **Clean.**

## OWASP-relevant spot-checks

- **Injection / unsafe interpolation:** none — no SQL/shell/eval; interpolations are widget keys and closed-enum log fields only.
- **Insecure storage:** correct store selection — non-secret enum prefs go to `keyValueStoreProvider` (SharedPreferences-backed, `storage_providers.dart:13`); `secureStoreProvider` (`FlutterSecureStore`) exists separately and is **not** used here (nothing sensitive to protect). No token/secret stored.
- **Missing null/error → insecure default:** all fail-closed. Permission gateway maps `MissingPluginException`/any error to `unavailable`, **never** `granted` (`camera_permission.dart:114-124`). Stored-value parsing falls back to a safe default. Acquire/start failures tear down and return. `build()` seeds `permissionState: denied` (conservative), corrected by the dialog-free status read.
- **Supply chain:** no `pubspec`, asset, native-manifest, or `.podspec/gradle` change in the diff — no new dependency, permission, or asset surface.

## What was verified clean (summary)

Scope = exactly the 15 declared files, all within `allowed_paths`. No network/IO/secure-store/secret/AI-provider surface introduced. No frame subscription anywhere. Feature dark by default (both flags `false`); route structurally unreachable when off. Tests genuinely gate the boundaries (exact-map persistence assertion, `requestCalls` counter, `captures isEmpty` on skip, close-before-open lease assertion, recursive real-router flag check), not incidental passes.

## Recommendation

**Merge is not blocked by this security review.** The three NOTEs are non-security (state-consistency edge case, a privacy-positive UX observation, and a pre-existing manifest fact) and belong to the correctness reviewer / future tracking — none require a change in this round. Merge on exact-SHA green CI per the round's own §11.

---

**Summary: PASS — 0 BLOCKER, 0 MAJOR** (0 CRITICAL; 3 NOTE, all non-blocking).
