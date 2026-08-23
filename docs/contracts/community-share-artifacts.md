# Community Share Artifacts — Contract & Deprecation Rules

> **E09-R10** — minimal, versioned Community export from Practice, Song,
> Analysis and Gamification features.
>
> **Status:** sealed contract (E09-R10, ADR 0404).
> **Mirror source:** [`share_artifact.dart`](../../lib/features/community/domain/entities/share_artifact.dart)
> (Dart) and [`artifacts.py`](../../backend/app/community/schemas/artifacts.py)
> (Pydantic). The two sides MUST stay wire-compatible; bump them together.

This document is the canonical reference for the share-artifact wire
shape, the deprecation policy, and the backward-compatibility rules. A
future schema bump reads this file first — not scattered code
comments.

---

## 1. Scope

Seven closed artifact types, each carrying the minimum data the
Community surface shows. The artifact is a **projection** of a
source-feature row through a per-feature mapper; it never imports
the source feature's internals (ADR 0404 §D2, brief §5.1, A1
measure-matrix).

| `type` literal       | Source feature         | Mapper file                                  | Source public type                                                      |
|----------------------|------------------------|----------------------------------------------|-------------------------------------------------------------------------|
| `practiceSummary`    | Practice (E02)         | `practice_share_mapper.dart`                 | `PracticeSessionResult`                                                 |
| `songResult`         | Songs (E04-R07+)       | `song_share_mapper.dart::songResultFromSong` | `Song`                                                                  |
| `originalProgression`| Songs (E04-R07+)       | `song_share_mapper.dart::originalProgressionFromSong` | `Song`                                                          |
| `planTemplate`       | Songs (E04-R07+)       | `song_share_mapper.dart::planTemplateFromSong`| `Song`                                                                 |
| `analysisImprovement`| Audio Analysis (E06+)  | `analysis_share_mapper.dart`                 | `AnalysisComparison`                                                    |
| `achievement`        | Gamification (E08)     | `achievement_share_mapper.dart::achievementFromDefinitionAndProgress` | `AchievementDefinition`, `AchievementProgress`         |
| `challenge`          | Gamification (E08)     | `achievement_share_mapper.dart::challengeFromDefinitionAndReceipt` | `DailyChallengeDefinition`, `RewardLedgerEntry`, `LedgerEntrySyncStatus` |

Seven artifacts, four mapper files. The brief `allowed_paths`
constraint forced this consolidation (ADR 0404 §D1).

## 2. Wire shape — common envelope

Every artifact is wrapped in:

```json
{
  "artifact": { ... }
}
```

(`ShareArtifactEnvelope` on the backend.) The wrapper has
`extra="forbid"` — any additional key is a parse-time rejection.
Inside the wrapper, the `type` field selects the concrete
discriminator.

## 3. Required fields per artifact

All seven artifacts carry:

* `type: <literal>` — the discriminator.
* `schemaVersion: 1` — the wire schema version. **Must equal
  `SHARE_ARTIFACT_SCHEMA_VERSION`** (=1 on both sides); any other
  value raises `pydantic.ValidationError` (A3 measure-matrix,
  brief §5.2). The Dart `ShareArtifact.fromJson` raises
  `ArgumentError` on the same mismatch.
* `sourceId: <string>` — the originating row id (survives source
  deletion under retention policy; SDD §11.3).
* `createdAt: <ISO-8601 timestamp>` — when the artifact was
  created (may predate the post).

The per-subtype fields are:

| Artifact             | Fields                                                                                |
|----------------------|----------------------------------------------------------------------------------------|
| `practiceSummary`    | `activeSeconds`, `pausedSeconds`, `attemptCount`, `finishReasonCode`, `bestScore?`, `coachingCodes[]` |
| `songResult`         | `songName`, `chords[]`, `strumPattern`, `bpm`, `beatsPerBar`                            |
| `originalProgression`| same wire fields as `songResult`                                                      |
| `planTemplate`       | same wire fields as `songResult`                                                      |
| `analysisImprovement`| `metrics[]` — each entry: `metricId`, `directionCode`, `beforeValue?`, `afterValue?`, `relativeDelta?` |
| `achievement`        | `achievementId`, `categoryCode`, `catalogVersion`, `progressValue`, `completedAt?`     |
| `challenge`          | `challengeTypeCode`, `challengeName`, `rewardStatusCode`, `completedAt?`, `rewardXp?`, `ledgerId?` |

Each concrete Pydantic model whitelists its fields with
`extra="forbid"`; the Dart `toJson`/`fromJson` codec refuses
unknown keys.

## 4. Explicitly excluded fields

These fields MUST NEVER appear in any artifact. The
`extra="forbid"` whitelist plus the field-by-field mapper
construction is the enforcement; the §6.1 measure-matrix
"raw audio / video / waveform / landmark" row is enforced by
**absence** (A5 measure-matrix):

* `rawAudioPath`, `audioSamples`, `waveform`, `waveformSamples`,
  `audioBuffer`, `recordingBytes`.
* `videoPath`, `videoFrames`, `pixelBuffer`, `imageBytes`.
* `landmarks`, `handLandmarks`, `poseKeypoints`, `featureVectors`.
* `deviceId`, `userId`, `profileId`, `publicId` (the artifact is
  content-addressed, the post carries the identity, Kör 11+).
* `internalScore`, `debugInfo`, `engineTrace`, `engineVersion`
  (DSP-debug fields — out of scope for the Community surface).
* `totalXp` — the gamification aggregate is server-computed (ADR
  0394 §5.1); a tampered client cannot inflate it.

A regression that introduces any of these fields into an artifact
will be caught by:

