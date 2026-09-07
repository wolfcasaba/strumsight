// R9/2 — which gateway a tutor turn actually runs on.
//
// The measurement is the SELECTION, not a screen: the cloud gateway may be
// chosen only with model-use consent AND an enabled account layer AND an
// authenticated stream client, and the decision must be re-made per attempt
// so a mid-session revocation or sign-out lands on the next turn. The
// client's provenance is measured at the transport boundary (a recording
// `HttpClientAdapter`), so "it goes through DioFactory" is proven by the
// headers DioFactory's own interceptors add — not by a type check.
//
// R9/3: the client is the auth feature's `accountStreamClientProvider`, so
// the session it rides is the REAL one — the token comes from the restored
// auth session (fake token store + fake auth backend), never from a reader
// the tutor owns, and an authenticated 401 signs the student out app-wide
// exactly as it does for the account API client.

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/logging/app_logger.dart';
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
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';

import '../../../support/fake_auth.dart';

/// A near-wire probe: it only ever sees a request the interceptor chain has
/// already let through.
final class _WireProbe implements HttpClientAdapter {
  _WireProbe({this.status = 200});

  final int status;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('{}', status);
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

AppConfig _config({required bool accountEnabled}) => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags.forEnvironment(
    AppEnvironment.development,
    accountEnabled: accountEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'debug',
  appVersion: 'test',
);

/// A container whose auth session is RESTORED from [token] (null = signed
/// out), so the stream client rides the same credential holder the account
/// API client does.
Future<ProviderContainer> _container({
  required bool accountEnabled,
  required _WireProbe probe,
  String? token = 'jwt-token',
}) async {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        _config(accountEnabled: accountEnabled),
      ),
      accountDioFactoryProvider.overrideWithValue(_factory(probe)),
      tokenStoreProvider.overrideWithValue(FakeTokenStore(token)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authControllerProvider.future);
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

  group('tutorStreamClientProvider — rides the auth session', () {
    test('an account-disabled build gets no client at all', () async {
      final container = await _container(
        accountEnabled: false,
        probe: _WireProbe(),
      );

      expect(container.read(tutorStreamClientProvider), isNull);
    });

    test('the client carries the bearer token and correlation id DioFactory '
        'installs, and the SSE-specific options', () async {
      final probe = _WireProbe();
      final container = await _container(accountEnabled: true, probe: probe);

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
      final container = await _container(
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

    test('an authenticated 401 on the stream invalidates the whole account '
        'session, exactly as it does for the account API client', () async {
      final probe = _WireProbe(status: 401);
      final container = await _container(accountEnabled: true, probe: probe);
      expect(container.read(authControllerProvider).value, isNotNull);

      final client = container.read(tutorStreamClientProvider)!;
      await expectLater(
        client.get<Object?>('/tutor/capability'),
        throwsA(isA<DioException>()),
      );
      // The interceptor reports the 401 on an event-queue turn (Timer.run).
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(probe.requests, hasLength(1));
      expect(
        container.read(authControllerProvider).value,
        isNull,
        reason:
            'the stream client shares the account session closures — a '
            'rejected session must sign the student out on BOTH clients',
      );
    });
  });

  group('tutorModelGatewayFactoryProvider — decided per attempt', () {
    test('granted consent on an account build selects the cloud', () async {
      final container = await _container(
        accountEnabled: true,
        probe: _WireProbe(),
      );
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();

      final gateway = container.read(tutorModelGatewayFactoryProvider)(0);

      expect(gateway, isA<RemoteTutorModelGateway>());
    });

    test('the default (no consent granted) selects the local stub', () async {
      final container = await _container(
        accountEnabled: true,
        probe: _WireProbe(),
      );

      final gateway = container.read(tutorModelGatewayFactoryProvider)(0);

      expect(gateway, isA<LocalTutorModelGatewayStub>());
    });

    test('an account-disabled build selects the local stub even with '
        'consent granted', () async {
      final container = await _container(
        accountEnabled: false,
        probe: _WireProbe(),
      );
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();

      final gateway = container.read(tutorModelGatewayFactoryProvider)(0);

      expect(gateway, isA<LocalTutorModelGatewayStub>());
    });

    test('revoking consent changes the NEXT attempt without rebuilding the '
        'factory', () async {
      final container = await _container(
        accountEnabled: true,
        probe: _WireProbe(),
      );
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
