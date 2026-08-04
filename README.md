# StrumSight 🎸

**See what you strum.** An offline, on-device Flutter app that shows the current chord **and the
strum direction (↓ down / ↑ up)** in real time while you play guitar — the one output every other
chord-detection app leaves out.

- **On-device detection** — the mic → DSP → ML pipeline runs entirely on the phone; **no audio
  ever leaves the device**, and the app is fully usable offline and logged out.
- **Strum direction as the headline** — down/up per beat, with a confidence ramp.
- **Optional account** — an opt-in login (FastAPI backend, [`backend/`](backend/README.md)) syncs
  your *settings* across devices. Purely additive: logged out, nothing hits the network — enforced
  by a system-level zero-request test (`test/app/offline_network_guard_test.dart`).
- **Android-first** (iOS later; needs a Mac to build).

> **Client version:** the single source of truth is `version:` in [`pubspec.yaml`](pubspec.yaml)
> (read at runtime via `package_info_plus` and shown in Settings). Do not restate a version number
> anywhere else in the docs.
>
> **Status:** Epic 1 is complete. Epic 3 has an evidence ledger, but its release
> blockers are still open; see
> [`docs/sdd/epic-03-completion-report.md`](docs/sdd/epic-03-completion-report.md).
> Live state snapshot: [`HANDOFF.md`](HANDOFF.md).

---

## Features

| Surface | State |
|--------|-------|
| 🎤 **Live** — current chord, ↓/↑ arrow, confidence pill, beat counter; DSP + CRNN ML on-device | ✅ real detection |
| 🎛️ **Tuner** — note + cents gauge (YIN pitch) | ✅ real detection |
| 🎬 **Analyze** — record a clip, get a chord/strum timeline | ✅ |
| 📚 **Library** — saved sessions (rename, review) | ✅ |
| 🎓 **Learn** — lessons with chord audio + metronome · **Songs** · **Progress** · **Streak** | ✅ |
| 🎯 **Practice (V2)** — Strum Pattern / Chord Changes / Chord Progression / Rhythm Only / Free Practice / Speed Builder · migrated Learn path is live (`migratedLearnEnabled` flag), self-practice Hub→Session path is feature-flagged (see known limitations) | ⚠️ domain tested; rollout flag-gated |
| 🎼 **Song Trainer (V2)** — local StrumSight JSON, MusicXML/MXL, and SMF 0/1 MIDI import; scoped trainer/result/progress and Setlist V2 components | ⚠️ controlled rollout; no direct Guitar Pro import, Setlist route, device acceptance, or production enable yet |
| ⚙️ **Settings** — theme, language (en/hu), thresholds; cloud-synced when logged in | ✅ |
| 🔐 **Account** (optional) — email/password JWT login, settings sync only | ✅ opt-in |
| 🧪 **Lab mode** — on-device diagnostics capture + upload to the Lab backend | ✅ dev-only |

## Known limitations

- **Self-practice Hub → Setup → Session path** is feature-flagged:
  `practiceSessionHostProvider` defaults to `null` and the production
  presentation→controller wiring is deferred to a follow-up round. The
  Practice V2 **domain** (timer, matcher, scorer, history) is fully
  tested and live behind the migrated Learn path
  (`migratedLearnEnabled` ON); the standalone self-practice route is
  blocked at the gate. See
  [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md)
  §3 for the rendszerszintű rés and §5 for the per-cell DoD status.
- **Legacy Learn parity at the 280 ms window edge** carries one
  documented micro-divergence between the legacy `LessonScorer` `double`
  arithmetic and the V2 integer-µs timeline (ADR 0075 §2b, R19 §0.3).
  Pinpoint cells: `first-strums[0]` and `anthem-drive[5,6]`.
- **Free Practice result tile** shows `attemptsCount` instead of the
  raw strum count (R18 n1 follow-up, opened).
- **DSP and ML asset parity** is locked at the Epic-1 baseline — no DSP
  parameter change in Epic-2 (AGENTS.md §9).
- **Song Trainer V2 and Setlist V2 are not release-enabled.** Guitar Pro uses
  external conversion to MusicXML/MXL/MIDI; the Setlist UI components have no
  registered app route yet, and the device checklist/CI review evidence remains
  open. The exact supported subset and each named blocker are in
  [`docs/sdd/epic-03-completion-report.md`](docs/sdd/epic-03-completion-report.md).
- **iOS build** requires a Mac (no Linux toolchain).

## Architecture

