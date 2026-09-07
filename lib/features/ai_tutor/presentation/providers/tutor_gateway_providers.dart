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

import '../../../auth/public.dart'
    show accountEnabledProvider, accountStreamClientProvider;
import '../../application/orchestration/tutor_orchestrator.dart';
import '../../data/model_gateway/http_tutor_stream_transport.dart';
import '../../data/model_gateway/local_tutor_model_gateway_stub.dart';
import '../../data/model_gateway/remote_tutor_model_gateway.dart';
import '../../data/model_gateway/tutor_model_gateway.dart';
import '../../domain/models/tutor_consent.dart';
import 'tutor_privacy_providers.dart';
import 'tutor_providers.dart';

/// The authenticated SSE client the cloud gateway rides, or null when this
/// build has no account layer.
///
/// A thin alias over the auth feature's [accountStreamClientProvider] on
/// purpose: the session — token, generation, 401 invalidation — belongs to
/// auth, and the tutor must never grow its own copy of it (R9/2 briefly read
/// the secure-store key directly; R9/3 replaced that with this seam). It
/// stays a separate provider only so a tutor test can substitute a client
/// without standing up the whole auth graph.
final tutorStreamClientProvider = Provider<Dio?>(
  (ref) => ref.watch(accountStreamClientProvider),
);

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
