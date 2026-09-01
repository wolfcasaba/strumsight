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

## `corrupted_storage.json` — pairs with an injected storage-write fault

This file's own bytes are **not** malformed — every value round-trips
through `jsonDecode` cleanly, in the same `fromVersion = 0` shape as
`legacy_v1_storage.json` (smaller record counts, distinct ids). That is
deliberate, and measured, not an oversight:

`RenameKeyMigration.apply` and `WrapJsonDocumentMigration.apply`
(`lib/core/storage/storage_migrator.dart`) never throw on bad *data* — an
unreadable type, unparsable JSON, or a shape mismatch is logged and the
value is left untouched or quarantined (see their doc comments: "never
destroy an unreadable value"). Given `appStorageMigrations` is built
entirely from these two migration kinds, **no legacy JSON content, however
malformed, can make `StorageMigrator.migrate()` return a non-null
`failure`** on the current tree. The only thing that can is the
`KeyValueStore` itself refusing a write (`StorageException`) — the real-world
analogue is a full disk or a filesystem gone read-only mid-write.

The A3 cell in `upgrade_migration_test.dart` therefore loads this fixture
into an `InMemoryKeyValueStore` and additionally marks one specific write
target as failing via the store's own `failingKeys` (a pre-existing test
double, `test/core/storage/in_memory_key_value_store.dart` — not a new
fake). That is what produces `StorageMigrationReport(failure: ...)`,
`toVersion == fromVersion`, and the untouched-raw-data assertion; the
fixture supplies the realistic pre-fault legacy state the failed upgrade
must not have damaged.

## Provenance

Project-authored synthetic fixtures written for E12-R23. Song/chord/lesson
names are common public-domain-adjacent references (song titles only, no
lyrics or audio) used purely as plausible sample strings — no shipped song
content, no third-party data file, and no capture of an actual device.
