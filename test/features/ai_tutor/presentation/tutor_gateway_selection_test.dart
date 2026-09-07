// R9/2 — which gateway a tutor turn actually runs on.
//
// The measurement is the SELECTION, not a screen: the cloud gateway may be
// chosen only with model-use consent AND an enabled account layer AND an
// authenticated stream client, and the decision must be re-made per attempt
// so a mid-session revocation or sign-out lands on the next turn. The
// client's provenance is measured at the transport boundary (a recording
// `HttpClientAdapter`), so "it goes through DioFactory" is proven by the
// headers DioFactory's own interceptors add — not by a type check.

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/network/auth_interceptor.dart';
import 'package:strumsight/core/network/correlation_id_interceptor.dart';
import 'package:strumsight/core/network/dio_factory.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_assembler.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_orchestrator.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_template.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_version.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/tutor_prompt_builder.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_index.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_retriever.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/fake_tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/local_tutor_model_gateway_stub.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/remote_tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_consent.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_gateway_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';
import 'package:strumsight/features/auth/public.dart'
    show accountEnabledProvider;

/// A near-wire probe: it only ever sees a request the interceptor chain has
/// already let through.
final class _WireProbe implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

DioFactory _factory(_WireProbe probe) => DioFactory(
  baseUrl: 'https://api.strumsight.test',
  appVersion: 'test',
  logger: const NoopAppLogger(),
  adapter: probe,
  correlationIdGenerator: () => 'tutor-stream-probe',
);

AccessTokenReader _tokenReader(String? token) =>
    () async => Success<String?>(token);

