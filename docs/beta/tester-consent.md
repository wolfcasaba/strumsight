# Beta tester consent — what we collect, what we don't, how to revoke it

> Companion to [`docs/privacy/data-inventory.yaml`](../privacy/data-inventory.yaml) (the
> machine-checked egress inventory) and [`docs/privacy/consent-enforcement.md`](../privacy/consent-enforcement.md)
> (how a revocation actually stops data on the wire). This document is the tester-facing mirror
> of that inventory — every row below names a route the app actually produces and a field the
> tree actually sends, not an aspirational description. See
> [`docs/beta/enrollment.md`](enrollment.md) for how you join/leave the program and
> [`docs/beta/feedback-triage.md`](feedback-triage.md) for what happens to a diagnostics report
> you send us.

## The short version

Being a beta tester does not, by itself, turn on any extra data collection. Everything below is
either (a) something the released app already does when you use an account, sync settings, join
Community, or share something, or (b) something you separately, explicitly opt into from Lab
mode (diagnostics reports). Nothing here is retroactive, and nothing here is silent — every field
that leaves your device is listed below, next to the route it travels on.

## What leaves the device, and under what consent

The table below is generated against [`docs/privacy/data-inventory.yaml`](../privacy/data-inventory.yaml)
— specifically, every field on every route the inventory marks `leaves_device: true`. It is
cross-checked by `test/tooling/beta_release_notes_test.dart` in **both directions**: a field the
inventory adds and this document has not caught up with fails the check, and a row this document
invents that the inventory does not actually declare fails it too. If you are reading this after
a privacy-relevant code change and the check is red, trust the check, not the prose above it.

<!-- data-inventory-crosscheck:begin -->
| route | field |
|---|---|
| account_api | email |
| account_api | password |
| account_api | settings_profile (theme_mode, locale, confidence_threshold, tuning_a4) |
| account_api | community_profile (handle, display_name, visibility, audience_default) |
| account_api | community_social_graph (follow/unfollow/block/mute target ids) |
| account_api | community_challenge_activity (invite/accept/decline/cancel/submit_result payloads) |
| diagnostics_upload | ml_dsp_comparison_events (tSec, mlChord, dspChord, agree, mlConf, dspConf, strumDir, bpm, inputLevel) |
| diagnostics_upload | audio_clip (raw 16-bit WAV, base64, decimated to fit a ~5MB pre-encode cap) |
| diagnostics_upload | device_metadata (appVersion, device platform string) |
| share_export | strum_card_png (rendered on-screen 'Strum Card' capture) |
| share_export | share_caption (chords, strum-glyph sequence, BPM, optional session title only if includeTitle=true, install link, hashtags) |
| share_export | redacted_analysis_export_json (RedactionPolicy-filtered allowlist view of an AnalysisDocument) |
| account_api_community_post_repository | post_body (a poszt szabad szövege — createPost/updatePost `body`) |
| account_api_community_post_repository | post_audience (a poszt láthatósága — `audience` wire-érték) |
| account_api_community_post_repository | post_artifact (a poszthoz csatolt artefaktum JSON-payloadja — `artifact`) |
| account_api_community_post_repository | comment_body (a komment szabad szövege + `parent_public_id` — createComment/updateComment) |
| account_api_community_post_repository | reaction_kind (a reakció típusa — PUT /community/posts/{id}/reaction `kind`) |
| account_api_community_post_repository | idempotency_key / resource_version (írás-kísérlet azonosítója és optimista verzió) |
| account_api_community_post_repository | community_media_bytes (a felhasználó által választott kép nyers bájtjai — POST /community/media multipart `file`) |
| account_api_community_post_repository | media_ids (a poszthoz csatolt médiák publikus azonosítói — POST /community/posts `media_ids`) |
| account_api_community_club_repository | club_name (a klub neve — createClub `name`) |
| account_api_community_club_repository | club_description (a klub szabad szövegű leírása — createClub/updateClub `description`) |
| account_api_community_club_repository | club_visibility (a klub láthatósága — `visibility` wire-érték) |
| account_api_community_club_repository | target_public_id (meghívott, illetve új tulajdonos publikus profil-azonosítója — inviteMember `target_public_id`, transferOwnership `target_public_id`) |
| account_api_community_club_repository | club_membership_action (csatlakozás/kilépés/tag-eltávolítás cél-azonosítói az útvonalban — /join, /leave, /members/{id}) |
| account_api_community_club_repository | idempotency_key (írás-kísérlet azonosítója) |
| tutor_stream | tutor_turn_message (student free-text message + the assembled, redacted context snapshot the prompt builder renders) |
<!-- data-inventory-crosscheck:end -->

