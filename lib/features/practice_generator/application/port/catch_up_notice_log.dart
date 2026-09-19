/// Remembers whether the non-shaming catch-up explainer has already been
/// offered for a given plan revision (ADR 0269 §5, E07-R27 A8).
///
/// ADR 0269 forbids a backlog AND forbids shaming copy. A banner that
/// reappears on every visit to the Today screen is a third kind of pressure
/// the ADR's tone rule exists to prevent, so the explainer is offered ONCE
/// per plan revision: the learner either reads it or says "Got it", and the
/// Today screen stops raising it until the plan is revised (a new revision
/// is a new plan state, so the explanation is worth offering again).
///
/// The port is deliberately narrow — two calls, keyed by an opaque revision
/// key the caller builds. Reads are SYNCHRONOUS because the whole storage
/// layer is (`KeyValueStore`'s own contract): a `StatelessWidget` build can
/// therefore ask "has this already been offered?" without an async gap that
/// would flash the notice for one frame and then remove it.
library;

/// The two-call contract the Today screen needs.
abstract interface class CatchUpNoticeLog {
  /// Whether [revisionKey] has already had its catch-up offer acknowledged.
  bool wasAcknowledged(String revisionKey);

  /// Records that [revisionKey]'s offer was acknowledged — either because
  /// the learner opened the explainer or because they dismissed it.
  Future<void> acknowledge(String revisionKey);
}

/// Process-local default, used when no persistent log is injected.
///
/// This is the DEFAULT, never the production binding: the composition root
/// (`practice_generator_providers.dart`) injects the `KeyValueStore`-backed
/// log. A test that pumps the screen directly gets this one, which forgets
/// everything when the object goes away — honest for a test, and honest as
/// a fallback too, because the worst case is that the offer is made again,
/// never that a learner's own content is lost.
final class InMemoryCatchUpNoticeLog implements CatchUpNoticeLog {
  final Set<String> _acknowledged = <String>{};

  @override
  bool wasAcknowledged(String revisionKey) =>
      _acknowledged.contains(revisionKey);

  @override
  Future<void> acknowledge(String revisionKey) async {
    _acknowledged.add(revisionKey);
  }
}