ProviderContainer _container({
  required bool accountEnabled,
  required _WireProbe probe,
  String? token = 'jwt-token',
}) {
  final container = ProviderContainer(
    overrides: [
      accountEnabledProvider.overrideWithValue(accountEnabled),
      tutorStreamDioFactoryProvider.overrideWithValue(_factory(probe)),
      tutorAccessTokenReaderProvider.overrideWithValue(_tokenReader(token)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('selectTutorModelGateway — the pure rule', () {
    test('consent + account + client is the only cloud combination', () {
      expect(
        selectTutorModelGateway(
          consent: const TutorConsent(modelUseGranted: true),
          accountEnabled: true,
          streamClient: Dio(),
        ),
        isA<RemoteTutorModelGateway>(),
      );
    });

    test('each missing precondition falls back to the local stub', () {
      final withoutConsent = selectTutorModelGateway(
        consent: const TutorConsent(),
        accountEnabled: true,
        streamClient: Dio(),
      );
      final withoutAccount = selectTutorModelGateway(
        consent: const TutorConsent(modelUseGranted: true),
        accountEnabled: false,
        streamClient: Dio(),
      );
      final withoutClient = selectTutorModelGateway(
        consent: const TutorConsent(modelUseGranted: true),
        accountEnabled: true,
        streamClient: null,
      );

      expect(withoutConsent, isA<LocalTutorModelGatewayStub>());
      expect(withoutAccount, isA<LocalTutorModelGatewayStub>());
      expect(withoutClient, isA<LocalTutorModelGatewayStub>());
    });
  });

  group('tutorStreamClientProvider — built through DioFactory', () {
    test('an account-disabled build gets no client at all', () {
      final container = _container(accountEnabled: false, probe: _WireProbe());

      expect(container.read(tutorStreamClientProvider), isNull);
    });

    test('the client carries the bearer token and correlation id DioFactory '
        'installs, and the SSE-specific options', () async {
      final probe = _WireProbe();
      final container = _container(accountEnabled: true, probe: probe);

      final client = container.read(tutorStreamClientProvider);
      expect(client, isNotNull);
      expect(
        client!.options.receiveTimeout,
        DioFactory.tutorStreamReceiveTimeout,
      );
      expect(client.options.headers['Accept'], 'text/event-stream');
      expect(client.options.baseUrl, 'https://api.strumsight.test');

      await client.get<Object?>('/tutor/capability');

      expect(probe.requests, hasLength(1));
      final sent = probe.requests.single.headers;
      expect(sent['Authorization'], 'Bearer jwt-token');
      expect(sent[CorrelationIdInterceptor.headerName], 'tutor-stream-probe');
    });

    test('a signed-out student is rejected BEFORE the wire adapter', () async {
      final probe = _WireProbe();
      final container = _container(
        accountEnabled: true,
        probe: probe,
        token: null,
      );

      final client = container.read(tutorStreamClientProvider)!;
      await expectLater(
        client.get<Object?>('/tutor/capability'),
        throwsA(isA<DioException>()),
      );

      expect(
        probe.requests,
        isEmpty,
        reason:
            'AuthInterceptor must reject a tokenless request before the '
            'transport adapter — a signed-out turn never reaches the network',
      );
    });
  });

  group('tutorModelGatewayFactoryProvider — decided per attempt', () {
    test('granted consent on an account build selects the cloud gateway', () {
      final container = _container(accountEnabled: true, probe: _WireProbe());
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();

      final gateway = container.read(tutorModelGatewayFactoryProvider)(0);

      expect(gateway, isA<RemoteTutorModelGateway>());
    });

    test('the default (no consent granted) selects the local stub', () {
      final container = _container(accountEnabled: true, probe: _WireProbe());

      final gateway = container.read(tutorModelGatewayFactoryProvider)(0);

      expect(gateway, isA<LocalTutorModelGatewayStub>());
    });

    test('an account-disabled build selects the local stub even with '
        'consent granted', () {
      final container = _container(accountEnabled: false, probe: _WireProbe());
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();

      final gateway = container.read(tutorModelGatewayFactoryProvider)(0);

      expect(gateway, isA<LocalTutorModelGatewayStub>());
    });

    test('revoking consent changes the NEXT attempt without rebuilding the '
        'factory', () {
      final container = _container(accountEnabled: true, probe: _WireProbe());
      final factory = container.read(tutorModelGatewayFactoryProvider);
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();
      expect(factory(0), isA<RemoteTutorModelGateway>());

      container.read(tutorConsentControllerProvider.notifier).revokeModelUse();

      expect(
        factory(1),
        isA<LocalTutorModelGatewayStub>(),
        reason:
            'the factory re-reads the live consent on every attempt — a '
            'boot-time snapshot would keep the cloud gateway for the rest '
            'of the session',
      );
    });
  });

  group('TutorOrchestrator.withGatewayFactory', () {
    test('shares the collaborators and uses the supplied factory', () async {
      var calls = 0;
      final base = TutorOrchestrator(
        contextAssembler: const TutorContextAssembler(),
        knowledgeRetriever: KnowledgeRetriever(
          index: const KnowledgeIndex.empty(),
        ),
        promptBuilder: TutorPromptBuilder(templateLoader: _Loader()),
        gatewayForAttempt: (_) => LocalTutorModelGatewayStub(),
      );
      addTearDown(() => unawaited(base.dispose()));

      TutorModelGateway selected(int attempt) {
        calls++;
        return FakeTutorModelGateway(script: const <FakeGatewayStep>[]);
      }

      final derived = base.withGatewayFactory(selected);
      addTearDown(() => unawaited(derived.dispose()));

      expect(derived.contextAssembler, same(base.contextAssembler));
      expect(derived.knowledgeRetriever, same(base.knowledgeRetriever));
      expect(derived.promptBuilder, same(base.promptBuilder));
      expect(derived.outputValidator, same(base.outputValidator));
      expect(derived.gatewayForAttempt(0), isA<FakeTutorModelGateway>());
      expect(calls, 1);
      expect(
        base.gatewayForAttempt(0),
        isA<LocalTutorModelGatewayStub>(),
        reason: 'the base orchestrator keeps its own factory',
      );
    });
  });
}

final class _Loader implements PromptTemplateLoader {
  @override
  Future<PromptTemplate> load(ContextPurpose purpose) async => PromptTemplate(
    id: 'test.${purpose.name}',
    version: PromptVersion.v1,
    locale: 'en',
    intent: purpose,
    template: 'Return structured tutor output.',
    outputSchemaVersion: PromptVersion.v1,
  );
}
