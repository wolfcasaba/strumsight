import 'package:flutter/widgets.dart';

import '../foundations/ss_motion.dart';
import 'ss_motion_scope.dart';

/// Lays [children] out in a column and lets them enter one after another —
/// a fade plus a short upward slide, each item [stagger] behind the previous
/// (Ch18 spec §0.2). One finite [AnimationController] drives every item, so
/// the whole entrance is one gesture and `pumpAndSettle` terminates.
///
/// Under reduced motion ([SsMotionScope]) every child is fully visible on
/// the first frame — the layout is identical, only the motion is gone.
/// Theme-agnostic: reads no theme extension, so legacy `AppTheme` screens
/// can use it.
final class SsStaggeredEntrance extends StatefulWidget {
  const SsStaggeredEntrance({
    super.key,
    required this.children,
    this.stagger = SsMotion.stagger,
    this.itemDuration = SsMotion.contentFade,
    this.slideOffset = 12,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;

  /// Delay between consecutive items.
  final Duration stagger;

  /// Each item's own fade/slide length.
  final Duration itemDuration;

  /// How far (logical px) an item slides up while fading in.
  final double slideOffset;

  final CrossAxisAlignment crossAxisAlignment;

  /// The whole entrance's length: the last item starts `(count − 1) ×
  /// stagger` in and takes [itemDuration]. Pure, for tests and callers.
  static Duration totalDuration(
    int count, {
    Duration stagger = SsMotion.stagger,
    Duration itemDuration = SsMotion.contentFade,
  }) {
    if (count <= 0) return Duration.zero;
    return itemDuration + stagger * (count - 1);
  }

  @override
  State<SsStaggeredEntrance> createState() => _SsStaggeredEntranceState();
}

final class _SsStaggeredEntranceState extends State<SsStaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total);
  }

  Duration get _total => SsStaggeredEntrance.totalDuration(
    widget.children.length,
    stagger: widget.stagger,
    itemDuration: widget.itemDuration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (SsMotionScope.reduceMotionOf(context) || _total == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(SsStaggeredEntrance old) {
    super.didUpdateWidget(old);
    if (!_controller.isCompleted) _controller.duration = _total;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Item [i]'s slice of the shared controller: it starts `i × stagger` in
  /// and lasts [SsStaggeredEntrance.itemDuration], as a 0..1 [Interval].
  Interval _intervalFor(int i, int totalMicros) {
    if (totalMicros == 0) return const Interval(0, 1, curve: SsMotion.enter);
    final start = (widget.stagger * i).inMicroseconds / totalMicros;
    final end = (widget.stagger * i + widget.itemDuration).inMicroseconds;
    return Interval(start, end / totalMicros, curve: SsMotion.enter);
  }

  @override
  Widget build(BuildContext context) {
    final total = _total.inMicroseconds;
    final children = widget.children;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.crossAxisAlignment,
      children: [
        for (var i = 0; i < children.length; i++)
          _StaggeredItem(
            controller: _controller,
            interval: _intervalFor(i, total),
            slideOffset: widget.slideOffset,
            child: children[i],
          ),
      ],
    );
  }
}

final class _StaggeredItem extends StatelessWidget {
  const _StaggeredItem({
    required this.controller,
    required this.interval,
    required this.slideOffset,
    required this.child,
  });

  final AnimationController controller;
  final Interval interval;
  final double slideOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final t = interval.transform(controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * slideOffset),
            child: child,
          ),
        );
      },
    );
  }
}
