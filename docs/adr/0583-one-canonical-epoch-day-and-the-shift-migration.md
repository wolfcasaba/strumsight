# ADR 0583 — One canonical epoch day (UTC-anchored), and the best-effort migration that repairs the days already stored

- Status: accepted (2026-09-18, round C1-epoch-day)
- Numbering: continues 0582; 0550–0580 stay reserved for the unmerged `claude/e18-r06-verify-followup` branch.
- Related: ADR 0068 §4 (the practice aggregator takes no cross-feature dependency), ADR 0084/0085 (Practice History V2 and the V1∪V2 rollup), ADR 0387 (daily challenge instance + ledger dedup), ADR 0496 §1 (gamification composition layer), ADR 0500 §5.1 (Progress V2 composition layer), SDD Ch2 Kör 5 §5.3 / Kör 7 §7.3 (the storage migrator and the document envelope).

## Context

An **epoch day** is how this app does calendar maths: the streak, the weekly bar
chart, the daily goal ring, the daily challenge seed and the gamification
streak state all reduce a moment to one integer and then use plain integer
arithmetic, so consecutive days are exactly 1 apart and no DST or timezone rule
can leak into the logic. That is a good decision. The conversion behind it was
wrong, and wrong in four separate copies:

```dart
DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay
```

`DateTime(y, m, d)` is **local** midnight. Its epoch milliseconds are the true
day's minus the device's UTC offset, and `~/` truncates. So the expression
answered `trueDay - 1` **at the offset the device had at the moment of the
call**, whenever that offset was east of UTC, and `trueDay` at or west of it.

That distinction matters for everything below: the expression is a statement
about **the device at write time**, not about the store. The same store can hold
both kinds of day — a user who travels, or simply a user in Europe/London whose
zone is UTC+0 in winter and UTC+1 in summer.

MEASURED (scratchpad Dart, the same instant evaluated at explicit offsets, so
the numbers do not depend on the box):

| Offset | `2026-09-18T12:00Z` old → new | `2024-01-01T12:00Z` old → new |
|---|---|---|
| `+00:00` | 20714 → 20714 | 19723 → 19723 |
| `+01:00` | 20713 → 20714 | 19722 → 19723 |
| `+02:00` | 20713 → 20714 | 19722 → 19723 |
| `+05:30` | 20713 → 20714 | 19722 → 19723 |
| `+09:00` | 20713 → 20714 | 19722 → 19723 |
| `−05:00` | 20714 → 20714 | 19723 → 19723 |

The `+00:00` and `−05:00` rows are why this survived: the defect is **invisible
at UTC and in the Americas**, and a CI runner with no `TZ` set is UTC
(`grep -rn "runs-on\|TZ" .github/workflows/*.yml` → `ubuntu-latest`, no `TZ`).
Any regression test that lets the ambient zone decide is therefore vacuous in
CI, which is why every test in this round passes the offset explicitly (D6).

The four copies:

| Copy | File |
|---|---|
| `StreakLogic.epochDayOf` | `lib/features/streak/streak_logic.dart` |
| `DefaultStreakPolicy._epochDayFor` | `lib/features/gamification/infrastructure/default_streak_policy.dart` |
| `todayEpochDayProvider` | `lib/features/gamification/providers/gamification_providers.dart` |
| `PracticeProgressAggregator._epochDayOf` | `lib/features/practice/domain/service/practice_progress_aggregator.dart` |

…plus a fifth copy in `test/features/gamification/application/streak_service_test.dart`,
which is the clearest evidence that copying was the root cause: the test
mirrored the shipping expression instead of measuring it, so the two drifted
together and the suite stayed green over the defect.

What the off-by-one actually cost:

1. **`lastPracticeDay` is persisted as an absolute integer.** A device east of
   UTC stored `trueDay - 1`; the moment the conversion is fixed, the producer
   writes `trueDay` and the gap arithmetic in `streak_logic.dart` sees a jump.
   The same integer also moves by one when a device changes zone across UTC, so
   the streak silently skips (or repeats) a day.
2. **`WeeklyBars`** reads the weekday off the integer, which assumed a TRUE
   epoch day. East of UTC the producer fed it a day that was one short, so the
   whole chart was labelled one day behind. (The widget itself is correct and is
   **not** changed here — see D2.)
3. **`LegacyPracticeAdapter`** converted back with `day * msPerDay` read as UTC
   midnight, which does not round-trip: `EpochDay.of(utcMidnight(d)) == d - 1`
   west of UTC.
