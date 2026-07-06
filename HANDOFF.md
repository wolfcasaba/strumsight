# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next". Update it after every development round (see
> [How to update](#how-to-update-this-file) at the bottom). Last updated: **2026-07-06** (round 18).

---

## 1. What this project is

**StrumSight** — an **offline, on-device** Flutter (Android-first) app that shows, in real time
while you play guitar: the **current chord** + the **strum direction (↓ down / ↑ up)** — the headline
feature other chord apps skip. **Detection is 100% on-device** (no audio ever leaves the phone).

As of round 15 there is an **OPTIONAL account layer** (FastAPI backend, `backend/`) for login +
cloud settings sync. It is opt-in: the app is **fully usable logged out**, and detection never
touches the network. Payments are out of scope.

- Repo: `/home/ubuntu/music-theory` (standalone; reuses recipewiser-mobile infra, NOT part of it).
- Spec: `docs/` (`c7b1a4e` spec, `b593ca4` plan). DSP source-of-truth: `docs/rag/chunks/`.
- Version: **v0.2.0** — REAL on-device detection in pure Dart; optional account layer added.

## 2. Current status — DONE ✅

| Area | State | Where |
|------|-------|-------|
| **Live** screen — big chord, ↓/↑ arrow, confidence pill, `1 & 2 & 3 & 4` beat counter, status bar | ✅ REAL mic detection | `lib/features/live/` |
| **Tuner** — note + cents gauge + in-tune indicator | ✅ REAL YIN pitch (mic) | `lib/features/tuner/` |
| **Settings** — theme (persisted), lang en/hu, confidence threshold (persisted), version | ✅ built | `lib/features/settings/` |
| **DSP pipeline** — whitened spectral-flux onsets, peak-picked chroma → 24-template chord, sub-band strum ↓/↑, median-IOI tempo | ✅ pure Dart, runs in isolate | `lib/features/live/engine/dsp/` |
| **YIN pitch detector** (CMNDF, threshold 0.12) | ✅ pure Dart | `lib/features/tuner/engine/dsp/` |
| **Mic capture** | ✅ `audio_streamer` → PCM chunks | `lib/core/audio/mic_capture.dart` |
| **Design system** — dark M3, copper accent, semantic confidence ramp (shape+colour) | ✅ | `lib/core/theme/` |
| **i18n** en/hu, go_router bottom-nav shell | ✅ | `lib/l10n/`, `lib/app/` |
| **Live mic error surfacing** — Retry banner, no silent no-op | ✅ round 13 | `lib/features/live/` |
| **Account backend** (FastAPI + SQLite + JWT): register/login/me, GET/PUT settings | ✅ round 14, 14 pytest green | `backend/` |
| **Flutter auth** — optional login/register, secure token, Account UI in Settings | ✅ round 15 | `lib/features/auth/` |
| **Settings cloud sync** — pull on login, push on change, register adopts local | ✅ rounds 16–17 | `lib/features/settings/providers/settings_sync.dart` |
| **Tests** | ✅ **65 Flutter + 14 backend green** (widget + DSP unit + randomized property + auth/sync + pytest) | `test/`, `backend/tests/` |
| **CI → APK** | ✅ (Flutter only; backend has no CI yet) | `.github/workflows/build-apk.yml` |
| **HORIZON**: git-notes experience buffer + randomized property gate | ✅ adopted round 12 | see notes below |

**Account layer (optional, `backend/`):** FastAPI · SQLAlchemy 2 · SQLite (Postgres-ready) · JWT
(PyJWT) · bcrypt. Endpoints: `/health`, `/auth/register|login|me`, `GET/PUT /settings`. Flutter side:
`ApiConfig` (`STRUMSIGHT_API_URL` dart-define, default `http://10.0.2.2:8000`), Dio + bearer
interceptor, `flutter_secure_storage` (v10 — keeps ONE win32 major), `AuthController`
(AsyncNotifier), `SettingsSync`. Login/register: `SecureTokenStore` stores JWT; **login/restore
pulls** the cloud profile, **register pushes** local settings up (no clobber). Run: see `backend/README.md`.

**Architecture (the important mental model):**
```
mic (audio_streamer) ─▶ DSP ISOLATE  (LivePipeline)          ┌─ Live screen watches LiveFrame ~15Hz
  PCM chunks           ├─ fast 1024/256 : whitened flux → onsets → sub-band ↓/↑
                       ├─ slow 4096/1024: peak-picked chroma → 24-template chord
                       └─ tempo (median IOI) + bar slots ─▶ LiveFrame
```
UI only talks to `StrumEngine` / `TunerEngine` **interfaces**. `RealStrumEngine`/`RealTunerEngine`
run the pipeline off the UI isolate; `stop()` releases the mic. Mocks remain as deterministic test infra.
Pipeline is driven by a **sample-count clock** (not wall-clock) → deterministic + platform-free.

## 3. What's NOT done — NEXT 🔜

- **⚠️ Live mic on a real device** — the mic→DSP→UI wiring is audited & correct in code, and mic
  start-errors now surface (round 13). But "does it detect a real guitar" is **NOT verified on
  hardware** — this is the user's real-guitar APK acceptance test. If it still seems dead, the new
  Retry banner + error will now say *why* (permission vs mic-busy vs platform error).
- **`tuning_a4` sync** — the backend/model has it, but there is NO local A4 setting/UI yet, so it is
  intentionally NOT synced (see `settings_sync.dart`). Wire a tuner-calibration UI + local provider first.
- **Backend hardening for prod** — SQLite→Postgres, Alembic migrations, real `STRUMSIGHT_SECRET_KEY`,
  lock CORS origins, rate-limit auth, add backend CI. Currently dev-grade (documented in `backend/README.md`).
- **Password reset / email verification / refresh tokens** — not implemented (14-day JWT, no refresh).
- **Analyze** (recording → timeline) — placeholder only (`lib/features/analyze/`). → v2.
- **Library** (offline saved sessions) — placeholder only (`lib/features/library/`). → v2.
- **iOS build** — needs a Mac. Android-first for now.
- **FINAL acceptance is the user's real-guitar APK test** — synthetic-green is never "done" (HORIZON).
  The optional C++/FFI port is an optimization path *only if on-device profiling demands it*.
- Optional later: TFLite strum-direction model.

## 4. Round history (from git notes — `git log --show-notes`)

| Round | Commit | tests | Lesson (compressed) |
|------:|--------|------:|---------------------|
| 18 | (this) | 65+14 | docs + CORS polish (bearer → allow_credentials=False so "*" stays valid); handoff/README/CLAUDE updated for the account layer |
| 17 | — | 65 | devil-advocate caught register-clobber (C1) + offline silent-lost-write (H1), both green in mocks. Fix = typed AuthEvent (login pull vs register push) + signature-only-after-confirm + explicit _applyingPull guard; resume must invalidate provider to clear AsyncError |
| 16 | — | 63 | settings sync echo-guard via value-signature (listeners fire async); SharedPreferences.setMockInitialValues needed for notifier-setter tests; override settingsRepo in widget tests that restore a session |
| 15 | — | 59 | secure_storage v10 keeps win32 ^6 (ONE major); Riverpod 3.3.2 AsyncValue uses `.value` (nullable) not `.valueOrNull`; `Override` type not nameable in test build; INTERNET perm needed for release APK |
| 14 | — | +14 py | FastAPI account backend; bcrypt-direct avoids passlib 4.x breakage; model_fields_set distinguishes null vs omitted in partial PUT; StaticPool in-memory SQLite for isolated tests |
| 13 | `591abc2`… | 50 | mic path was correct; only gap = swallowed platform start-error → surface via stream addError + Retry banner; heartbeat frame already emits `listening` in silence |
| 12 | `591abc2` | 49 | randomized gate caught 2 real bugs deterministic suite missed (tail-spikes, slow-rake split); property generator must match domain (guitar voicings) |
| 10 | `f985aee` | 47 | sample-count clock keeps pipeline deterministic + platform-free |
| 9  | `4e80e22` | 43 | YIN first-try green, CMNDF 0.12 |
| 8  | `49c5e74` | 36 | REJECTED 2×: raw flux drowns in ring-out; log-flux lambda wrong. Fix = adaptive whitening + linear flux; synth hard-cutoff clicks need release ramp |
| 7  | `7c9ce1f` | 28 | REJECTED 1×: naive bin→pitch-class fails <250Hz. Fix = spectral peak-picking + parabolic interp |
| 6  | `c61d021` | 21 | RAG chunks are DSP source-of-truth |
| 5  | `2d48b0b` | 21 | adversarial review 38 agents / 15 findings / 14 fixed / 1 deferred (rebuild-scope) |
| 4  | `2220c98` | 18 | shell child = no nested Scaffold |
| 3  | `138b078` | 14 | shape+colour for meaning (never colour alone) |
| 2  | `acd525f` | 8  | engine interface before real impl |
| 1  | `3036a07` | 1  | design-token retune: keep names |

## 5. How to work here (must-follow)

- **Verify gate before "done"** — run as **SEPARATE** calls (chaining OOMs this box):
  ```bash
  ~/flutter/bin/flutter analyze lib/     # clean
  ~/flutter/bin/flutter test             # all green
  cd backend && .venv/bin/python -m pytest   # backend green (if you touched backend/)
  ```
- **Never chain `analyze && test`.** Adding a plugin? Keep **ONE win32 major** across the tree
  (that's why `flutter_secure_storage` is pinned to v10, not v9).
- Riverpod 3 hand-written providers (NO codegen). Repository-provider pattern. Feature-first.
  **AsyncValue uses `.value` (nullable), NOT `.valueOrNull`** in this version (3.3.2).
- **DSP param change ⇒ update `docs/rag/chunks/` in the SAME commit** (source of truth).
- New DSP behaviour ⇒ add a **randomized property** in `test/property/` (not only fixed fixtures).
  Reads `PROPERTY_SEED` env (absent → 42 deterministic; CI runs a HARD step with the run id).
- **Backend writes / cloud sync are best-effort and easy to lose silently** — a failed push must NOT
  mark state as synced (round 17 H1). Verify persistence; test the offline path.
- Backend dev loop: `cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`,
  then `.venv/bin/uvicorn app.main:app --reload`. Android emulator reaches the host at `10.0.2.2`.

## 6. Every commit / round ritual (HORIZON)

```bash
git notes add -m "round=<n> verdict=pass|fail tests=<n> lesson=<slug>"   # rejected attempts logged too
git push origin 'refs/notes/*'   # notes don't push by default; push alongside the branch
```

---

## How to update this file

After **every** development round, before/at commit time, update:
1. The **date + round number** in the header.
2. Section **2 (DONE)** — move anything newly finished here.
3. Section **3 (NEXT)** — remove what's done, add newly discovered work.
4. Section **4 (Round history)** — add one row (mirror the git-notes lesson).

Keep it tight — this is a state snapshot, not a changelog. Git history holds the detail.
