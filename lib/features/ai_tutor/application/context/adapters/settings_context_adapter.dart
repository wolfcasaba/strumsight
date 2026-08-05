import 'package:strumsight/features/settings/public.dart';

import '../tutor_context_snapshot.dart';

/// Public-safe preference values read by a caller through Settings' barrel.
final class SettingsContextInput {
  const SettingsContextInput({
    required this.capoFret,
    required this.inputLatencyMs,
    required this.labModeEnabled,
    required this.leftHanded,
    required this.tuningReferenceHz,
    required this.visualLatencyMs,
  });

  final int capoFret;
  final int inputLatencyMs;
  final bool labModeEnabled;
  final bool leftHanded;
  final int tuningReferenceHz;
  final int visualLatencyMs;
}

/// Projects coaching-relevant preferences and never a settings storage record.
final class SettingsContextAdapter {
  const SettingsContextAdapter({this.schemaVersion});

  final String? schemaVersion;

  /// Public provider symbols that a caller may use to construct the input.
  Iterable<Object> get publicPreferenceContracts => <Object>[
    capoProvider,
    inputLatencyProvider,
    labModeProvider,
    leftHandedProvider,
    tuningReferenceProvider,
    visualLatencyProvider,
  ];

  TutorContextField? adapt(SettingsContextInput input) {
    if (schemaVersion == null) return null;
    return TutorContextField.available(
      key: TutorContextFieldKey.settings,
      values: <String, Object?>{
        'capoFret': input.capoFret,
        'inputLatencyMs': input.inputLatencyMs,
        'labModeEnabled': input.labModeEnabled,
        'leftHanded': input.leftHanded,
        'tuningReferenceHz': input.tuningReferenceHz,
        'visualLatencyMs': input.visualLatencyMs,
      },
      provenance: ContextProvenance(
        sourceFeature: ContextSourceFeature.settings,
        schemaVersion: schemaVersion,
      ),
    );
  }
}