4. **`test/core/store_race_sweep_test.dart` → "a cold-start practice EXTENDS the
   stored streak" was RED on this box** (`advanced` was `false`): the recorded
   moment converted back to the *stored* day, so a 7-day streak refused to
   become 8.

Separately, and with the same symptom class: `todayEpochDayProvider` and
`progressNowProvider` are plain cached `Provider`s. Their value is computed once
and kept for the container's lifetime, so an app left in the background across
midnight keeps evaluating the streak against **yesterday** until a cold
restart.

## Decision

### D1 — One function, in `core`, and every copy routed through it

`lib/core/foundation/epoch_day.dart` defines `EpochDay`:

| Member | Meaning |
|---|---|
| `ofCalendarDate(y, m, d)` | the primitive: a bare calendar date has no time and no zone, so it is anchored at **UTC** midnight |
| `of(DateTime)` | the calendar date the instant falls on in **local** time, then `ofCalendarDate` |
| `ofInstant(DateTime, Duration utcOffset)` | the same, at an **explicit** device offset |
| `utcMidnightOf(int)` | the inverse: the UTC-midnight instant the integer names |
| `localStartOf(int)` | the inverse that round-trips through `of` in every zone |

`core/foundation` is the home because the callers span four features and one of
them (`PracticeProgressAggregator`) is forbidden a cross-feature dependency
(ADR 0068 §4). The file imports nothing — no Flutter, no Riverpod — so
`lib/features/practice/domain/` keeps its framework-independence guarantee
(`tool/check_architecture.dart`).

`StreakLogic.epochDayOf` survives as the name its eleven call sites already use
and delegates to `EpochDay`. It gains **one optional parameter**,
`utcOffset`, and nothing else: left out (every shipping call site) the device's
own offset decides; passed, the answer is the day a device at *that* offset
would record. See D6 — without that seam the round's regression tests cannot
fail on the old code in CI.

### D2 — `WeeklyBars` is deliberately NOT changed

The first draft of this round rewrote `_Bar._weekdayRef` to use
`EpochDay.utcMidnightOf`. That is reverted. MEASURED: over every integer in
−5000…40000 the old body (`DateTime(2024, 1, 1).add(((epochDay % 7) + 3) % 7
days)`) and `EpochDay.utcMidnightOf(epochDay).weekday` give the same weekday —
**zero** disagreements. Dart's `%` is non-negative, so negative days agree too,
and the addition never exceeds six days from 1 January, so it cannot reach a DST
transition either.

So the widget was never the defect, and changing it is a refactor this round did
not need (AGENTS.md §4, §10). What was wrong is the chart **end to end**,
because it is a two-sided contract: the **producer**
(`StreakLogic.epochDayOf`, which every recording path stores through) and the
**consumer** (this label) have to read one integer the same way. Before D1 they
did not — east of UTC the producer answered `trueDay - 1` while the label was
read off the true day — so a session played on a Friday was announced as
Thursday. The regression test is written to match: it feeds the **producer** at
an explicit `+02:00` for a known Friday and asserts the Friday label
(`weekly_bars_a11y_test.dart`).

### D3 — `LegacyPracticeAdapter.occurredAt` uses the local start of the day

`PracticeEntry.day` is a *local calendar day*, so the instant that represents it
must be the one whose local calendar date is that day — `EpochDay.localStartOf`,
not UTC midnight. This makes `EpochDay.of(event.occurredAt) == entry.day`
hold in every zone. The event id is unaffected (the fingerprint is
`day/source/seconds/strokes/chords/direction`), so replayed migrations stay
deterministic and the ledger's dedup is untouched.

### D4 — Schema 23: one step, both documents, best effort, per record

`EpochDayShiftMigration` (`lib/core/storage/storage_migrator.dart`) repairs the
days the old conversion wrote. Two rules, in this order:

1. **The device's current UTC offset is the shift**: `+1` east of UTC, nothing
   at or west of it. This is a **guess about the past** — the offset now is not
   necessarily the offset at write time — and the "Known limitation" section
   below states exactly who the guess is wrong for and what it costs them.

