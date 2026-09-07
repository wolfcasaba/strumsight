/// Tutor model-gateway SELECTION (R9/2).
///
/// R9/1 closed the consent gate on the request path; this file decides which
/// gateway a turn actually runs on. The rule is deliberately narrow and
/// fail-closed — the cloud gateway is chosen only when ALL of:
///
/// 1. the student granted model use (`tutorConsentControllerProvider`),
/// 2. the account layer is enabled for this build (`accountEnabledProvider`),
/// 3. an authenticated stream client exists,
///
/// and the local stub answers in every other case. The decision is re-made
/// on EVERY attempt (see [tutorModelGatewayFactoryProvider]), so a
/// mid-session revocation or a sign-out takes effect on the next turn
/// without rebuilding the chat controller.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/logging/logger_provider.dart';
import '../../../../core/network/auth_interceptor.dart';
import '../../../../core/network/dio_factory.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../auth/public.dart' show accountEnabledProvider;
import '../../application/orchestration/tutor_orchestrator.dart';
import '../../data/model_gateway/http_tutor_stream_transport.dart';
import '../../data/model_gateway/local_tutor_model_gateway_stub.dart';
import '../../data/model_gateway/remote_tutor_model_gateway.dart';
import '../../data/model_gateway/tutor_model_gateway.dart';
import '../../domain/models/tutor_consent.dart';
import 'tutor_privacy_providers.dart';
import 'tutor_providers.dart';

/// Builds the SSE transport client. Split out so tests can inject a Dio
/// carrying a recording `HttpClientAdapter` without reaching the network.
final tutorStreamDioFactoryProvider = Provider<DioFactory>((ref) {
  final config = ref.watch(appConfigProvider);
  return DioFactory(
    baseUrl: config.apiBaseUrl,
    appVersion: config.appVersion,
    logger: ref.watch(appLoggerProvider),
  );
});

/// Reads the stored bearer token for the tutor stream's [AuthInterceptor].
///
/// REVIEW NOTE (R9/2): the auth feature owns [StorageKeys.secureAuthToken]
/// (`lib/features/auth/data/token_store.dart`), and its `tokenStoreProvider`
/// is NOT part of `lib/features/auth/public.dart`. Reaching that provider
/// from here would be a cross-feature deep import the architecture gate
/// rejects, so this reads the same CORE secure-store key directly. It is a
/// deliberate, declared duplication of one key, not an accident: the clean
/// replacement is a six-line `accountStreamClientProvider` next to
/// `accountApiClientProvider` in the auth feature, after which this provider
/// is overridden with it and deleted. A missing/emptied token (signed out,
/// or cleared on logout) makes `AuthInterceptor` reject the request BEFORE
/// the transport adapter, so the path is fail-closed either way.
final tutorAccessTokenReaderProvider = Provider<AccessTokenReader>((ref) {
  final store = ref.watch(secureStoreProvider);
  return () => store.read(StorageKeys.secureAuthToken);
});

/// The authenticated SSE client, or null when this build has no account
/// layer (there is then nothing to authenticate a cloud turn with).
final tutorStreamClientProvider = Provider<Dio?>((ref) {
  if (!ref.watch(accountEnabledProvider)) return null;
  final factory = ref.watch(tutorStreamDioFactoryProvider);
  final client = factory.createTutorStreamClient(
    accountEnabled: true,
    readToken: ref.watch(tutorAccessTokenReaderProvider),
    // The tutor stream does not own the account session: it never advances
    // a generation, and a 401 here must not silently sign the student out
    // of the whole app (the account client owns that).
    readSessionGeneration: () => 0,
    onUnauthorized: (_) {},
  );
  ref.onDispose(client.close);
  return client;
});

/// The selection rule itself, as a pure function of the three inputs — so
/// the "cloud only with consent AND account" property is provable without a
/// container, a widget, or a socket.
TutorModelGateway selectTutorModelGateway({
  required TutorConsent consent,
  required bool accountEnabled,
  required Dio? streamClient,
}) {
  if (!consent.modelUseGranted) return LocalTutorModelGatewayStub();
  if (!accountEnabled) return LocalTutorModelGatewayStub();
  if (streamClient == null) return LocalTutorModelGatewayStub();
  return RemoteTutorModelGateway(
    transport: HttpTutorStreamTransport(dio: streamClient),
  );
}

/// Chooses the gateway for one attempt. `ref.read`, not `ref.watch`: the
/// decision is re-made on every attempt, so revoking consent or signing out
/// changes the NEXT turn without tearing down the conversation.
final tutorModelGatewayFactoryProvider =
    Provider<TutorModelGateway Function(int)>((ref) {
      return (attempt) => selectTutorModelGateway(
        consent: ref.read(tutorConsentControllerProvider),
        accountEnabled: ref.read(accountEnabledProvider),
        streamClient: ref.read(tutorStreamClientProvider),
      );
    });

/// The orchestrator the chat controller actually runs.
///
/// The boot layer supplies [tutorOrchestratorProvider] with the local stub
/// hardcoded; this re-composes the same context/knowledge/prompt pipeline
/// with the consent- and account-aware gateway factory above.
final tutorTurnOrchestratorProvider = Provider<TutorOrchestrator>((ref) {
  final base = ref.watch(tutorOrchestratorProvider);
  final factory = ref.watch(tutorModelGatewayFactoryProvider);
  final orchestrator = base.withGatewayFactory(factory);
  // This provider BUILDS the orchestrator, so this provider closes its
  // stream controllers. The boot-supplied `base` is disposed by its owner.
  ref.onDispose(() => unawaited(orchestrator.dispose()));
  return orchestrator;
});
