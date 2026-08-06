import '../../data/knowledge/knowledge_retriever.dart';
import '../../domain/models/tutor_consent.dart';
import '../../domain/models/tutor_source_ref.dart';
import '../controller/tutor_state.dart';
import '../debrief/deterministic_coach.dart';
import '../debrief/session_debrief_builder.dart';

/// Honest capability axis for the current tutor environment.
///
/// The resolver combines state, consent, and failure codes into a set of
/// capabilities that the UI can surface. A capability that is *not* present
/// must never be implied by UI text or imagery.
enum TutorCapability {
  /// Full cloud AI is reachable and consent is granted.
  online,

  /// The device has no network or the gateway is unavailable; only local
  /// computation is possible.
  offline,

  /// Model-use consent has not been granted by the user.
  consent,

  /// The usage quota for this user has been exhausted.
  limit,
}

/// Resolved result from [LocalTutorFallback].
///
/// This is a pure data object with no I/O or side effects. Every field is
/// populated deterministically from the inputs.
final class LocalTutorFallbackResult {
  LocalTutorFallbackResult({
    required this.capabilities,
    this.debriefOutput,
    Iterable<TutorSourceRef> retrievedSources = const <TutorSourceRef>[],
  }) : retrievedSources = List<TutorSourceRef>.unmodifiable(retrievedSources);

  /// Honest capability set for the current environment.
  final Set<TutorCapability> capabilities;

  /// Deterministic coaching output, always produced when the fallback runs.
  final LocalizedCoachingOutput? debriefOutput;

  /// Knowledge sources retrieved from the local index, if available.
  final List<TutorSourceRef> retrievedSources;
}

/// Produces deterministic offline fallback content from the tutor state.
///
/// This class is pure: it has no network access, no gateway reference, and
/// all its methods are synchronous. It consumes the already-emitted
/// [TutorTurnStatus.fallback] / [TutorTurnStatus.consentRevoked] /
/// [TutorTurnStatus.usageLimit] states and converts them into honest,
/// useful content without ever reaching the cloud.
final class LocalTutorFallback {
  const LocalTutorFallback({
    required this.coach,
    required this.builder,
    required this.retriever,
    required this.localizationLookup,
  });

  /// Selects one grounded focus from a deterministic fact list.
  final DeterministicCoach coach;

  /// Builds facts that a coach may prioritize.
  final SessionDebriefBuilder builder;

  /// Retrieves knowledge from the local, offline [KnowledgeIndex].
  final KnowledgeRetriever retriever;

  /// Localized-string lookup matching the application's ARB contract.
  final String Function(String key) localizationLookup;

  /// Resolves capabilities, debrief, and knowledge from the current state.
  ///
  /// All computation is synchronous and deterministic. This method never
  /// initiates network I/O, never calls a gateway, and never returns a
  /// capability that is not honestly supported by the inputs.
  LocalTutorFallbackResult resolve({
    required TutorTurnStatus status,
    required TutorConsent consent,
    String? failureCode,
    KnowledgeRetrievalQuery? retrievalQuery,
    SessionDebriefInput? debriefInput,
  }) {
    final capabilities = _resolveCapabilities(
      status: status,
      consent: consent,
      failureCode: failureCode,
    );

    final debriefOutput = _buildDebrief(debriefInput);

    final retrievedSources = retrievalQuery != null
        ? retriever.retrieve(retrievalQuery)
        : const <TutorSourceRef>[];

    return LocalTutorFallbackResult(
      capabilities: capabilities,
      debriefOutput: debriefOutput,
      retrievedSources: retrievedSources,
    );
  }

  // ── Capability resolution ────────────────────────────────────────────

  Set<TutorCapability> _resolveCapabilities({
    required TutorTurnStatus status,
    required TutorConsent consent,
    String? failureCode,
  }) {
    final caps = <TutorCapability>{};

    final bool isGatewayUnavailable =
        failureCode == 'tutor.model_gateway.unavailable';

    // Consent check — highest priority
    if (!consent.modelUseGranted) {
      caps.add(TutorCapability.consent);
      caps.add(TutorCapability.offline);
      return caps;
    }

    // Status-based
    switch (status) {
      case TutorTurnStatus.usageLimit:
        caps.add(TutorCapability.limit);
      case TutorTurnStatus.fallback:
      case TutorTurnStatus.consentRevoked:
      case TutorTurnStatus.failed:
        caps.add(TutorCapability.offline);
      case TutorTurnStatus.completed:
      case TutorTurnStatus.idle:
      case TutorTurnStatus.cancelled:
        if (isGatewayUnavailable) {
          caps.add(TutorCapability.offline);
        } else {
          caps.add(TutorCapability.online);
        }
      default:
        if (isGatewayUnavailable) {
          caps.add(TutorCapability.offline);
        } else {
          caps.add(TutorCapability.online);
        }
    }

    return caps;
  }

  // ── Debrief construction ─────────────────────────────────────────────

  LocalizedCoachingOutput? _buildDebrief(SessionDebriefInput? input) {
    if (input == null) {
      return null;
    }
    final facts = builder.build(input);
    final insight = coach.coach(facts);
    return coach.localize(insight: insight, lookup: localizationLookup);
  }
}