2. **Never onto today, and never past it.** A `+1` that would put a stored day
   on or after today is refused **for that record** and logged
   (`storage.migration.epoch_day_not_in_the_past`). The bound is per record, not
   per document, and "today" comes from the injected clock at the injected
   offset, so it is testable.

   The bound is `stored + 1 >= today`, not `> today`, and the equality half is
   the point: `StreakLogic.applyPractice` returns early while
   `today <= lastPracticeDay` (`streak_logic.dart`), so a day moved *onto* today
   costs the user exactly what a future day costs them — the UI shows a practice
   day they never had, and the practice they do on the upgrade day is silently
   not recorded. The reachable case is the traveller of "Known limitation" 1
   case 2: wrote west of UTC (the days are already right), practised
   **yesterday**, upgrades east of UTC. A `>` bound would move yesterday to
   today; the `>=` bound leaves it alone
   (`epoch_day_shift_migration_test.dart` → "the traveller who practised
   YESTERDAY west of UTC keeps yesterday").

   **The trade-off, stated.** The two cases are indistinguishable in the data —
   both present a stored `today - 1` — so refusing the equality shift also
   refuses a *legitimate* repair: the eastern user who practised **today** and
   then upgraded really did have `trueDay - 1` written for a day that is today,
   and that record keeps yesterday's value. (Every older eastern record is
   unaffected: for a last practice on `T < today` the bound is `T >= today`,
   which is false, so it is repaired.) What it costs that user: if they practise
   again on the upgrade day, nothing at all — `today > last`, gap 1, the streak
   extends and the day is corrected. If they do not, their next practice is a
   day later and `applyPractice` sees a gap of **2**, so a banked freeze is
   spent or the streak resets to 1 — the same "one missing streak day, once"
   ceiling as "Known limitation" 1 case 1.

   That is the deliberate choice: under-credit rather than fabricate. The
   equality shift would write a practice day the user never had **and** swallow
   the practice they do on the upgrade day; the strict bound at worst costs one
   already-banked streak day, and never claims something untrue about the user's
   history.

**Why there is no per-record evidence rule in the code.** The obvious way to
avoid the guess in rule 1 is to read the shift off a co-stored absolute
timestamp: recompute the calendar date that instant falls on *at its own
offset* and compare it with the day stored beside it. That is right even for a
device that has since changed zone, and it repairs a *mixed* document record by
record. The survey below asked that question of **every** persisted epoch-day
field, and the answer for both fields this step repairs is **none**: `StreakData`
persists `current`/`longest`/`last`/`freezes`/`total`, `PracticeEntry` persists
`day`/`src`/`sec`/`str`/`chd`/`dir`. An earlier draft of this round shipped the
rule anyway, with a `recordedAt` key that no shipping document set — ~60 lines
of migration logic reachable only from its own test. That is the speculative
generality AGENTS.md §4/§10 bars, so it is **removed**, and the rule is recorded
here instead, as the thing to implement on the day a repaired record carries a
timestamp:

- a bare local wall clock (`2026-09-18T07:30:00.000`) **is** the write-time
  local calendar date, and an offset-bearing instant (`…T05:30:00.000+02:00`)
  names it — both are usable evidence;
- a plain UTC instant (`…Z`) is **not**: the same instant is two different
  calendar dates either side of the date line;
- a difference other than 0 or +1 is not an off-by-one and must be left alone
  and logged, not "corrected".

**One step, both documents, one reading of the offset.** Schema 23 repairs the
streak state *and* the practice log. It is deliberately **not** split into two
versions: two steps evaluate `deviceUtcOffset()` twice, and if the second one's
write is refused the migrator stops at the first one's version and retries the
second on a later boot — possibly after the device has crossed UTC, leaving the
streak day shifted and the practice-log days not, i.e. the weekly chart and the
streak permanently one day apart. One step makes that impossible: a single
`deviceUtcOffset()` call decides both documents.

**Idempotence is still the migrator's own version gate, and nothing else.**
`StorageMigrator` writes the schema version after *each* completed step, so a
step that finished is never entered again. For that to remain the *whole* story
across two documents, the step has to be all-or-nothing: it repairs both
documents **in memory first**, then writes them, and if a write is refused it
puts the documents it already wrote back to their exact previous bytes before
the exception leaves `apply` (`storage.migration.epoch_day_rollback_failed` if
even the restore is refused). The retry on the next boot therefore starts from
an unshifted store and cannot shift a document twice. Measured in
`epoch_day_shift_migration_test.dart` → "a refused write on the second document
rolls the first one back, so the retry cannot shift it twice".

The step keeps **no marker of its own**. An earlier design wrote an
`epochDayBase: utc` breadcrumb into the document envelope; that does not work —
`JsonDocumentStore.write` re-encodes the envelope as exactly
`{"schemaVersion": …, <body>}`, so the breadcrumb is erased by the user's very
next save. The version gate, plus the all-or-nothing write above, removes
the need for one.

