/// Maps caller-supplied Tutor-like outlines to the PlannerAssist boundary.
///
/// This deliberately defines its own input shape. The frozen `ai_tutor`
/// public boundary exports no reachable domain type, so this adapter never
/// imports that feature.
library;

import '../../application/port/planner_assist_gateway.dart';
import '../../application/port/practice_catalog_reader.dart';
import '../../domain/id/planner_ids.dart';

/// Typed, caller-fed outline for an AI advice proposal, not an active plan.
final class TutorPlanOutline {
  TutorPlanOutline({
    required Iterable<GoalId> goalIds,
    required Iterable<String> skillIds,
    required this.learnerNote,
  }) : goalIds = List<GoalId>.unmodifiable(goalIds),
       skillIds = _requiredSkills(skillIds) {
    if (this.goalIds.isEmpty ||
        this.goalIds.toSet().length != this.goalIds.length) {
      throw ArgumentError.value(
        goalIds,
        'goalIds',
        'must be unique and non-empty',
      );
    }
  }

  final List<GoalId> goalIds;
  final List<String> skillIds;
  final String learnerNote;
}

/// Builds exact allowlists only from practice-generator public catalog data and
/// typed caller input. It has no dependency on `ai_tutor` internals.
final class TutorPlanProposalAdapter {
  const TutorPlanProposalAdapter({required this.catalogReader});

  final PracticeCatalogReader catalogReader;

  PlannerAssistRequest toRequest({
    required String requestId,
    required String locale,
    required TutorPlanOutline outline,
  }) {
    final catalog = catalogReader.read();
    return PlannerAssistRequest(
      requestId: requestId,
      locale: locale,
      learnerNote: outline.learnerNote,
      allowlist: PlannerAssistAllowlist(
        goalIds: outline.goalIds.map((id) => id.value),
        skillIds: <String>{
          ...outline.skillIds,
          for (final candidate in catalog.candidates) ...candidate.skillTargets,
        },
        candidateIds: catalog.candidates.map(
          (candidate) => '${candidate.source.code}:${candidate.exerciseId}',
        ),
      ),
    );
  }
}

List<String> _requiredSkills(Iterable<String> skills) {
  final result = skills.map((skill) => skill.trim()).toList();
  if (result.isEmpty || result.any((skill) => skill.isEmpty)) {
    throw ArgumentError.value(skills, 'skillIds', 'must be non-empty');
  }
  if (result.toSet().length != result.length) {
    throw ArgumentError.value(
      skills,
      'skillIds',
      'must not contain duplicates',
    );
  }
  return List<String>.unmodifiable(result);
}
