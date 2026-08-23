import 'package:flutter/widgets.dart';

import '../foundations/ss_motion.dart';
import 'ss_motion_scope.dart';

/// Common screen- and element-level transitions built from [SsMotion]
/// tokens. Every duration here traces back to a named [SsMotion] constant —
/// no transition invents its own raw millisecond value.
abstract final class SsTransitions {
  /// A route transition using the token-backed [SsMotion.routeTransition]
  /// duration and [SsMotion.emphasizedCurve] easing. Collapses to an
  /// instant cut when [context] resolves to reduced motion.
  static Route<T> route<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) {
    final duration = SsMotionScope.durationOf(
      context,
      SsMotion.routeTransition,
    );
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (duration == Duration.zero) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: SsMotion.emphasizedCurve,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }
}

/// Cross-fades between successive [child] instances using
/// [SsMotion.contentFade], collapsing to an instant swap when the ambient
/// [SsMotionScope] resolves to reduced motion.
final class SsContentFade extends StatelessWidget {
  const SsContentFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = SsMotionScope.durationOf(context, SsMotion.contentFade);
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: SsMotion.enter,
      switchOutCurve: SsMotion.exit,
      child: child,
    );
  }
}
