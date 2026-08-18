# E07-R22 — Security / Privacy Review (dedicated, mandatory — brief `risk = "high"`)

Brief: `docs/rounds/e07-r22-weekly-and-today-screen.md` (incl. §0.0 pre-flight revision)
Diff reviewed: `git diff 4c0b6b82..cbee3d1c` (10 files, +1061/−2) in the isolated clone `/tmp/review-e07-r22`, branch `terra/e07-r22-weekly-and-today-screen`, HEAD `cbee3d1c` (verified with `git rev-parse HEAD`)
Reviewer: Claude (security-reviewer subagent) · Date: 2026-08-18 · Scope: READ-ONLY, no production edits (AGENTS.md §15.1)

## Verdict: **CHANGES REQUIRED**

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
