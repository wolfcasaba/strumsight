import 'dart:collection';

enum TutorActionSource { modelSuggestion, userInitiated }

enum TutorActionCapability {
  updateProfile,
  savePlan,
  launchPracticeSession,
  launchSongRange,
}

enum TutorSessionLaunchCapability { practiceSession, songRange }

enum TutorActionPreviewKind { profileUpdate, planSave, sessionLaunch }

final class TutorActionRevisionToken {
  const TutorActionRevisionToken(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is TutorActionRevisionToken && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class TutorActionValidity {
  const TutorActionValidity({
    this.songId,
    this.songRevision,
    this.sourceSessionId,
  }) : assert((songId == null) == (songRevision == null));

  final String? songId;
  final TutorActionRevisionToken? songRevision;
  final String? sourceSessionId;
}

final class TutorActionMetadata {
  TutorActionMetadata({
    required this.source,
    required DateTime expiresAt,
    required this.requiredCapability,
    required this.clientActionId,
    this.validity = const TutorActionValidity(),
  }) : expiresAt = expiresAt.toUtc() {
    if (clientActionId.trim().isEmpty) {
      throw ArgumentError.value(clientActionId, 'clientActionId');
    }
  }

  final TutorActionSource source;
  final DateTime expiresAt;
  final TutorActionCapability requiredCapability;
  final String clientActionId;
  final TutorActionValidity validity;
}

final class TutorActionPreview {
  TutorActionPreview({required this.kind, required Map<String, Object?> fields})
    : fields = UnmodifiableMapView<String, Object?>(
        Map<String, Object?>.from(fields),
      );

  final TutorActionPreviewKind kind;
  final Map<String, Object?> fields;
}

sealed class TutorActionProposal {
  const TutorActionProposal(this.metadata);

  final TutorActionMetadata metadata;
}

sealed class TutorAction extends TutorActionProposal {
  TutorAction(super.metadata);

  TutorActionPreview get preview;
}

final class TutorProfileUpdateAction extends TutorAction {
  TutorProfileUpdateAction({
    required TutorActionMetadata metadata,
    required Map<String, Object?> changes,
  }) : changes = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.from(changes),
       ),
       super(metadata) {
    if (metadata.requiredCapability != TutorActionCapability.updateProfile) {
      throw ArgumentError.value(metadata, 'metadata');
    }
    if (this.changes.isEmpty) {
      throw ArgumentError.value(changes, 'changes');
    }
  }

  final Map<String, Object?> changes;

  @override
  TutorActionPreview get preview => TutorActionPreview(
    kind: TutorActionPreviewKind.profileUpdate,
    fields: changes,
  );
}

final class TutorPlanSaveAction extends TutorAction {
  TutorPlanSaveAction({
    required TutorActionMetadata metadata,
    required this.planId,
    required this.title,
  }) : super(metadata) {
    if (metadata.requiredCapability != TutorActionCapability.savePlan) {
      throw ArgumentError.value(metadata, 'metadata');
    }
    if (planId.trim().isEmpty || title.trim().isEmpty) {
      throw ArgumentError.value(<String>[planId, title], 'plan');
    }
  }

  final String planId;
  final String title;

  @override
  TutorActionPreview get preview => TutorActionPreview(
    kind: TutorActionPreviewKind.planSave,
    fields: <String, Object?>{'planId': planId, 'title': title},
  );
}

final class TutorSessionLaunchAction extends TutorAction {
  TutorSessionLaunchAction({
    required TutorActionMetadata metadata,
    required this.launchCapability,
  }) : super(metadata) {
    if (metadata.requiredCapability != _capabilityFor(launchCapability)) {
      throw ArgumentError.value(metadata, 'metadata');
    }
  }

  final TutorSessionLaunchCapability launchCapability;

  @override
  TutorActionPreview get preview => TutorActionPreview(
    kind: TutorActionPreviewKind.sessionLaunch,
    fields: <String, Object?>{'launchCapability': launchCapability.name},
  );
}

final class TutorUnknownActionProposal extends TutorActionProposal {
  TutorUnknownActionProposal({
    required TutorActionMetadata metadata,
    required this.actionType,
  }) : super(metadata) {
    if (actionType.trim().isEmpty) {
      throw ArgumentError.value(actionType, 'actionType');
    }
  }

  final String actionType;
}

final class TutorRawRouteActionProposal extends TutorActionProposal {
  TutorRawRouteActionProposal({
    required TutorActionMetadata metadata,
    required this.route,
  }) : super(metadata) {
    if (route.trim().isEmpty) {
      throw ArgumentError.value(route, 'route');
    }
  }

  final String route;
}

TutorActionCapability _capabilityFor(TutorSessionLaunchCapability capability) =>
    switch (capability) {
      TutorSessionLaunchCapability.practiceSession =>
        TutorActionCapability.launchPracticeSession,
      TutorSessionLaunchCapability.songRange =>
        TutorActionCapability.launchSongRange,
    };
