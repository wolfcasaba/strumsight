/// Shared contract for legacy-source evidence adapters (ADR 0293, SDD Ch8
/// Kör 7).
///
/// A [SkillSnapshotReader] never reads a live provider, a wall clock, or
/// infers identity/skill from content — every snapshot item already carries
/// whatever a caller-supplied wrapper type requires (a stable outcome id, a
/// target skill, `measuredAt`/`capturedAt`). An item this reader cannot
/// confidently map produces a [SkillSnapshotWarning], never an exception
/// (ADR 0293 §3) — legacy input is a best-effort signal, not a contract the
/// caller is trusted to have satisfied.
library;

import '../../domain/model/skill_evidence.dart';

/// One legacy snapshot item this reader could not turn into evidence, and
/// why. [code] is a stable, log-safe reason; [detail] is a non-sensitive
/// identifier (e.g. a lesson id or outcome id) for diagnosing which item was
/// skipped — never raw legacy content.
final class SkillSnapshotWarning {
  const SkillSnapshotWarning({required this.code, required this.detail});

  final String code;
  final String detail;

  @override
  String toString() => 'SkillSnapshotWarning($code: $detail)';

  @override
  bool operator ==(Object other) =>
      other is SkillSnapshotWarning &&
      code == other.code &&
      detail == other.detail;

  @override
  int get hashCode => Object.hash(code, detail);
}

/// The outcome of adapting one legacy snapshot: the evidence it could
/// confidently derive, plus one warning per skipped item.
final class SkillSnapshotResult {
  const SkillSnapshotResult({required this.evidence, required this.warnings});

  final List<SkillEvidence> evidence;
  final List<SkillSnapshotWarning> warnings;
}

/// Adapts a caller-supplied [TSnapshot] list into [SkillEvidence]. The same
/// [snapshot] must always yield the same [SkillSnapshotResult], regardless of
/// item order (SDD Ch8 §5.5) — implementations must not depend on a wall
/// clock or any mutable external state.
abstract interface class SkillSnapshotReader<TSnapshot> {
  SkillSnapshotResult readEvidence(List<TSnapshot> snapshot);
}
