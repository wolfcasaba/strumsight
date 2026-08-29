import 'resource_consumer.dart';
import 'resource_priority.dart';

/// Why the arbiter denied a request.
///
/// Deliberately NOT a [FailureCode] (`lib/core/foundation/app_failure.dart`)
/// — a denial here is a scheduling outcome between coexisting consumers, not
/// an exclusive-resource error. The two coordinators' own busy codes
/// (`audio.session_busy`, `camera.session_busy`) are untouched and remain the
/// only source of truth for exclusive-resource contention (ADR 0476 D5).
enum ResourceDenialReason {
  /// An active, unsuspended consumer at the SAME priority already holds this
  /// tier. Equal priority never preempts (ADR 0476 D1).
  equalPriorityActive,
}

/// The arbiter's decision for one [ResourceArbiter.request] call — a closed,
/// `lib/core/resources`-local result type with an explicit reason value
/// (ADR 0476 D5).
sealed class ResourceDecision {
  const ResourceDecision();
}

/// The requester may proceed. [suspended] lists the active, strictly-lower
/// priority consumers the arbiter paused to make room for it — each one was
/// paused via [ResourceConsumer.pauseForHigherPriority], never revoked or
/// released (ADR 0476 D2).
final class ResourceGranted extends ResourceDecision {
  const ResourceGranted({this.suspended = const []});

  final List<ResourceConsumer> suspended;
}

/// The requester may NOT proceed; [reason] explains why. Nothing was
/// suspended or otherwise touched.
final class ResourceDenied extends ResourceDecision {
  const ResourceDenied(this.reason);

  final ResourceDenialReason reason;
}

/// Orders requests between registered [ResourceConsumer]s by
/// [ResourcePriority] (ADR 0476).
///
/// Sits above the exclusive audio/camera coordinators without knowing about
/// either of them — it only ever talks to the [ResourceConsumer] contract.
/// It never takes a lease away: no code path here calls a coordinator's
/// `revokeActive()` or another consumer's `release()` to make room for a
/// higher-priority request (D2). The only thing it does to a lower-priority
/// active consumer is pause it ([ResourceConsumer.pauseForHigherPriority]),
/// which that consumer can resume from later (D3).
final class ResourceArbiter {
  final List<ResourceConsumer> _consumers = [];

  /// Makes [consumer] known to the arbiter, so future [request] and
  /// [onMemoryPressure] calls can consider it. Registering does not activate
  /// it. Safe to call more than once for the same consumer.
  void register(ResourceConsumer consumer) {
    final known = _consumers.any((other) => identical(other, consumer));
    if (!known) _consumers.add(consumer);
  }

  /// Forgets [consumer]. Safe to call whether or not it is active.
  void unregister(ResourceConsumer consumer) {
    _consumers.removeWhere((other) => identical(other, consumer));
  }

  /// Requests activation for [consumer].
  ///
  /// Denied when an active, unsuspended consumer at the SAME priority
  /// already holds that tier (D1 — ties never preempt); nothing is suspended
  /// in that case. Otherwise every active, unsuspended, strictly-lower
  /// priority consumer is paused (never revoked or released), then
  /// [consumer]'s own [ResourceConsumer.acquire] runs.
  Future<ResourceDecision> request(ResourceConsumer consumer) async {
    final tie = _consumers.any(
      (other) =>
          !identical(other, consumer) &&
          other.isActive &&
          !other.isSuspended &&
          other.priority == consumer.priority,
    );
    if (tie) {
      return const ResourceDenied(ResourceDenialReason.equalPriorityActive);
    }

    final toSuspend = _consumers
        .where(
          (other) =>
              !identical(other, consumer) &&
              other.isActive &&
              !other.isSuspended &&
              consumer.priority.outranks(other.priority),
        )
        .toList(growable: false);
    for (final other in toSuspend) {
      await other.pauseForHigherPriority();
    }

    await consumer.acquire();
    return ResourceGranted(suspended: List.unmodifiable(toSuspend));
  }

  /// The arbiter's own, synchronous-entry memory-pressure signal (ADR 0476
  /// D4). Nothing on the tree calls this yet — no platform channel and no
  /// `WidgetsBindingObserver` back it; wiring a real low-memory source is a
  /// later round's job (ADR 0476 §0.0 R2).
  ///
  /// Pauses the single lowest-priority active, unsuspended consumer, if any.
  /// A caller under sustained pressure calls this repeatedly: each call sheds
  /// the next-lowest survivor, so the highest-priority active consumer is
  /// always the last one touched.
  Future<void> onMemoryPressure() async {
    final active = _consumers
        .where((consumer) => consumer.isActive && !consumer.isSuspended)
        .toList(growable: false);
    if (active.isEmpty) return;

    final lowest = active.reduce(
      (a, b) => a.priority.index >= b.priority.index ? a : b,
    );
    await lowest.pauseForHigherPriority();
  }

  /// Ends [consumer]'s work (calls its [ResourceConsumer.release]) and then
  /// resumes whichever suspended consumers are no longer outranked by any
  /// active, unsuspended one — the way back from [request]'s suspension,
  /// without ever taking or granting a lease itself (D2 unaffected: this
  /// only calls [ResourceConsumer.resume] on consumers the arbiter itself
  /// suspended earlier).
  Future<void> releaseConsumer(ResourceConsumer consumer) async {
    await consumer.release();
    await _resumeNoLongerOutranked();
  }

  /// The way back from a suspension caused by [onMemoryPressure]. The caller
  /// — whoever knows the memory-pressure signal has cleared — invokes this
  /// explicitly; the arbiter itself has no platform signal to react to.
  Future<void> onMemoryPressureRelieved() async {
    await _resumeNoLongerOutranked();
  }

  /// Resumes every suspended, still-active consumer that no active,
  /// unsuspended consumer currently outranks — highest priority first, so a
  /// resumed higher-priority consumer can keep a lower one suspended in the
  /// same pass (e.g. `cameraFeedback` resumes but still keeps `backgroundAi`
  /// suspended). A consumer still outranked by another active one stays
  /// suspended.
  Future<void> _resumeNoLongerOutranked() async {
    final suspended =
        _consumers
            .where((consumer) => consumer.isActive && consumer.isSuspended)
            .toList(growable: false)
          ..sort((a, b) => a.priority.index.compareTo(b.priority.index));

    for (final consumer in suspended) {
      final stillOutranked = _consumers.any(
        (other) =>
            !identical(other, consumer) &&
            other.isActive &&
            !other.isSuspended &&
            other.priority.outranks(consumer.priority),
      );
      if (!stillOutranked) await consumer.resume();
    }
  }
}
