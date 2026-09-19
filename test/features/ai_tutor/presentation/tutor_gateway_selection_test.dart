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
//
// R24: two more conditions. `FeatureFlags.aiTutorCloudEnabled` — which had
// ZERO consumers before that round, so a consenting, signed-in student
// would have streamed to a cloud the build's own flag says is not rolled
// out — and the server's OWN answer at `/tutor/capability`: a deployment
// still running the backend's canned `fake` adapter must never have its
// scripted reply presented as a cloud tutor's answer.
//
// E-R29a: the flag itself is now OPEN in the shipped development build
// (`FeatureFlags.forShippedBuild`), because with it closed every artifact
// resolved the stub — whose `start()` always fails — and the Coach could
// not answer anything at all (2026-09-08 re-audit, BLOCKER B1). So the
// cells below flip around: the SHIPPED resolution is the cloud one, and
// each single missing precondition (no consent, no account, no client, a
// `fake` server, the explicit kill-switch define) is what still falls back
// to the stub. The capability check stays provider-AGNOSTIC — the rule is
// `provider != fake`, never a vendor name.

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
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_cloud_capability.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_consent.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_gateway_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';

import '../../../support/fake_auth.dart';
import '../../../support/preference_store.dart';

/// A near-wire probe: it only ever sees a request the interceptor chain has
/// already let through.
final class _WireProbe implements HttpClientAdapter {
  _WireProbe({this.status = 200, this.body = '{}'});

  final int status;

  /// The body every request gets back. The capability probe is the only GET
  /// this suite issues, so a capability JSON here IS the server's answer to
  /// "which adapter do you run?".
  final String body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(body, status);
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

AppConfig _configOf(FeatureFlags flags) => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: flags,
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'debug',
  appVersion: 'test',
);

/// The build with the E-R29a kill switch thrown — the shipped development
/// resolution PLUS an explicit `--dart-define=STRUMSIGHT_AI_TUTOR_CLOUD=
/// false`, which is now the only shipped way to get `aiTutorCloudEnabled:
/// false`. It is spelled out as a define rather than left to
/// `forEnvironment`, because "the flag is off" must be measured against the
/// configuration a build command can actually produce.
AppConfig _cloudDisabledConfig({required bool accountEnabled}) => _configOf(
  FeatureFlags.forShippedBuild(
    AppEnvironment.development,
    accountDefine: accountEnabled,
    aiTutorCloudDefine: false,
  ),
);

/// The SHIPPED development build, exactly as `AppBootstrap.run` resolves it
/// for the tester APK (E-R29a): `aiTutorCloudEnabled` is TRUE there.
///
/// Until E-R29a it was false in every artifact anyone could install, so
/// [selectTutorModelGateway] returned `LocalTutorModelGatewayStub` for every
/// student, and that stub's `start()` always fails — the Coach could not
/// answer a single question (2026-09-08 re-audit, BLOCKER B1). Opening the
/// gate changes NOTHING about consent: the cells below measure that the
/// other four fail-closed conditions still decide each turn on their own.
AppConfig _shippedConfig({required bool accountEnabled}) => _configOf(
  FeatureFlags.forShippedBuild(
    AppEnvironment.development,
    accountDefine: accountEnabled,
  ),
);

/// The capability body a deployment answers with once its operator has
/// flipped `STRUMSIGHT_TUTOR_PROVIDER` (`backend/app/tutor/schemas.py`,
/// step list: `docs/operations/backend-live-deploy.md` §7.2). The provider
/// NAME here is incidental — `TutorCloudCapability.servesRealModel` only
/// asks whether it is the canned `fake` adapter.
const String _realCapabilityBody =
    '{"enabled":true,"version":"v1","streaming":false,'
    '"provider":"anthropic","model":"claude-sonnet-5"}';

/// The body the backend's DEFAULT, canned adapter answers with.
const String _fakeCapabilityBody =
    '{"enabled":true,"version":"v1","streaming":false,'
    '"provider":"fake","model":"fake-model"}';

