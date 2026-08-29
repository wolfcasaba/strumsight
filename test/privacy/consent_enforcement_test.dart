// E12-R17 — consent enforcement (ADR 0479 D2/D3): every one of the three
// channels that can actually send data today is proven, on the real turn/
// wire path (never a screen render — L140), to (a) not send once its own
// consent switch is off, and (b) stop sending the moment that switch flips
// mid-session, with no `ProviderContainer`/orchestrator rebuild in between
// (ADR 0132's "azonnal hat" requirement — A6).
//
// The fourth egress route (Community media, `CommunityMediaUploader`) has no
// production construction site in `lib/**` (§0.0.A.2) — it cannot be turn-
// path tested until a later round wires it, and is `wired: false` in
// docs/privacy/data-inventory.yaml.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/core/network/dio_factory.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_assembler.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_command.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_action_validator.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_orchestrator.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_template.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_version.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/tutor_prompt_builder.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_index.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_retriever.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/fake_tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_consent.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_response_mode.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_request.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/diagnostics/data/diagnostics_uploader.dart';
import 'package:strumsight/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:strumsight/features/settings/data/settings_repository.dart';
import 'package:strumsight/features/settings/providers/settings_sync.dart';
import 'package:strumsight/core/theme/theme_mode_provider.dart';

