import 'package:flutter/material.dart';

import '../../foundations/ss_breakpoints.dart';
import '../../foundations/ss_elevation.dart';
import '../../foundations/ss_motion.dart';
import '../../foundations/ss_radius.dart';
import '../../foundations/ss_spacing.dart';
import 'ss_side_sheet.dart';

/// The physical shape a size-adaptive overlay resolves to (ADR 0279 §5.6).
enum SsOverlayPresentation { bottomSheet, sideSheet }

/// The modal-overlay engine shared by every SS overlay surface (dialog,
/// confirmation sheet, tool-confirmation sheet). It presents through
/// Flutter's own [Navigator]/[ModalRoute] machinery ([showGeneralDialog])
/// rather than a hand-rolled barrier: the framework's [ModalBarrier] already
/// blocks the screen painted before it from the semantics tree
/// (`BlockSemantics`, ADR 0279 §5.4), and [Navigator] already restricts
/// keyboard focus traversal to the topmost route and restores focus to the
/// element that opened it once the route pops. This host owns exactly what
/// Flutter does not provide out of the box: which physical shape an
/// adaptive sheet takes at the current width (§5.6, §0.0/D6).
abstract final class SsOverlayHost {
  /// Below [SsBreakpoints.expandedMin] resolves to a bottom sheet; at or
  /// above it resolves to a side sheet — the medium band (600–839 dp) sides
  /// with "bottom", not "side" (§0.0/D6, measured against the exact
  /// [SsBreakpoints] constants rather than a literal).
  static SsOverlayPresentation presentationForWidth(double width) {
    return width >= SsBreakpoints.expandedMin
        ? SsOverlayPresentation.sideSheet
        : SsOverlayPresentation.bottomSheet;
  }

  /// Presents [builder] centered as a standard dialog surface (used by
  /// `SsDialog`). Dismissible by tapping the barrier, Android back, and
  /// Escape alike (§5.4/A7) via `barrierDismissible: true`.
  static Future<T?> showDialogSurface<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    required String barrierLabel,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.black54,
      transitionDuration: SsMotion.routeTransition,
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(SsSpacing.space6),
              child: Builder(builder: builder),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: SsMotion.enter),
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: SsMotion.enter),
            ),
            child: child,
          ),
        );
      },
    );
  }

  /// Presents [builder] as a size-adaptive sheet: a bottom sheet on compact
  /// and medium widths, a side sheet at/above [SsBreakpoints.expandedMin]
  /// (§5.6). Used by `SsConfirmationSheet` and `SsToolConfirmationSheet`.
  static Future<T?> showSheetSurface<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    required String barrierLabel,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.black54,
      transitionDuration: SsMotion.routeTransition,
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Builder(
            builder: (innerContext) {
              final width = MediaQuery.sizeOf(innerContext).width;
              final presentation = presentationForWidth(width);
              final content = Builder(builder: builder);
              return switch (presentation) {
                SsOverlayPresentation.bottomSheet => Align(
                  alignment: Alignment.bottomCenter,
                  child: _SsBottomSheetSurface(child: content),
                ),
                SsOverlayPresentation.sideSheet => Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    height: MediaQuery.sizeOf(innerContext).height,
                    child: SsSideSheet(child: content),
                  ),
                ),
              };
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final width = MediaQuery.sizeOf(context).width;
        final presentation = presentationForWidth(width);
        final beginOffset = switch (presentation) {
          SsOverlayPresentation.bottomSheet => const Offset(0, 1),
          SsOverlayPresentation.sideSheet => const Offset(1, 0),
        };
        return SlideTransition(
          position: Tween(
            begin: beginOffset,
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: SsMotion.enter)),
          child: child,
        );
      },
    );
  }
}

/// Compact/medium chrome for [SsOverlayHost.showSheetSurface] — full width,
/// capped height, rounded only at the top edge.
final class _SsBottomSheetSurface extends StatelessWidget {
  const _SsBottomSheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    final style = SsElevation.modal.resolve(Theme.of(context));
    return SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          color: style.background,
          elevation: style.shadowElevation,
          shadowColor: style.shadowColor,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(SsRadius.lg),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
