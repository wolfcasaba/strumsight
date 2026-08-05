import 'dart:collection';

import 'tutor_tool.dart';

/// The names and local permissions exposed to a model for one tutor turn.
final class TutorToolTurnPolicy {
  TutorToolTurnPolicy({
    required Iterable<String> allowedToolNames,
    required Iterable<TutorToolPermission> allowedPermissions,
  }) : allowedToolNames = UnmodifiableSetView<String>(
         Set<String>.from(allowedToolNames),
       ),
       allowedPermissions = UnmodifiableSetView<TutorToolPermission>(
         Set<TutorToolPermission>.from(allowedPermissions),
       ) {
    if (this.allowedToolNames.any((name) => name.trim().isEmpty)) {
      throw ArgumentError.value(allowedToolNames, 'allowedToolNames');
    }
  }

  final Set<String> allowedToolNames;
  final Set<TutorToolPermission> allowedPermissions;
}

/// A single model-requested tutor tool invocation with its turn policy.
final class TutorToolRequest {
  TutorToolRequest({
    required this.toolName,
    required this.input,
    required this.policy,
    required this.timeout,
  }) {
    if (toolName.trim().isEmpty) {
      throw ArgumentError.value(toolName, 'toolName');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
  }

  final String toolName;
  final TutorToolInput input;
  final TutorToolTurnPolicy policy;
  final Duration timeout;
}
