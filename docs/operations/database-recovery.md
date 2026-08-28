# Database recovery runbook — backup / restore (E12-R08, ADR 0449)

> **Audience:** whoever needs to back up or restore the StrumSight account
> database. Reference: [ADR 0449](../adr/0449-staging-readiness-traffic-gate-and-recovery.md)
> D4/D5, [ADR 0060](../adr/0060-alembic-schema-source-and-injected-engine-lifecycle.md)
> (Alembic is the only schema source — the restore path never uses
> `create_all` or hand-written DDL).

## 1. What the scripts do

- `backend/scripts/backup.py` connects to a database and writes a JSON dump:
  every row of every ORM table, the per-table row count, and the **applied
  migration head** (`MigrationContext.get_current_heads()`) at dump time.
- `backend/scripts/restore.py` reads that dump, rebuilds the target's schema
  with `alembic upgrade` to the revision recorded in the dump (never
  `create_all`), and reloads the rows.
- Both are proven end-to-end by
  `backend/tests/test_readiness_and_recovery.py::test_backup_then_restore_round_trip`
  (A3) and `::test_restore_refuses_to_overwrite_existing_data_without_double_confirmation`
  (A4), against local SQLite databases.

## 2. Backup

**The dump file contains PII and password hashes** (the `users` table's
`email` and bcrypt `hashed_password` columns, verbatim, alongside every other
row) — it MUST be written **outside this repository's working tree**, never
committed, and never left in a directory a `git add -A` could pick up. Point
`--output` at a dedicated backup directory, e.g. `/var/backups/strumsight/`
or a path from an operator-controlled `$STRUMSIGHT_BACKUP_DIR`:

```bash
cd backend
.venv/bin/python scripts/backup.py \
  --database-url "$STRUMSIGHT_DATABASE_URL" \
  --output "${STRUMSIGHT_BACKUP_DIR:-/var/backups/strumsight}/backup-$(date -u +%Y%m%dT%H%M%SZ).json"
```

The output file records the revision and a per-table row count on success —
check both before trusting the backup:

```
backup written to /var/backups/strumsight/backup-20260828T120000Z.json (revision=e09_r27_0020, users=42, user_settings=42, ...)
```

`backup.py` creates the file at `0600` (owner read/write only) from its first
byte. This is not machine-enforced beyond that file-mode bit — the following
are **operational rules, not code-checked invariants**, and are the operator's
responsibility every time a dump is taken:

- **Never commit a dump.** It is not covered by `backend/.gitignore` or the
  repo's secret scanner (a JSON `"hashed_password": "..."` field does not
  match the scanner's credential-assignment patterns) — the only guard is
  that the file lives outside the tree in the first place.
- **Store it encrypted at rest**, in a location with access restricted to
  the operators who need it for recovery (the same bar as a raw production
  database export).
- **Set an explicit retention window** and delete the file (not just let it
  age out silently) once that window passes or the backup is superseded by
  a newer one.

## 3. Restore

The default target is an **empty or non-existent** database — restoring is
safe by default only because of that assumption:

```bash
cd backend
.venv/bin/python scripts/restore.py \
  --database-url "$TARGET_DATABASE_URL" \
  --input "${STRUMSIGHT_BACKUP_DIR:-/var/backups/strumsight}/backup-20260828T120000Z.json" \
  --target-name <a name identifying the target, e.g. staging-primary>
```

On success, prints the restored revision and per-table row counts and exits
`0`.

### Overwriting a target that already has data

If the target already contains application rows, `restore.py` refuses by
default — **nothing is modified** — and exits non-zero:

```
restore refused: target already contains data; refusing to overwrite without --force AND a --confirm-target matching --target-name
```

Overwriting requires **both** of the following in the same invocation (ADR
0449 D4); either missing or mismatched is the same refusal:

```bash
.venv/bin/python scripts/restore.py \
  --database-url "$TARGET_DATABASE_URL" \
  --input "${STRUMSIGHT_BACKUP_DIR:-/var/backups/strumsight}/backup-20260828T120000Z.json" \
  --target-name staging-primary \
  --force \
  --confirm-target staging-primary
```

`--confirm-target` must equal `--target-name` **exactly, character for
character**. There is deliberately no shorter confirmation (`--yes`, a bare
`--force`) — this is the point where a mistyped target name (restoring a
production dump onto staging, or vice versa) is caught by a human re-reading
what they typed, not by a flag.

### If the restore is refused for the wrong reason

- `backup revision '...' is not part of the migration chain` — the dump was
  taken from a database whose applied revision isn't in this checkout's
  `backend/alembic/versions/`. Restore from a checkout at (or newer than) the
  revision the dump recorded, or re-generate the dump from the current chain.

## 4. Verification after a restore

1. `alembic current` against the target should print the same revision the
   backup recorded.
2. Compare row counts from the restore's own summary line against the
   original backup's summary line — they must match table-for-table (this is
   exactly what A3 automates against local SQLite; do the same comparison
   manually for a real restore).
3. `GET /health/ready` against the restored deployment should return `200
   {"status": "ready"}` — confirms both DB connectivity and the migration
   head match from the *application's* point of view, not just the script's.

## 5. RTO / RPO

These are **procedural** targets — the round adds the mechanism (backup /
restore scripts, proven round-trip), not a scheduled backup job or an
infrastructure SLA, which are operator decisions outside this repo.

- **RPO (Recovery Point Objective) = time since the last `backup.py` run.**
  There is no automated backup schedule shipped by this round — the operator
  decides the cadence (e.g. a cron/CI job invoking `backup.py` and shipping
  the output to durable storage). The RPO is exactly as good as that
  schedule; an ad-hoc backup right before a risky migration bounds the RPO
  for that specific operation to zero.
- **RTO (Recovery Time Objective) = time to run `restore.py` against a fresh
  target + verify.** For the local SQLite databases exercised by A3, this is
  seconds. Against a real Postgres target, the dominant cost is the JSON
  dump's row count (row-by-row `INSERT`, not a bulk-loader) and network
  latency to the target — measure it against a realistic data volume before
  quoting an RTO number in an SLA.
- Neither number is machine-checked by this round's tests; both are stated
  here so a future round tightening them (a scheduled backup job, a
  bulk-insert restore path) has an explicit starting point to improve on.
