# Legacy upgrade-migration fixtures (E12-R23, ADR 0487)

Three synthetic, project-authored `KeyValueStore` snapshots for
`test/e2e/upgrade_migration_test.dart`. None of these files contains real
user data (`containsUserData: false` in `test/fixtures/manifest.json` for
each) — every id, chord, song title and timestamp below was invented for
this round.

Each file is a flat JSON object: `key -> value`, loaded verbatim into an
`InMemoryKeyValueStore` (`test/core/storage/in_memory_key_value_store.dart`).
A key whose value is itself a JSON-encoded **string** (`library_sessions`,
`user_songs_v1`, `user_setlists_v1`, `practice_log_v1`, `lesson_progress_v1`,
`practice_streak_v1`) reproduces exactly how a pre-envelope build stored it —
one `SharedPreferences` string holding a raw JSON blob — matching what
`WrapJsonDocumentMigration.apply` (`lib/core/storage/storage_migrator.dart`)
reads via `store.readString(from)`.

Key names come from `LegacyStorageKeys` / `StorageKeys`
(`lib/core/storage/storage_keys.dart`) — none were guessed.

## `legacy_v1_storage.json` — pre-`E01-R06` install

No `ss.storage.schema_version` key at all, so `StorageMigrator.migrate()`
reads `fromVersion = 0` and every one of the 22 `appStorageMigrations` steps
is pending. Every legacy key the migrator's version list touches
(`storage_migrator.dart` versions 1–22) is populated in its original,
pre-namespace shape: plain settings values plus six pre-envelope JSON blobs
(library sessions, songs, setlists, practice log, lesson progress, streak).

## `legacy_v2_storage.json` — mid-upgrade, between `E01-R06` and `E01-R07`

`storage_migrator.dart`'s own doc-comment on `appStorageMigrations` records
that schema **1–16** (E01-R06) moved the simple preference keys onto their
`ss.*` names, and **17–22** (E01-R07) moved the six user-content documents —
two separate shipped rounds. This fixture models a real device that updated
through the first round but not (yet) the second: `ss.storage.schema_version`
is `16`, all sixteen settings keys already sit at their `ss.*` names, and the
six content keys are still on their legacy names in pre-envelope shape.
`migrate()` therefore has only the six `E01-R07` steps (`r07.*`, versions
17–22) pending — the A1 cell proves the resume-from-checkpoint math (ADR
0117/0239/0350) on a real historical seam, not an invented one.

## `corrupted_storage.json` — one genuinely malformed field, shared by two cells

Almost every value in this file round-trips through `jsonDecode` cleanly, in
the same `fromVersion = 0` shape as `legacy_v1_storage.json` (smaller record
counts, distinct ids) — **except `user_setlists_v1`**, which is deliberately
truncated mid-object (`[{"id":"setlist-corrupt-solo","name":"Solo
practice",`) and does **not** parse as JSON. This is the fix-round resolution
of `docs/reviews/e12-r23-review.md` MINOR-1: the filename must mean what it
says, so the file now carries one field that is actually corrupted, and every
other field stays well-formed so the write-fault cell below is unaffected.

Two cells in `upgrade_migration_test.dart` load this same fixture, each
exercising a DIFFERENT failure source:

* **A3** additionally marks `themeMode` (version 1, the first pending
  migration) as a failing write via the store's own `failingKeys` (a
  pre-existing test double, `test/core/storage/in_memory_key_value_store.dart`
  — not a new fake). That is what produces `StorageMigrationReport(failure:
  ...)`, `toVersion == fromVersion == 0`, and `applied` empty — the
  **storage-refuses-the-write** path (the real-world analogue is a full disk
  or a filesystem gone read-only mid-write). Because the fault fires on the
  very first step, none of the later `WrapJsonDocumentMigration` steps ever
  run, so the malformed `user_setlists_v1` field is irrelevant to this cell —
  it asserts on the `songs` document instead, which stays well-formed.
* **A3b** (added in the fix round, MAJOR-1) runs with **no** injected write
  fault. `RenameKeyMigration.apply` and `WrapJsonDocumentMigration.apply`
  (`lib/core/storage/storage_migrator.dart`) never throw on bad *data* — an
  unreadable type, unparsable JSON, or a shape mismatch is logged and the
  value is left untouched (see their doc comments: "never destroy an
  unreadable value"). So the truncated `user_setlists_v1` blob makes
  `WrapJsonDocumentMigration.apply` log a warning and return, `migrate()`
  sees no exception, and the report comes back `failure: null`,
  `toVersion == 22`, `applied` with all 22 ids — a **silently "successful"**
  run. The raw malformed bytes stay on the legacy key untouched (measured:
  `legacyKeyPreserved=true`, `newKeyWritten=false`), but
  `JsonDocumentStore.readBody()` — the same path `AppBootstrap` and every
  repository read through — decodes the same malformed legacy fallback and
  also fails, returning `null`. This is the **known limitation** the cell
  pins: a genuinely corrupted document surfaces as an empty document after
  the update, not as a controlled `report.failure`. See
  `docs/release/client-migration.md` for the user-facing description of this
  limit.

Given `appStorageMigrations` is built entirely from `RenameKeyMigration` and
`WrapJsonDocumentMigration`, the **only** thing that can make
`StorageMigrator.migrate()` return a non-null `failure` on the current tree
is the `KeyValueStore` itself refusing a write — never the *content* of a
legacy document, however malformed. A3 measures that write-refusal path; A3b
measures what genuinely malformed content does instead (nothing throws, but
the read path comes back empty).

## Provenance

Project-authored synthetic fixtures written for E12-R23. Song/chord/lesson
names are common public-domain-adjacent references (song titles only, no
lyrics or audio) used purely as plausible sample strings — no shipped song
content, no third-party data file, and no capture of an actual device.
