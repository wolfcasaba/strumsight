# Client storage migration — what upgrades, what doesn't, and its limits

**Kör:** `E12-R23` (Legacy user migration release candidate).
**Normatív forrás:** [ADR 0487](../adr/0487-legacy-upgrade-migration-evidence-contract.md).
**Mérce:** `test/e2e/upgrade_migration_test.dart` (A1–A5, A3b), `test/fixtures/migrations/`.

This is the release-candidate evidence for a user upgrading from an older
StrumSight build: what the boot-time migrator moves, what it deliberately
does not touch, and the hard limit on "rollback" — there is none, by design.

## 1. What runs, and when

Every app start runs `StorageMigrator.migrate()`
(`lib/core/storage/storage_migrator.dart`) against the fixed
`appStorageMigrations` list — **22 steps**, each a 1-based `version` and a
stable `id`, applied in order starting one past the store's persisted
`ss.storage.schema_version` (absent means `0`):

| Versions | What moves | Shipped in |
|---|---|---|
| 1–16 | Sixteen simple preference keys (theme, locale, tuner, capo, latency calibration, onboarding-seen, favorite chords, metronome mute, practice speed, daily goal) from their pre-namespace name to their `ss.*` name. | E01-R06 |
| 17–22 | Six user-content documents (library sessions, songs, setlists, practice log, lesson progress, streak) — renamed onto `ss.*` **and** wrapped in the versioned `{"schemaVersion":1,"items"/"data":...}` envelope (`documentSchemaVersion`, `lib/core/storage/json_document_store.dart`). | E01-R07 |

The exact key pairs are `LegacyStorageKeys` → `StorageKeys`
(`lib/core/storage/storage_keys.dart`). A user who updated straight from a
pre-R06 build starts at version 0 and runs all 22 steps; a user who already
had an R06-or-later build (but pre-R07) starts at version 16 and runs only
the six content steps — both paths are exercised by this round's fixtures
(`legacy_v1_storage.json`, `legacy_v2_storage.json`).

**Scope limit (§0.0/R6):** this is the *only* migration chain that runs at
boot. 12+ other migrators/adapters exist on the tree (gamification, song
storage, library, practice-plan) but start from their own provider/use-case
call site, not from `AppBootstrap`. This document and its evidence make no
claim about those — they are measured by their own tests.

## 2. The no-loss guarantee, and how it's measured

Per key, migration **moves** a value — it never transforms its content and
never merges records. The evidence (`test/e2e/upgrade_migration_test.dart`
A1) compares, before vs. after migration, for every one of the six content
documents:

- **record count** (list length, or map-key count for lesson progress);
- **id-set** (the natural identifier per document: `id` for library
  sessions/songs/setlists, `day` for practice-log entries, the lesson id
  itself for lesson progress);
- for the streak document specifically, the **balance fields**
  (`current`/`longest`/`last`/`freezes`/`total`, `StreakData.toJson`) —
  the only gamification-adjacent numeric state this migration chain
  touches. A general XP ledger, if one exists, lives outside
  `appStorageMigrations` and is out of this document's scope.

"The app starts" is explicitly **not** evidence of any of this — a
migration that silently dropped a record would still let the app start.

## 3. Interruption: resume, never restart

`schemaVersion` is written **after each** successful step (not once at the
end), so a process death mid-migration leaves the store at the last
completed version. The next boot's `migrate()` call resumes there — already
-migrated keys are not touched again, and the resulting id-sets/record
counts are identical to an uninterrupted run of the same input
(`upgrade_migration_test.dart` A2, and the pre-existing ADR 0117/0239/0350
checkpoint pattern this round measures again at the boot-migration layer).

## 4. A failed step: fail-safe, not fail-closed, and never a reset

If a step's *write* fails (the only way any current `StorageMigration`
implementation can throw — see §5), `StorageMigrator.migrate()` returns a
report with `failure != null` and `toVersion == fromVersion`; the step is
retried on the next boot. Critically:

- the **raw legacy data is untouched** — write-then-remove ordering means a
  failed write never reaches the `remove` step;
- `AppBootstrap.run` **discards** the migration report
  (`lib/app/bootstrap/app_bootstrap.dart:84`), so a failed migration still
  produces `BootstrapSuccess` — the app starts on its pre-migration values,
  not on a blank slate (`upgrade_migration_test.dart` A3);