### Reading the table

- **account_api** — everything a signed-in account touches: authentication, cross-device
  settings sync, and Community (profile, social graph, challenges). Gated by
  `FeatureFlags.accountEnabled` plus a live per-request auth-session check — signing out or a
  cleared session stops every one of these before the request leaves the interceptor (see
  `docs/privacy/consent-enforcement.md` §3). None of this requires Lab mode or beta enrollment;
  it is the same behavior in the general release.
- **diagnostics_upload** — Lab mode's opt-in field-diagnostics report. Off by default
  (`diagnosticsConsentProvider` defaults to `false`, fail-closed), and re-checked live on every
  upload attempt, not just once at boot (`docs/privacy/consent-enforcement.md` §2). The
  `audio_clip` field only ever leaves the device as part of a diagnostics upload — a beta tester
  can send `ml_dsp_comparison_events` and `device_metadata` without ever recording or sending
  audio; see the two-layer consent model in the next section.
- **share_export** — whatever you explicitly choose to hand to the OS share sheet (a practice
  card image, a caption, or a redacted analysis export you previewed and confirmed first). Not
  Lab-mode-specific; it is the same share path every user has.
- **account_api_community_post_repository** — Community posts, comments and reactions. This route
  rides the very same account transport and session gate as `account_api` (its provider re-exports
  `accountApiClientProvider` verbatim), but it is listed separately because it carries fields of
  its own: the **free text you write** in a post or a comment, the audience you pick for a post,
  the practice/analysis artifact you attach, the reaction kind you tap, and a per-attempt
  idempotency key / resource version that exists only to stop a double submit or a lost update.
  Nothing here is sent unless you are signed in and you explicitly compose, edit or react — with
  no signed-in account, the repository resolves to the disabled variant, which sends nothing.
  Since the javító sáv R27 round the route also carries **an image you explicitly attach** in the
  composer, plus the ids of the images a post is published with. Three things about that are worth
  stating plainly. (1) It is never automatic: the bytes leave the device only after you tap
  "Attach media" and pick a file. (2) The server does **not** store the file you sent — it
  re-encodes the picture from the decoded pixels, so the EXIF block a phone camera writes,
  **including GPS coordinates**, is not part of what is stored or ever served back. (3) The
  affordance is behind the `communityMediaEnabled` flag, which is **off in every shipped build**
  today, so unless you are running a build that explicitly turns it on, the button is not there at
  all and nothing on this path can leave your device.
- **account_api_community_club_repository** — Community clubs. Same transport and session gate as
  above, with its own fields: the **club name and free-text description** you write, the club's
  visibility setting, the public profile id of whoever you invite or hand ownership to, the
  membership actions you take (join, leave, remove a member), and the same write-integrity
  idempotency key. Again: signed out, nothing on this route leaves the device.
