import 'dart:ui';

import '../foundations/ss_semantics.dart';

/// Audits a MEASURED [Size] against the design system's minimum interactive
/// dimension (ADR 0280 §5). This does not build or measure a widget itself
/// — callers pass in a real, rendered size (e.g. `tester.getSize(finder)`
/// on an already-pumped component) so the check exercises the component's
/// actual layout, not a re-assertion of [SsSemantics.minimumInteractiveDimension]
/// against itself.
abstract final class SsTapTarget {
  /// `true` iff both axes of [size] meet or exceed
  /// [SsSemantics.minimumInteractiveDimension].
  static bool meetsMinimum(Size size) =>
      size.width >= SsSemantics.minimumInteractiveDimension &&
      size.height >= SsSemantics.minimumInteractiveDimension;
}
