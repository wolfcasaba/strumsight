import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/tutor_vision_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/vision/domain/integration/public.dart';

void main() {
  final snapshot = VisionContextSnapshot(
    sessionId: VisionSessionId('vision-session-1'),
    sessionTimestamp: SessionTimestamp(1_250_000),
    insightCode: InsightCode.pickingStable,
    confidence: 0.8,
    observationState: ObservationState.observed,
  );

  test(
    'projects the minimal vision snapshot through a tutor context field',
    () {
      final adapted = const TutorVisionContextAdapter(
        schemaVersion: 'vision-context.v1',
      ).adapt(snapshot);

      expect(adapted!.key, TutorContextFieldKey.vision);
      expect(adapted.values, snapshot.toJson());
      expect(adapted.provenance.sourceFeature, ContextSourceFeature.vision);
    },
  );

  test('does not project vision context without a version', () {
    expect(const TutorVisionContextAdapter().adapt(snapshot), isNull);
  });

  test('adapter use creates no network client or request', () {
    final networkSpy = _NetworkSpyOverrides();

    HttpOverrides.runZoned(
      () => const TutorVisionContextAdapter(
        schemaVersion: 'vision-context.v1',
      ).adapt(snapshot),
      createHttpClient: networkSpy.createHttpClient,
    );

    expect(networkSpy.clientCreations, 0);
  });

  test('imports only the narrow Vision integration barrel', () {
    const path =
        'lib/features/ai_tutor/application/context/adapters/tutor_vision_context_adapter.dart';
    final imports = File(path)
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '))
        .join('\n');

    expect(imports, contains('features/vision/domain/integration/public.dart'));
    expect(imports, isNot(contains('features/vision/public.dart')));
  });
}

final class _NetworkSpyOverrides {
  int clientCreations = 0;

  HttpClient createHttpClient(SecurityContext? context) {
    clientCreations++;
    throw StateError('The pure adapter must not create a network client.');
  }
}