* the backend `extra="forbid"` at parse-time,
* the §6.1 measure-matrix A5 cell (`share_artifact_test.dart`).

## 5. The `rewardStatusCode` contract (challenge artifact, ADR 0404 §D4)

The challenge artifact carries `rewardStatusCode` — a wire literal
that mirrors the gamification `LedgerEntrySyncStatus` enum
(`unverified`, `verified`, ADR 0394 §5.3, E08-R28). The mapping is
fixed:

| Wire literal  | Maps to gamification       | Meaning                                              |
|---------------|----------------------------|------------------------------------------------------|
| `unverified`  | `LedgerEntrySyncStatus.unverified` | The receipt is uploaded but not yet server-confirmed |
| `verified`    | `LedgerEntrySyncStatus.verified`   | The receipt passed server-side validation            |

The Community domain does **not** import the gamification enum
directly (A1 measure-matrix); the mapper translates at the seam.
Future Kör 21+ may add server-side guards like "a `verified`
artifact without a matching `ledgerId` is rejected" — that is a
post-creation endpoint concern, not an artifact-schema concern.

## 6. The `schemaVersion` rejection contract (ADR 0404 §D3, brief §5.2)

The Pydantic discriminated union and the Dart `ShareArtifact.fromJson`
both reject any `schemaVersion != SHARE_ARTIFACT_SCHEMA_VERSION`. The
failure modes are:

* **Backend:** `pydantic.ValidationError` from
  `_validate_schema_version`. The router maps the validation error
  to HTTP 422 in Kör 11+.
* **Dart:** `ArgumentError` from
  `ShareArtifact.fromJson` (and each concrete model's `fromJson`).
  There is no best-effort fallback.

The §6.1 measure-matrix A3 cell explicitly tests this:

> Unknown `schemaVersion` csendben az 1-es verzióként értelmeződik
> → a mérce-cella `share_artifact_test.dart` ezt a kódot eldobva
> PIROSRA váltja.

## 7. The field-level share toggles (ADR 0404 §D5)

`SharePreview` in `share_artifact.dart` is the toggle surface. All
flags default to `false` (off). The conservative default is the
`SharePreview.conservative` constant; the `SharePreview.none`
constant is the explicit-never-share intent.

A flag must be explicitly flipped to `true` by the user before the
artifact is materialised (the §9.3 SDD invariant — "share kapcsolók
alapértelmezetten konzervatívak"). The flag's name maps to a
post-creation endpoint concern in Kör 11+; this round only defines
the surface.

## 8. Backward compatibility — what a future schema bump MUST do

A `schemaVersion` bump is the **only** mechanism for evolving the
wire shape (ADR 0404 §D3). The discipline, enforced by both sides:

1. **Bump `SHARE_ARTIFACT_SCHEMA_VERSION`** (Dart and Python
   constants) in the same commit.
2. **Document the bump in this file** — list the new fields, the
   deprecated fields, the migration window.
3. **Server must keep accepting the OLD `schemaVersion`** for at
   least one minor release. A bump from 1 → 2 means the server
   parses BOTH 1 and 2, with a `version_router` selecting the right
   concrete model per version.
4. **A field rename is forbidden.** Add the new name, mark the old
   as deprecated, drop the old after the migration window. Never
   silently rename a wire field — old clients would silently lose
   data.
5. **A field removal is forbidden without a major version bump.**
   The Dart and Python sides age the field together.

## 9. Deprecation rules — how a wire field goes away

A wire field becomes deprecated through this sequence:

1. **Mark deprecated in the constant file.** Add a `DEPRECATED_*`
   comment with the `schemaVersion` that introduced the deprecation
   and the planned removal `schemaVersion`.
2. **Both sides keep accepting the field** until the planned
   removal version. The Pydantic model carries the field with
   `Optional[...]` and a `@field_validator` that warns on parse
   (a future Kör will add a structured warning path).
3. **Remove the field in the planned version bump.** The removal
   commit MUST land together with the `schemaVersion` bump, NOT
   silently. Old clients that still send the field raise
   `extra="forbid"` `ValidationError` — the explicit, loud failure
   the §6.1 measure-matrix demands.

## 10. Reference — file map

| File                                                                    | Role                                                      |
|-------------------------------------------------------------------------|-----------------------------------------------------------|
| `lib/features/community/domain/entities/share_artifact.dart`            | Sealed Dart hierarchy, JSON codec, `SharePreview` toggles |
| `lib/features/community/application/mappers/practice_share_mapper.dart` | Practice → `PracticeSummaryArtifact`                      |
| `lib/features/community/application/mappers/song_share_mapper.dart`     | Song → `SongResultArtifact` / `OriginalProgressionArtifact` / `PlanTemplateArtifact` |
| `lib/features/community/application/mappers/analysis_share_mapper.dart` | `AnalysisComparison` → `AnalysisImprovementArtifact`      |
| `lib/features/community/application/mappers/achievement_share_mapper.dart` | Gamification → `AchievementArtifact` / `ChallengeArtifact` |
| `backend/app/community/schemas/artifacts.py`                            | Pydantic discriminated union, envelope, parser            |
| `test/features/community/application/share_artifact_test.dart`          | Dart §6 / §6.1 measure-matrix                             |
| `backend/tests/community/test_share_artifact_schema.py`                  | Backend §6 / §6.1 measure-matrix                          |
| `docs/rounds/e09-r10-share-artifact-contracts.md`                       | Round handoff (Kör 10)                                    |

A future Vision / Tutor share integration (E09-R15+) lands in a
separate ADR; this file's mapper-table grows a row when the new
subtype ships.