/// Tutor model-gateway SELECTION (R9/2; cloud flag + capability, R24).
///
/// R9/1 closed the consent gate on the request path; this file decides which
/// gateway a turn actually runs on. The rule is deliberately narrow and
/// fail-closed — the cloud gateway is chosen only when ALL of:
///
/// 1. the student granted model use (`tutorConsentControllerProvider`),
/// 2. this build ships the cloud capability at all
///    (`FeatureFlags.aiTutorCloudEnabled`),
/// 3. the account layer is enabled for this build (`accountEnabledProvider`),
/// 4. an authenticated stream client exists,
/// 5. and the server has not ANSWERED that it runs the canned `fake`
///    adapter (or no tutor at all) — see [tutorCloudCapabilityProvider],
///
/// and the local stub answers in every other case. Condition 2 was the
/// 2026-09-07 re-audit's MAJOR M2: `aiTutorCloudEnabled` had zero consumers
/// in `lib/**`, so a consenting, signed-in student on the shipped
/// development build would have streamed turns to the cloud from a build
/// whose own flag says the cloud tutor is not rolled out
/// (`docs/release/ga-scope.md` — `postponed`, open `R-PRIV-01`).
///
/// The decision is re-made on EVERY attempt (see
/// [tutorModelGatewayFactoryProvider]), so a mid-session revocation or a
/// sign-out takes effect on the next turn without rebuilding the chat
/// controller.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../auth/public.dart'
    show accountEnabledProvider, accountStreamClientProvider;
import '../../application/orchestration/tutor_orchestrator.dart';
import '../../data/model_gateway/http_tutor_stream_transport.dart';
import '../../data/model_gateway/local_tutor_model_gateway_stub.dart';
import '../../data/model_gateway/remote_tutor_model_gateway.dart';
import '../../data/model_gateway/tutor_cloud_capability.dart';
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

/// What the server reports about its own tutor, or null when this build
/// cannot (or must not) ask: the cloud flag is off, or there is no
/// authenticated stream client.
///
/// The flag gate is deliberate — a build whose cloud tutor is not rolled out
/// does not even probe the endpoint. The probe itself carries no student
/// data (an authenticated GET with no body), so when it does run it is safe
/// to run before any turn; [tutorTurnOrchestratorProvider] kicks it off when
/// the chat is opened, so the answer is normally in hand before the first
/// send.
///
/// A probe that fails (offline, 404 because the tutor routes are not
/// mounted, malformed body) resolves to null = UNKNOWN, which leaves the
/// other four conditions in force rather than inventing an answer: an
/// unreachable server fails the turn itself, and that path already ends in
/// the deterministic local fallback.
final tutorCloudCapabilityProvider = FutureProvider<TutorCloudCapability?>((
  ref,
) async {
  if (!ref.watch(appConfigProvider).flags.aiTutorCloudEnabled) return null;
  final client = ref.watch(tutorStreamClientProvider);
  if (client == null) return null;
  final probed = await HttpTutorStreamTransport(dio: client).capability();
  return probed.valueOrNull;
});

/// The selection rule itself, as a pure function of its inputs — so the
/// "cloud only with consent AND the build's cloud flag AND an account AND a
/// server that runs a real model" property is provable without a container,
/// a widget, or a socket.
///
/// [capability] is the server's own answer, or null when it is UNKNOWN (not
/// probed yet, or the probe failed). A KNOWN capability that does not serve
/// a real model — the backend's canned `fake` adapter, or a tutor that is
/// switched off — selects the local stub, because a scripted answer
/// presented as a cloud tutor's answer is a lie the student cannot detect.
TutorModelGateway selectTutorModelGateway({
  required TutorConsent consent,
  required bool cloudEnabled,
  required bool accountEnabled,
  required Dio? streamClient,
  TutorCloudCapability? capability,
}) {
  if (!consent.modelUseGranted) return LocalTutorModelGatewayStub();
  if (!cloudEnabled) return LocalTutorModelGatewayStub();
  if (!accountEnabled) return LocalTutorModelGatewayStub();
  if (streamClient == null) return LocalTutorModelGatewayStub();
  if (capability != null && !capability.servesRealModel) {
    return LocalTutorModelGatewayStub();
  }
  return RemoteTutorModelGateway(
    transport: HttpTutorStreamTransport(dio: streamClient),
  );
}

/// Chooses the gateway for one attempt. `ref.read`, not `ref.watch`: the
/// decision is re-made on every attempt, so revoking consent, signing out or
/// a capability answer that has arrived meanwhile changes the NEXT turn
/// without tearing down the conversation.
final tutorModelGatewayFactoryProvider =
    Provider<TutorModelGateway Function(int)>((ref) {
      return (attempt) => selectTutorModelGateway(
        consent: ref.read(tutorConsentControllerProvider),
        cloudEnabled: ref.read(appConfigProvider).flags.aiTutorCloudEnabled,
        accountEnabled: ref.read(accountEnabledProvider),
        streamClient: ref.read(tutorStreamClientProvider),
        capability: ref.read(tutorCloudCapabilityProvider).value,
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
  // Start the capability probe when the chat's orchestrator is built, so
  // the server's own answer is normally in hand before the first send. A
  // `listen` with an empty callback, not a `watch`: it keeps the probe
  // alive for this orchestrator's lifetime, while a resolved answer must
  // NOT rebuild — and therefore dispose — a live orchestrator in the middle
  // of a conversation. The factory re-reads the value on every attempt.
  ref.listen(tutorCloudCapabilityProvider, (_, _) {});
  final orchestrator = base.withGatewayFactory(factory);
  // This provider BUILDS the orchestrator, so this provider closes its
  // stream controllers. The boot-supplied `base` is disposed by its owner.
  ref.onDispose(() => unawaited(orchestrator.dispose()));
  return orchestrator;
});