/// A container whose auth session is RESTORED from [token] (null = signed
/// out), so the stream client rides the same credential holder the account
/// API client does.
///
/// [cloudEnabled] picks between the two shipped development configurations:
/// `true` is the tester APK's own resolution (E-R29a: the rollout gate is
/// open), `false` is that same build with the explicit
/// `STRUMSIGHT_AI_TUTOR_CLOUD=false` kill switch. It defaults to the CLOSED
/// gate so a cell has to ask for the cloud on purpose.
Future<ProviderContainer> _container({
  required bool accountEnabled,
  required _WireProbe probe,
  bool cloudEnabled = false,
  String? token = 'jwt-token',
}) async {
  final config = cloudEnabled
      ? _shippedConfig(accountEnabled: accountEnabled)
      : _cloudDisabledConfig(accountEnabled: accountEnabled);
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      appConfigProvider.overrideWithValue(config),
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
    test('consent + cloud flag + account + client is the only cloud '
        'combination', () {
      expect(
        selectTutorModelGateway(
          consent: const TutorConsent(modelUseGranted: true),
          cloudEnabled: true,
          accountEnabled: true,
          streamClient: Dio(),
        ),
        isA<RemoteTutorModelGateway>(),
      );
    });

    test('each missing precondition falls back to the local stub', () {
      final withoutConsent = selectTutorModelGateway(
        consent: const TutorConsent(),
        cloudEnabled: true,
        accountEnabled: true,
        streamClient: Dio(),
      );
      final withoutCloudFlag = selectTutorModelGateway(
        consent: const TutorConsent(modelUseGranted: true),
        cloudEnabled: false,
        accountEnabled: true,
        streamClient: Dio(),
      );
      final withoutAccount = selectTutorModelGateway(
        consent: const TutorConsent(modelUseGranted: true),
        cloudEnabled: true,
        accountEnabled: false,
        streamClient: Dio(),
      );
      final withoutClient = selectTutorModelGateway(
        consent: const TutorConsent(modelUseGranted: true),
        cloudEnabled: true,
        accountEnabled: true,
        streamClient: null,
      );

      expect(withoutConsent, isA<LocalTutorModelGatewayStub>());
      expect(
        withoutCloudFlag,
        isA<LocalTutorModelGatewayStub>(),
        reason:
            'aiTutorCloudEnabled is the build-level rollout gate — consent '
            'cannot open a capability the build does not ship',
      );
      expect(withoutAccount, isA<LocalTutorModelGatewayStub>());
      expect(withoutClient, isA<LocalTutorModelGatewayStub>());
    });

    test('a server that ANSWERS with the canned fake adapter, or with its '
        'tutor switched off, falls back to the local stub', () {
      final fakeAdapter = selectTutorModelGateway(
        consent: const TutorConsent(modelUseGranted: true),
        cloudEnabled: true,
        accountEnabled: true,
        streamClient: Dio(),
        capability: const TutorCloudCapability(
          enabled: true,
          provider: TutorCloudCapability.fakeProvider,
          model: TutorCloudCapability.fakeModel,
        ),
      );
      final tutorDisabled = selectTutorModelGateway(
        consent: const TutorConsent(modelUseGranted: true),
        cloudEnabled: true,
        accountEnabled: true,
        streamClient: Dio(),
        capability: const TutorCloudCapability(
          enabled: false,
          provider: 'anthropic',
          model: 'claude-sonnet-5',
        ),
      );

      expect(
        fakeAdapter,
        isA<LocalTutorModelGatewayStub>(),
        reason:
            'a scripted answer presented as a cloud tutor answer is a lie '
            'the student cannot detect',
      );
      expect(tutorDisabled, isA<LocalTutorModelGatewayStub>());
    });

    test('a real provider keeps the cloud, and an UNKNOWN capability leaves '
        'the other four conditions in force', () {
      final realProvider = selectTutorModelGateway(
        consent: const TutorConsent(modelUseGranted: true),
        cloudEnabled: true,
        accountEnabled: true,
        streamClient: Dio(),
        capability: const TutorCloudCapability(
          enabled: true,
          provider: 'anthropic',
          model: 'claude-sonnet-5',
        ),
      );
      final unknown = selectTutorModelGateway(
        consent: const TutorConsent(modelUseGranted: true),
        cloudEnabled: true,
        accountEnabled: true,
        streamClient: Dio(),
      );

      expect(realProvider, isA<RemoteTutorModelGateway>());
      expect(unknown, isA<RemoteTutorModelGateway>());
    });

    test('an unparseable capability body reads as the canned default, not '
        'as a real model', () {
      const body = <Object?, Object?>{'version': 'v1'};
      final capability = TutorCloudCapability.fromJson(body);

      expect(capability.enabled, isFalse);
      expect(capability.provider, TutorCloudCapability.fakeProvider);
      expect(capability.servesRealModel, isFalse);
      expect(
        selectTutorModelGateway(
          consent: const TutorConsent(modelUseGranted: true),
          cloudEnabled: true,
          accountEnabled: true,
          streamClient: Dio(),
          capability: capability,
        ),
        isA<LocalTutorModelGatewayStub>(),
      );
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
    test('granted consent on a cloud-flagged account build whose server '
        'runs a real provider selects the cloud', () async {
      final container = await _container(
        accountEnabled: true,
        probe: _WireProbe(body: _realCapabilityBody),
        cloudEnabled: true,
      );
      await container.read(tutorCloudCapabilityProvider.future);
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();

      final gateway = container.read(tutorModelGatewayFactoryProvider)(0);

      expect(gateway, isA<RemoteTutorModelGateway>());
    });

    // E-R29a (re-audit BLOCKER B1) — the cell R24 left behind said the
    // SHIPPED development build always lands on the stub. That was true, and
    // it was the bug: `LocalTutorModelGatewayStub.start()` always fails, so
    // the Coach in the only artifact a tester can install could not answer
    // anything. The build's own resolution is measured here, not a
    // hand-built flag set — `FeatureFlags.forShippedBuild(development)` is
    // literally what `AppBootstrap.run` hands `appConfigProvider`.
    test('the shipped development build streams to the CLOUD with consent, '
        'an account, a live client and a real server capability', () async {
      final probe = _WireProbe(body: _realCapabilityBody);
      final container = await _container(
        accountEnabled: true,
        probe: probe,
        cloudEnabled: true,
      );
      final capability = await container.read(
        tutorCloudCapabilityProvider.future,
      );
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();

      expect(container.read(tutorStreamClientProvider), isNotNull);
      expect(capability?.servesRealModel, isTrue);
      expect(
        container.read(tutorModelGatewayFactoryProvider)(0),
        isA<RemoteTutorModelGateway>(),
        reason:
            'all five conditions hold — this is the turn that must actually '
            'reach the backend gateway in the tester APK',
      );
      expect(
        probe.requests.map((request) => request.path),
        contains('/tutor/capability'),
        reason: 'a rolled-out build DOES ask the server what it runs',
      );
    });

    // …and each single missing precondition still lands on the stub, on that
    // very same shipped build. The rollout gate is not a consent, and it is
    // not a substitute for a real provider either.
    test('the same shipped build with no consent granted selects the local '
        'stub', () async {
      final probe = _WireProbe(body: _realCapabilityBody);
      final container = await _container(
        accountEnabled: true,
        probe: probe,
        cloudEnabled: true,
      );
      await container.read(tutorCloudCapabilityProvider.future);

      expect(
        container.read(tutorModelGatewayFactoryProvider)(0),
        isA<LocalTutorModelGatewayStub>(),
        reason:
            'ADR 0132 §1/§3: the build-time rollout gate never stands in '
            'for the student\'s own model-use consent',
      );
    });

    test('the same shipped build whose server answers `fake` selects the '
        'local stub', () async {
      final container = await _container(
        accountEnabled: true,
        probe: _WireProbe(body: _fakeCapabilityBody),
        cloudEnabled: true,
      );
      await container.read(tutorCloudCapabilityProvider.future);
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();

      expect(
        container.read(tutorModelGatewayFactoryProvider)(0),
        isA<LocalTutorModelGatewayStub>(),
        reason:
            'a deployment still running the canned adapter must not have '
            'its scripted reply presented as a cloud tutor answer',
      );
    });

    // The kill switch: the shipped build PLUS an explicit
    // `--dart-define=STRUMSIGHT_AI_TUTOR_CLOUD=false`. This is the flag-off
    // configuration a build command can actually produce, and a build whose
    // cloud tutor is not rolled out must not even probe the endpoint.
    test('an explicitly flag-off build selects the local stub and issues no '
        'capability request at all', () async {
      final probe = _WireProbe(body: _realCapabilityBody);
      final container = await _container(
        accountEnabled: true,
        probe: probe,
        cloudEnabled: false,
      );
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();

      expect(container.read(tutorStreamClientProvider), isNotNull);
      expect(
        container.read(tutorModelGatewayFactoryProvider)(0),
        isA<LocalTutorModelGatewayStub>(),
      );
      expect(
        await container.read(tutorCloudCapabilityProvider.future),
        isNull,
        reason:
            'a build whose cloud tutor is not rolled out does not even '
            'probe the capability endpoint',
      );
      expect(probe.requests, isEmpty);
    });

    test('a server still running the canned fake adapter selects the local '
        'stub, consent and flag notwithstanding', () async {
      final container = await _container(
        accountEnabled: true,
        probe: _WireProbe(body: _fakeCapabilityBody),
        cloudEnabled: true,
      );
      final capability = await container.read(
        tutorCloudCapabilityProvider.future,
      );
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();

      expect(capability?.provider, TutorCloudCapability.fakeProvider);
      expect(
        container.read(tutorModelGatewayFactoryProvider)(0),
        isA<LocalTutorModelGatewayStub>(),
      );
    });

    test('the default (no consent granted, gate closed) selects the local '
        'stub', () async {
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
        probe: _WireProbe(body: _realCapabilityBody),
        cloudEnabled: true,
      );
      container.read(tutorConsentControllerProvider.notifier).grantModelUse();

      final gateway = container.read(tutorModelGatewayFactoryProvider)(0);

      expect(gateway, isA<LocalTutorModelGatewayStub>());
    });

    test('revoking consent changes the NEXT attempt without rebuilding the '
        'factory', () async {
      final container = await _container(
        accountEnabled: true,
        probe: _WireProbe(body: _realCapabilityBody),
        cloudEnabled: true,
      );
      await container.read(tutorCloudCapabilityProvider.future);
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