```
mic (audio_streamer) ──▶ DSP ISOLATE                         ┌─ Live screen
  PCM chunks             LivePipeline                        │   watches
                         ├─ fast  1024/256 : whitened flux ─ onsets → sub-band ↓/↑
                         ├─ slow 4096/1024 : peak-picked chroma → 24-template chord
                         ├─ CRNN chord + strum nets (TFLite-free pure-Dart inference)
                         └─ tempo (median IOI) + bar slots → LiveFrame ~15 Hz ──▶ UI
```

- **Feature-first layout:** `lib/features/<feature>/` (screens/providers/repositories/models),
  shared code in `lib/core/` (music domain, audio codec/DSP, foundation `AppResult`/`AppFailure`,
  network, storage, logging, platform seams, theme, i18n).
- **State:** Riverpod 3 hand-written providers (no codegen); repository-provider pattern.
- **Routing:** `go_router` with a central route catalogue (`lib/app/routing/`, ADR 0059).
- **Architecture rules are machine-enforced:** `dart run tool/check_architecture.dart` — core
  never imports features, the shared domain is Flutter-free, cross-feature imports go through
  `public.dart`, and the 12-entry allowlist may only shrink (ADR 0057/0058). Runs in CI.
- Every DSP parameter is documented + sourced in [`docs/rag/`](docs/rag/README.md); changes
  require an ADR and a same-commit chunk update (AGENTS.md §9).

## Run

```bash
~/flutter/bin/flutter pub get
~/flutter/bin/flutter run          # boots to the Live tab
```

## Build environments

`--dart-define=STRUMSIGHT_ENV=development|staging|production` (validated, fail-closed
`AppConfig` at bootstrap). Key flags:

- `STRUMSIGHT_API_URL` — account backend base URL (default `http://10.0.2.2:8000` for emulators).
- `STRUMSIGHT_ACCOUNT_ENABLED` — opt-in account layer; disabled ⇒ zero account requests.
- Diagnostics (Lab) has its own flag + consent gate; disabled ⇒ the client is never created.
- Production APK: `release-apk.yml` only — **fail-closed signing** (missing secrets stop the
  first step; no debug-signing fallback, ADR 0062). Local `flutter build apk --release`
  without `key.properties` intentionally uses the debug key for sideloading.

## Backend (optional account layer)

FastAPI + SQLite + JWT in [`backend/`](backend/README.md) — login + settings sync only;
detection never touches it. Alembic owns the production schema; `/health/live` +
`/health/ready`; production is fail-closed (secret validation, SQLite guard, Lab routes not
registered). Run/tests: `backend/README.md`.

## Lab mode

Dev-only diagnostics: flag-gated routes (`diagnostics_enabled`, prod default OFF — the routes
do not exist in production), token-guarded streaming upload with size limits, explicit user
consent in-app. See ADR 0061.

## Testing

Run as **SEPARATE** calls (chaining `analyze && test` OOMs this box):

```bash
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
~/flutter/bin/flutter analyze lib/ test/ tool/
~/flutter/bin/flutter test                          # ~1000 tests; full suite normally in CI
~/flutter/bin/flutter test test/property            # randomized property gate (PROPERTY_SEED)
~/flutter/bin/dart run tool/check_architecture.dart
cd backend && .venv/bin/python -m pytest            # 64 backend tests
```

CI (`.github/workflows/`): `build-apk.yml` and `release-apk.yml` share one gate chain via
`.github/actions/flutter-gates` (format → analyze → architecture → asset → test → randomized
property), with coverage in a parallel required job; `backend-ci.yml` runs Ruff + pytest +
an isolated Alembic upgrade. The final acceptance predicate is always a real-guitar APK test
on a physical device — synthetic green is never "done".

## Offline & privacy

- Audio never leaves the device; detection is 100% on-device.
- Logged out / account-disabled / diagnostics-disabled ⇒ **zero network requests**, proven by
  `test/app/offline_network_guard_test.dart` at the single `DioFactory` seam
  (`test/tooling/dio_factory_guard_test.dart` guarantees no other Dio source exists).
- Tokens live in `flutter_secure_storage`; logs are redacted (no token/password/raw audio).

## Model assets

CRNN chord/strum models ship as binary assets under `assets/ml/`, described by a **generated
manifest** (`assets/ml/model_manifest.json`, created by `ml/make_manifest.py`). A two-way CI
gate (`test/tooling/ml_asset_manifest_test.dart` + asset gate) keeps pubspec, manifest and
binaries in sync (ADR 0063). The manifest is intentionally not a Flutter asset — it is
build/guard-time metadata.

## What's next

Epic 2 — Practice Engine (`docs/sdd/03-epic-02-practice-engine.md`). Payments/monetization
remain out of scope for now.
