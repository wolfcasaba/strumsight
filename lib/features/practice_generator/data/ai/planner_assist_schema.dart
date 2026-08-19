/// Strict schema and allowlist validation for untrusted model responses.
library;

import '../../application/port/planner_assist_gateway.dart';

const int _maximumRationaleLength = 500;
const int _maximumBlocks = 6;

sealed class PlannerAssistValidation {
  const PlannerAssistValidation();
}

final class PlannerAssistAccepted extends PlannerAssistValidation {
  const PlannerAssistAccepted(this.proposal);

  final PlannerAssistProposal proposal;
}

final class PlannerAssistRejected extends PlannerAssistValidation {
  const PlannerAssistRejected(this.reason);

  final PlannerAssistRejectionReason reason;
}

enum PlannerAssistRejectionReason {
  schemaViolation,
  localeMismatch,
  unknownGoalId,
  unknownSkillId,
  unknownCandidateId,
  unsafeContent,
}

/// Parses a complete response atomically. No field is returned unless every
/// schema and allowlist check succeeds.
final class PlannerAssistSchema {
  static const int schemaVersion = 1;

  static PlannerAssistValidation validate(
    PlannerAssistRequest request,
    Object? raw,
  ) {
    if (raw is! Map<Object?, Object?>) {
      return const PlannerAssistRejected(
        PlannerAssistRejectionReason.schemaViolation,
      );
    }
    final response = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        return const PlannerAssistRejected(
          PlannerAssistRejectionReason.schemaViolation,
        );
      }
      response[entry.key as String] = entry.value;
    }
    if (response['schemaVersion'] != schemaVersion ||
        response['locale'] is! String ||
        response['requiresLearnerConfirmation'] != true) {
      return const PlannerAssistRejected(
        PlannerAssistRejectionReason.schemaViolation,
      );
    }
    if (response['locale'] != request.locale) {
      return const PlannerAssistRejected(
        PlannerAssistRejectionReason.localeMismatch,
      );
    }

    final goalIds = _readCodes(response['goalIds']);
    final skillIds = _readCodes(response['skillIds']);
    final candidateIds = _readCodes(response['candidateIds']);
    final rationale = _readSafeText(response['rationale']);
    final blocks = _readBlocks(response['blocks']);
    if (goalIds == null ||
        skillIds == null ||
        candidateIds == null ||
        rationale == null ||
        blocks == null) {
      return const PlannerAssistRejected(
        PlannerAssistRejectionReason.schemaViolation,
      );
    }
    if (goalIds.any((id) => !request.allowlist.containsGoal(id))) {
      return const PlannerAssistRejected(
        PlannerAssistRejectionReason.unknownGoalId,
      );
    }
    if (skillIds.any((id) => !request.allowlist.containsSkill(id))) {
      return const PlannerAssistRejected(
        PlannerAssistRejectionReason.unknownSkillId,
      );
    }
    if (candidateIds.any((id) => !request.allowlist.containsCandidate(id)) ||
        blocks.any(
          (block) =>
              !request.allowlist.containsCandidate(block.candidateId) ||
              !candidateIds.contains(block.candidateId),
        )) {
      return const PlannerAssistRejected(
        PlannerAssistRejectionReason.unknownCandidateId,
      );
    }
    if (_containsUnsafeContent(rationale) ||
        blocks.any((block) => _containsUnsafeContent(block.rationale))) {
      return const PlannerAssistRejected(
        PlannerAssistRejectionReason.unsafeContent,
      );
    }

    return PlannerAssistAccepted(
      PlannerAssistProposal(
        goalIds: goalIds,
        skillIds: skillIds,
        candidateIds: candidateIds,
        rationale: rationale,
        blocks: blocks,
        requiresLearnerConfirmation: true,
      ),
    );
  }
}

List<String>? _readCodes(Object? value) {
  if (value is! List<Object?> || value.isEmpty) return null;
  final values = <String>[];
  for (final entry in value) {
    if (entry is! String || entry.trim().isEmpty) return null;
    values.add(entry.trim());
  }
  if (values.toSet().length != values.length) return null;
  return List<String>.unmodifiable(values);
}

String? _readSafeText(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > _maximumRationaleLength) {
    return null;
  }
  return normalized;
}

List<PlannerAssistBlockOutline>? _readBlocks(Object? value) {
  if (value is! List<Object?> ||
      value.isEmpty ||
      value.length > _maximumBlocks) {
    return null;
  }
  final blocks = <PlannerAssistBlockOutline>[];
  for (final entry in value) {
    if (entry is! Map<Object?, Object?>) return null;
    final candidateId = _readSafeText(entry['candidateId']);
    final minutes = entry['minutes'];
    final rationale = _readSafeText(entry['rationale']);
    if (candidateId == null || minutes is! int || rationale == null) {
      return null;
    }
    try {
      blocks.add(
        PlannerAssistBlockOutline(
          candidateId: candidateId,
          minutes: minutes,
          rationale: rationale,
        ),
      );
    } on ArgumentError {
      return null;
    }
  }
  return List<PlannerAssistBlockOutline>.unmodifiable(blocks);
}

bool _containsUnsafeContent(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains('<script') ||
      normalized.contains('ignore previous instructions') ||
      value.runes.any((rune) => rune < 32 && rune != 10);
}