- **tutor_stream** — the AI tutor's cloud turn (javító sáv 3, 2026-09-07; cloud flag +
  capability gate 2026-09-08). When you send a message to the tutor, the message text and a
  redacted, on-device-assembled context snapshot go to the StrumSight backend's `/tutor/stream`
  endpoint and from there to the configured model provider. **Five** gates, all re-checked on
  every turn and all fail-closed: your explicit **model-use consent** on the Tutor privacy
  screen (the request object is never even built without it), the build's own
  `aiTutorCloudEnabled` rollout flag, an enabled account layer, a live signed-in session (the
  same bearer token and 401 handling as `account_api`), and the server's own answer at
  `/tutor/capability` — a backend still running its default, canned provider is never presented
  to you as a cloud tutor. With any gate closed the tutor answers from the local, on-device
  gateway and nothing leaves the phone.
- **The cloud tutor is OFF in the build you install.** `aiTutorCloudEnabled` resolves to
  `false` in every shipped build today (`docs/release/ga-scope.md` — postponed behind the open
  `R-PRIV-01` blocker), so the tester APK answers every tutor turn on-device. If your build is
  ever flipped on and the backend's operator has configured a real model provider, that
  provider is a **third-party processor — Anthropic (Claude API)** — which receives exactly the
  message and the redacted context snapshot above; its own retention is governed by that
  provider's API data policy, which this repository does not measure. The full row, including
  what the operator must verify before any such flip, is `tutor_stream` in
  [`docs/privacy/data-inventory.yaml`](../privacy/data-inventory.yaml).

## The diagnostics report you can send us — two independent layers

A diagnostics report is built by `tool/release/build_diagnostics_bundle.py` from a stored Lab-mode
session and requires you to have separately granted consent for each layer it can carry (ADR
0486 D1):

| You granted | What's in the report |
|---|---|
| neither | nothing — the tool refuses to produce a report at all |
| diagnostics only | ML-vs-DSP comparison events and device/app metadata — **no recorded audio** |
| raw audio only (no diagnostics) | still nothing — audio consent alone does not authorize a report |
| diagnostics **and** raw audio | the above, plus the recorded audio clip(s) from that session |

"The whole of Lab mode is already opt-in" is deliberately **not** treated as consent for raw
audio on its own — the two consents are independent, and the tool enforces that mechanically, not
just in this document (see the four-row acceptance table in
[ADR 0486](../adr/0486-beta-distribution-consent-and-redacted-diagnostics-bundle.md) D1).

## What we redact before a report ever reaches us

Before any diagnostics report is written to disk, the packaging tool masks four classes of value,
recursively, at every level of the stored session — not just the top level (ADR 0486 D2):

- any field whose **name** contains "token" (case-insensitive) → `[REDACTED:token]`
- an **e-mail address** appearing anywhere in any text field → `[REDACTED:email]`
- an **absolute file path** (POSIX or Windows) appearing anywhere in any text field →
  `[REDACTED:path]`
- a **device identifier** field (`deviceId`, `device_id`, `androidId`, `installId`, `udid`) →
  `[REDACTED:device-id]`

The app version and platform-string fields (`appVersion`, `device`) are **not** redacted — they
identify which build and platform produced the report, not you.

This redaction happens on the report-building side, not on our server: the server that receives a
Lab-mode upload stores the bytes you sent exactly as received (it has to, to stay dumb and robust
to client-format changes), so a report you build and hand to us yourself is the only place the
masking is guaranteed to have happened before the data reaches anyone reading your report.

## Revoking consent

- **Lab mode / diagnostics uploads:** turn Lab mode off in-app. This stops the next upload
  immediately — the consent check is re-read live, not cached from app start
  (`docs/privacy/consent-enforcement.md` §2).
- **Account data (settings sync, Community):** sign out. This invalidates the session
  immediately; no further account-gated request reaches the network (§3 of the same document).
- **A diagnostics report you already sent us:** the upload is a one-shot POST with no
  client-measured deletion path today (see the `retention` column for `diagnostics_upload` in
  `docs/privacy/data-inventory.yaml`) — this is a known, named gap, not a silent one.
- **Beta enrollment itself:** see [`docs/beta/enrollment.md`](enrollment.md) — leaving the
  program does not, by itself, delete data already sent under the sections above.
