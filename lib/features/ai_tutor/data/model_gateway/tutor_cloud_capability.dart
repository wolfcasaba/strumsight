import 'package:meta/meta.dart';

/// What the SERVER says its tutor actually runs — the parsed body of
/// `GET /tutor/capability` (`backend/app/tutor/schemas.py`,
/// `TutorCapabilityResponse`).
///
/// The endpoint reports `provider` + `model` so an operator can verify a
/// provider flip from outside the container; neither is a secret (the API
/// key is on no surface at all). The CLIENT reads it for one reason:
/// honesty. A deployment that still runs the backend's default `fake`
/// adapter answers a turn with a canned, scripted reply — presenting that
/// as a cloud tutor's answer would be a lie the student cannot detect, so
/// the selection falls back to the local, on-device stub instead (see
/// `selectTutorModelGateway`).
@immutable
final class TutorCloudCapability {
  const TutorCloudCapability({
    required this.enabled,
    required this.provider,
    required this.model,
  });

  /// Parses a capability body.
  ///
  /// Every field resolves fail-closed: a body that does not SAY it is
  /// enabled, or does not name a provider, reads as the backend's own
  /// default — the canned `fake` adapter — never as a real model.
  factory TutorCloudCapability.fromJson(Map<Object?, Object?> json) {
    final enabled = json['enabled'];
    return TutorCloudCapability(
      enabled: enabled is bool && enabled,
      provider: _nonEmptyString(json['provider']) ?? fakeProvider,
      model: _nonEmptyString(json['model']) ?? fakeModel,
    );
  }

  /// The adapter name a server serves canned answers from. It is the
  /// backend's default, so it is what a deployment whose operator has NOT
  /// flipped `STRUMSIGHT_TUTOR_PROVIDER` still reports.
  static const String fakeProvider = 'fake';

  /// The model name that adapter reports.
  static const String fakeModel = 'fake-model';

  /// Whether the server mounted its tutor routes at all.
  final bool enabled;

  /// The adapter the deployment actually built (`fake`, `anthropic`, ...).
  final String provider;

  /// The model identifier that adapter was configured with.
  final String model;

  /// Whether a turn sent to this deployment reaches a real model.
  bool get servesRealModel => enabled && provider != fakeProvider;

  @override
  bool operator ==(Object other) =>
      other is TutorCloudCapability &&
      other.enabled == enabled &&
      other.provider == provider &&
      other.model == model;

  @override
  int get hashCode => Object.hash(enabled, provider, model);

  @override
  String toString() =>
      'TutorCloudCapability(enabled: $enabled, provider: $provider, '
      'model: $model)';
}

/// The trimmed value of a wire field that is a non-blank string, else null.
String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
