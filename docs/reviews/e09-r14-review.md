# E09-R14 — Review

Brief: `docs/rounds/e09-r14-feed-ui-cache-and-mindful-use.md`
Diff: `git diff ae555d82...d85f940b` (branch `minimax/e09-r14-feed-ui-cache-and-mindful-use`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-23
Verdikt: **APPROVED** (javító kör 1 után, `d85f940b`) — lásd a §"Javító kör 1 zárása" szakaszt a jelentés végén.

## Összegzés

BLOCKER: 0 · MAJOR: 2 (mindkettő ZÁRVA javító kör 1-ben) · MINOR: 1 (ZÁRVA) · NOTE: 2

Independent gate re-run (isolated `/tmp/review-e09-r14` clone cloned from
`origin/minimax/e09-r14-feed-ui-cache-and-mindful-use` @ `144a4208`,
untruncated): **MINDEN GATE ZÖLD** — format, analyze, the brief's
`gate_tests` path, architecture, secrets, l10n (all green). The implementer's
own gate run is genuinely untruncated (`gate_shape=VIOLATION` in the signal
is a confirmed FALSE POSITIVE — the regex matched two `implementer_guard.py`
BLOCKED attempts to `cat tools/round-gate.sh | head -30/50` for inspection,
never an actual truncated gate execution; the log shows 6 real
`tools/round-gate.sh test/features/community/presentation/following_feed_test.dart
2>&1` invocations, all full and green — same false-positive class already
noted for E09-R05).

A dedicated `security-reviewer` agent pass (risk=high) returned **PASS, no
BLOCKER/MAJOR** — cache isolation is structurally sound (storage key never
defaults/hardcodes `userId`), no injection surface (`Text()`-only rendering,
no `WebView`/`launchUrl`/`Markdown`), no secret reaches the plaintext cache,
the no-autoplay/no-auto-pagination invariant is genuinely enforced (the one
scroll listener only records position, never fetches), and no raw
exception/stack trace reaches a widget.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Hálózati hiba esetén a feed nem omlik össze | ✅ | `following_feed_test.dart` A1 group (2 tests), own gate run green, independently re-run |
| A2 | A cache nem keveredik accountok között | ✅ | `following_feed_test.dart` A2 group; independently read `feed_cache.dart:167` `_storageKeyFor` — `userId` is a required, non-defaulted `int`; security-reviewer independently confirmed |
| A3 | Nincs automatikus hang-/videólejátszás, nincs auto-pagination | ✅ | `following_feed_test.dart` A3 group + dedicated "Real-violation probe" test; §10.3 documents the mandatory real-violation probe (scroll-listener auto-pagination added → A3 RED → reverted) — code inspection confirms the probe code is NOT present in the final diff (only `_rememberScroll`, which records position and never calls `loadMore`) |
| A4 | Duplikált post nem jelenik meg egy session-ben | ✅ | `following_feed_test.dart` A4 group (loadMore overlap + refresh subset) |
| A5 | Ismeretlen artifact-típus fallback-kártyát kap, nem crash-t | ✅ | `following_feed_test.dart` A5 group; `feed_card_registry.dart` exhaustive `switch` over the sealed `ShareArtifact` hierarchy, compile-time-checked |
| A6 | Létezik egyértelmű end-of-feed állapot | ✅ | `following_feed_test.dart` A6 group |
| A7 | Pull-to-refresh megőrzi a scroll-pozíciót és jelzi az új posztokat | ✅ | `following_feed_test.dart` A7 group (scroll delta assertion + offline banner test doubles as the "jelzi" half) |

All 7 acceptance cells pass by their own dedicated test AND by my
independent, untruncated gate re-run. However, two MAJOR findings below
survive the acceptance-criteria table because they are not covered by any
A1–A7 cell — they concern the round's own stated goal (§1) and a
project-wide binding convention (CLAUDE.md), not a §6 cell.

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e09-r14 --brief
docs/rounds/e09-r14-feed-ui-cache-and-mindful-use.md --base ae555d82` →
`Legacy scope audit OK (ae555d82e99d..144a42081da2, 6 changed path(s), 0
generated/ignored)`. All 6 changed files are exactly the 5 `allowed_paths`
production/test files plus the brief itself (§10 handoff). **Nincs
listán-kívüli fájl.**

## Megállapítások

### F1 — MAJOR — Both new UI files ship zero localization; the exact same gap was ruled MAJOR in E09-R08's review

- **Fájl:** `lib/features/community/presentation/screens/following_feed_screen.dart:50-61`
  (11 hardcoded Hungarian labels in `_FeedLabels`, plus 2 more inline
  `SnackBar` strings at `:287` and `:430`) and
  `lib/features/community/presentation/widgets/feed_card_registry.dart`
  (every card's Hungarian copy — `'Gyakorlás összegzés'`, `'Ehhez a
  poszthoz nincs megjeleníthető tartalom.'`, etc. — none routed through
  `AppLocalizations`).
