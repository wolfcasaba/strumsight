import 'dart:collection';

import '../../domain/models/tutor_action.dart';

enum TutorActionValidationIssue {
  unknownAction,
  rawRouteForbidden,
  expired,
  capabilityUnavailable,
  songRevisionChanged,
  sourceSessionUnavailable,
}

final class TutorActionValidationContext {
  TutorActionValidationContext({
    required DateTime now,
    required Iterable<TutorActionCapability> availableCapabilities,
    required Iterable<String> activeSessionIds,
    required Map<String, TutorActionRevisionToken> songRevisions,
  }) : now = now.toUtc(),
       availableCapabilities = UnmodifiableSetView<TutorActionCapability>(
         Set<TutorActionCapability>.from(availableCapabilities),
       ),
       activeSessionIds = UnmodifiableSetView<String>(
         Set<String>.from(activeSessionIds),
       ),
       songRevisions = UnmodifiableMapView<String, TutorActionRevisionToken>(
         Map<String, TutorActionRevisionToken>.from(songRevisions),
       );

  final DateTime now;
  final Set<TutorActionCapability> availableCapabilities;
  final Set<String> activeSessionIds;
  final Map<String, TutorActionRevisionToken> songRevisions;
}

final class TutorActionValidationResult {
  TutorActionValidationResult(Iterable<TutorActionValidationIssue> issues)
    : issues = List<TutorActionValidationIssue>.unmodifiable(issues);

  final List<TutorActionValidationIssue> issues;

  bool get isValid => issues.isEmpty;
}

final class TutorActionValidator {
  const TutorActionValidator();

  TutorActionValidationResult validate(
    TutorActionProposal proposal, {
    required TutorActionValidationContext context,
  }) {
    if (proposal is TutorUnknownActionProposal) {
      return TutorActionValidationResult(const <TutorActionValidationIssue>[
        TutorActionValidationIssue.unknownAction,
      ]);
    }
    if (proposal is TutorRawRouteActionProposal) {
      return TutorActionValidationResult(const <TutorActionValidationIssue>[
        TutorActionValidationIssue.rawRouteForbidden,
      ]);
    }
    if (proposal is! TutorAction) {
      return TutorActionValidationResult(const <TutorActionValidationIssue>[
        TutorActionValidationIssue.unknownAction,
      ]);
    }

    final issues = <TutorActionValidationIssue>[];
    final metadata = proposal.metadata;
    if (!metadata.expiresAt.isAfter(context.now)) {
      issues.add(TutorActionValidationIssue.expired);
    }
    if (!context.availableCapabilities.contains(metadata.requiredCapability)) {
      issues.add(TutorActionValidationIssue.capabilityUnavailable);
    }

    final validity = metadata.validity;
    final songId = validity.songId;
    final songRevision = validity.songRevision;
    if (songId != null && context.songRevisions[songId] != songRevision) {
      issues.add(TutorActionValidationIssue.songRevisionChanged);
    }
    final sourceSessionId = validity.sourceSessionId;
    if (sourceSessionId != null &&
        !context.activeSessionIds.contains(sourceSessionId)) {
      issues.add(TutorActionValidationIssue.sourceSessionUnavailable);
    }

    return TutorActionValidationResult(issues);
  }
}
