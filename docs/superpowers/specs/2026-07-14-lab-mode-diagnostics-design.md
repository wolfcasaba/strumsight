# Lab Mode — Field Diagnostics — Design

**Date:** 2026-07-14 · **Rounds:** 197+ · **Status:** approved (user, inline Q&A)

## Goal

Close the improve-loop for the full-band ML chord model: the user tests on a
real guitar, the app captures real detection data, uploads it over the internet,
and Claude reads it on the box to see exactly what to improve. Replaces manual
reporting. The real-guitar/full-mix test stays the acceptance gate.

## Settled decisions (user)

- **Collect:** metadata + CQT features + **short audio clips** (opt-in; the user
  is the consenting tester on their own device — this does NOT change the default
  "audio stays on device" promise, which remains true when Lab mode is OFF).
- **Surfaces:** BOTH Live (streaming) and Analyze (batch).
- **Opt-in** toggle in Settings, OFF by default, with explicit consent copy.

## Architecture

### Client (Flutter)
1. **Settings toggle** `labModeProvider` (persisted, off by default) + consent
   copy: "Lab mode collects detection data and short audio clips and uploads them
   over the internet to improve chord detection. Only while it's ON."
2. **Dual detection when ON:** run the NEW ML chord path
   (`CqtExtractor`→`ChordCrnn`→`ViterbiChordDecoder`, r194-196, parity-locked)
   ALONGSIDE the shipped DSP chroma-dictionary, in both Live and Analyze. This is
   also the r197 ML-wiring — but gated by the flag, so the default experience is
   unchanged. (Viterbi is fed the ChordCrnn's 25-dim log-posteriors instead of
   chroma cosine; `selfBonus` re-fit for the log-posterior scale — the one knob.)
3. **DiagnosticsRecorder** — a rolling session buffer: per detection event
   `{tSec, mlChord, dspChord, agree, mlConf, dspConf, strumDir, bpm, inputLevel}`;
   a ring of CQT feature frames; short (~3-6 s) audio clips captured around
   low-confidence / ML≠DSP moments (bounded total size).
4. **Diagnostics screen** (from Settings / a Lab badge) — live ML-vs-DSP view
   (both current chords, agreement %, confidence bars, rolling event log), session
   stats, and upload status.
5. **Uploader** — batch the session (JSON metadata + gzipped features + audio) →
   `POST ${ApiConfig.baseUrl}/diagnostics` with a build-time `STRUMSIGHT_DIAG_TOKEN`
   header. Background/chunked; retries; never blocks detection.

### Backend (FastAPI, `backend/`, on the box)
- New `/diagnostics` router: `POST /diagnostics` (multipart: JSON session +
  optional audio) → store to disk (one dir per session) + a SQLite row; validate
  the shared token; return the session id. `GET /diagnostics/health`.
- Keep it dependency-light; reuse the existing app factory + SQLite.

### Transport / infra
- Box public IP **130.61.34.141**; `cloudflared` installed; `gitea-tunnel.service`
  proves the pattern. Run uvicorn (`backend/`) on the box; expose via a
  **cloudflared quick tunnel** → `https://…trycloudflare.com`.
- Build the APK (GitHub CI, per apk-build-on-github) with
  `--dart-define=STRUMSIGHT_API_URL=<tunnel>` and `--dart-define=STRUMSIGHT_DIAG_TOKEN=<secret>`.
- Quick-tunnel URL changes on restart → rebuild APK, or set up a named tunnel for
  a stable URL (later).

### Claude's analysis loop
- Read stored sessions on the box → ML-vs-DSP disagreement, confidence
  distributions, per-chord error patterns, and offline reference detection on the
  short audio for ground truth → a "what to improve" report driving the next rounds.

## Rollout (increments)
- **r197:** wire `CqtExtractor→ChordCrnn→ViterbiChordDecoder` behind the flag
  (Analyze first, then Live); adapt Viterbi to 25-dim posteriors; integration test.
- **r198:** DiagnosticsRecorder + Diagnostics screen (live ML-vs-DSP).
- **r199:** backend `/diagnostics` + uploader client + tunnel + APK build.
- Then: Claude's offline analysis of the first real sessions.

## Privacy / safety
- OFF by default; audio only uploaded while explicitly ON; clear consent copy.
- Shared build-time token gates the endpoint (blocks random spam), not real auth.
- Data lives on the box (the user's own infra); used only to improve detection.

## Verification
- Backend: pytest for `/diagnostics` (store + token reject) + a live `curl` to the
  tunnel. Client: unit tests for the recorder + uploader (mock Dio); the ML-wiring
  integration test; screen widget test. Final: the real-guitar APK session end to
  end (Claude confirms the uploaded session on the box).