The other migrator contracts are kept:

- **non-destructive** — the single write per document replaces it with a value
  derived from its own bytes, and only when something actually changed; a
  document that cannot be parsed, or whose body has an unexpected shape, is
  logged (`storage.migration.unparsable`, `storage.migration.unexpected_shape`)
  and **left exactly as it is**, the same rule as `WrapJsonDocumentMigration`. A
  list record that is not an object is copied through untouched rather than
  dropped — its own decoder already skips it and keeps the rest of the history.
- **loud** — a store that refuses the write throws out of `apply`, the migrator
  stops, and the schema version does not advance, so the step runs again on the
  next boot.

Negative values are **not** shifted: `-1` is the "never practised" sentinel, not
a day.

### D5 — The cached "today" is invalidated on resume

`lib/app/day_rollover_guard.dart` adds `DayRolloverGuard` +
`dayRolloverGuardProvider`, watched for the app's lifetime by `StrumSightApp`
exactly as `audioLifecycleGuardProvider` already is. On
`AppLifecycleState.resumed` it invalidates `todayEpochDayProvider` and
`progressNowProvider`.

Resume is the hook because it is the first moment a stale answer can be *seen*;
recomputing while the app is not shown would burn work for nobody. Backgrounding
alone changes nothing. Riverpod only notifies on `!=`, so an in-day resume
recomputes two cheap values and wakes no listener.

### D6 — The tests drive the offset, never the runner's zone

A regression test for this defect is worthless if it is evaluated at UTC, where
old and new agree (see the Context table). Three seams make the round's tests
measure the defect on any machine:

- `EpochDay.ofInstant(instant, offset)` — the conversion at an explicit offset;
- `StreakLogic.epochDayOf(instant, utcOffset: …)` — the same seam on the
  **shipping** entry point every recording path calls, so a test can prove the
  producer, not just the primitive;
- `EpochDayShiftMigration(deviceUtcOffset: …, clock: …)` — the migration's
  offset and clock.

`test/features/streak/epoch_day_test.dart` additionally reproduces the pre-fix
expression as `oldEpochDayOf(instant, utcOffset)`. Every claim about "the old
code" in this ADR is therefore an assertion in the suite, evaluated at an
explicit offset, and the round's regression tests fail against the old body on a
UTC runner as well as on the UTC+2 dev box.

## The persisted epoch-day fields, their evidence, and what D4 does with each

