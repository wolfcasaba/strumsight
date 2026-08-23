/// Practice → Community share-artifact mapper (E09-R10, ADR 0404 §D1).
///
/// Translates a typed [PracticeSessionResult] from the Practice
/// feature's `public.dart` barrel into the minimal
/// [PracticeSummaryArtifact] the Community contract exposes. The
/// mapper is the SEAM that enforces §5.1 — the Community domain
/// never imports the Practice feature's internals.
///
/// The mapper is intentionally a thin projection: it copies a
/// hand-picked subset of fields (active/paused duration, attempt
/// count, finish reason, best overall score, coaching codes). Raw
/// per-attempt DSP, per-attempt score components and per-attempt
/// vision evidence are NOT carried over — the §6.1 measure-matrix
/// "raw audio / waveform / landmark" row is enforced by ABSENCE.
library;

import 'package:strumsight/features/practice/public.dart';

import '../../domain/entities/share_artifact.dart';

/// Builds a [PracticeSummaryArtifact] from a [PracticeSessionResult].
///
/// The mapper is pure — no I/O, no time, no random. The caller
/// supplies [createdAt] (typically the post's share moment, not
/// `DateTime.now()` — every Community mapper keeps the domain
/// framework-free).
PracticeSummaryArtifact practiceSummaryFromSessionResult(
  PracticeSessionResult result, {
  required DateTime createdAt,
  String sourceId,
  int schemaVersion = shareArtifactSchemaVersion,
}) {
  final best = result.bestAttempt;
  final bestScore = switch (best?.metrics.overall) {
    MetricAvailable(:final value) => value,
    MetricInsufficientData() || MetricNotApplicable() || null => null,
  };
  return PracticeSummaryArtifact(
    schemaVersion: schemaVersion,
    sourceId: sourceId.isEmpty ? result.id : sourceId,
    createdAt: createdAt,
    activeSeconds: result.activeDuration.inSeconds,
    pausedSeconds: result.pausedDuration.inSeconds,
    attemptCount: result.attempts.length,
    finishReasonCode: result.finishReason.code,
    bestScore: bestScore,
    coachingCodes: result.coachingSummary,
  );
}