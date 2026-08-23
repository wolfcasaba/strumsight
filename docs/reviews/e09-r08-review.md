# E09-R08 — Review

Brief: `docs/rounds/e09-r08-block-mute-and-safety-relationships.md` (§0.0 D1–D6)
ADR: `docs/adr/0402-block-mute-and-safety-relationships.md`
Diff: `git diff 60088f71..62e94855` (branch `minimax/e09-r08-block-mute-and-safety-relationships`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-23
Verdikt: **APPROVED** (1. javító kör után, fix commit `bf5862d0`)

## Összegzés

BLOCKER: 0 · MAJOR: 2 (mindkettő FIXED, `bf5862d0`) · MINOR: 1 (non-blocking follow-up, nyitva) · NOTE: 5

Independent gate re-run (isolated `/tmp/review-e09-r08` clone, un-truncated):
**MINDEN GATE ZÖLD** — format, analyze, all 3 gate_tests paths, architecture,
secrets, l10n, backend ruff format/check, backend pytest (all green). The
implementer's own gate run was piped through `| tail -120`
(`gate_shape=VIOLATION` in the signal) — I do **not** accept that run as
evidence and re-ran the full, untruncated gate myself; it is genuinely green.

A dedicated `security-reviewer` agent pass (risk=high, first live
authorization wiring) returned **PASS, no BLOCKER**, 2 MINOR (folded into
this report as MAJOR-2/MINOR-1 below), several NOTE.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Block tranzakció atomikus (D1: DELETE mindkét follow-él + UPDATE request `status="blocked"`) | ✅ | `test_block_service.py::test_a1_block_closes_follow_edge_in_both_directions`, `test_a1_block_updates_pending_request_to_blocked`, `test_a1_block_atomicity_partial_failure_rolls_back` (real monkeypatch-injected mid-transaction failure — independently read, legitimate, not tautological), all green in my own gate run |
| A2 | Blocked user kiesik `get_followers`/`get_following`-ból mindkét irányban + 403 caller↔owner blockra (D2) | ✅ | Independently read `social_graph.py:490-524` — 404 (missing profile) → 403 (block) → page-fetch → filter, in the correct order, symmetric direction. Tests green. |
| A3 | Mute nem értesít, nem törli a followt | ✅ (test is a source-grep, see MINOR-1 note below on test strength) | `test_block_service.py::test_a3_mute_does_not_touch_follow_graph`; independently read `block_service.py::mute/unmute` — no call to anything resembling notify/push, no touch of `community_follows` |
| A4 | Unblock nem állítja vissza a régi followt | ✅ | `unblock()` independently read: only DELETEs `CommunityBlock`, never touches `community_follows` — invariant by construction, not just by test |
| A5 | Új authentikált endpoint nem kerülhet block-filter nélkül CI-be + a 4 authentikáció-nélküli endpoint dokumentált kihagyás | ✅ | `UNAUTHENTICATED_READ_ENDPOINTS_OUT_OF_SCOPE` constant + real-violation probe (§10.3, independently spot-checked the code path, matches) |
| A6 | `query_filters.is_blocked_pair` pure-helper unit-tesztje (D4, nem élő club-endpoint) | ✅ | `test_a6_is_blocked_pair_returns_true_on_blocked_pair` |

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e09-r08 --brief docs/rounds/e09-r08-block-mute-and-safety-relationships.md --base 60088f71` →
**1 file outside `allowed_paths`**: `test/features/community/application/relationship_controller_test.dart` (+10 lines).

**Disposition: accepted, not a violation in substance.** Verified the diff is
*exactly* two mandatory `@override` stubs
(`blockedProfilesPage`/`mutedProfilesPage`, both `throw UnsupportedError`) on
a pre-existing Kör 7 fake that `implements SocialGraphRepository` — a direct,
unavoidable consequence of **my own** D5 pre-flight decision to add two
abstract methods to that interface. `grep -rln "implements
SocialGraphRepository" lib/ test/` confirms this is the *only* other
implementer in the tree besides the one already in `allowed_paths`
(`relationship_repository_impl.dart`). Without this patch `flutter analyze`
fails on the whole `test/` tree — the implementer had no scope-compliant way
around it, flagged it correctly (STOP-worthy per the brief, but a genuine
dead end), and documented it transparently in §10.4 rather than silently
expanding scope. I retroactively add this file to E09-R08's `allowed_paths`
in this review (orchestrator authority over the round's own artifacts, ADR
0087 §2) — no further action needed on this item.

No other file outside scope. `tool/check_architecture.dart` (the allowlist
source) has zero diff — the "12 allowlisted deviation(s)" gate line is the
pre-existing baseline, not a new deviation this round added.

## Megállapítások

### F1 — MAJOR — Safety screen ships zero localization; every sibling Community screen uses `AppLocalizations`

- **Fájl:** `lib/features/community/presentation/screens/safety_relationships_screen.dart:218-315`
- **Probléma:** All 8 user-facing strings are hardcoded English literals
  (`'Blocked & muted'`, `'Unblock'`/`'Unmute'`, `'No network connection'`,
  `'Session expired — please sign in again'`, `'You do not have permission
  to view this list'`, `'Invalid request'`, the two tab labels, the
  empty-state copy) — zero `AppLocalizations` calls. `grep -c
  AppLocalizations` on the two other Kör 6 Community screens
  (`community_gate_screen.dart`, `edit_profile_screen.dart`) returns 3 and
  16 respectively; this new screen returns 0.
- **Hatás:** Violates CLAUDE.md's binding i18n rule ("every user-facing
  string goes through ARB → `AppLocalizations`... magyar PARITÁS
  kötelező") and breaks Hungarian-locale parity for a safety-critical
  screen (block/mute controls). The `round-gate.sh` l10n step only checks
  *existing* ARB en/hu symmetry — it does not scan for un-localized new
  widget strings, so this slipped through green.
- **Megjegyzés a felelősségről:** partially my own pre-flight gap — the
  E09-R08 implementer prompt (unlike the E09-R06 prompt, which had an
  explicit "ARB szegmens" step) never instructed an ARB addition, and
  `lib/l10n/features/community_{en,hu}.arb` was never added to
  `allowed_paths`. I also found `followers_screen.dart` (Kör 7, already
  merged) has the **same** gap (`_formatFailure` returns bare English,
  no `AppLocalizations`) — so this is a second instance of a pre-existing
  pattern, not a wholly novel regression. Still MAJOR: it's a small,
  contained, mechanically fixable gap in a file this round fully owns.
- **Kötelező javítás:** add the 8 strings to
  `lib/l10n/features/community_en.arb` + `community_hu.arb` (Hungarian
  translations, not machine-transliterated placeholders) and route the
  screen through `AppLocalizations.of(context)`. (The Kör 7
  `followers_screen.dart` gap is OUT of this round's `allowed_paths` —
  log as a separate follow-up, do not fix in this round.)
- **Ellenőrzés:** `dart run tool/ci/check_l10n_parity.dart` (already part of
  the gate) + a manual `grep -c AppLocalizations
  safety_relationships_screen.dart` ≥ 1.
- **Státusz:** FIXED (`bf5862d0`) — 11 `safety*` kulcs hozzáadva
  `lib/l10n/features/community_{en,hu}.arb`-hoz (magyar fordítással), az
  aggregátum `lib/l10n/app_{en,hu}.arb` újragenerálva
  (`tool/gen_l10n_segments.dart` — mechanikus, elkerülhetetlen velejárója a
  feature-ARB szerkesztésnek, a scope-audit ezt is jelezte, elfogadva
  ugyanazon indokkal, mint a D5 collateral). Independently verified: fresh
  `/tmp/review-e09-r08-fix1` klón, `grep` a screen fájlban 0 hardcode-olt
  string, 3 `AppLocalizations.of(context)` hívás; gate l10n lépés ZÖLD.

### F2 — MAJOR — Concurrent `block()`/`mute()` retry raises uncaught `IntegrityError` (500), contradicting the service's own idempotent-retry doc-claim; the concurrency test that should catch this discards thread exceptions without asserting on them

- **Fájl:** `backend/app/community/services/block_service.py:114-152` (`block`),
  `194-226` (`mute`); router: `backend/app/community/routers/safety.py:135-149,234-249`
  (only catches `ValueError`/`SelfBlockNotAllowed`, not `IntegrityError`).
- **Probléma:** Both functions SELECT-then-INSERT with no `IntegrityError`
  catch, unlike `follow_service.py:185-193` / `220-227`, which explicitly
  catch `IntegrityError`, rollback, re-read, and return the existing row
  (the documented "idempotent at retry" pattern this round's own module
  docstring claims parity with — "same precedent as `follow_service.py`" —
  a claim that is false for the concurrent case). Confirmed independently:
  `test_a1_concurrent_block_writes_produce_one_row`
  (`backend/tests/community/test_block_service.py:767-807`) spins two real
  threads racing `block()`, appends any raised exception to an `errors`
  list — **and never asserts `errors == []`**. The test only checks the
  final row count is 1 (true regardless, because the DB `UNIQUE` constraint
  is fail-closed), so it passes green whether or not one thread's call
  raised an uncaught `IntegrityError`. This is exactly the "green
  guard-test that never actually exercises the failure path" class
  `docs/LESSONS.md` L349–L351 names.
- **Hatás:** Two genuinely concurrent block/mute requests on the same pair
  (e.g. a mobile double-tap + client retry) → one request gets a 500
  instead of the idempotent-success the docstring promises. DB integrity
  is fine (no duplicate row); this is an availability/robustness gap, not
  a data-safety breach. **Currently unreachable in production** — see NOTE-1.
- **Kötelező javítás:** mirror `follow_service.py`'s pattern in both
  `block()` and `mute()`: wrap the `db.add(...); db.flush()` in
  `try/except IntegrityError`, `db.rollback()`, re-read the existing row,
  return it. Then fix the test to actually assert `errors == []` (or
  assert the specific tolerated outcome) so a future regression cannot
  silently reintroduce this.
- **Ellenőrzés:** the corrected `test_a1_concurrent_block_writes_produce_one_row`
  asserting `errors == []`, run 5-10× (thread races are flaky) to build
  confidence; same for an equivalent mute concurrency test if one is added.
- **Státusz:** FIXED (`bf5862d0`) — `block()`/`mute()` now wrap the
  follow/request mutation (`block`) or the mute INSERT (`mute`) in
  `try/except IntegrityError: db.rollback(); re-read; return`, mirroring
  `follow_service.follow()` exactly. Independently read the diff: correct.
  The concurrency test now asserts `errors == []` at the end (previously
  silently discarded). Implementer reported 5/5 green re-runs. Gate
  re-verified green in a fresh isolated clone (`/tmp/review-e09-r08-fix1`).

### F3 — MINOR — Block-existence oracle: a blocked party can learn they were blocked by comparing 403 vs 404

- **Fájl:** `backend/app/community/routers/social_graph.py:501-510, 562-569`
- **Probléma:** Owner-not-found → 404; block exists (either direction) →
  403. A caller B who has not blocked anyone can distinguish "A blocked me"
  (403) from "A doesn't exist" (404) by probing `GET
  /community/profiles/{A}/followers`. Most social products keep block
  state opaque to the blocked party specifically to avoid this kind of
  enumeration/harassment-adjacent signal.
- **Hatás:** A blocked user can confirm they were blocked (rather than the
  usual "nothing happened" ambiguity), across any public_id they can
  guess/enumerate. Not a data breach (no content is exposed), a UX/privacy
  design question.
- **Kötelező javítás (vagy dokumentált WONTFIX):** either return a uniform
  404 for both "not found" and "blocked-and-caller-is-not-the-blocker", or
  explicitly accept the current behavior as intended design and record the
  decision in the ADR. Given this is unreachable in production today
  (NOTE-1), does not block this round's merge — but should be decided
  before the mount round.
- **Ellenőrzés:** n/a until the mount round decides the direction.
- **Státusz:** OPEN (non-blocking — tracked as a pre-mount follow-up)

### N1 — NOTE — Entire community router (safety.py + the block-filter wiring in social_graph.py) is unmounted in production

`backend/app/community/__init__.py:71` — `build_community_router` still
only returns `routers.profile.router`; `main.py` mounts nothing from
Community. Same latent-until-mount posture as every Community round since
Kör 2 (confirmed by grep — no new regression). F1–F3 above are all
consequences of code paths that are exercised only under test fixtures
today. Flag for the eventual mount round: re-review F1–F3 at that point,
since "unreachable" stops being true.

### N2 — NOTE — `relationship_context_from_block_flag` (access_policy.py extension) is defined but never called

`backend/app/community/policies/access_policy.py:86-108` — the read path
calls `is_blocked_pair` directly and hard-codes the 403 rather than routing
through `CommunityAccessPolicy.evaluate_profile_access`. Not a defect (the
hard-coded 403 is strictly more conservative), but the "wire
`RelationshipContext.blocked` to live data" framing in ADR 0402 §D2 is
scaffolding, not yet exercised on the live path. Worth tightening in a
future round that actually needs `evaluate_profile_access`'s SUMMARY tier
here (e.g. if `read_profile` gets authenticated per the D2 follow-up).

### N3 — NOTE — `idempotency_key` parameter is required but unused in `block_service.py`

Declared on all four mutation functions, never referenced in any body
(grep-confirmed). Idempotency is achieved via the UNIQUE constraint +
existing-row read, not key-based dedup — identical to the existing
`follow_service.py` pattern, so not a regression. No action needed; noting
so a future reader doesn't assume replay protection that isn't there.

### N4 — NOTE — Private-account follower/following visibility remains fully deferred

`social_graph.py` docstrings explicitly defer per-profile visibility
gating (private accounts) to "Kör 8/13" — this round adds the *block*
filter but not the *private-account* filter. Pre-existing deferral (not
introduced by E09-R08); becomes load-bearing once N1's mount round lands,
since until then a private account's graph would be enumerable by any
non-blocked authenticated caller.

### N5 — NOTE — `profile.py::read_profile` / `privacy.py::get_privacy` / `handles.py` GETs remain unauthenticated

Confirmed untouched by this round's diff (`git diff --name-only` clean) and
still lacking `CurrentUser` at HEAD. Matches the documented D2 scope
decision (brief §0.0, ADR 0402) — not a new regression. Restated here only
because the security pass flagged it independently; same conclusion.

## Kötelező próbatesztek — saját, eldobható

Két saját, eldobható próba futott (nem a jelentésbe committolva):

1. Independent gate re-run in a fresh `/tmp/review-e09-r08` clone (untruncated
   — the implementer's own run was piped through `| tail`, which the
   `mm-round.sh` anti-hallucination guard correctly flagged
   `gate_shape=VIOLATION`). Result: **MINDEN GATE ZÖLD**, all 11 steps.
2. Read-through of `test_a1_block_atomicity_partial_failure_rolls_back` to
   confirm the monkeypatch-injected failure is a *real* mid-transaction
   fault injection (not a tautology) — confirmed: it patches
   `block_service._existing_follow` to raise on its second call, then
   asserts BOTH that no block row landed AND that the follow edge is still
   intact. Legitimate.

The security-reviewer agent additionally ran its own independent grep-based
verification of the IDOR/actor-resolution, block-first-ordering, CHECK
constraint correctness, and SQL-injection-surface claims (see its findings
folded into "Checked and clean" implicitly above — all PASS, no BLOCKER).

## Architektúra + termékhatárok

`tool/check_architecture.dart` diff: none (allowlist baseline unchanged,
12 pre-existing deviations, none added). `access_policy.py` stays DB-free
(no `Session`/SQLAlchemy import added — confirmed by grep). No raw audio,
mic, or plugin access in this diff (backend + Community UI only). No secret
material added (`check_secrets.dart`: 0 findings, part of the green gate).

## Javító kör (2026-08-23, ugyanaz a motor — MiniMax, ugyanazon a branchen)

Prompt: `.pipeline/fix-prompt-E09-R08-1.md`. Eredmény: `done`, commit
`bf5862d0` a review-commit (`985d2af6`) fölött. Az implementer saját gate-
futása ismét `gate_shape=VIOLATION`-t jelzett (`| tail`/`&&` mögé rejtve) —
a jelentést emiatt megint NEM fogadtam el bemondásra: friss, izolált
`/tmp/review-e09-r08-fix1` klónban, csonkolatlanul újrafuttattam a teljes
gate-et. **MINDEN GATE ZÖLD** (mind a 11 lépés, l10n-nel együtt).

A scope-audit 4 fájlt jelzett a `bf5862d0` diffben:
`lib/l10n/features/community_{en,hu}.arb` (ÉN magam engedélyeztem a
fix-promptban, csak elfelejtettem a brief `allowed_paths` TOML-ját is
frissíteni — saját folyamat-hiányosság, nem implementer-sértés) és
`lib/l10n/app_{en,hu}.arb` (a `tool/gen_l10n_segments.dart` GENERÁLT
aggregátuma a feature-ARB-okból — mechanikus, elkerülhetetlen velejárója az
engedélyezett `community_{en,hu}.arb` szerkesztésnek, ugyanaz a minta, mint
az első fordulói D5-collateral). Mindkettő elfogadva, nem lelet.

F1 és F2 mindkét fix tartalmát önállóan elolvastam a diffben (nem csak az
implementer önbevallására hagyatkozva) — mindkettő a review §Kötelező
javítás pontjait pontosan követi. F3 (block-existence oracle) nyitva marad,
non-blocking, a pre-mount kör dolga a döntés.

## Következő lépés

**APPROVED.** F1 és F2 javítva és függetlenül igazolva. F3 (MINOR) és a
NOTE-ok nyitva maradnak, non-blocking follow-upként — a legtöbbet a
§10.4/N1 (a modul router-je még nincs mountolva élesben) már amúgy is
védi. Következő: CI-dispatch a `bf5862d0` SHA-n (a diff `docs/rounds/**`-t
érint, tehát a Router CI is triggerelődik — mindkettőt meg kell várni
exact-SHA-n), majd zöld kapu esetén squash-merge.