- there is **no user-facing signal** for this today. The `RecoveryScreen`
  exists (`lib/app/bootstrap/recovery_screen.dart`) but nothing on the
  `lib/` tree navigates to it, and `BootstrapFailure` (a *different*, rarer
  condition — see §5) runs `BootstrapFailureApp`, not `RecoveryScreen`. This
  is a known, measured gap (ADR 0487 D4) — wiring a safe-mode entry point
  for a failed-but-swallowed migration is explicitly out of this round's
  scope and would be its own `lib/**`-touching, reviewed round.

## 5. `BootstrapFailure`: the fail-closed path

Only three inputs currently produce `BootstrapFailure` (measured, not
inferred from the layer diagram): an unparsable `STRUMSIGHT_ENV` define, an
`openStore` that returns `Failure` (e.g. the platform preference store
cannot be opened — full disk, permission denial), and an unexpected
exception inside `AppBootstrap.run`'s try block. In the `openStore` case
specifically (`upgrade_migration_test.dart` A4), **no store is opened at
all** — no read, no write, nothing to lose. This is the deliberate
fail-closed counterpart to §4's fail-safe path: a corrupt-but-openable store
keeps the user's data and boots; a store that cannot be opened at all
refuses to start rather than guess.

## 6. Why no step currently reports data-shape corruption as a failure — and the empty-document limit that follows from it

Both migration kinds on the tree — `RenameKeyMigration` and
`WrapJsonDocumentMigration` — are written to **never throw on bad data**: an
unreadable type, unparsable JSON, or an unexpected shape is logged and the
value is left on its legacy key (or quarantined) rather than raising. The
`corrupted_storage.json` fixture carries one field, `user_setlists_v1`, that
is genuinely malformed (truncated JSON) for exactly this reason — the A3
cell pairs the *same* fixture with a test-only injected `KeyValueStore`
write fault (see `test/fixtures/migrations/README.md`) to exercise the one
path that *does* produce `report.failure != null` on the current tree; that
write-fault path is unaffected by the malformed field because it fires on
the very first pending step.

**The genuinely-malformed-content path is measured separately (A3b, fix
round, docs/reviews/e12-r23-review.md MAJOR-1), and its outcome is a real,
accepted limit of this release candidate:**

- `WrapJsonDocumentMigration.apply` catches the parse failure, logs it, and
  returns — `StorageMigrator.migrate()` sees no exception, so the run
  reports **`failure: null`** and reaches the last schema version, exactly
  as if nothing had gone wrong.
- The raw malformed bytes are **not lost** — they stay on the legacy key
  untouched (the migration never writes the new key nor removes the old one
  for a document it could not parse), and the very next successful `write()`
  through `JsonDocumentStore` quarantines them (`storage.document.quarantined`,
  `lib/core/storage/json_document_store.dart`) rather than discarding them.
- **But the user sees an empty document immediately after the update.**
  `JsonDocumentStore.readBody()` — the same production read path
  `AppBootstrap` and every repository use — has no new-key value to read
  (the migration never wrote one), falls back to the legacy key, and tries
  to decode the *same* malformed bytes; that decode fails the same way and
  `readBody()` returns `null`. For a list document (library sessions, songs,
  setlists, practice log) this reads as an empty list; for an object
  document (lesson progress, streak) it reads as "no saved state" and the
  feature falls back to its default. The document is not deleted and is not
  silently discarded — it is quarantined on the next write — but between the
  update and that next write, the screen the user sees is empty.
- This is a **known limitation of the current tree**, not a regression this
  round introduces or a gap this round closes: fixing it (e.g. having the
  migrator surface a per-document failure the app can act on, or having
  `JsonDocumentStore` distinguish "nothing here" from "something here I
  could not read") is a `lib/**`-touching change and is explicitly out of
  this round's scope (§0.0/R3, ADR 0487 D3/D4).

## 7. Rollback: there is none, by design — the limit

There is no downgrade path. Once a document is written in the versioned
envelope, an OLDER build that has never seen `documentSchemaVersion` reads
the raw legacy key (now removed) and sees nothing for that document —
`JsonDocumentStore.readBody` only reads the envelope shape *forward*: a
`schemaVersion` **greater** than the running build's `documentSchemaVersion`
is explicitly quarantined as `future_version`
(`lib/core/storage/json_document_store.dart`), never decoded. Migrating
forward is safe and resumable; going back to an older build after migrating
is not supported and is expected to look like data loss to that older
build. This is the release-candidate's explicit, accepted limit — not a
gap this round closes.
