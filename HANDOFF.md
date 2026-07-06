# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next". Update it after every development round (see
> [How to update](#how-to-update-this-file) at the bottom). Last updated: **2026-07-05** (round 12).

---

## 1. What this project is

**StrumSight** — an **offline, 100% on-device** Flutter (Android-first) app that shows, in real time
while you play guitar: the **current chord** + the **strum direction (↓ down / ↑ up)** — the headline
feature other chord apps skip. No backend, no network at runtime. Payments are out of scope.

- Repo: `/home/ubuntu/music-theory` (standalone; reuses recipewiser-mobile infra, NOT part of it).
- Spec: `docs/` (`c7b1a4e` spec, `b593ca4` plan). DSP source-of-truth: `docs/rag/chunks/`.
- Version: **v0.2.0** — REAL on-device detection in pure Dart.

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
| **Tests** | ✅ **49 tests green** (widget + DSP unit + randomized property) | `test/` |
| **CI → APK** | ✅ | `.github/workflows/build-apk.yml` |
| **HORIZON**: git-notes experience buffer + randomized property gate | ✅ adopted round 12 | see notes below |

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

- **Analyze** (recording → timeline) — placeholder only (`lib/features/analyze/`). → v2.
- **Library** (offline saved sessions) — placeholder only (`lib/features/library/`). → v2.
- **iOS build** — needs a Mac. Android-first for now.
- **FINAL acceptance is the user's real-guitar APK test** — synthetic-green is never "done" (HORIZON).
  The optional C++/FFI port is an optimization path *only if on-device profiling demands it*.
- Optional later: TFLite strum-direction model.

## 4. Round history (from git notes — `git log --show-notes`)

| Round | Commit | tests | Lesson (compressed) |
|------:|--------|------:|---------------------|
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
  ```
- **Never chain `analyze && test`.** `dependency_overrides` pins `device_info_plus: ^13` (load-bearing — don't remove).
- Riverpod 3 hand-written providers (NO codegen). Repository-provider pattern. Feature-first.
- **DSP param change ⇒ update `docs/rag/chunks/` in the SAME commit** (source of truth).
- New DSP behaviour ⇒ add a **randomized property** in `test/property/` (not only fixed fixtures).
  Reads `PROPERTY_SEED` env (absent → 42 deterministic; CI runs a HARD step with the run id).
- `lucide_icons_flutter` icon names fail only at compile — verify them.
- Backend writes are swallowed by try/catch → verify persistence (currently no backend configured).

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
