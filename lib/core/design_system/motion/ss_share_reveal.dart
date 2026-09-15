import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../foundations/ss_motion.dart';
import 'ss_motion_scope.dart';

/// Builds a shareable card up in front of the user (Ch18 spec §12): one
/// finite progress 0 → 1 over [duration] that every [SsRevealSlot] below it
/// maps onto its own window, so the wordmark comes first, the ↓/↑ arrows
/// "land" one by one and the footer closes the sequence.
///
/// The export pipeline is untouched: once the reveal completes (and always
/// when there is no [SsShareReveal] above a slot) a slot renders its child
/// as-is, so the `RepaintBoundary` capture is the final card. [onCompleted]
/// tells the host when that is — a share button waits for it.
///
/// Under reduced motion ([SsMotionScope]) the card is complete on the first
/// frame and [onCompleted] still fires, at the end of that frame.
final class SsShareReveal extends StatefulWidget {
  const SsShareReveal({
    super.key,
    required this.child,
    this.duration = SsMotion.celebration,
    this.onCompleted,
  });

  final Widget child;
  final Duration duration;
  final VoidCallback? onCompleted;

  /// The nearest reveal's progress, or 1 when there is none — a slot with
  /// no reveal above it is always complete.
  static double progressOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_RevealScope>();
    return scope?.progress ?? 1;
  }

  @override
  State<SsShareReveal> createState() => _SsShareRevealState();
}

final class _SsShareRevealState extends State<SsShareReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onCompleted?.call();
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (SsMotionScope.reduceMotionOf(context) ||
        widget.duration == Duration.zero) {
      _controller.value = 1;
      // Jumping to the end fires no `completed` transition; tell the host
      // once this frame is out so it never setState()s mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCompleted?.call();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) =>
          _RevealScope(progress: _controller.value, child: child!),
    );
  }
}

final class _RevealScope extends InheritedWidget {
  const _RevealScope({required this.progress, required super.child});

  final double progress;

  @override
  bool updateShouldNotify(_RevealScope old) => old.progress != progress;
}

/// One element of a revealed card: hidden until the reveal's progress
/// reaches [start], fully shown at [end]. Between the two it fades in and
/// either slides up a little or, with [landing], drops onto the card from
/// slightly larger (an arrow landing on its spot). At or past [end] — and
/// with no [SsShareReveal] above — the child is returned untouched.
final class SsRevealSlot extends StatelessWidget {
  const SsRevealSlot({
    super.key,
    required this.start,
    required this.end,
    required this.child,
    this.landing = false,
  }) : assert(
         start >= 0 && end <= 1 && start < end,
         'window must satisfy 0 ≤ start < end ≤ 1',
       );

  /// Window of the reveal's progress this slot animates over.
  final double start;
  final double end;

  /// Land from above at [landingScale] instead of sliding up.
  final bool landing;

  final Widget child;

  /// Starting scale of a [landing] slot.
  static const double landingScale = 1.6;

  /// How far (logical px) a non-landing slot rises while fading in.
  static const double rise = 10;

  /// [index] of [count] evenly spaced windows of [span] each between
  /// [from] and [to] — the arrows of a pattern, in order.
  static ({double start, double end}) windowFor(
    int index,
    int count, {
    double from = 0,
    double to = 1,
    double span = 0.12,
  }) {
    if (count <= 1) return (start: from, end: math.min(from + span, to));
    final lead = (to - from - span) / (count - 1);
    final start = from + lead * index;
    return (start: start, end: start + span);
  }

  /// This slot's own 0..1 progress for a reveal at [progress].
  double localProgress(double progress) {
    if (progress >= end) return 1;
    if (progress <= start) return 0;
    return SsMotion.enter.transform((progress - start) / (end - start));
  }

  @override
  Widget build(BuildContext context) {
    final t = localProgress(SsShareReveal.progressOf(context));
    if (t >= 1) return child;
    final scale = landing ? landingScale - (landingScale - 1) * t : 1.0;
    return Opacity(
      opacity: t,
      child: Transform(
        alignment: Alignment.center,
        transform: landing
            ? Matrix4.diagonal3Values(scale, scale, 1)
            : Matrix4.translationValues(0, (1 - t) * rise, 0),
        child: child,
      ),
    );
  }
}
