# ADR 0054 — Versioned user-content documents and their size limits

- **Status:** Accepted
- **Date:** 2026-07-29
- **Round:** E01-R07 (SDD Ch2, Kör 7)
- **Supersedes:** nothing. Builds on [ADR 0002](0002-feature-first-clean-architecture.md)
  and the storage layer introduced in E01-R05.

## Context

Six pieces of local **user content** were still serialized by their own providers
straight into `SharedPreferences`: the analyzed-session library, songs, setlists,
the practice log, lesson progress and the practice streak. Each provider held its
own plugin instance, encoded its own JSON, and guarded a load/write race with a
hand-rolled `Completer` (the r149/r150 data-loss class).

Three problems followed from that shape:

1. **A single corrupt byte cost everything.** Decoding was one
   `jsonDecode(...).map(Model.fromJson)` inside a `try/catch (_)`: one bad record
   meant the whole collection read as empty, and the next write persisted that
   emptiness. The user's songbook could disappear because of one malformed song.
2. **There was no version marker**, so a future shape change would have had to
   guess what an old blob meant — or migrate blind.
3. **Nothing was bounded** except the two collections that had grown a cap by
   hand (library 100, practice log 400).

## Decision

### 1. One envelope for every complex document (§7.3)

```json
{"schemaVersion": 1, "items": []}
```

`items` for a collection, `data` for a single object (streak, lesson progress).
`lib/core/storage/json_document_store.dart` owns reading and writing it.
A document written by a **newer** schema version is isolated rather than decoded
— guessing at an unknown shape is how data gets mangled.

### 2. Provider → repository → KeyValueStore (§7.2)

No provider serializes JSON any more. Each feature owns a repository interface
(`SongsRepository`, `LibraryRepository`, …) with a `KeyValue*` implementation
built over the shared document store, injected through a Riverpod provider. Tests
can inject a fake repository or a fake store.

Reads are **synchronous**, because the key-value store is opened during bootstrap.
That deletes the r149/r150 race class outright: there is no window between "empty
default" and "loaded content" for a mutation to fall into, so the `Completer`
gates are gone rather than merely guarded.

### 3. Corruption isolates, it never wipes (§7.4)

- A collection decodes **record by record**: a bad record is skipped and logged
  (`storage.document.record_skipped` with the index and the failing field), the
  rest of the collection loads.
- A whole document that cannot be parsed is **kept**. The app carries on with an
  empty document, and the unreadable bytes are copied to `<key>.corrupt` on the
  next write, so they stay recoverable.
- Models validate explicitly (`lib/core/foundation/json_validation.dart`):
  missing fields, unknown enums, negative durations, unparseable dates, blank
  chord labels and oversized lists are rejected as bad records.
- One deliberate exception: an **unknown practice-source name** degrades to
  `live` instead of dropping the entry. A newer build's source name must not cost
  this build a practice moment that really happened; only its attribution is
  unknown.

### 4. Documented size limits (§7.5)

| Document | Cap | Eviction | Where |
|---|---|---|---|
| Library sessions | 100 | oldest (list is newest-first) | `LibraryRepository.maxSessions` |
| Songs | 200 | oldest | `SongsRepository.maxSongs` |
| Setlists | 100 | oldest | `SetlistsRepository.maxSetlists` |
| Practice log | 400 | oldest (list is newest-last) | `PracticeLogRepository.maxEntries` |
| Lesson progress | 500 entries | excess entries dropped | `LessonProgressRepository.maxLessons` |
| Streak | single object | — | — |

Per-record bounds guard the decoder itself: `maxSongBars` (512),
`maxSetlistEntries` (500), `maxTimelineChords` (5000), `maxTimelineStrums`
(20000). They are far above anything the app produces; their job is to reject a
corrupt or hand-edited blob before it is decoded into memory.

Caps are enforced on read **and** write, so a document that grew past its bound in
an older build is trimmed instead of carried forever.

**Diagnostics payloads are explicitly out of this store.** A Lab-mode upload
carries recorded audio (up to `DiagnosticsUploader.maxWavBytes` = 5 MB) and is
posted, never persisted — mixing it into the boot-path documents would put
megabytes of audio in front of the first frame and, worse, keep raw audio on the
device by default. `test/tooling/diagnostics_storage_separation_test.dart` guards
the separation.

### 5. Migration (schema 17–22)

One `WrapJsonDocumentMigration` per document renames the legacy key to its `ss.`
key and wraps the blob in the envelope, keeping the write-before-remove ordering.

Belt and braces: the document store **still reads the legacy key** when the new
one is absent, and the next write completes the move. So a migration that could
not finish (a refused write) cannot cost the user their content — the classic
failure mode where the app writes fresh data to the new key and the retrying
migration then deletes the old one.

An unparsable blob is left on the legacy key by the migration and quarantined by
the document store on the next write; it is never deleted by either.

## Consequences

- Corruption now costs one record, not one feature's entire content.
- The race-guard machinery is gone; the providers are materially simpler.
- Every persisted document is versioned, so a future shape change is a migration
  rather than a guess.
- Cost: each feature carries a repository file it did not have before, and a
  record that fails validation is dropped rather than half-loaded — deliberate,
  but it means a decoder rule that is too strict would silently lose a record.
  That is why every model's rules are covered by
  `test/core/storage/persisted_record_validation_test.dart`, including the
  "a valid/older record still decodes" direction.
