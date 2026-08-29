import 'resource_priority.dart';

/// A participant the [ResourceArbiter] can order and suspend without losing
/// its work (ADR 0476 D3/D6).
///
/// Deliberately abstract: no coordinator-specific type (audio, camera, local
/// AI) appears here or in the arbiter. A concrete consumer wraps whatever
/// exclusive resource it actually owns and decides for itself what pausing
/// means; the arbiter only ever calls these four methods.
abstract interface class ResourceConsumer {
  /// Where this consumer sits in the coexistence order.
  ResourcePriority get priority;

  /// True while the consumer is doing work — including while suspended (see
  /// [isSuspended]). False again only after [release].
  bool get isActive;

  /// True while paused for a higher-priority consumer or memory pressure. A
  /// consumer can be suspended only while [isActive].
  bool get isSuspended;

  /// Starts the consumer's work. The arbiter calls this once a
  /// [ResourceArbiter.request] is granted.
  Future<void> acquire();

  /// Stops the consumer's work for good — not resumable. Idempotent.
  Future<void> release();

  /// Pauses the consumer to free capacity for a higher-priority consumer or
  /// because of memory pressure.
  ///
  /// MUST preserve in-progress work — this is a pause, not a cancellation
  /// (ADR 0476 D3). A consumer that discards its state here (i.e. implements
  /// this as `cancel`) violates the contract. Idempotent.
  Future<void> pauseForHigherPriority();

  /// Continues a consumer paused by [pauseForHigherPriority], with its
  /// preserved state intact. Idempotent.
  Future<void> resume();
}
