# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next". Update it after every development round (see
> [How to update](#how-to-update-this-file) at the bottom). Last updated: **2026-07-09** (round 52).

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
  Round 28 upgraded the chord path to a Chordino-class **dictionary + Viterbi** engine (extended chords).
  Round 29 added the first **growth feature**: a shareable 9:16 "Strum Card" (research chunk 013).

## 2. Current status — DONE ✅

| Area | State | Where |
|------|-------|-------|
| **Live** screen — big chord, ↓/↑ arrow, confidence pill, `1 & 2 & 3 & 4` beat counter, status bar | ✅ REAL mic detection | `lib/features/live/` |
| **Tuner** — note + cents gauge + in-tune indicator | ✅ REAL YIN pitch (mic) | `lib/features/tuner/` |
| **Settings** — theme (persisted), lang en/hu, confidence threshold (persisted), version | ✅ built | `lib/features/settings/` |
| **DSP pipeline** — whitened spectral-flux onsets, **NNLS bass+treble chroma → chord-dictionary + Viterbi** chord, sub-band strum ↓/↑, median-IOI tempo | ✅ pure Dart, runs in isolate | `lib/features/live/engine/dsp/` |
| **Voice/noise rejection** — tuner clarity+stability+range gates; chord tonalness gate | ✅ round 23 | `dsp/tuner_analyzer.dart`, `dsp/chroma…` |
| **NNLS chord engine** — STFT→log-freq→NNLS transcription→chroma (overtone suppression) + **bass+treble 24-dim split** | ✅ round 25, split round 28 | `lib/features/live/engine/dsp/nnls_chroma.dart` |
| **Chord DICTIONARY + Viterbi** — 24-dim chord profiles (maj/min/7/maj7/m7/sus4 + N.C.) → online self-transition Viterbi; **extended chords (7ths), inversions via bass, N.C. state**; replaces templates + hysteresis. Fixes the round-26 7th failure (G7/A7/B7 detected; plain triads stay triads) | ✅ **round 28** | `dsp/chord_dictionary.dart`, `dsp/viterbi_chord_decoder.dart` |
| **YIN pitch detector** (CMNDF, threshold 0.12) | ✅ pure Dart | `lib/features/tuner/engine/dsp/` |
| **Mic capture** | ✅ `audio_streamer` → PCM chunks | `lib/core/audio/mic_capture.dart` |
| **Design system** — dark M3, copper accent, semantic confidence ramp (shape+colour) | ✅ | `lib/core/theme/` |
| **i18n** en/hu, go_router bottom-nav shell | ✅ | `lib/l10n/`, `lib/app/` |
| **Live mic error surfacing** — Retry banner, no silent no-op | ✅ round 13 | `lib/features/live/` |
| **Account backend** (FastAPI + SQLite + JWT): register/login/me, GET/PUT settings | ✅ round 14, 14 pytest green | `backend/` |
| **Flutter auth** — optional login/register, secure token, Account UI in Settings | ✅ round 15 | `lib/features/auth/` |
| **Settings cloud sync** — pull on login, push on change, register adopts local | ✅ rounds 16–17 | `lib/features/settings/providers/settings_sync.dart` |
| **Tuning reference A4** (400–480 Hz) — Settings stepper, drives tuner note/cents, shown on Live+Tuner, synced | ✅ round 19 | `lib/features/settings/providers/tuning_reference_provider.dart` |
| **Analyze** — record a clip → chord + strum-direction **timeline** (batch DSP off-isolate) | ✅ round 20 | `lib/features/analyze/` |
| **Library** — save / list / reopen analyzed sessions (offline) | ✅ round 21 | `lib/features/library/` |
| **Account UI gating** — Sign-in hidden by default until a backend is hosted | ✅ round 22 | `ApiConfig.accountEnabled` |
| **Capo / transpose** — Settings stepper (0–11), shows the fretted SHAPE (detected − capo) on Live + Analyze + Library, "Capo N" badge | ✅ round 26 (local-only, view-time) | `lib/features/settings/providers/capo_provider.dart`, `Chord.transposeLabel/Summary` |
| **Share / viral "Strum Card"** — 9:16 branded card (chords + the ↓/↑ **strum pattern** hero + BPM/down/up/length + wordmark) → OS share sheet w/ caption + `#StrumSightChallenge` + install link; text-only fallback. Entry: Analyze done + Library detail. **Growth: the moat as shareable content** (research chunk 013) | ✅ **round 29** | `lib/features/share/` |
| **Practice streak + daily challenge** — 🔥 streak (loss-aversion: +1/day, streak-freeze covers a 1-day gap, awarded every 7d cap 3) persisted local; **deterministic daily strum-pattern challenge**; 🔥 badge in Live header → `/streak` screen (streak/longest/freezes + nudge + today's pattern). Practice credited on a real Live strum or a completed Analyze. **Growth: retention loop** (chunk 013) | ✅ **round 30** | `lib/features/streak/` |
| **First-run onboarding** — 3-page skippable flow (moat-first: real-time chord → ↓/↑ direction → daily streak) + mic-permission priming → Live. Gated by a persisted flag loaded in `main()`, enforced by the router `redirect` (no flicker; default seen=true so tests skip it). **Growth: activation** (chunk 013) | ✅ **round 31** | `lib/features/onboarding/` |
| **Learn (play-along)** — Yousician-class trainer with our OWN animation: a **strum highway** (chord + ↓/↑ arrows flow to a strike line in tempo, down=copper/up=green, pulse on cross) + count-in. 5th **Learn** nav tab (built-in lessons + today's challenge as a playable lesson). Pure `LessonTiming` + `Ticker`-driven player. (chunk 014) | ✅ **round 32** | `lib/features/learn/` |
| **Learn — live scoring** — while a lesson plays, the real mic/DSP scores each stroke on **direction + timing** (hit/wrong-way/miss, combo, accuracy, pass ≥70%) via a pure `LessonScorer`; live HUD + hit-flash + end summary; a passed run records practice (feeds the streak). `LiveFrame.strumSeq` makes discrete strums detectable. Mic→score path verifiable only on-device. (chunk 014) | ✅ **round 33** | `lib/features/learn/lesson_scorer.dart` |
| **Learn — curriculum** — 12 lessons across Beginner/Intermediate/Advanced tiers; per-lesson **best-score + 0–3 stars** (persisted local); list grouped by tier with **progression** (pass a lesson to unlock the next). (chunk 014) | ✅ **round 34** | `lib/features/learn/model/lesson_progress.dart`, `providers/lesson_progress_provider.dart` |
| **Learn — shareable score card** — end-of-lesson 9:16 brag card (score % + stars + best combo + moat + install link) → OS share sheet; reuses a generic `ShareService.shareImage`. Wires Learn into the viral loop. (chunks 013/014) | ✅ **round 35** | `lib/features/learn/widgets/lesson_score_card.dart`, `screens/lesson_score_preview_screen.dart` |
| **Learn — metronome** — hear the beat while playing along: a **pure-Dart synthesised click** (no asset) played via `audioplayers`, on every crossed beat (accent on downbeats, count-in included), with a mute toggle. Fire-and-forget playback. (chunk 014) | ✅ **round 36** | `lib/features/learn/audio/metronome.dart` |
| **Learn — jam mode (backing)** — a Jam toggle plays a synthesised chord backing (soft pad on bar downbeats) with **scoring off** (so the mic doesn't grade the app's own audio). Shared `audio/wav.dart`. | ✅ **round 48** | `lib/features/learn/audio/chord_audio.dart` |
| **Progress dashboard** — a Yousician/Simply-class practice tracker, **on-device**: total practice time, days played, sessions, current streak, a **weekly minutes bar chart** (hand-drawn, no chart-lib overflow risk), a **per-source breakdown** (Live/Learn/Analyze), and — the moat metric no competitor tracks — **strum-direction accuracy over time** (avg + best). Fed by a new `PracticeLog` store; Live/Analyze/Learn each append a `PracticeEntry` (Learn carries the ↓/↑ score). Reached from the streak app-bar + a Settings tile. | ✅ **round 49** | `lib/features/progress/` |
| **Song Builder (your own songs)** — a build-your-own answer to Ultimate Guitar / Chordify / Songsterr song libraries, **offline + with our ↓/↑ scoring**: pick a chord progression, author an 8-slot **strum pattern** (tap each slot rest→↓→↑ — the moat, now author-able), set the tempo → save. Saved songs persist locally and **play as fully scorable Learn lessons** (feed the streak + Progress). List with edit/delete + a `StrumPatternEditor` widget. Reached from the Learn app-bar. | ✅ **round 50** | `lib/features/songs/` |
| **Songwriter helper (suggest a progression)** — a ✨ Suggest sheet in the Song Builder: pick a **key** (C/G/D) → tap a **common progression** (Pop I–V–vi–IV, '50s, Axis, Folk, Pachelbel) → its diatonic chords fill the song. Pure, tested music theory (`theory/progressions.dart`); every generated chord is guaranteed to have a `ChordShapes` fingering (asserted). | ✅ **round 51** | `lib/features/songs/theory/`, `widgets/progression_picker.dart` |
| **Share a song** — a share ⬆ action on each saved song turns it into the same 9:16 **Strum Card / Strum Reel** a recorded clip gets (via `Song.toAnalyzeResult()` — chords + ↓/↑ pattern → synthetic `AnalyzeResult`), so a user-authored song is a moat-showcasing, install-linked post. Reuses the whole share pipeline verbatim. | ✅ **round 52** | `lib/features/songs/` (`toAnalyzeResult`), `song_list_screen.dart` |
| **Strum Reel** — a full-screen, looping, branded ANIMATED replay of a recording (chords + ↓/↑ flowing in tempo) to **screen-record & share** — the "Strum Cam" moat-as-motion, no encoder plugin/mic conflict. From the share hub. (chunks 013/014) | ✅ **round 47** | `lib/features/share/screens/strum_reel_screen.dart` |
| **Learn — more content + library search** — 12 lessons now (added Fifties Doo-Wop, Anthem Drive, Rising Minor, Blues Shuffle); a **search box** on the chord library. | ✅ **round 46** | `lib/features/learn/model/lesson.dart`, `chords/screens/chord_library_screen.dart` |
| **Left-handed mode** — a Settings toggle mirrors all chord diagrams (high-E on the left) for left-handed guitars; persisted local. `ChordDiagram` is now a `ConsumerWidget`. | ✅ **round 45** | `lib/features/settings/providers/left_handed_provider.dart` |
| **Chord library** — a browsable dictionary of every chord fingering at `/chords` (grouped Major/Minor/Sevenths/Suspended), opened from the Learn app-bar. (chunk 014) | ✅ **round 43** | `lib/features/chords/screens/chord_library_screen.dart` |
| **Chord diagrams — on Live** — the detected chord's fretting shows on the Live screen as a small top-left overlay (`Stack`/`Positioned`, no label). | ✅ **round 42** | `lib/features/live/screens/live_screen.dart` |
| **Chord diagrams** — `ChordShapes` (21 open-position fingerings) + a `CustomPaint` fretboard `ChordDiagram` (○/× + dots); the Learn player shows the current chord's fretting under the highway. (chunk 014) | ✅ **round 41** | `lib/features/chords/` |
| **Learn — practice speed** — a 50/75/100% tempo selector scales the lesson (playhead + metronome + scorer via a `bpm:` override); slow-down practice. (chunk 014) | ✅ **round 40** | `lib/features/learn/screens/learn_screen.dart` |
| **Learn — polish** — metronome mute preference **persisted**; "Practice as a lesson" also on the Analyze done view (import a fresh recording without saving). (chunk 014) | ✅ **round 39** | `lib/features/learn/providers/metronome_pref_provider.dart` |
| **Learn — chord-aware scoring** — a secondary, lag-tolerant **chord grade** (was the right chord sounding at/just-after each stroke?) shown as `Chords: N%`; never gates the direction hit. (chunk 014) | ✅ **round 38** | `lib/features/learn/lesson_scorer.dart` (`observeChord`) |
| **Learn — import a recording** — `Lessons.fromAnalyze` turns a saved Analyze clip into a play-along lesson (strums→beat-timed events on the sounding chord, clip's BPM); "Practice as a lesson" 🎓 action on the Library session detail. Unlimited content. (chunk 014) | ✅ **round 37** | `lib/features/learn/model/lesson.dart` (`fromEvents`/`fromAnalyze`) |
| **Tests** | ✅ **257 Flutter + 14 backend green** (song→share conversion + progression-theory + song model/provider/builder-flow + progress-stats/dashboard + widget + DSP unit + chord-dictionary + Viterbi + extended-chord + randomized property (9-seed verified) + auth/sync + analyze/library + capo/transpose + share-card + streak/challenge + onboarding + learn/play-along + scoring + curriculum + lesson-score-share + metronome + import-as-lesson + chord-scoring + learn-polish + speed + chord-diagrams + chord-library + left-handed + content-search + strum-reel + jam-backing + pytest) | `test/`, `backend/tests/` |
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

- **⚠️ Login / account backend is NOT hosted** — `ApiConfig.baseUrl` defaults to `10.0.2.2:8000`
  (Android **emulator** only). On a real phone login can't reach it, so the account UI is **gated OFF**
  (`ApiConfig.accountEnabled=false`, round 22). To enable: deploy `backend/` to a public host, then
  build with `--dart-define=STRUMSIGHT_ACCOUNT=true --dart-define=STRUMSIGHT_API_URL=https://…`.
  User chose to defer login (2026-07-07); app is fully usable logged out. Local ARM64 box CANNOT
  build the APK — use CI (see [[apk-delivery]]).
- **⚠️ Live mic on a real device** — the mic→DSP→UI wiring is audited & correct in code, and mic
  start-errors now surface (round 13). But "does it detect a real guitar" is **NOT verified on
  hardware** — the user's real-guitar APK acceptance test. If it seems dead, the Retry banner says why.
- **Backend hardening for prod** — SQLite→Postgres, Alembic migrations, real `STRUMSIGHT_SECRET_KEY`,
  lock CORS origins, rate-limit auth, add backend CI. Currently dev-grade (documented in `backend/README.md`).
- **Password reset / email verification / refresh tokens** — not implemented (14-day JWT, no refresh).
- **Analyze** (recording → timeline) — placeholder only (`lib/features/analyze/`). → v2.
- **Library** (offline saved sessions) — placeholder only (`lib/features/library/`). → v2.
- **iOS build** — needs a Mac. Android-first for now.
- **FINAL acceptance is the user's real-guitar APK test** — synthetic-green is never "done" (HORIZON).
  The optional C++/FFI port is an optimization path *only if on-device profiling demands it*.
- **✅ DONE round 28 — chord DICTIONARY + Viterbi engine (spec: `docs/rag/chunks/012`).** Built the
  pure-Dart, testable port: **bass+treble split chroma (24-dim) → chord-profile similarity → online
  Viterbi (+ no-chord state)**, replacing note-templates + hand-tuned hysteresis. Extended chords
  (7/maj7/m7/sus4), inversions via the bass chroma, and a principled smooth track. The round-26
  7th failure is fixed (G7/A7/B7 detected; plain triads stay triads). See "AS BUILT" params in
  chunk 012. **Strum ↓/↑ direction remains our unique moat — no competitor does it.**
- **⭐ NEXT — carry over the two remaining chunk-012 stages: spectral whitening (pre-NNLS, exp ≈1.0)
  and per-frame tuning estimation.** Both were deferred in round 28 because they only bite on REAL
  coloured/detuned audio — synth is perfectly in-tune, so there's nothing to validate here. Best done
  alongside the user's real-guitar APK test. Also open: **full-sequence (batch) Viterbi with backtrace
  for Analyze** (today Analyze streams the online decoder), and **growing the chord vocabulary** (add,
  dim, aug, slash/inversions) once the base is validated on a real guitar.
- **Extended chord vocabulary** — the round-26 revert is now SUPERSEDED: 7ths work via the dictionary
  engine (round 28). Known honest limit (measured, in chunk 012): a dom7 whose m7 coincides with the
  root's own 7th harmonic (roots ≥ C3) still collapses to the triad — correct when the tone isn't
  audible; hearing every voicing is the ML-era goal. Power-5/sus2 remain OUT of the vocabulary (they
  steal weak-third triads); revisit with real-guitar data.
- Optional later: ML path (CQT→CNN/transformer, TFLite) — proven on-device (Chord AI ships an offline
  CNN) but deferred; needs a labelled trainset + Mac-free export, breaks pure-Dart offline design.
- Optional later: TFLite strum-direction model.
- **⭐ GROWTH TRACK (research: `docs/rag/chunks/013`) — make the moat go viral.** Round 29 shipped the
  static shareable **Strum Card** (the fast-to-ship v1). Ranked next, evidence-backed:
  1. **"Strum Cam" video/animated card** — a 9:16 clip with the ↓/↑ arrows + chords animating in sync
     with the audio (the ultimate moat-as-content; heavier — frame capture + a maintained encoder like
     `ffmpeg_kit_flutter_new`/`widget_record_video`; note `ffmpeg_kit_flutter` was discontinued Apr-2025).
  2. ✅ **DONE round 30 — Streak + daily strum-pattern challenge** (`lib/features/streak/`). TODO on top:
     a Friday-aware local-notification nudge (needs a notifications plugin) + reframe streak as skill progress.
  3. **`#StrumSightChallenge` UGC feed** — hashtag already seeded in every share caption; grow in-app.
  4. **Referral via deferred deep links** (Branch `flutter_branch_sdk`) — closes + *measures* the
     share→install loop; the one hosted dependency. Honest target K ≈ 0.3–0.7 (CAC reduction, not K>1).
  - When published, swap `ShareContent.installUrl` (currently the GitHub Release) for the store/landing URL.
- **⭐ LEARN TRACK (chunk 014) — the play-along trainer.** Round 32 shipped the strum-highway animation +
  lessons. Next, ranked: (1) **⭐ live scoring (round 33)** — run the real DSP while a lesson plays and
  score each event on the right **chord AND strum direction** within a timing window → hit/miss, accuracy
  %, combo; a passed lesson counts as practice (feeds the streak). Reuse `LivePipeline`, compare to the
  nearest `LessonEvent` by time. (2) a real lesson library + difficulty/progression + import a saved
  Analyze clip as a lesson. (3) metronome click / backing track (existing `audioplayers`). (4) share a
  completed-lesson score card (feeds the chunk-013 share loop).

## 4. Round history (from git notes — `git log --show-notes`)

| Round | Commit | tests | Lesson (compressed) |
|------:|--------|------:|---------------------|
| 52 | (this) | 257+14 | **Share a song — the growth loop reaches user-authored content.** A share action on each saved song reuses the ENTIRE round-29/47 share pipeline (Strum Card + Strum Reel + caption + install link) with zero new share code, via `Song.toAnalyzeResult()`: the song's chords → per-bar `TimelineChord`s, its expanded lesson events → `TimelineStrum`s at `beat×secPerBeat`, bpm + duration filled — a synthetic `AnalyzeResult` indistinguishable from a recorded clip to the card. So authoring a song now also produces a moat-showcasing, install-linked post. 2 tests (conversion counts/tempo + share-preview opens `StrumCard`). Key reuse insight: converting to the existing domain model beats re-teaching the card a new type. Next: notification nudge, Strum Cam MP4, setlists |
| 51 | `1291620` | 255+14 | **Songwriter helper — suggest a common progression.** Extends round 50: a ✨ Suggest sheet in the Song Builder picks a key (C/G/D) + a named progression (Pop I–V–vi–IV, '50s, Axis, Folk, Pachelbel) and fills the song's chords. Pure `theory/progressions.dart`: `SongKey` holds the 6 useful diatonic triads (I..vi; vii° omitted — out of open-chord vocab) spelled to match `ChordShapes`; `ProgressionTemplate` is a degree list → `chordsFor(key)`. Deliberately only C/G/D — the keys whose whole diatonic set is a playable open shape (A/E need C#m/G#m we don't have; F needs Gm). A test asserts EVERY generated chord has a fingering, so adding a key/template can't silently produce an undrawable chord. 6 tests (theory + suggest-sheet flow). Next: notification nudge, Strum Cam MP4, song setlists |
| 50 | `520446c` | 249+14 | **Song Builder — create your own songs (Ultimate Guitar / Chordify / Songsterr parallel, done offline + with ↓/↑ scoring).** `lib/features/songs/`: a `Song` model (chords-per-bar + 8-slot nullable strum pattern + bpm; JSON with rests preserved as `-`) that becomes a playable `Lesson` via `toLesson()` — so a user song reuses the whole Learn scoring/streak/Progress pipeline for free. `SongsController` persists a newest-first list (add/update/remove, shared_preferences). Builder screen: name + chord chips (add from `ChordShapes.allLabels`, delete via InputChip) + a reusable `StrumPatternEditor` (tap a slot to cycle rest→↓→↑, down=copper/up=green) + a tempo slider; save gated on name+≥1 chord+≥1 stroke. List screen plays/edits/deletes; reached from the Learn app-bar. 10 tests (model round-trip, provider CRUD+persist, end-to-end builder flow, editor tap). Next: notification nudge, Strum Cam MP4, song setlists/reorder-bars |
| 49 | `8487cee` | 239+14 | **Progress dashboard — the competitor retention backbone, done better.** Yousician/Simply/Fender-Play all lean on a progress tracker; StrumSight had a streak but no unified view. Built `lib/features/progress/`: a `PracticeEntry`/`PracticeLog` local store (shared_preferences, capped 400, streak-style epoch-day maths) + a pure `PracticeStats` rollup (totals, 7-day zero-filled window, per-source counts, avg/best direction accuracy) + a dashboard (hand-drawn weekly bar chart — deliberately NOT fl_chart, which would overflow the 600px test viewport; total time, streak, source breakdown, and the moat: **strum-direction accuracy over time**, which no competitor can show). Hooked recording into all 3 practice surfaces — Learn carries the ↓/↑ score + real elapsed secs, Analyze the clip duration/strums, Live a real session (captured notifier in build so dispose never touches `ref`; strokes via `strumSeq` deltas). Reached from the streak app-bar + a Settings tile. 10 tests. Gotcha: the bar Column needed +12px headroom for its two labels or a full-height bar overflowed; source breakdown is below the 600px fold → `scrollUntilVisible` in the test. Next: notification nudge, Strum Cam MP4, on-device audio tuning |
| 48 | `bfd2251` | 229+14 | **Progress dashboard — the competitor retention backbone, done better.** Yousician/Simply/Fender-Play all lean on a progress tracker; StrumSight had a streak but no unified view. Built `lib/features/progress/`: a `PracticeEntry`/`PracticeLog` local store (shared_preferences, capped 400, streak-style epoch-day maths) + a pure `PracticeStats` rollup (totals, 7-day zero-filled window, per-source counts, avg/best direction accuracy) + a dashboard (hand-drawn weekly bar chart — deliberately NOT fl_chart, which would overflow the 600px test viewport; total time, streak, source breakdown, and the moat: **strum-direction accuracy over time**, which no competitor can show). Hooked recording into all 3 practice surfaces — Learn carries the ↓/↑ score + real elapsed secs, Analyze the clip duration/strums, Live a real session (captured notifier in build so dispose never touches `ref`; strokes via `strumSeq` deltas). Reached from the streak app-bar + a Settings tile. 10 tests. Gotcha: the bar Column needed +12px headroom for its two labels or a full-height bar overflowed; source breakdown is below the 600px fold → `scrollUntilVisible` in the test. Next: notification nudge, Strum Cam MP4, on-device audio tuning |
| 48 | `bfd2251` | 229+14 | **Jam-mode backing track — resolving the mic conflict.** A backing track during SCORED play is unworkable (the mic hears + grades the app's own audio), so it's a **Jam toggle** that turns scoring OFF and plays a synthesised chord backing (`ChordAudio`: chord tones parsed off the label → a soft pad WAV) on each bar downbeat. Extracted a shared `audio/wav.dart` (metronome + backing). Audio quality is on-device-only to judge; the WAV + chord-tone maths are unit-tested. This completes the user's "do all four" (content, Strum Cam→Reel, backing, + polish next). 5 tests. Next: on-device audio tuning (needs the user's ears), general polish |
| 47 | `9de527f` | 224+14 | **Strum Reel — the "Strum Cam" growth item, done safely.** A full-screen, looping, branded ANIMATED replay of a recording (chords + ↓/↑ arrows flowing in tempo, `Lessons.fromAnalyze` + `LessonHighway` + a looping `Ticker`) made to be SCREEN-RECORDED and shared. Deliberately NOT a video-encoder plugin (fragile, discontinued ffmpeg_kit, unverifiable, could break the APK) and NOT a mic-conflicting backing track — pure animation, buildable + testable now. Reached from the share hub ("Play as reel"). A true MP4 export stays a later option. 1 test. Next: backing track (jam mode, scoring off to avoid mic conflict), polish |
| 46 | `89176df` | 223+14 | **More content + library search.** 4 new lessons (Fifties Doo-Wop I–vi–IV–V, Anthem Drive G–D–Em–C, Rising Minor Am–C–D–F, Blues Shuffle A7–D7) → 12 lessons across the 3 tiers. Added a case-insensitive **search box** to the chord library (`ChordLibraryScreen` → StatefulWidget; `_grouped(query)` filters). Dropped a brittle `scrollUntilVisible` from a test (the search test covers the lower group). Next: backing track, Strum Cam video |
| 45 | `d858334` | 222+14 | **Left-handed mode (accessibility).** A Settings "Playing → Left-handed" toggle (persisted local, like the capo) mirrors every chord diagram (high-E on the left) via a `mirror` flag in the painter (`_slot(s) = 5−s`). `ChordDiagram` became a `ConsumerWidget` watching `leftHandedProvider` — so it updates everywhere (Live, Learn, Library) at once; the 2 tests that pumped it bare were wrapped in `ProviderScope`. 3 tests. Next: backing track, library search, Strum Cam video |
| 44 | `1331d5b` | 220+14 | **More chords + a barre lesson (content).** Added ~9 shapes to `ChordShapes` (B, Bm, Bb, F#m, Cadd9, G/B, Dsus2, Esus4, A7sus4 — all within the first 4 frets so the diagram renders) and a new intermediate lesson **Barre Groove** (Bm–G–D–A) that introduces a barre chord. Enriches the library + curriculum. Next: backing track, left-handed mode, library search |
| 43 | `cf8aa47` | 220+14 | **Chord library — a browsable chord dictionary.** `ChordLibraryScreen` at `/chords` (opened from the Learn app-bar grid icon) lists every `ChordShapes` fingering, grouped Major/Minor/Sevenths/Suspended via a suffix classifier; reuses `ChordDiagram`. `ChordShapes.allLabels` added. A reference tool for learners. 2 tests. Next: backing track, left-handed mode, barre shapes, library search |
| 42 | `aa8fe12` | 218+14 | **Chord diagrams on the Live screen.** The detected chord's fretting now shows on Live too, as a small top-left OVERLAY (`Positioned` in a `Stack`, `showLabel:false` so it doesn't duplicate the huge chord letter). Deliberately an overlay, not a column child: the Live hero layout is height-tight and adding it inline overflowed by 72px in the test viewport. Added a `showLabel` flag to `ChordDiagram`. Next: backing track, left-handed mode, barre-chord shapes |
| 41 | `d18b569` | 218+14 | **Chord diagrams — show HOW to fret each chord (essential for beginners).** `lib/features/chords/`: `ChordShapes` = a data table of ~21 open-position shapes (low-E→high-E frets, −1 muted/0 open, covers every lesson chord — asserted); `ChordDiagram` = a `CustomPaint` mini fretboard (○/× markers + finger dots). The Learn player shows the currently-fretted chord under the highway (`_activeChord()`). Layout gotcha: the diagram's Column overflowed its box in the 600px test viewport → tightened highway (140) + diagram (size 66, ×1.05, smaller title) to fit. 5 tests. Next: chord diagrams on Live, backing track |
| 40 | `27294cb` | 214+14 | **Practice speed control (slow-down).** A 50/75/100% selector scales the effective tempo (`_bpm = lesson.bpm × speed`); playhead, metronome and scorer all use it (`LessonScorer` gained a `bpm:` override). Changing speed restarts the run so the tempo-dependent playhead maths stays clean. The classic learning lever — play it slow, then speed up. 2 tests. Next: chord diagrams (fretting), backing track |
| 39 | `b1499e3` | 212+14 | **Learn polish.** Persisted the metronome mute preference (`metronomeMutedProvider`, local — LearnScreen now watches it instead of a local bool). Added "Practice as a lesson" 🎓 to the Analyze DONE view (import a riff you just recorded straight into the player, no save needed) via `Lessons.fromAnalyze`. 2 tests. Next: backing track, the animated Strum Cam video share |
| 38 | `4d98e3c` | 210+14 | **Chord-aware scoring (secondary, lag-tolerant).** `LessonScorer.observeChord(label,t)` records detected-chord change-points; each chord-bearing event is graded correct if the target chord was sounding at the stroke OR ~0.37s after (chord detection lags the onset by ~1 window). Deliberately a SECONDARY metric (`Chords: N%`) that never gates the reliable direction hit — chord detection during fast strumming is noisy. `ScoreSnapshot` gains chordHits/chordTotal/chordAccuracy. 4 tests. Next: import from Analyze screen, backing track |
| 37 | `2481ed5` | 206+14 | **Import a recording as a lesson — unlimited content.** `Lessons.fromAnalyze(AnalyzeResult)` maps each detected strum to a beat-timed event (`beat=(t−t0)/secPerBeat`, tempo=clip BPM) on the chord sounding then; length = the bar containing the last stroke. Refactored `Lesson` to store `totalBeats` + derive `chordSequence` from events + a `const Lesson.fromEvents` constructor (so it can hold irregular imported events, not only chords+pattern). "Practice as a lesson" 🎓 action on the Library session detail (only when the clip has strums). 4 tests. Next: chord-gated scoring, import from Analyze too, backing track |
| 36 | `b7c90d2` | 203+14 | **Learn metronome — hear the beat.** The click is SYNTHESISED in pure Dart (`Metronome.buildClickWav` → a valid 16-bit PCM WAV, unit-tested) so there's no bundled asset; playback via the existing `audioplayers`. `LessonTiming.beatsCrossed(prev,next)` (pure) drives a click on each crossed beat (accent on bar downbeats, count-in included); mute toggle in the app bar. Gotcha: creating/awaiting an `AudioPlayer` hangs the test isolate (open platform stream) → playback is fire-and-forget (`.ignore()`, never await) and the tick()-playback test was dropped (on-device-only, like mic scoring); WAV + scheduling stay unit-tested. Next: chord-gated scoring, import an Analyze clip as a lesson, backing track |
| 35 | `eba7124` | 197+14 | **Shareable lesson score card — wires Learn into the viral loop.** End-of-lesson summary gains a Share action → a 9:16 `LessonScoreCard` (score % + 0–3 stars + best combo + moat footer + install link + `#StrumSightChallenge`) shared via the OS sheet. Refactored `ShareService` to a generic `shareImage(boundaryKey, caption, fileName)` (shareCard now delegates to it) so both the Analyze Strum Card and the lesson card reuse one capture→share path. `ShareContent.lessonCaption`. Gotcha: the card footer Row overflowed 8.5px → `Flexible` on the tagline. 3 tests. Next: metronome/backing audio, chord-gated hits, import an Analyze clip as a lesson |
| 34 | `e776a50` | 194+14 | **Learn curriculum — turned 2 demo lessons into a real learning program.** 12 lessons across Beginner/Intermediate/Advanced tiers (`Difficulty` + `Lessons.byDifficulty`); `LessonProgressController` persists per-lesson **best accuracy** (local like the streak) → `LessonProgress.stars` (0–3 at ≥90/80/70%). `LearnScreen` records the run's accuracy on finish. Lesson list grouped by tier with stars + **progression gating** (`isUnlocked` — pass the previous in a tier to unlock the next; locked tiles show a lock + snackbar). Gotcha: `ADVANCED` header is below the fold in the 600px test viewport → `scrollUntilVisible`. Next: import an Analyze clip as a lesson, chord-gated hits, metronome/backing, share a score card |
| 33 | `acf1fb6` | 187+14 | **Learn live scoring — score your real strum direction + timing against the lesson.** Pure `LessonScorer` (matches detected strums to the nearest open event within ±0.28 s → hit/wrong-way/miss + combo/accuracy, pass ≥70%) — the unique payoff (nobody else scores DIRECTION). `LearnScreen` now subscribes to `liveFrameProvider` only while playing (`ref.listenManual`, closed on pause/dispose — mic on just for the run), live HUD + hit-flash + end summary; a passed run records practice (feeds the streak). Key enabler: added `LiveFrame.strumSeq` (bumped per new strum in `LivePipeline`, default 0 non-breaking) so discrete strums are detectable — `latestStrum` lingers ~2 s and repeats share a direction. Scored on direction+timing; chord-gating deferred (~370 ms lag). Mic→score verifiable only on-device; scorer exhaustively unit-tested. Next: lesson library/difficulty, chord-gated hits, metronome/backing, share a score card |
| 32 | `ca5facd` | 179+14 | **Learn / play-along mode (user-requested, "like Yousician" but our own animation).** Built `lib/features/learn/`: a **strum highway** — chord + ↓/↑ arrow cards flow toward a strike line in tempo and pulse on cross (down=copper/up=green = the moat, animated) + a 4-beat count-in. Pure `LessonTiming` (playhead = elapsed·bpm/60 − countIn; xForEvent) split from a `Ticker`-driven `LearnScreen` (starts PAUSED so widget tests advance with `pump(Duration)`, never `pumpAndSettle` a live ticker). `Lesson` model expands chords/bar + 8-slot strum pattern → beat-timed events; built-ins (First Strums, Down-Up Groove) + `fromDailyChallenge`. Added a 5th **Learn** nav tab (/learn); streak "Play along" opens today's challenge as a lesson. 15 tests. NEXT ⭐ = live scoring (round 33): score the real DSP's chord+direction vs each event → hit/miss/accuracy, feeds the streak. |
| 31 | `25f330f` | 164+14 | **Growth #3 — first-run onboarding (activation).** A viral install only counts once active, so first-run matters (chunk 013). `lib/features/onboarding/`: a 3-page skippable flow (moat-first: real-time chord → ↓/↑ direction → daily streak) that primes the mic permission, then Live. Gated by a persisted `onboarding_seen_v1` flag loaded in `main()` before the first frame and enforced by a go_router `redirect`. Key trick to not break the 160 existing tests: the flag provider DEFAULTS to seen=true (skip onboarding) and `main()` overrides it with the real value — so un-overridden test contexts never hit the /welcome redirect. 4 tests. Next growth: UGC feed, referral deep links, Strum Cam video |
| 30 | `d566484` | 160+14 | **Growth #2 — practice streak + daily challenge (retention loop).** Best-evidenced retention mechanic (Duolingo 55% next-day return, streak-freeze +48%; chunk 013). Built `lib/features/streak/`: pure `StreakLogic` (loss-aversion — +1/day, a banked streak-freeze covers a 1-day gap, reset otherwise; freeze every 7d cap 3) + `StreakData` (shared_preferences, local-only like capo); `DailyChallenge.forDay(epochDay)` = deterministic strum pattern (on-beats down, off-beats mostly up) — same per date on every device, no server. 🔥 badge in Live header → `/streak` screen (streak/longest/freezes + at-risk/broken/done nudge + today's pattern + "Try in Live"). Practice credited on a real Live strum (once/visit) or a completed Analyze. Injectable clock (`epochDayOf`) keeps maths pure. 18 tests. Gotcha: the badge as its own row overflowed the tight Live column (+15px) → merged into the LiveStatusBar row + shrank it. Next growth: UGC feed, referral deep links, Strum Cam video |
| 29 | `8aff1b0` | 142+14 | **First GROWTH feature — shareable "Strum Card" (make the moat viral).** Researched how music apps grow (Spotify Wrapped 9:16 results-card → 21% install spike; GuitarTuna free-utility wedge; Yousician/Simply streaks; UG UGC; K-factor 0.3–0.7 realistic, K>1 hype) → RAG **chunk 013**. Built `lib/features/share/`: a 9:16 brand card whose **hero is the ↓/↑ strum pattern** (the one thing no competitor shows) + chords + BPM/down/up stats + wordmark; `RepaintBoundary`→PNG→`share_plus` share sheet with a caption (`#StrumSightChallenge` + install link) + text-only fallback. Entry on Analyze + Library detail. Added `share_plus` (win32 stayed ^6). 14 tests. Deliberately the STATIC card first (research rank #2 = fast/low-risk v1 of a "Strum Cam" video). Next growth: video card, streaks, referral deep links |
| 28 | `54d3be5` | 129+14 | **Built the chunk-012 chord DICTIONARY + Viterbi engine** (the round-27 spec), fixing the round-26 7th failure end-to-end. NnlsChroma now emits a **bass+treble 24-dim** chroma; `ChordDictionary` scores whole-chord profiles (maj/min/7/maj7/m7/sus4 + N.C., 73 states); `ViterbiChordDecoder` is an online self-transition-bonus decoder replacing templates+hysteresis. **4 discoveries while building** (all in chunk 012 "AS BUILT"): (1) treble chroma must fold the FULL range — a high treble floor dropped guitar's low root/third and read G7 as Dm; (2) power-5/sus2 STEAL weak-third triads → pulled from vocab (reconfirms r26); (3) a MAJOR third's 3rd-harmonic fakes a maj7 (a MINOR third's a m7) → needs a **per-quality Occam bias** (7=0.02, maj7/m7=0.055, dom7 needs less or real A7/B7 collapse); (4) honest limit measured — dom7 detected for roots E2–B2 but m7 = root's own 7th harmonic for roots ≥C3 → collapses (correct if inaudible). 9-seed randomized property gate. Whitening + tuning-est deferred (only bite on real audio) |
| 27 | (prev) | 107+14 | Research (docs): studied how production apps do chord recognition (Chordify/Chord AI/Chordino/madmom/BTC) + used Viking/Hermes bridge. Verified answer to round-26 = **chord DICTIONARY + Viterbi** (not templates): bass+treble chroma → chord-profile similarity → HMM/Viterbi + no-chord state. Wrote implementation spec → RAG **chunk 012**; refined 011 w/ competitor+TFLite feasibility intel. Chord AI ships an offline on-device CNN (ML path proven but deferred). Strum ↓/↑ confirmed a unique moat. Lessons pushed to Hermes shared brain |
| 26 | `c4f6376` | 107+14 | Capo/transpose shipped (Settings stepper 0–11 → `Chord.transposeLabel/Summary`, view-time shift on Live+Analyze+Library, "Capo N" badge; local-only — a capo is physical per-guitar state, deliberately not synced). Devil-advocate caught a title leak: saved-session summary showed concert pitch while the timeline body transposed → added `transposeSummary` on the detail AppBar + library list. **REJECTED first**: extended chord vocab (7ths/sus/power) — NNLS suppresses the added tone when it = a chord-tone's harmonic (measured); needs chord-profile NNLS, not templates (reconfirms r24) |
| 25 | `9bf0b6b` | 88+14 | Chordino-class chord engine: NnlsChroma (STFT 16384 → log-freq 3 bins/semitone → NNLS transcription vs harmonic dict shape 0.7, multiplicative updates → chroma) wired into LivePipeline, replacing peak-chroma on the chord path. Overtone suppression verified (220Hz note → A only; 3rd/5th partials <½ peak). Property + pipeline + analyze all green across seeds. ~370ms chord latency (long window needed for low-E resolution) — tune on device |
| 24 | `17e1bb6` | 84+14 | researched prod recognition → RAG 011; naive greedy harmonic-subtraction fights triad templates (reverted); real NNLS needs full transcription |
| 23 | `e32aff9` | 84+14 | DSP voice/noise rejection (user: "reacts to speech more than guitar"). Researched McLeod/YIN/pYIN: real tuners gate on CLARITY + pitch STABILITY, not just level. Tuner: +clarity(0.85)+range(70–1320)+4-frame ±30-cent stability+RMS 0.014 → gliding pitch never locks. Live: chroma tonalness (top-3 energy, gate 0.7) + matcher no longer bootstraps a chord on 1 frame → noise doesn't fake a chord. RAG 003/008 updated; 2 randomized properties added |
| 22 | `a09d4eb` | 78+14 | Analyze+Library shipped (were "coming soon"); account UI gated behind ApiConfig.accountEnabled (provider-wrapped so tests can toggle a compile-time flag); login deferred — needs hosted backend, ARM64 box can't build APK so CI + git-credential release (see apk-delivery). build-22 = features; build-23 = login hidden |
| 21 | — | 77 | Library persists via shared_preferences JSON array; extracted shared TimelineView |
| 20 | — | 74 | Analyze reuses LivePipeline in batch; compute() keeps FFT-heavy analysis off UI isolate; AnalyzeResult JSON for Library |
| 19 | — | 68+14 | tuning_a4 fully wired: local Notifier (persist/clamp 400–480) → tuner engine `start(a4:)` through the isolate → noteForFrequency; Settings stepper; Live/Tuner display; synced (pull/push/signature). Watching a4 in tunerReadingProvider restarts the engine with the new reference |
| 18 | `3dfce22` | 65+14 | docs + CORS polish (bearer → allow_credentials=False so "*" stays valid); handoff/README/CLAUDE updated for the account layer |
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