- **Probléma:** `grep -c AppLocalizations` on both files returns 0. CLAUDE.md
  is explicit and binding: "every user-facing string goes through ARB →
  `AppLocalizations`". The screen's own doc-comment rationalizes the gap as
  "a future round's scope" because `lib/l10n/**` is not on this round's
  `allowed_paths` — but this is the **identical** rationalization the
  E09-R08 review already rejected as MAJOR
  (`docs/reviews/e09-r08-review.md` F1: *"Safety screen ships zero
  localization; every sibling Community screen uses `AppLocalizations`"*,
  fixed by adding the ARB file to the fix round's scope). This round
  repeats the same gap across **two** files (worse: R08 was one file).
  Sibling Community screens `community_gate_screen.dart` (3 hits) and
  `edit_profile_screen.dart` (16 hits) — and now `safety_relationships_screen.dart`
  (3 hits, post-fix) — all follow the convention; the two new files in this
  round are the outliers.
- **Hatás:** Breaks Hungarian-locale parity for every string the feed
  surfaces — every label, banner, button, and all 7 artifact-card templates
  the round explicitly built to be "reszponzív, hozzáférhető" (§1). The
  `round-gate.sh` l10n step only checks *existing* ARB en/hu symmetry, so a
  wholly un-localized new screen passes it silently (measured, same
  blind-spot as E09-R08).
- **Kötelező javítás:** add `lib/l10n/features/community_en.arb` +
  `community_hu.arb` to the fix round's `allowed_paths` (an orchestrator-
  directed scope amendment, same precedent as E09-R08's fix), add the ~13
  feed-label keys (real Hungarian translations, not machine-transliterated
  placeholders) plus per-artifact-card strings, route both files through
  `AppLocalizations.of(context)!`, and regenerate the aggregate with
  `dart run tool/gen_l10n_segments.dart --write` (mechanical, same collateral
  the R08 fix accepted under the same reasoning).
- **Ellenőrzés:** `dart run tool/ci/check_l10n_parity.dart` (already in the
  gate) + `grep -c AppLocalizations following_feed_screen.dart
  feed_card_registry.dart` ≥ 1 each.
- **Státusz:** FIXED (`d85f940b`, commitok `d2522dea`/`b87574cb`/`c0237b83`)
  — independently verified in a fresh `/tmp/review-e09-r14-fix1` clone:
  `grep -c AppLocalizations` → 8 (`following_feed_screen.dart`) / 9
  (`feed_card_registry.dart`), 0 remaining hardcoded Hungarian strings
  (`grep` for the original literals returns nothing), real Hungarian
  translations added to `lib/l10n/features/community_hu.arb` (not
  machine-transliterated — spot-checked), ICU placeholders used correctly
  for parameterised strings, aggregate regenerated via
  `tool/gen_l10n_segments.dart --write`. Gate l10n step ZÖLD (1750 messages,
  en↔hu parity).

### F2 — MAJOR — Cache rehydration silently discards the artifact type on every offline/cached render, even though the correct wire data is persisted and a working decoder already exists in-repo

- **Fájl:** `lib/features/community/application/controllers/feed_controller.dart:715-730`
  (`_artifactFromEnvelope`).
- **Probléma:** `_envelopeOf` (`:537-558`) correctly persists the artifact's
  full wire JSON via `artifact.toJson()` for every known `ShareArtifact`
  subtype. But `_artifactFromEnvelope`, the rehydration path used every time
  a post is read back FROM the cache (the initial cache-priming step of
  `load()` at `:274-276`, and the entire offline fallback path), **always**
  returns `UnfilledCommunityShareArtifact()` regardless of the stored
  `type` — even for a fully valid, known-type payload. The comment claims
  "the artifact's full Kör 13 schema is a future round's job", but the
  decoder is not missing: `ShareArtifact.fromJson(Object? json)`
  (`share_artifact.dart:120`) already exists, is public, and is already
  imported in this very file (`:68`). **Confirmed by an independent probe
  test** (real `PracticeSummaryArtifact.toJson()` written to the cache via
  the exact envelope shape `_envelopeOf` produces, then read back through
  the real `FollowingFeedScreen` + `FeedController` with a repository that
  throws to force the offline path): the rendered card is the FALLBACK
  card (`'Ehhez a poszthoz nincs megjeleníthető tartalom.'`), not the
  practice-summary card (`'Gyakorlás összegzés'`) — `practiceCard=0
  fallbackCard=1`.
- **Hatás:** Every cached / offline-displayed post in the feed — the
  round's own headline feature ("Reszponzív, hozzáférhető feed **offline
  cache-sel**", §1) — renders as a generic "content not available" card,
  regardless of its real type, defeating the purpose of caching a rich
  feed. This is untested: the widget test's own cache-priming helper
  (`_envelopeOfForTest`, `following_feed_test.dart:762-779`) hardcodes
  `'artifact': {'type': 'unfilled', 'schemaVersion': 0}` unconditionally —
  even in the A1 "falls back to offline state" test, which builds its post
  with a real `_practiceArtifact()` — so no test ever exercises a
  known-type artifact through the cache round-trip.
- **Kötelező javítás:** in `_artifactFromEnvelope`, attempt
  `ShareArtifact.fromJson(raw)` inside a try/catch for the non-`unfilled`/
  non-`unknown` case; on success return the decoded typed artifact, on any
  decode failure (corrupt/genuinely-unknown-future-type) fall through to
  `UnfilledCommunityShareArtifact()` (preserves A5's "unknown type never
  crashes" guarantee while fixing the "known type never rehydrates" bug).
- **Ellenőrzés:** a new test asserting that a cache-primed post with a
  known artifact type (e.g. `PracticeSummaryArtifact`) renders its real
  card (not the fallback) when the feed falls back to the offline/cached
  path — add to the existing A1 group or a new A1.3 cell.
- **Státusz:** FIXED (`d85f940b`, commit `37d31037` + test `4c3886ff`) —
  independently read the fix: `_artifactFromEnvelope` now calls
  `ShareArtifact.fromJson(raw)` inside a try/catch, falling back to
  `UnfilledCommunityShareArtifact()` only on decode failure — exactly the
  prescribed patch. New test `following_feed_test.dart:335` ("a
  cache-primed post with a known artifact type rehydrates to its own
  card, not the fallback — A1.3") asserts
  `find.text('Gyakorlás összegzés')` (the practice-summary card), not the
  fallback copy. Independently re-ran the full gate in a fresh clone: 14
  tests green (was 13), including the new A1.3 cell; A5 (unknown type →
  fallback) still green, confirming the try/catch preserves that
  guarantee.

### F3 — MINOR — `_AudienceBadge.audience` is untyped (`dynamic`), losing compile-time safety for no documented reason

- **Fájl:** `lib/features/community/presentation/widgets/feed_card_registry.dart:152-154`.
- **Probléma:** `_AudienceBadge({required this.audience})` declares
  `final dynamic audience;` and reads `audience?.wireValue?.toString()` —
  the caller (`_CardHeader`, `:134`) always passes a typed
  `CommunityAudience`. There is no reason for the loosened type; it drops
  the compiler's ability to catch a future call-site mistake and silently
  degrades a null/wrong-type value to `'public'` instead of failing loudly.
- **Hatás:** Low — the class is private, single call-site, all correct
  today. Purely a latent footgun for a future edit.
- **Kötelező javítás:** change `final dynamic audience` to
  `final CommunityAudience audience` (already imported).
- **Ellenőrzés:** `flutter analyze` stays green (a type-safe signature is
  strictly narrower, no call site breaks).
- **Státusz:** FIXED (`d85f940b`, commit `c0237b83`) — `_AudienceBadge`
  now declares `final CommunityAudience audience;`. `flutter analyze`
  ZÖLD in the independent gate re-run.

## Biztonsági review (risk=high, dedikált pass)

**PASS — 0 BLOCKER/MAJOR.** Teljes jelentés a session jegyzeteiben; a
lényeg: a cache-kulcs sosem default-ol/hardcode-ol `userId`-t (A2
strukturálisan helyes, bár a `feedCacheProvider`/
`communityFeedRepositoryProvider` production wiringja jövőbeli kör dolga —
D6 szerint szándékosan); nincs injection-felület (`Text()`-only render);
titok nem kerülhet a plaintext cache-be (a `CommunityPost` domain-típusnak
nincs token/jelszó mezője); a no-autoplay/no-auto-pagination invariáns
ténylegesen érvényesül (az egyetlen scroll-listener csak pozíciót jegyez,
nem fetch-el); nyers kivétel/stacktrace sosem jut widgetbe.

- **NOTE-1:** a jövőbeli HTTP-repository-wiring körnek account-váltáskor
  invalidálnia kell a `feedControllerProvider`-t is (nem csak a cache-t) a
  defense-in-depth kedvéért — a mai `_seenIds` per-controller-instance és a
  `load()` törli induláskor, tehát MA nincs szivárgás, ez egy jövőbeli
  körre vonatkozó megjegyzés.
- **NOTE-2:** ugyanaz a jelenség, mint F2, biztonsági szemszögből
  kockázatmentesnek minősítve (holt, dekódolatlan adat, nem szivárgás) — F2
  alatt funkcionális hibaként kezelve, mert a kör saját célját sérti.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (saját `/tmp/review-e09-r14` klón, untruncated) |
| analyze | zöld | ✅ |
| `test test/features/community/presentation/following_feed_test.dart` | zöld (13 teszt + valódi-sértés próba) | ✅ |
| architecture | zöld (12 allowlisted deviation — pre-existing baseline, nem ez a kör hozta) | ✅ |
| secrets | zöld | ✅ |
| l10n (aggregate freshness + parity) | zöld | ✅ (megjegyzés: ez a lépés csak a MEGLÉVŐ ARB-k szimmetriáját nézi, F1 emiatt csúszott át rajta) |
| CI (teljes suite + property + APK) | — | a javító kör után dispatch-elve |

## Javító kör 1 zárása (2026-08-23, `d85f940b`)

Mind a 3 lelet (F1 MAJOR, F2 MAJOR, F3 MINOR) FIXED, egyenként
függetlenül ellenőrizve fenti (fájl:sor + parancskimenet). Gate újra
lefuttatva egy friss `/tmp/review-e09-r14-fix1` klónban, csonkítatlanul:
**MINDEN GATE ZÖLD** (format, analyze, 14/14 teszt — 1 új az F2 A1.3
cellához —, architecture, secrets, l10n). Scope-audit:
`tools/scope-audit.py --repo /tmp/review-e09-r14-fix1 --brief
docs/rounds/e09-r14-feed-ui-cache-and-mindful-use.md --base 29fcc44d` →
`OK (9 changed path(s), 0 generated/ignored)` — pontosan a bővített
`allowed_paths` (5 eredeti + 4 ARB fájl) elemei, listán kívüli fájl nincs.

## Javító kör 2 — CI-only baseline bump (2026-08-23, `ef9e9a1a`)

Az első `full-gate.yml` dispatch (`4ede6232`-n) **PIROS lett**: a TELJES
CI-suite (ADR 0053 — a round-gate.sh csak a brief célzott tesztjét futtatja,
a teljes suite-ot a CI) elkapta a `test/ui/ui_inventory_test.dart`
hardcode-olt képernyő-számláló driftjét (`Expected: hasLength(70), Actual:
hasLength(71)`) — ugyanaz a hibaosztály, mint E09-R05...R13-ban ismételten
(a kör új `following_feed_screen.dart`-ja bővíti a valódi számot, a
baseline nem az `allowed_paths` része, mert a fájl körön kívüli, meglévő
mérce). Orchestrátor-oldali, egysoros, mechanikus javítás (`ef9e9a1a`),
lokálisan ellenőrizve (`flutter test test/ui/ui_inventory_test.dart` zöld)
— nem production kód, nem a kör tartalmi scope-ja, ugyanaz a precedens,
mint az E09-R07 fix2 / E09-R06 fix / E08-R22/R23 baseline-bump commitjai
(mind "Ralph (autonomous)" orchestrátor-identitással, nem implementer-
dispatch-csel).

## Merge-döntés

**Nincs nyitott BLOCKER/MAJOR/MINOR.** Minden gate zöld a javító kör 1 és a
CI-only javító kör 2 után, önállóan ellenőrizve. ADR 0052 szerint →
**squash-merge mehet a CI (teljes suite + property + APK) zöld futása
után** — újra-dispatch-elve az `ef9e9a1a` HEAD-re.
