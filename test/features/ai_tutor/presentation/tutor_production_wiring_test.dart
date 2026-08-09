import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/local_tutor_model_gateway_stub.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_event.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_request.dart';
import 'package:strumsight/features/ai_tutor/data/repositories/local_tutor_conversation_repository.dart';
import 'package:strumsight/features/ai_tutor/data/repositories/local_tutor_memory_repository.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';
import 'package:strumsight/main.dart';

import '../../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'production overrides construct all Tutor dependencies with the stub gateway',
    () async {
      final store = InMemoryKeyValueStore();
      final overrides = await buildTutorProductionOverrides(
        keyValueStore: store,
      );
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);

      final orchestrator = container.read(tutorOrchestratorProvider);
      expect(
        container.read(tutorConversationRepositoryProvider),
        isA<LocalTutorConversationRepository>(),
      );
      expect(
        container.read(tutorMemoryRepositoryProvider),
        isA<LocalTutorMemoryRepository>(),
      );

      final gateway = orchestrator.gatewayForAttempt(0);
      expect(gateway, isA<LocalTutorModelGatewayStub>());
      final started = await gateway.start(
        TutorModelRequest(
          requestId: TutorRequestId('request-1'),
          sequence: 0,
          conversationId: TutorConversationId('conversation-1'),
          message: 'prompt',
        ),
      );
      expect(started, isA<Failure<Stream<TutorModelEvent>>>());
      expect(started.failureOrNull?.code, 'tutor.model_gateway.unavailable');
    },
  );
}