Found with Serena (`search_for_pattern` over `lastPracticeDay|lastQualifiedDay|epochDay`
and over every `JsonDocumentStore` construction in `lib/`). "Evidence" is the
co-stored absolute timestamp a per-record repair would need (D4, "Why there is
no per-record evidence rule in the code"). **Every row's evidence column is
`none` or "not repaired", which is why the shipped step has only the two rules
D4 lists.**

| Key → field | Co-stored timestamp (evidence) | Decision |
|---|---|---|
| `ss.streak.state` → `data.last` | **none** — `StreakData` persists `current`/`longest`/`last`/`freezes`/`total` and no instant | **Repaired (schema 23), by the device-offset rule.** Also the source of gamification's `StreakState.lastQualifiedDay` (`LegacyStreakMigrator` reads this very document), so one repair serves both readers. |
| `ss.progress.practice_log` → `items[].day` | **none** — `PracticeEntry` persists `day`/`src`/`sec`/`str`/`chd`/`dir` | **Repaired (schema 23), by the device-offset rule.** This is what `PracticeStats.lastDays` rolls into the `DayTotal`s the weekly chart renders. |
| `ss.practice.history_v2` → `createdAt` | the record *is* an instant; no day is stored | **Nothing to repair.** The day is derived at read time by `PracticeProgressAggregator`, which D1 already fixed. |
| `ss.gamification.reward_ledger` → entries | `createdAt`; **no epoch-day field at all** (`RewardLedgerEntry` = `ledgerId`/`sourceEventId`/`createdAt`/`schemaVersion`/`policyVersion`/`baseXp`/`bonusXp`/`totalXp`/`reasonCodes`) | **Nothing to repair** — see below. |
| `ss.gamification.daily_challenge_v1` → `epochDay` | `generatedAt`, written as `.toUtc().toIso8601String()` → a bare `Z` instant, which would not count as evidence | **Not repaired** — identity-bearing; see below. |
| `ss.gamification.activity_outbox` → `…event.epochDay` | `occurredAt`, a local wall clock — genuine evidence, the only field in this table that has any | **Not repaired**: a queue of undelivered events keyed by a deterministic event id, and MEASURED unwritten by any shipping path (`grep -rn "ActivityEventIngestor(" lib` → only the declaration). |
| Legacy pre-namespace keys (`practice_streak_v1`, `practice_log_v1`) | — | Migrations 20 and 22 move these to the namespaced keys **before** 23 runs, so by then there is nothing there. The one case they survive is a blob those migrations could not parse and deliberately left behind — which 23 also leaves behind, by the same rule. |
| Secure store | — | Not covered by the preference migrator at all (`StorageKeys.secureAuthToken`); holds no epoch day. |

### What the +1 costs the daily challenge (measured)

`DailyChallengeService.ensureInstanceFor` keeps a stored instance only while
`stored.epochDay == epochDay` (`daily_challenge_service.dart:420`). After D1
`todayEpochDayProvider` answers the *true* day — one more than the day an
instance was stored under east of UTC — so on the first launch after the update
today's challenge would be **re-rolled and any progress inside it lost**. Once,
for one day, per device.

Shifting the stored `epochDay` does not avoid that and makes it worse:
`DailyChallengeInstance.instanceId` is
`daily-challenge:<type>:<catalogVersion>:<epochDay>` and is used as the reward
ledger's `sourceEventId` (ADR 0387 Decision 2), so moving the day mints a *new*
id and a challenge the user already completed could be credited a second time.
The day also seeds the challenge content.

MEASURED, and the reason this is not a shipping-user cost in this build:
`grep -rn "DailyChallengeService(" lib` returns only the constructor
declaration, and `questBoardProvider` (`gamification_providers.dart:229`) is a
constant with `dailyChallenge: null`. **No shipping path constructs the service,
so no build writes `ss.gamification.daily_challenge_v1`.** The re-roll above is
what would happen the day it is wired, on a store written by an earlier wired
build; whoever wires it owes that check.

### What the +1 costs the reward ledger (measured)

Less than the previous draft of this ADR claimed, and the claim it made ("the
stored days are only ever compared with each other, so a uniform offset is
self-consistent") was never established. The accurate statement:

- `RewardLedgerEntry` stores **no epoch day** (grep: `epochDay` does not appear
  in `reward_ledger_entry.dart`). There is nothing in the ledger for D4 to move.
- The daily-XP-cap grouping lives in `RewardPolicyHistory.epochDay`, which is
  *not* persisted: it is built per request by an injected `historyBuilder`.
  MEASURED: `grep -rn "historyBuilder:" lib` → **no matches**; every
  `Gamification*Adapter` is constructed only from tests. So today no shipping
  path computes an `earnedTodayXp` bucket at all.
- If the builder is wired later against an existing ledger, it will group by
  `createdAt`, an absolute instant, which D1/D4 do not touch. The one real
  exposure is a builder that groups by a *stored* day; there is none, and this
  ADR is the record that there must not be one without a migration.

`LocalRewardLedgerRepository` *is* wired
(`gamification_providers.dart:45`), but read-only, for the inbox join.

### The one coupling D4 creates: legacy event ids

`LegacyPracticeAdapter._fingerprint` hashes `entry.day` together with the
source, seconds, strokes, chords and direction accuracy, and that digest becomes
the event id `legacy-practice/v1/<sha256>/<ordinal>`. Schema 23 shifts
`items[].day` in `ss.progress.practice_log`, so **every legacy event id moves
with it**, exactly once, at the migration.

Today it is inert, and measurably so: `GamificationMigrator` is not wired into
`lib/` at all — it is constructed only by `test/features/gamification/data/…` —
and its resume checkpoint is an **index** into the entry list, not an event id.
No build has ever written a legacy-practice event id to the ledger, so there is
nothing a changed id can fail to match.

It stops being inert the moment the migrator is wired up. Whoever does that owes
one check first: that no shipped build both ran the migrator **and** then ran
schema 23. If one did, the ledger holds pre-shift ids, the replay presents
post-shift ids, the dedup misses, and the XP is credited twice. The cheap guard
is to compare the persisted `ss.storage.schema_version` against 23 next to the
migrator's checkpoint: a checkpoint written before 23 ran means the ids it would
generate now are not the ids it generated then, and the run must be treated as
complete rather than resumable.

## Known limitation (accepted, not fixed here)

### 1. The device-offset rule is a guess about the past, and for some users it is wrong

Neither field D4 repairs carries a timestamp, so for both of them the shift is
decided by the offset the device happens to have *at upgrade time*, not the one
it had at write time. That is correct for the overwhelming majority — a device
that has not changed hemisphere-of-UTC between writing and upgrading — and wrong
in two reachable cases. Stated plainly, with the user-visible consequence:

1. **Wrote east of UTC, upgrades at or west of it** (a Budapest user who updates
   while travelling in New York). The offset is negative, so nothing is
   repaired, the schema version advances to 23, and **the repair never runs
   again**. From then on the producer writes the true day while the store still
   holds `trueDay - 1`, so the next practice sees a gap of 2: the user spends a
   banked streak freeze, or the streak resets to 1. **One missing streak day,
   once.**
2. **Wrote at or west of UTC, upgrades east of it** (a New York user who updates
   in Tokyo; and the Europe/London, Europe/Dublin, Europe/Lisbon,
   Africa/Casablanca band, whose store is *internally mixed* because it is
   UTC+0 in winter and UTC+1 in summer — MEASURED above: at `+01:00` the old
   conversion gave 19722 where the true day is 19723, at `+00:00` it gave
   19723). Days that were already correct are moved forward by one. **One extra
   streak day, once** — the streak looks one day longer than it was.

   Rule 2 ("never onto today, never past it") bounds the damage where it matters
   most: the most recent stored day is usually today's or yesterday's, and
   shifting *that* one is what would silently stop the streak recording. Older
   days in a mixed store are still over-shifted by one, and nothing in the data
   can distinguish them. The strict `>=` bound is what extends the protection to
   yesterday — see D4 for the equality case and for what the strictness costs
   the eastern user whose legitimate repair it refuses along with it.

Both are one day, once, on one device, and they cannot grow: after D1 every new
write is correct. The alternative — not repairing at all — leaves **every**
east-of-UTC streak permanently off by one, which is strictly worse and
unbounded in the number of users it affects.

The way out, if this ever needs to be exact, is the per-record evidence rule
written down in D4: a record that persists the instant it was written can be
repaired from its own history with no guess at all. Adding such a field to
`PracticeEntry` or `StreakData` does not help the days already stored, which is
why it is not done here — but it is what a future store of days should carry,
and D4 says what the repair must then do with it.

### 2. The all-or-nothing write is best effort, not a transaction

An earlier draft of this round split the repair into schema 23 (the streak) and
24 (the practice log). That gave each document its own version gate, but it also
gave each its own `deviceUtcOffset()` call: if 24's write was refused, the
migrator stopped at 23 and retried 24 on a later boot, possibly **after the
device had crossed UTC** — the streak repaired, the practice log not, the weekly
chart and the streak a day apart for good. D4 merges them into one step to
remove that combination entirely, and the previous edition of this limitation
with it.

What remains is one step writing two keys through a `KeyValueStore` that has no
transaction. The step writes them back-to-back and, if the second write is
refused, restores the first to its exact previous bytes so the retry starts
clean (D4, measured). The residue is the restore itself failing — the store
refusing both the second write *and* the compensating write of the first key. It
is logged loudly (`storage.migration.epoch_day_rollback_failed`) and the store
is then left with the streak day repaired and the schema version unchanged, so
the next boot re-enters the step and shifts that day a second time. Rule 2 caps
even that: the second `+1` is refused for any record within a day of today, and
for older records the error is one further day on an already best-effort repair.
A real transaction, or a persisted "repair in progress" marker, would close it;
both cost a new stored field for a one-shot repair, and the failure needs a
store that refuses two writes in a row, so it is accepted and written down
rather than fixed.

## Consequences

- `StreakLogic.epochDayOf` keeps its name and its positional signature: the
  eleven production call sites are unchanged. The new `utcOffset` is optional
  and used only by tests.
- `lib/features/progress/widgets/weekly_bars.dart` is **unchanged** (D2). The
  round's diff is the root-cause fix and nothing else.
- `lib/features/streak/model/streak_data.dart` and
  `lib/features/progress/model/practice_entry.dart` had doc comments saying the
  day was "local midnight". Those sentences are what the bug was copied out of
  four times; they now describe the UTC anchor and point here.
- `test/features/gamification/application/streak_service_test.dart` no longer
  carries its own copy of the conversion; it calls `EpochDay.ofCalendarDate`, so
  it now *measures* the policy instead of mirroring it.
- `test/core/storage/preference_migration_test.dart` asserted "one migration per
  migrated key". That invariant is retired here — 23 repairs values, not keys,
  and covers two keys in one step — and the test now names the value repair and
  the documents it covers explicitly. Its rename/wrap assertions pin the repair
  to a zero offset so they measure their own subject and not the box's
  timezone.
- `lib/app/strumsight_app.dart` gains one `ref.watch`.
- `test/core/store_race_sweep_test.dart` built its recording moment from a fixed
  **UTC** noon instant, which is only "the day after the stored day" for a
  device within ±12 h of UTC. It now builds it from
  `EpochDay.localStartOf(day) + 12 h`, so it measures the cold-start merge it
  was written for and not the box's timezone.
- **`test/features/gamification/presentation/gamification_hub_screen_test.dart`
  → group "A7 — progress_screen untouched" is REPLACED, not deleted.** It was a
  *scope* guard for the round that introduced the hub, asserting that
  `lib/features/progress/**` was absent from `git diff --name-only main...HEAD`.
  It measures the **committed branch diff**, not the working tree, so it stopped
  describing its own round the moment that round merged: `main...HEAD` has
  carried `lib/features/progress/screens/progress_screen.dart` from a later
  round ever since — it was already red for work it was never about, and nothing
  done to the hub could turn it green again. Switching it off for a green gate
  would break AGENTS.md §10, so A7 now asserts the thing the scope guard stood
  in for, on the working tree instead of on branch history: **no `.dart` file
  anywhere under `lib/features/gamification/presentation/`** — the directory is
  walked recursively, 18 files today — may mention `features/progress`, and the
  cell also asserts the walk found something, so it cannot pass vacuously. That
  is true today (MEASURED: `grep -rn "features/progress"
  lib/features/gamification/presentation/` → no hits), stays checkable in every
  future round, and fails for a NEW hub file that starts reaching into the
  progress feature — which a hand-written list of four paths could not.
- Two new `lib/` files, both on the round's owned-files list and both required
  by the design above: `lib/core/foundation/epoch_day.dart` and
  `lib/app/day_rollover_guard.dart`.
  `lib/features/progress_v2/application/progress_providers.dart` was owned and
  is deliberately left unmodified — its `progressNowProvider` is invalidated
  from the new guard instead.
- **`docs/release/client-migration.md` (added to the round's owned list by
  tech-lead ruling R1, because this round makes it factually false).** It said
  the chain is "22 steps" and that "migration **moves** a value — it never
  transforms its content". Both stop being true at schema 23. It now lists 23 in
  the version table, counts 23 steps, and states the exception explicitly, with
  the A1 cells that measure each half of it.
- **`test/e2e/upgrade_migration_test.dart` (added to the round's owned list by
  tech-lead ruling R1, because this round makes it red).** Its A1/A2 no-loss
  invariants assert that a migration run changes **no** stored value, and its A5
  cells pinned the end schema version as the literal `22`. Schema 23
  deliberately changes values and moves the last version to 23, so three of its
  cells were red on **any** runner and one was red only east of UTC. The repair
  keeps every invariant and removes the machine-dependence: the version literals
  become `appStorageMigrations.last.version` /
  `…where((m) => m.version > 16).length`, the A1/A2 cells run the shipped list
  with the repair pinned to a device **at UTC** (where it is a no-op by design,
  so those cells keep measuring the rename/wrap steps they were written for),
  and one new A1 cell runs the same fixture at an explicit **+02:00** and
  asserts the repair: every practice-log day and the streak's `last` move by
  exactly `+1`, the record count does not change, and the counters and the other
  five documents are bit-for-bit preserved. The A5 cells are the one place the
  shipped list still runs at the box's own offset — they assert the step *list*
  (ids, order, count), not any repaired value, so the offset cannot change what
  they measure.

## Measurement

Every "before" below was run, not reasoned about. Where a red is
zone-conditional it says so.

**Which cells pin an offset, and which run at the box's own.** Enumerated, not
asserted in general:

- *Pinned, because they assert a converted or repaired value.*
  `epoch_day_test.dart` (through `EpochDay.ofInstant` and
  `StreakLogic.epochDayOf(utcOffset: …)`); `weekly_bars_a11y_test.dart` (the
  producer at `+02:00`); **every** cell of
  `epoch_day_shift_migration_test.dart`, the three that run the shipped
  `appStorageMigrations` list included — those rebuild its repair at `+02:00`
  with the fixture clock, so none of them is vacuous at UTC;
  `preference_migration_test.dart`, whose rename/wrap cells pin the repair to
  `00:00` so they keep measuring their own subject; and the three **A1** cells of
  `upgrade_migration_test.dart` — two at `00:00` (where the repair is a no-op by
  design, so the bit-for-bit invariants still measure the rename/wrap steps) and
  one at an explicit `+02:00` that measures the repair itself.
- *No pin needed.* `store_race_sweep_test.dart` is zone-independent by
  construction (`EpochDay.localStartOf(day) + 12 h`), and
  `practice_progress_aggregator_test.dart`'s rollup case feeds a local wall
  clock to `EpochDay.ofCalendarDate`.
- *Run at the box's own offset and the real clock, deliberately.* The **A2**,
  **A3**, **A3b** and **A5** groups of `upgrade_migration_test.dart`. A2 compares
  an interrupted-then-resumed run against an uninterrupted one — both sides
  migrate at the same offset, so the equality holds whatever it is. A3 stops the
  run at the FIRST pending step, so the repair never runs there at all; A3b runs
  the whole chain but asserts only that a malformed legacy blob is left untouched
  and its namespaced key unwritten — neither key is one the repair reads. A5
  asserts the applied **id-list**, the end schema version and the per-key record
  counts — none of which the offset can change, because the repair rewrites
  values *inside* a document and adds, drops or merges nothing. Pinning these
  would add a seam without adding a measurement.

| Test | Before | After |
|---|---|---|
| `test/features/streak/epoch_day_test.dart` → "loses a day east of UTC and is right west of it" (new) | **RED** (no `EpochDay`) | green, and it is the file's own proof that the other cases are not vacuous at UTC |
| `test/features/streak/epoch_day_test.dart` → "the shipping entry point records the TRUE day east of UTC" / "practising on the next local calendar day extends the streak" | **RED on any runner** with the pre-fix `epochDayOf` body (20713 ≠ 20714; the streak stays at 7) | green |
| `test/features/progress/weekly_bars_a11y_test.dart` → "a bar names the weekday the session was actually recorded on" (new) | **RED on any runner** with the pre-fix body (the bar announced "Thursday" for a Friday session) | green |
| `test/features/progress/weekly_bars_a11y_test.dart` → the pre-existing a11y assertion | green (it pins the semantics node, not the calendar — the widget is unchanged) | green |
| `test/core/store_race_sweep_test.dart` — cold-start practice EXTENDS the stored streak | **RED** on this UTC+2 box (`advanced` was `false`); would have been green at or west of UTC | green, and now zone-independent by construction |
| `test/core/storage/epoch_day_shift_migration_test.dart` (new, 18 cells) | **RED** (no such migration) | green |
| …→ "a negative offset writes nothing — including for the traveller whose days DO need repairing" | — (new; pins the accepted cost of Known limitation 1) | green |
| `test/e2e/upgrade_migration_test.dart` → A1 "…on a device EAST of UTC…" (new) | **RED** without schema 23 (the days did not move) | green |
| `test/e2e/upgrade_migration_test.dart` → A1 ×2, A5 ×2 | **RED after round 1** (the hard-coded `22` / `6` no longer matched the list, and the A1 day-set moved east of UTC) | green, and the literals are now derived from `appStorageMigrations` |
| `epoch_day_shift_migration_test.dart` → "the traveller whose stored day is already today keeps it" | **RED** (the day was moved into the future) | green |
| `epoch_day_shift_migration_test.dart` → "the traveller who practised YESTERDAY west of UTC keeps yesterday" (new) | **RED, MEASURED** by putting the `> today` bound back and re-running the file: `+6 -1`, that cell only (20713 → 20714 == today, which `applyPractice` treats exactly like a future day) | green with the `>= today` bound (D4) |
| `epoch_day_shift_migration_test.dart` → "both documents of one step move together under a single offset reading" (new) | — (new; the shape it pins — two documents under ONE `deviceUtcOffset()` call — did not exist as two steps) | green |
| `epoch_day_shift_migration_test.dart` → "a refused write on the second document rolls the first one back" (new) | **RED, MEASURED** by deleting the `_rollBack` call and re-running the file: `+13 -1`, that cell only (the streak stayed shifted, so the retry would shift it twice) | green |
| `epoch_day_shift_migration_test.dart` → "the schema-version gate is the whole idempotence" | **RED** with the envelope breadcrumb (the save erased it and the day shifted twice) | green — and now run at an explicit `+02:00` with an asserted first-run shift, so it is no longer vacuous at UTC |
| `test/features/progress/day_rollover_guard_test.dart` (new, 3 cases) | **RED** (no such guard) | green |
| `weekly_bars` old `_weekdayRef` vs `EpochDay.utcMidnightOf` over −5000…40000 | — | **0 disagreements** — the basis for D2's revert |
