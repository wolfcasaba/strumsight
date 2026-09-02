# StrumSight — Store listing (draft)

**Státusz:** TERVEZET — a Play Console feltöltés előtti szöveg-forrás
(E12-R24, 2026-09-02). A tényleges store-fiók és feltöltés emberi lépés
(§0.0) — ez a dokumentum csak a szöveget és a kategorizálást adja.

**Kötött szabály (§5.3):** ez a dokumentum KIZÁRÓLAG olyan képességre
hivatkozhat, amely a `docs/testing/device-matrix.yaml`
`capabilities[].ga_scope` mezőjében `true`. A dokumentum alján lévő
gépileg olvasott `capabilities-marketed` jelölés (`test/tooling/store_package_test.dart`,
A3) ezt méri le minden futáskor a forrásból — nem szabad kézzel bővíteni
anélkül, hogy az adott capability a device-matrix-ban `ga_scope: true` ne
lenne.

## App name

StrumSight

## Short description (≤ 80 characters)

Offline guitar chord & strum-direction detection — tune, practice, track progress.

## Full description

StrumSight listens to your guitar in real time and recognizes chords and
strum direction entirely on your phone — no cloud round-trip, no account
required. Plug in, play, and see what you're playing as you play it.

**Live tuner & live chord detection.** A responsive on-device tuner and a
live chord readout for freeform practice — both run continuously from the
microphone, fully offline.

**Practice engine.** Structured practice sessions with a built-in
metronome, chord targets, and session results, so you can see what you
actually played, not just what you meant to play.

**Song Trainer (local library).** Import or write chord charts, then
practice them section by section against StrumSight's own on-device
detection — your song library lives on your device.

**Audio analysis.** After a session, StrumSight's audio analysis engine
gives you a timeline of what was detected — chords, strum pattern,
tempo — so you can review your own playing, not just a score.

**Progress, goals & streaks.** Daily practice streaks and goal tracking
keep you coming back, with an entirely optional daily-reminder
notification you can turn on or off in Settings.

**Works fully offline.** Detection never leaves your phone. StrumSight is
completely usable without creating an account — an optional account layer
exists only if you want your settings to follow you across devices.

**English & Hungarian.** The app ships fully localized in English and
Hungarian, with basic accessibility support (scalable text, screen-reader
labelling on the core practice flow).

Everything above runs the same whether you're online or offline, signed in
or not — StrumSight's detection loop makes zero network requests by
design.

## Category

Music & Audio

## Content rating considerations

- No user-generated content is required to use the app's core (offline)
  functionality.
- The optional, account-gated Community surface (profiles, follows,
  challenges) involves user-to-user interaction; the age-rating
  questionnaire should reflect "Users interact" for the signed-in path
  only, since it is entirely opt-in and absent when logged out.
- No gambling, no real-money mechanics, no ads in this release.

## Screenshot plan (placeholder — real captures pending device-lab pass)

1. Live tuner + live chord readout (core, GA).
2. Practice engine session in progress (core, GA).
3. Song Trainer local library + chart practice (core, GA).
4. Audio analysis session review timeline (core, GA).
5. Progress/streak/goals screen (core, GA).
6. Settings — showing the app is fully usable without an account.

## Permissions summary

See `docs/store/permissions-rationale.md` for the full, manifest-derived
rationale of every requested Android permission (function + data named for
each, per §5.2). Camera access is optional and not part of this release's
advertised feature set (see that document's `CAMERA` entry).

## Data safety summary

See `docs/store/data-safety.yaml` for the machine-checked mapping from
every store "data collected" category to its `docs/privacy/data-inventory.yaml`
source route/field.

<!-- capabilities-marketed: onboarding, live_and_tuner, practice_engine, song_trainer_local, audio_analysis_core, progress_goals_streak, offline_operation, localization_en_hu, accessibility_minimum -->