import '../support/fake_auth.dart';
import '../support/fake_settings.dart';
import '../support/preference_store.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('A3 — tutor turn path never reaches the model gateway without '
      'model-use consent (turn-path measurement, not a screen render — '
      'L140)', () {
    test('a turn sent with modelUseGranted: false is rejected before a '
        'gateway is ever created', () async {
      var gatewayCalls = 0;
      final orchestrator = _tutorOrchestrator((attempt) {
        gatewayCalls++;
        return FakeTutorModelGateway(script: const <FakeGatewayStep>[]);
      });

      final transition = await orchestrator.dispatch(
        SendTutorMessage(_tutorRequest(consent: const TutorConsent())),
      );

      expect(transition.isRejected, isFalse);
      expect(orchestrator.state.status, TutorTurnStatus.consentRevoked);
      expect(
        gatewayCalls,
        0,
        reason:
            'revoked consent must short-circuit before the gateway '
            'factory is even invoked — never mind started',
      );
      await orchestrator.dispose();
    });
  });

  group('A6 (tutor) — revoking model-use consent stops the NEXT turn on '
      'the SAME orchestrator instance, no restart', () {
    test('turn 1 (granted) reaches the gateway; turn 2 (revoked, same session) '
        'does not', () async {
      final clock = FakeClock();
      var gatewayCalls = 0;
      final orchestrator = _tutorOrchestrator((attempt) {
        gatewayCalls++;
        return FakeTutorModelGateway(
          clock: clock,
          script: <FakeGatewayStep>[
            FakeGatewayDelta(_validTutorOutput(), sequence: 1),
            const FakeGatewayDone(sequence: 2),
          ],
        );
      });

      await orchestrator.dispatch(
        SendTutorMessage(
          _tutorRequest(
            requestId: 'turn-1',
            consent: const TutorConsent(modelUseGranted: true),
          ),
        ),
      );
      clock.advance(Duration.zero);
      await _settle();

      expect(orchestrator.state.status, TutorTurnStatus.completed);
      expect(gatewayCalls, 1);

      // Same orchestrator, same process — the user revoked consent in the
      // privacy screen between two turns of one live session.
      await orchestrator.dispatch(
        SendTutorMessage(
          _tutorRequest(requestId: 'turn-2', consent: const TutorConsent()),
        ),
      );

      expect(orchestrator.state.status, TutorTurnStatus.consentRevoked);
      expect(
        gatewayCalls,
        1,
        reason: 'the revoked second turn must not create a second gateway',
      );
      await orchestrator.dispose();
    });
  });

  group('A4 — diagnostics upload never reaches the transport adapter '
      'without diagnosticsConsentProvider granted', () {
    test(
      'upload() with consent false never touches the wire adapter',
      () async {
        final probe = _WireProbe();
        final container = ProviderContainer(
          overrides: [
            appConfigProvider.overrideWithValue(_diagnosticsConfig()),
            diagnosticsConsentProvider.overrideWithValue(false),
            diagnosticsUploaderProvider.overrideWithValue(
              DiagnosticsUploader(
                client: ApiClient(Dio()..httpClientAdapter = probe),
                diagToken: 'test-token',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(diagnosticsUploadProvider.notifier).upload(
          _diagnosticResult(),
          const [0.1],
          44100,
        );

        expect(probe.requests, isEmpty);
        expect(
          container.read(diagnosticsUploadProvider),
          DiagnosticsUploadStatus.idle,
        );
      },
    );
  });

  group('A6 (diagnostics) — revoking upload consent stops the NEXT upload '
      'in the SAME container, no restart', () {
    test('upload 1 (consent true) reaches the wire; upload 2 (consent flipped '
        'false, same container) does not', () async {
      final probe = _WireProbe();
      final consent = NotifierProvider<_MutableBoolNotifier, bool>(
        _MutableBoolNotifier.new,
      );
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(_diagnosticsConfig()),
          diagnosticsConsentProvider.overrideWith((ref) => ref.watch(consent)),
          diagnosticsUploaderProvider.overrideWithValue(
            DiagnosticsUploader(
              client: ApiClient(Dio()..httpClientAdapter = probe),
              diagToken: 'test-token',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(diagnosticsUploadProvider.notifier).upload(
        _diagnosticResult(),
        const [0.1],
        44100,
      );
      expect(probe.requests, hasLength(1));

      // The user flips Lab-mode off mid-session — no container rebuild,
      // no app restart.
      container.read(consent.notifier).set(false);

      await container.read(diagnosticsUploadProvider.notifier).upload(
        _diagnosticResult(),
        const [0.2],
        44100,
      );

      expect(
        probe.requests,
        hasLength(1),
        reason:
            'the second, post-revocation upload must not reach the '
            'wire — the consent check re-reads the live provider value, '
            'not a snapshot taken at boot',
      );
    });
  });

  group('A5\' — account-session revocation stops the Community write path '
      '(challenge/profile/relationship repos ride the shared '
      'accountApiClientProvider)', () {
    test(
      'a profile update sent while signed in reaches the wire; the same '
      'call after logout does not — same container, no restart (A6)',
      () async {
        final probe = _WireProbe();
        final container = ProviderContainer(
          overrides: [
            appConfigProvider.overrideWithValue(_accountConfig()),
            tokenStoreProvider.overrideWithValue(FakeTokenStore()),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            accountDioFactoryProvider.overrideWith(
              (ref) => probe.dioFactory(ref.watch(appConfigProvider)),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(authControllerProvider.notifier)
            .login('player@strumsight.app', 'correct horse');
        await _settle();
        expect(container.read(authControllerProvider).value, isNotNull);

        final apiClient = container.read(accountApiClientProvider);
        expect(
          apiClient,
          isNotNull,
          reason: 'account layer is enabled and a session is established',
        );
        final profileRepo = HttpCommunityProfileRepository(apiClient!);

        await profileRepo.updateProfile(displayName: 'Alex');
        expect(
          probe.requests,
          hasLength(1),
          reason:
              'a signed-in Community write must reach the transport '
              'adapter',
        );

        // Session revocation, same container/process — no rebuild, no
        // restart (A6).
        await container.read(authControllerProvider.notifier).logout();
        await _settle();

        await profileRepo.updateProfile(displayName: 'Alex (should not send)');

        expect(
          probe.requests,
          hasLength(1),
          reason:
              'AuthInterceptor must reject the post-logout request '
              '(cleared credentials) before it ever reaches the wire '
              'adapter — the request count must not grow',
        );
      },
    );
  });

  group('A5\' — account-session revocation stops settings-sync', () {
    test('a local settings edit while signed in triggers a push; the same '
        'kind of edit after logout does not — same container, no restart '
        '(A6)', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = FakeSettingsRepository();
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(_accountConfig()),
          ...preferenceOverrides(),
          tokenStoreProvider.overrideWithValue(FakeTokenStore()),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          settingsRepositoryProvider.overrideWithValue(settings),
          settingsSyncDebounceProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(container.dispose);
      container.read(settingsSyncProvider); // instantiate the listener

      await container
          .read(authControllerProvider.notifier)
          .login('player@strumsight.app', 'correct horse');
      await _settle(); // initial pull settles

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      await _settle();

      expect(
        settings.updates,
        isNotEmpty,
        reason: 'a signed-in local edit must push to the backend',
      );
      final pushesWhileSignedIn = settings.updates.length;

      // Session revocation, same container/process.
      await container.read(authControllerProvider.notifier).logout();
      await _settle();

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      await _settle();

      expect(
        settings.updates,
        hasLength(pushesWhileSignedIn),
        reason:
            'SettingsSync._onLocalChange short-circuits on '
            '!_signedIn — a post-logout local edit must never reach '
            'SettingsRepository.update',
      );
    });
  });

  // -------------------------------------------------------------------------
  // MAJOR-3 (E12-R17 javító kör #1) — the machine guard against the measured
  // gap: reduceTutorTurn's consent gate is sound, but the ONLY production
  // TutorTurnRequest builder (`_previewTurnRequest`,
  // lib/features/ai_tutor/presentation/providers/tutor_providers.dart:433,438)
  // hardcodes `consent: const TutorConsent(modelUseGranted: true)` instead of
  // reading `tutorConsentControllerProvider`. Today that is a latent gap, not
  // a leak, because nothing in lib/** also constructs an
  // HttpTutorStreamTransport (`wired: false` in the inventory). This group
  // pins BOTH measured facts and proves the guard's own logic turns red for
  // exactly the regression a future round could introduce (wiring the cloud
  // transport without also fixing the request builder) — lib/** itself is
  // out of scope for this round (§2), so the guard cannot be exercised by
  // actually flipping production code; it is exercised as a pure function
  // fed synthetic booleans, plus a real-tree cell that measures today's
  // actual values.
  group('MAJOR-3 guard — the tutor cloud gateway must not become reachable '
      'while the production request-builder still hardcodes '
      'modelUseGranted: true', () {
    test('pure guard: wiring the cloud gateway while the hardcode is still '
        'present is UNSOUND (the exact MAJOR-3 regression)', () {
      expect(
        tutorTurnConsentWiringIsSound(
          cloudGatewayHasConstructionSite: true,
          requestBuilderHardcodesGrantedTrue: true,
        ),
        isFalse,
      );
    });

    test('pure guard: wiring the cloud gateway AFTER the hardcode is '
        'removed is sound', () {
      expect(
        tutorTurnConsentWiringIsSound(
          cloudGatewayHasConstructionSite: true,
          requestBuilderHardcodesGrantedTrue: false,
        ),
        isTrue,
      );
    });

    test("pure guard: today's measured state (gateway unwired, hardcode "
        'present) is sound — a latent gap only, not a live leak', () {
      expect(
        tutorTurnConsentWiringIsSound(
          cloudGatewayHasConstructionSite: false,
          requestBuilderHardcodesGrantedTrue: true,
        ),
        isTrue,
      );
    });

    test('real tree: HttpTutorStreamTransport has no construction site outside '
        'its own declaring file, and _previewTurnRequest still hardcodes '
        'modelUseGranted: true — both measured facts are pinned so either '
        'silently changing trips this cell', () {
      final repository = Directory.current;
      final libDir = Directory('${repository.path}/lib');
      final declaringFile = File(
        '${repository.path}/lib/features/ai_tutor/data/model_gateway/'
        'http_tutor_stream_transport.dart',
      ).absolute.path;
      final constructionPattern = RegExp(r'\bHttpTutorStreamTransport\s*\(');
      final gatewayConstructedElsewhere = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.absolute.path != declaringFile)
          .any((f) => constructionPattern.hasMatch(f.readAsStringSync()));

      final providersSource = File(
        '${repository.path}/lib/features/ai_tutor/presentation/providers/'
        'tutor_providers.dart',
      ).readAsStringSync();
      final hardcodesGrantedTrue = RegExp(
        r'consent:\s*const\s+TutorConsent\(modelUseGranted:\s*true\)',
      ).hasMatch(providersSource);

      // Pin today's exact measured state (E12-R17 javító kör #1 §2 —
      // fixing THIS gap is explicitly out of scope; the pin is what makes
      // a silent regression loud instead of invisible).
      expect(gatewayConstructedElsewhere, isFalse);
      expect(hardcodesGrantedTrue, isTrue);

      // ...and feeding those exact measured values through the pure guard
      // must be sound today, and would stop being sound the moment
      // gatewayConstructedElsewhere flips to true without
      // hardcodesGrantedTrue also flipping to false.
      expect(
        tutorTurnConsentWiringIsSound(
          cloudGatewayHasConstructionSite: gatewayConstructedElsewhere,
          requestBuilderHardcodesGrantedTrue: hardcodesGrantedTrue,
        ),
        isTrue,
      );
    });
  });
}

/// The MAJOR-3 guard's pure logic, kept separate from the real-tree
/// measurement above so the regression it exists to catch can be proven
/// red/green without lib/** needing to actually change.
bool tutorTurnConsentWiringIsSound({
  required bool cloudGatewayHasConstructionSite,
  required bool requestBuilderHardcodesGrantedTrue,
}) {
  if (!cloudGatewayHasConstructionSite) return true; // latent gap only.
  return !requestBuilderHardcodesGrantedTrue;
}

// ---------------------------------------------------------------------------
// Tutor fixtures (mirrors test/features/ai_tutor/application/tutor_orchestrator_test.dart's
// established construction shape — this file builds its own copy so the
// round's acceptance evidence does not depend on another round's test file).
// ---------------------------------------------------------------------------

TutorOrchestrator _tutorOrchestrator(
  TutorModelGateway Function(int) gatewayForAttempt,
) => TutorOrchestrator(
  contextAssembler: const TutorContextAssembler(),
  knowledgeRetriever: KnowledgeRetriever(index: const KnowledgeIndex.empty()),
  promptBuilder: TutorPromptBuilder(templateLoader: _TutorTemplateLoader()),
  gatewayForAttempt: gatewayForAttempt,
);

TutorTurnRequest _tutorRequest({
  String requestId = 'request-1',
  TutorConsent consent = const TutorConsent(modelUseGranted: true),
}) => TutorTurnRequest(
  requestId: TutorRequestId(requestId),
  conversationId: TutorConversationId('conversation-1'),
  message: 'How can I improve my rhythm?',
  createdAt: DateTime.utc(2026, 8, 5),
  consent: consent,
  purpose: ContextPurpose.generalQuestion,
  contextFields: const <TutorContextField>[],
  retrievalQuery: const KnowledgeRetrievalQuery(
    queryText: 'rhythm',
    locale: 'en',
  ),
  responseLocale: 'en',
  responseMode: TutorResponseMode.concise,
  toolPolicy: TutorToolTurnPolicy(
    allowedToolNames: const <String>{'getContextField', 'summarizeContext'},
    allowedPermissions: TutorToolPermission.values,
  ),
  actionContext: TutorActionValidationContext(
    now: DateTime.utc(2026, 8, 5),
    availableCapabilities: const [],
    activeSessionIds: const <String>[],
    songRevisions: const {},
  ),
);

String _validTutorOutput() => jsonEncode(<String, Object?>{
  'answerBlocks': <Object?>[],
  'claims': <Object?>[],
  'actions': <Object?>[],
  'followUpSuggestions': <Object?>[],
  'safetyNotices': <Object?>[],
  'memoryCandidates': <Object?>[],
});

final class _TutorTemplateLoader implements PromptTemplateLoader {
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

// ---------------------------------------------------------------------------
// Diagnostics fixtures.
// ---------------------------------------------------------------------------

AppConfig _diagnosticsConfig() => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: const FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: true,
    labModeAvailable: true,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'debug',
  appVersion: 'test',
);

AnalyzeResult _diagnosticResult() => const AnalyzeResult(
  durationSec: 1,
  bpm: 120,
  chords: [TimelineChord(label: 'C', startSec: 0, endSec: 1)],
  strums: [],
  diagnostics: MlChordDiagnostics(
    mlChords: [TimelineChord(label: 'C', startSec: 0, endSec: 1)],
    agreement: 1,
  ),
);

/// A mutable boolean provider a test can flip mid-session, standing in for
/// the persisted Lab-mode setting `diagnosticsConsentProvider` is bound to
/// in production (`labModeProvider`, `lib/main.dart`).
class _MutableBoolNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

// ---------------------------------------------------------------------------
// Account/community/settings fixtures.
// ---------------------------------------------------------------------------

AppConfig _accountConfig() => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags.forEnvironment(
    AppEnvironment.development,
    accountEnabled: true,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'debug',
  appVersion: 'test',
);

// ---------------------------------------------------------------------------
// A near-wire probe: an `HttpClientAdapter` that only ever sees a request
// AFTER `AuthInterceptor`/consent-gate logic has already let it through.
// Reused across the diagnostics and account-client tests as the actual
// transport boundary measurement (never a screen render — L140).
// ---------------------------------------------------------------------------

final class _WireProbe implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  DioFactory dioFactory(AppConfig config) => DioFactory(
    baseUrl: config.apiBaseUrl,
    appVersion: config.appVersion,
    logger: const NoopAppLogger(),
    adapter: this,
    correlationIdGenerator: () => 'consent-enforcement-probe',
  );
}
