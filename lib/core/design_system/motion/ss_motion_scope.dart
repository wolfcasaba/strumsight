import 'package:flutter/widgets.dart';

/// Resolves whether motion should be reduced, combining the platform
/// accessibility setting ([MediaQuery.disableAnimationsOf]) with an optional
/// app-level override.
///
/// The app-level override is injected as [appOverride] rather than read
/// from a concrete preferences source: the design system does not import
/// `lib/features/**` (ADR 0274). A later round wires a concrete source
/// (e.g. `GamificationPreferences.reduceMotion`) by wrapping the widget
/// tree in an [SsMotionScope] with that value.
///
/// Resolution has three cells, verified by [ss_motion_scope_test.dart]:
/// * `appOverride == true` — reduced, regardless of the system setting.
/// * `appOverride == false` — NOT reduced, even if the system requests it.
/// * `appOverride == null` — the system setting decides.
@immutable
final class SsMotionScope extends InheritedWidget {
  const SsMotionScope({
    super.key,
    required this.appOverride,
    required super.child,
  });

  /// `null` defers to the platform accessibility setting; a non-null value
  /// overrides it in both directions.
  final bool? appOverride;

  /// Resolves the effective reduced-motion state for [context], combining
  /// the nearest [SsMotionScope.appOverride] (if any) with
  /// [MediaQuery.disableAnimationsOf].
  static bool reduceMotionOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SsMotionScope>();
    final systemReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return resolve(
      appOverride: scope?.appOverride,
      systemReduced: systemReduced,
    );
  }

  /// Returns [base] unchanged when motion is allowed, or [Duration.zero]
  /// when [context] resolves to reduced motion. Callers that need to keep
  /// feedback observable under reduced motion (ADR 0274 §5.1) must not
  /// gate the feedback itself on this value — only its motion extent.
  static Duration durationOf(BuildContext context, Duration base) =>
      reduceMotionOf(context) ? Duration.zero : base;

  /// Pure resolution rule, exposed for direct unit testing without a
  /// widget tree.
  static bool resolve({
    required bool? appOverride,
    required bool systemReduced,
  }) {
    return appOverride ?? systemReduced;
  }

  @override
  bool updateShouldNotify(SsMotionScope oldWidget) =>
      appOverride != oldWidget.appOverride;
}
