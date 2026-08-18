# E07-R22 — Security / Privacy Review (dedicated, mandatory — brief `risk = "high"`)

Brief: `docs/rounds/e07-r22-weekly-and-today-screen.md` (incl. §0.0 pre-flight revision)
Diff reviewed: `git diff 4c0b6b82..cbee3d1c` (10 files, +1061/−2) in the isolated clone `/tmp/review-e07-r22`, branch `terra/e07-r22-weekly-and-today-screen`, HEAD `cbee3d1c` (verified with `git rev-parse HEAD`)
Reviewer: Claude (security-reviewer subagent) · Date: 2026-08-18 · Scope: READ-ONLY, no production edits (AGENTS.md §15.1)

## Verdict (as reviewed at `cbee3d1c`): **CHANGES REQUIRED** — *superseded, see "Post-fix verification (commit `c2785002`)" at the end of this file*

**Current verdict at `c2785002`: APPROVED — merge permitted.** Both MAJORs are
closed by measurement; one **new MINOR** (caller-obligation residual on
`isDeepLinkLaunch`) is carried forward to the routing/notification wiring round.

CRITICAL: 0 · BLOCKER: 0 · **MAJOR: 2** · MINOR: 0 · NOTE: 4

Both MAJORs sit on the single seam the brief itself named as the round's risk
(§5.4 / §9 / A7 — "Külső bemenet: ellenőrzés nélkül **összeomlást** vagy **rossz
állapotot** okoz"). MAJOR-1 is the crash half, MAJOR-2 is the wrong-state half.
Both are reproducible today against the shipped public API; both share one root
cause (`tryParse` validates only the *static* map type and collapses "rejected
link" and "no link" into the same `null`). No secret leak, no consent bypass, no
network/mic/camera/storage surface was introduced — the rest of the round is
clean, and the leak scenarios the orchestrator asked me to construct (inactive /
paused / archived plan content escaping through a disallowed launch context)
**failed to reproduce**: that gate holds (probe P2c/P2d below).

---

## Findings

### MAJOR-1 — `TodayPlanRouteRequest.tryParse` **throws** on a hostile payload delivered through the idiomatic `cast<String, String>()` conversion

**Where:** `lib/features/practice_generator/application/controller/today_plan_controller.dart:156-163` (the `extra[_destinationKey]` lookup on line 159), doc-comment lines 146-149.

**Failure scenario (concrete input → concrete bad output):**
A notification payload is a `String` (`flutter_local_notifications` `NotificationResponse.payload`), and `go_router`'s `extra` is `Object?`. To satisfy this parser's `Map<String, String>` requirement the wiring layer must convert. The idiomatic zero-copy conversion is

```dart
final extra = (jsonDecode(response.payload!) as Map<String, dynamic>)
    .cast<String, String>();
TodayPlanRouteRequest.tryParse(extra);   // <-- throws
```

`Map.cast` returns a **lazy, unchecked view**: it satisfies `extra is Map<String, String>` and `extra.length == 1`, but the element type is only verified at lookup time. With the payload `{"destination":{"nested":1}}` (or `{"destination":1}`) the third clause of the guard — `extra[_destinationKey] != _todayDestination` — throws `TypeError: type '_Map<String, dynamic>' is not a subtype of type 'String?' in type cast` **inside `tryParse`**, before any caller can decide anything. A function named `tryParse`, documented as "malformed or unknown external values become null", propagates an exception from external input.

**Evidence (measured, probe P1c — passed):**

```dart
final hostile = (jsonDecode('{"destination":{"nested":1}}') as Map<String, dynamic>)
    .cast<String, String>();
expect(hostile, isA<Map<String, String>>());              // passes: the type gate is defeated
expect(() => TodayPlanRouteRequest.tryParse(hostile),
       throwsA(isA<TypeError>()));                        // passes: it throws
```

Supporting measurements:
- `jsonDecode('{"destination":"today"}')` is `_Map<String, dynamic>` → `tryParse` returns `null` even for a **well-formed** payload (probe P1b). So the wiring round *will* hit "it never parses" and the cast is the natural next step.
- `Uri.queryParameters` is a real `UnmodifiableMapView<String, String>` (measured) — that path is safe from this crash, which is why the defect is not visible from the round's own tests.
- The A7 test (`today_plan_screen_test.dart:48-65`) only feeds a literal `const <String, String>{'destination': 'unrecognised'}`; no shape in the delivered tests exercises a map whose element types are unverified, so this cell cannot go red.

**Violated rule:** brief §5.4 ("Ismeretlen vagy manipulált paraméter nem okozhat összeomlást") + acceptance A7; §6.1 red-trigger "A deep link ellenőrzés nélkül → A7" is inoperable for this input class. Also the file's own doc-comment claim (lines 148-149) is factually false, which is the same false-assurance pattern as E07-R20 MINOR-1.

**Suggested direction (no scope growth):** validate *contents*, not the generic type — accept `Object?`, check `extra is Map`, then check each key/value with `is String` (the repo's own codecs already do per-element validation, e.g. `_requireText`/`_decodeJsonId` in the domain layer). A `try`/`catch` around the lookup would also close it but hides the shape mismatch. Add a probe-shaped test (cast view + non-String value → `isNull`).

---

### MAJOR-2 — A **rejected** launch payload is indistinguishable from **no** launch payload, so a manipulated deep link renders MORE than a valid one (feature-flag gate bypassed)

**Where:** `lib/features/practice_generator/presentation/screens/today_plan_screen.dart:36-42`:

```dart
final isPermittedLaunch = launchRequest?.permits(
  activePlan: plan, isFeatureEnabled: isTodayRouteEnabled);
final state = controller.resolve(
  launchRequest != null && isPermittedLaunch != true ? null : plan);
```

**Failure scenario:** `launchRequest == null` means "not launched from a link" *and* "the link was rejected". When `tryParse` rejects a payload, the natural wiring (`launchRequest: TodayPlanRouteRequest.tryParse(extra)`) hands the screen `null`, the `&&` short-circuits, `permits(...)` is never called, and the screen renders the full active-plan content — **with `isTodayRouteEnabled == false`**. A *valid* payload with the flag off correctly falls back to the empty state (probe P2a). So a manipulated/unparseable parameter obtains strictly more than a well-formed one, which is the definition of a fail-open gate.

The trigger needs no attacker: `Uri.queryParameters` for
`strumsight://plan/today?destination=today&utm_source=push` has `length == 2` (measured) → `tryParse` → `null` → ungated render. A routine tracking/locale query parameter appended by the push pipeline is enough. The JSON-payload path (MAJOR-1 evidence) always yields `null` too, which means `permits(...)` — the only flag check this round ships — becomes dead code in the most likely wiring.

**Evidence (probe P2b — passed):**

```dart
final launch = TodayPlanRouteRequest.tryParse(
    const <String, String>{'destination': 'today', 'inject': 'x'});
expect(launch, isNull);
await _pump(tester, TodayPlanScreen(
  controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
  plan: activePlan,            // active plan with one scheduled day
  launchRequest: launch,       // isTodayRouteEnabled defaults to false
));
expect(find.byKey(const Key('today-plan-scheduled')), findsOneWidget);  // content renders
```

Contrast, same fixture, valid payload (probe P2a — passed): `today-plan-empty` is shown and `today-plan-scheduled` is absent. The round's own A7 "disabled deep link" test only proves the P2a direction; its malformed-payload sibling passes `plan: null`, so it is structurally incapable of detecting this inversion (same wrong-polarity family as E07-R20 MAJOR-1).

**Violated rule:** brief §5.4 ("Az értesítésből érkező link **csak akkor** visz a »ma« nézetre, ha van aktív terv **és a flag engedi**; egyébként biztonságos célra esik vissza") + acceptance A7 ("rossz állapot"). Not an AGENTS.md §5 non-negotiable: the content is the learner's own on-device plan, nothing leaves the device, and the exposure is to the device holder — that is why this is MAJOR, not BLOCKER.

**Suggested direction:** make the launch context explicit rather than nullable-implicit, e.g. a sealed `TodayLaunchContext` (`inApp` | `deepLink(TodayPlanRouteRequest)` | `rejectedDeepLink`), or an `isDeepLinkLaunch` bool alongside the request, so a *rejected* payload takes the safe branch instead of the ungated in-app branch. Extend the A7 malformed-payload test to carry an **active** plan so the cell can go red.

**Honest counter-argument (for the orchestrator's downgrade call):** a future `app_router.dart` could refuse to build the screen at all when `tryParse` fails, making the screen-level check pure defense-in-depth. I keep MAJOR because (a) this round ships the *only* gate that exists today, (b) the brief assigns the fallback duty to this round's own files ("a `today_plan_screen.dart` … ismeretlen/hiányzó/rossz típusú érték esetén a §5.3 szerinti biztonságos nézetre esik vissza"), and (c) the delivered A7 test cannot fail on it.

---

### NOTE-1 — `WeeklyPlanScreen` has no status gate and no flag parameter at all

`weekly_plan_screen.dart:19-47` renders `plan!.days` for **any** `PlanStatus`. Measured (probe P3b): an `archived` plan still renders `2026-08-19 · 1 blocks scheduled · 30m`. No free text is exposed (see the clean list below) and the caller passes the plan explicitly, so this is a composition decision, not a defect — but it is asymmetric with `TodayPlanScreen`, whose `resolve()` hard-gates on `status == active`. The wiring round should decide deliberately whether the weekly view may show paused/archived plans, and where its flag check lives.

### NOTE-2 — `TodayPlanState` retains the whole `AdaptivePracticePlan` (hence `PracticeGoal.userNote`) in a presentation-state object

`today_plan_controller.dart:34` keeps `plan` on the state even for `notScheduled`/`restDay`/`unavailableDay`. Nothing serializes, logs or exports it today (zero sinks, proven below), and the rendered tree is free-text-clean (probe P3a). Forward NOTE for the round that adds analytics, crash breadcrumbs or state dumps: route anything leaving this layer through `AdaptivePracticePlan.toSummary()` (which structurally omits goals — the E07-R10 seam), never the canonical model.

### NOTE-3 — Forward note for the notification/router wiring round

Measured facts the wiring round must not rediscover the hard way: `lib/core/notifications/nudge_service.dart` still passes **no** `payload` to `zonedSchedule` and registers **no** `onDidReceiveNotificationResponse`; `lib/app/routing/` has no Today/Weekly route (grep: 0 hits). When that wiring lands, build the `Map<String, String>` with a **checked** conversion (per-entry `is String`), never `.cast()`; and treat `tryParse == null` as *reject and redirect*, not as "no link" (see MAJOR-2).

### NOTE-4 — "{duration} remaining" presents a plan-time estimate as a definite claim

`today_plan_screen.dart:153` renders `l10n.todayPlanRemaining(...)` summed from `PracticeBlock.estimatedElapsed`; the ARB strings ("{duration} remaining" / "{duration} van hátra") drop the "estimated" qualifier. AGENTS.md §5 ("gyenge confidence nem jelenhet meg biztos állításként") is aimed at *measurement* confidence, so this is adjacent, not a violation — recorded so a copy pass can decide whether the wording should hedge.

---

## What I verified clean (positive evidence — the empty half of the report)

| Area | Evidence |
|---|---|
| **Sinks / logging** | `grep -nE "print\|debugPrint\|Logger\|log(\|logger\|dart:io\|dio\|http\|File(\|jsonEncode\|jsonDecode\|toJson\|SecureStorage\|SharedPreferences\|analytics\|Sentry\|Repository\|repository\|Store\|store"` over all four new `lib/` files → **exit 1, zero matches**. No plan content can be logged or persisted from this round. |
| **`shorten`/`skip`/`pause` write nothing** | `active_plan_controller.dart` imports only 8 domain models (no repository, no store, no `dart:io`); every action returns a new `ActivePlanUpdate` snapshot. The doc-comment claim (persistence deferred to composition) is accurate. |
| **Free text / PII** | `grep -nE "userNote\|songReference\|discomfort\|\bnote\b\|freeText\|email\|name"` over the four new files → **zero matches**. Canary probes P3a/P3b seeded `userNote: 'PRIVATE-NOTE-CANARY'`, `songReference: 'SONG-REF-CANARY'`, `title: 'PLAN-TITLE-CANARY'` and asserted absence from the rendered `Text` tree — passed. Full rendered text was `6m remaining Next block primaryFocus Start Swap Skip Make today shorter Pause plan Today` (Today) and `2026-08-19 1 blocks scheduled 30m Weekly plan` (Weekly). The only plan-derived values that reach the tree are `BlockKind.code`, `LocalDate.toString()`, `blocks.length`, `timeBudget.inMinutes` — all machine-derived. |
| **ARB strings** | The 22 new keys in each of `app_en.arb`/`app_hu.arb` carry no PII and exactly two placeholders: `duration` (a `String` produced by the private `_formatDuration`) and `count` (`int`). No user-supplied value is interpolated into a translatable string. |
| **Change-set payloads** | `active_plan_controller.dart:79-87, 94-97, 120-123`: `before`/`after` carry only enum `code`s and `inMicroseconds` ints; `target` interpolates charset-locked `BlockId`/`PlanId` values; `evidenceRefs: const <String>[]`. Nothing free-form enters the future change-log sink (contrast with the E07-R18 `evidenceRefs` NOTE). |
| **Type confusion into domain ctors (orchestrator question 3)** | **Closed.** `TodayPlanRouteRequest` has **no fields** and a library-private const ctor (`._()`), so no external value survives parsing, and a request cannot be forged outside the library — `permits()` cannot be bypassed by fabricating one. `LocalDate` is constructed only from the injected clock's calendar fields (`today_plan_controller.dart:55`), which are always in range, and `LocalDate` validates by `throw` (not `assert`), so release-mode assert stripping is irrelevant. No `Uri`, `int.parse`, `DateTime.parse` or `as` cast exists anywhere in the four new files. |
| **Inactive-plan leak attempt (orchestrator question 2)** | **Failed to reproduce = gate holds.** Probe P2c: `paused`, `archived`, `draft`, `cancelled` plans, with a **valid** payload and `isTodayRouteEnabled: true`, all render `today-plan-empty` and never `today-plan-scheduled`. Probe P2d: same with no launch request → still empty. `TodayPlanController.resolve` gates on `plan.status != PlanStatus.active` *before* any day/block is touched, so inactive day/block content cannot reach the tree by any route through this screen. |
| **`tryParse` rejection matrix (orchestrator question 1)** | Probe P1 — all of these return `null`: `null`, a `String`, a `Uri`, a `List`, `{}`, `{'destination':'today','planId':'plan.1'}` (extra key), `{'Destination':'today'}` (case), `{'destination':'today '}` (trailing space), `{'destination':'TODAY'}`, and `const <String, Object?>{'destination':'today'}`. Exactly one shape parses. Within the `Map<String,String>` static type the parser is strict and fail-closed; its weakness is the *unverified element type* (MAJOR-1) and the *meaning of null* (MAJOR-2), not permissiveness. |
| **Fail-closed enum handling** | Both `switch` statements (`today_plan_screen.dart:48-78` over 6 `TodayPlanMode` values; `today_plan_controller.dart:134-143` over all 8 `PracticeItemStatus` values) are exhaustive expression switches with **no `default`** → adding an enum value is a compile error, not a silent fall-through (contrast with the E06-R24 `else show` fail-open). |
| **§6 architecture / platform surface** | `today_plan_controller.dart` and `active_plan_controller.dart` import **no** Flutter (pure Dart, domain-only imports); the screens import only `package:flutter/material.dart`, `l10n`, and domain models. No plugin, permission, `dart:io`, network, microphone or camera reference anywhere in the diff. The offline base experience is untouched. |
| **Prompt injection (ADR 0131–0136 / §5.1)** | **N/A, verified:** the diff touches no AI provider, no tool-calling allowlist, no knowledge-base retrieval, no import/parser of external song content, and no prompt template. The only external-input surface is `tryParse`, covered above. No downloaded or generated content can influence policy, permissions or `allowed_paths`. |
| **Supply chain** | `pubspec.yaml`/`pubspec.lock` are **not in the diff** — zero new dependencies, zero new assets, so no provenance/licence entry was required. |
| **Secrets** | `dart run tool/ci/check_secrets.dart` → `Secret scan OK (2852 file(s) scanned, 0 finding(s))`. Semantic pass over the diff: the only literals added are l10n copy, widget `Key` strings, the `'destination'`/`'today'` route tokens, and synthetic test ids (`plan.1`, `day.19`, `revision.2`) — no key, token, URL or credential-shaped value. |
| **Scope** | The diff matches the brief's `allowed_paths` exactly (10 files); `lib/app/routing/**`, `lib/core/notifications/**`, the domain layer and `feature_flags.dart` are byte-for-byte unchanged. Zero production consumers of the new symbols (`grep -rn` over `lib/` and `test/` minus the round's own files → exit 1), so both MAJORs are latent-until-wired, which is exactly why they should be fixed now rather than inherited by the wiring round. |

## Reproduction

The probes above were run as a temporary file
`test/features/practice_generator/presentation/zz_security_probe_test.dart`
inside the isolated clone (`flutter test` → `+10: All tests passed`), then
**deleted**; `git status --short` in the clone is clean apart from this report.
Every probe is quoted inline above and can be recreated verbatim; the two
pure-Dart type probes (`Map<String,dynamic> is Map<String,String>` → `false`,
`Uri.queryParameters` → `UnmodifiableMapView<String, String>`) were run with
`dart run` outside the repo.

## Merge recommendation

**Do not merge as-is.** Both MAJORs are contained in two files already inside
`allowed_paths` (`today_plan_controller.dart`, `today_plan_screen.dart`) plus
the two existing test files; the fix is small and needs no new file, no ADR and
no scope change. After the fix, the required evidence is: (1) a `tryParse` test
whose input is a `cast<String, String>()` view over a non-String value,
asserting `isNull` (not a throw); (2) an A7 test whose malformed payload is fed
**together with an active plan** and asserts `today-plan-scheduled` is absent
while `isTodayRouteEnabled` is false.

---

# Post-fix verification (commit `c2785002`)

Re-review date: 2026-08-18 · Reviewer: Claude (security-reviewer subagent) ·
Scope: **closure of MAJOR-1 and MAJOR-2 only**, plus a fresh look at whether the
fix diff itself introduces anything new. NOTE-1…NOTE-4 and the "verified clean"
table were deliberately **not** re-checked (unchanged code).

Provenance verified independently, not taken from the hand-off summary:
`git -C /tmp/review-e07-r22 rev-parse HEAD` → `c2785002`,
`git branch --show-current` → `terra/e07-r22-weekly-and-today-screen`,
fix diff `git diff c2785002~1 c2785002` = 5 files (+96/−30): the two production
files, the two test files, and `docs/rounds/e07-r22-weekly-and-today-screen.md`.
No other file changed since the reviewed commit except the two review reports.

## Closure verdicts

| Finding | Verdict |
|---|---|
| MAJOR-1 (`tryParse` throws on a `cast` view) | **FIXED** |
| MAJOR-2 (rejected link ≡ no link → ungated render) | **FIXED** for the finding as filed; the gate now holds on every flagged path |
| *new* MINOR-1 (`isDeepLinkLaunch` is unsafe-by-omission) | **NEW-ISSUE — non-blocking, carry-forward to the wiring round** |
| Anything else new in the fix diff | **None found** (evidence below) |

---

## MAJOR-1 — **FIXED**

**New code:** `today_plan_controller.dart:156-175` — `extra is! Map` (raw `Map`,
no type argument) + `extra.length != 1`, then a per-entry
`entry.key is! String || entry.value is! String || key != 'destination' ||
value != 'today'` loop wrapped in `try { … } on TypeError { return null; }`.

**My own reproduction (not the delivered test's shape).** Pure-Dart probe over
**32 input shapes**, run with `dart run` inside the isolated clone against the
real `TodayPlanRouteRequest` (temporary file, since deleted):

- Lazy-`cast` views over a non-String **value**: `int` (the delivered test's
  shape), **nested `Map`**, **`List`**, `null`, `bool`, `double`, `Object()`,
  a double-applied `.cast()`, a `cast` over a `SplayTreeMap` source, a `cast`
  over an `UnmodifiableMapView` source, and an explicit
  `Map.castFrom<String, Object?, String, String>`.
- Lazy-`cast` views over a non-String **key** (`{1: 'today'}`) and over a
  non-String key *and* value simultaneously.
- The realistic wiring shape from the original finding:
  `(jsonDecode('{"destination":{"a":1}}') as Map<String, dynamic>).cast<String, String>()`
  and its `{"destination":42}` sibling.
- Raw (non-cast) hostile maps, the previous rejection matrix (null / String /
  Uri / List / `{}` / extra key / case / whitespace), and the accepted shapes.

**Result: 32/32 as expected — `failures=0`. Every Map-shaped hostile input
returns `null`; none throws.** The `TypeError` raised while the lazy view
materialises each `MapEntry` is raised *inside* the `for` header, i.e. inside
the `try`, so it is caught; and for raw (uncast) maps the per-entry `is String`
checks reject before any cast can occur. The fix is content-based, not tailored
to the `int` case.

**Red-trigger proof (the green result is meaningful).** I materialised the
pre-fix parser from `cbee3d1c` side-by-side with the fixed one (prefixed
imports) and ran the same shapes through both:

```
pre-fix (cbee3d1c) -> post-fix (c2785002)
THREW _TypeError   -> null       cast/int value
THREW _TypeError   -> null       cast/nested-Map value
THREW _TypeError   -> null       cast/List value
THREW _TypeError   -> null       jsonDecode -> cast (realistic wiring shape)
null               -> REQUEST    raw Map<String,dynamic> valid payload
null               -> REQUEST    jsonDecode valid payload
REQUEST            -> REQUEST    valid Map<String,String>
null               -> null       extra key
```

**Behaviour change worth recording (safety-positive, not a finding).** Dropping
the `Map<String, String>` static gate means a *well-formed* payload delivered as
`Map<String, dynamic>` — i.e. every `jsonDecode` result, the exact shape the
notification wiring will produce — now **parses** instead of being rejected.
That removes the strongest pressure toward `.cast()` in the wiring round and
routes valid payloads through `permits()` (flag + active-plan gate) instead of
through the ambiguous `null` branch. The accepted token still carries no fields
and has a library-private const ctor, so nothing external survives parsing.

**Residual, NOTE-level, not reproducible from external input:** `extra.length`
on line 157 is evaluated *outside* the `try`, and the `catch` is narrowed to
`TypeError`. A `Map` implementation whose `length`/`entries` getter throws (or
throws a non-`TypeError`) would still propagate. I could not construct such an
input from any realistic external source — `jsonDecode`, `Uri.queryParameters`,
`Uri.splitQueryString` and `Map.cast` views all have total `length` — so this is
recorded, not filed.

---

## MAJOR-2 — **FIXED** (with a new MINOR residual, below)

**New code:** `today_plan_screen.dart:43-53` —
`final isDeepLinkContext = isDeepLinkLaunch || launchRequest != null;` then
`planForState = isDeepLinkContext ? (launchRequest?.permits(…) == true ? plan : null) : plan;`
plus the new `isDeepLinkLaunch` parameter (default `false`, doc-commented
"Routing must set this when it calls `TodayPlanRouteRequest.tryParse`").

**Gating matrix I measured** (temporary widget test in the clone, since deleted;
`plan` = active plan with a scheduled day for the controller's clock date;
"PLAN EXPOSED" = the `today-plan-scheduled` key is in the tree):

| # | `launchRequest` | `isDeepLinkLaunch` | flag | Result | Correct? |
|---|---|---|---|---|---|
| P1 | rejected (`null`) | `true` | off | empty | yes |
| P2 | rejected (`null`) | `true` | **on** | empty | yes |
| P3 | rejected (`null`) | **omitted** | off | **PLAN EXPOSED** | **no — see MINOR-1** |
| P4 | valid | omitted | off | empty | yes (flag gate) |
| P5 | valid | omitted | on | PLAN EXPOSED | yes |
| P6 | valid | `true` | on | PLAN EXPOSED | yes |
| P7 | none (in-app) | `false` | off | PLAN EXPOSED | yes (intended in-app path) |
| P9 | rejected, canary | `true` | off | rendered text = `No active plan yet` / `Create and activate a practice plan…` / `Today` only; plan title absent | yes |

P1/P2 are the direct closure of the finding as filed: a rejected payload can no
longer obtain more than a valid one, and the flag gate is no longer dead code.

**The delivered A7 cell is a genuine behavioural red-trigger** — not merely a
compile-time one as §10 modestly claims. I mutated line 43 back to the pre-fix
discriminator (`final isDeepLinkContext = launchRequest != null;`) and re-ran
`flutter test today_plan_screen_test.dart`: the cell fails with
`Actual: Found 0 widgets with key [<'today-plan-empty'>]` (`+4 -1`). The file was
restored with `git checkout --` immediately afterwards; the clone's working tree
is clean apart from this report.

Both evidence items demanded by the original merge recommendation are delivered
and were re-run by me: controller **7/7** and screen **5/5** (12 tests, all
green) — matching the counts §10 claims.

---

## NEW MINOR-1 — `isDeepLinkLaunch` is safe-by-default but **unsafe-by-omission**; the old MAJOR-2 behaviour reproduces verbatim if a caller forgets it

**Where:** `lib/features/practice_generator/presentation/screens/today_plan_screen.dart:14, 28-32, 43`.

**Failure scenario (measured — row P3 above).** A future
`app_router.dart` writes the natural call
`TodayPlanScreen(plan: plan, launchRequest: TodayPlanRouteRequest.tryParse(state.extra))`
and omits `isDeepLinkLaunch: true`. For a rejected payload
(`?destination=today&utm_source=push`) `tryParse` returns `null` →
`isDeepLinkContext = false || false = false` → `planForState = plan` → the full
active plan renders **with `isTodayRouteEnabled == false`**. That is
bit-for-bit the original MAJOR-2 outcome.

**Root cause (structural, not stylistic):** rows **P3 and P7 are the same
argument tuple** at the widget boundary — `plan != null`, `launchRequest == null`,
`isDeepLinkLaunch == false`. The screen provably cannot distinguish "rejected
deep link" from "no deep link"; the whole discriminator now lives in the caller,
enforced only by a doc-comment. And the flag is load-bearing in *exactly one*
row (P3) — the rejected case, i.e. the case the caller is least likely to think
about, because the call site visibly "handles" the link via `launchRequest`.
Rows P4/P5/P6 show the flag is redundant whenever the request parsed.

**Why MINOR and not "MAJOR still open":**
1. **No live gap in this round.** `grep -rn "TodayPlanScreen(" lib/` → the
   constructor declaration only; all four call sites are in the round's own
   tests. Nothing in the delivered code makes the unsafe call.
2. The screen went from "cannot be used safely" to "can be used safely, and the
   correct usage is documented on the parameter" — a real reduction, and the
   correct usage is now covered by an operable red-triggering test.
3. **My own original finding explicitly sanctioned this shape** — MAJOR-2's
   "Suggested direction" offered "a sealed `TodayLaunchContext` … **or an
   `isDeepLinkLaunch` bool alongside the request**". Codex implemented the
   weaker of the two options I named; grading it MAJOR now would be moving the
   goalposts.
4. Exposure remains the learner's own on-device plan to the device holder — no
   AGENTS.md §5 non-negotiable, nothing leaves the device.

**Carry-forward requirement for the routing/notification wiring round** (this is
where it becomes blocking): either
(a) make `tryParse` total — return a non-nullable `TodayPlanLaunch` with
`accepted(req)` / `rejected` members and let `null` mean only "no link", which
deletes the bool and makes omission impossible; or
(b) a sealed `TodayLaunchContext` (`inApp | deepLink(req) | rejectedDeepLink`)
as originally suggested;
and in either case ship an acceptance cell that drives the **real router call
path** with a rejected payload plus an active plan and asserts
`today-plan-scheduled` is absent — a test on the screen's parameters alone
cannot detect the omission, because P3 and P7 are indistinguishable to it.

---

## Fresh look at the fix diff itself — nothing new filed

| Checked | Evidence |
|---|---|
| New sinks / logging / network / storage | `git diff c2785002~1 c2785002 -- lib/` adds no import and no call to `print`/`debugPrint`/`Logger`/`dart:io`/`dio`/`File`/`jsonEncode`/`SharedPreferences`/`SecureStorage`. The two production files' import lists are byte-identical to `cbee3d1c`. |
| New dependency / asset / permission | `pubspec.yaml`, `pubspec.lock`, `assets/`, platform manifests: not in the fix diff. |
| Secrets | Fix diff adds no literal beyond `'destination'`, `1`, `'utm_source'`, `'push'`, `'day.19'` and Hungarian prose. |
| Scope creep | 5 files, all inside the round's `allowed_paths`; `lib/app/routing/**` and `lib/core/notifications/**` still untouched. |
| `on TypeError` breadth (could the new catch swallow something real?) | Scoped to the entry loop, whose body performs only `is` tests and `!=` comparisons. The only extra thing it can absorb is a `TypeError` thrown from a hostile `operator ==` — which fails **closed** (`return null`). It cannot mask a failure in `permits()`, in rendering, or in the domain layer. |
| Widened accepted-input set | Measured above: only well-formed `{'destination':'today'}` payloads that were previously rejected for their *static* map type now parse. Verified no other shape flipped from `null` to `REQUEST` across the 32-shape matrix. |
| §10/§11 doc claims | Verified, and honest: the "7/7" and "5/5" counts reproduce (12 tests green); the F2 RED note truthfully says the new cell previously *did not compile* rather than overclaiming a behavioural red — and I separately proved a behavioural red exists (mutation test above). No claim in the fix diff's prose was found to be false. |
| False-confidence surface (§5.5) | The fix adds no user-visible copy; NOTE-4 wording is unchanged. |

**Reproduction / cleanliness:** two temporary pure-Dart probes at the clone root
and one temporary widget test under
`test/features/practice_generator/presentation/` were run and then deleted, and
the one mutated production line was restored via `git checkout --`;
`git status --porcelain` in the clone is clean apart from this report. Nothing
in `/home/ubuntu/music-theory` was touched, and no git remote operation was run.

## Updated merge recommendation

**Merge permitted.** CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 (2 closed) ·
**MINOR: 1 (new, carry-forward)** · NOTE: 4 (unchanged, not re-reviewed).
MINOR-1 must be listed as an explicit input to the routing/notification wiring
round's brief, with the acceptance cell named above; it must not be inherited
silently, because its failure mode is a verbatim recurrence of MAJOR-2.
