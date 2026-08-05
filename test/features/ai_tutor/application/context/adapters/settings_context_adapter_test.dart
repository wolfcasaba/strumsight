import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/settings_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';

void main() {
  test('projects only the public preference values needed by coaching', () {
    const input = SettingsContextInput(
      capoFret: 2,
      inputLatencyMs: -10,
      labModeEnabled: true,
      leftHanded: true,
      tuningReferenceHz: 442,
      visualLatencyMs: 20,
    );

    final adapted = const SettingsContextAdapter(
      schemaVersion: 'settings.v1',
    ).adapt(input);

    expect(adapted!.key, TutorContextFieldKey.settings);
    expect(adapted.values['capoFret'], 2);
    expect(adapted.values['labModeEnabled'], isTrue);
    expect(adapted.values['leftHanded'], isTrue);
    expect(adapted.provenance.sourceFeature, ContextSourceFeature.settings);
  });

  test('imports only the Settings public boundary', () {
    const path =
        'lib/features/ai_tutor/application/context/adapters/settings_context_adapter.dart';
    final imports = File(path)
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '))
        .join('\n');
    expect(imports, contains('features/settings/public.dart'));
    expect(imports, isNot(contains('features/settings/providers/')));
  });
}
