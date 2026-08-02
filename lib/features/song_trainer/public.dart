/// Public boundary of the Song Trainer V2 feature (E03-R01, SDD Ch4 §3).
///
/// This file is intentionally empty in the E03-R01 baseline round. The
/// SongDocument V2 / file+asset storage / importer / Practice Engine
/// integration has its architectural decisions locked in by ADR 0089–0092
/// (committed in the pre-flight) but **no production code** yet — the
/// feature is default-OFF via [FeatureFlags.songTrainerV2Enabled] and no
/// model, repository, importer, screen or wiring is reachable.
///
/// The boundary exists so that, from the moment the first public symbol is
/// added in a later round, the cross-feature surface has a single, reviewable
/// entry point — every other feature imports `package:strumsight/features/
/// song_trainer/public.dart` and never reaches into the feature internals.
///
/// **Do NOT export anything from here until a later round** explicitly
/// extends the Song Trainer public surface (E03-R02+) and the export is
/// reviewable against the Epic 3 SDD. Empty exports — e.g. a `show` clause
/// that exposes nothing — are rejected by the linter and the architecture
/// guard, so the file carries only the library directive.
library;
