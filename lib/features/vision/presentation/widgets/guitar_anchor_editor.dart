/// Touch/drag editor for the manual guitar-geometry calibration screen
/// (SDD Ch6 §13.3, E05-R11, §5).
///
/// **Coordinate contract (§5.2 — BLOCKER if violated):** Every pointer event
/// goes through the R07 [PreviewFit.toNormalized] inverse transform to
/// recover the canonical `[0,1]×[0,1]` point. The widget performs **NO**
/// `1 - x`, `swap`, or `MediaQuery`-based manual mapping of its own — that
/// is precisely the bug class the mirror/orientation parity-mátrix in the
/// acceptance criteria is designed to catch.
///
/// **Clamp visibility (§5.4):** a point dragged outside `[0,1]×[0,1]` is
/// clamped, and a faint outline glow signals the clamp to the user so the
/// point does not "stick" silently. The clamp is the only allowed
/// coordinate policy downstream of the R07 inverse.
///
/// **a11y (§6 acceptance #5):** Each anchor and polygon vertex has a
/// `Semantics` label; the drag gestures are paired with
/// `Semantics(onIncrease/onDecrease)` so screen-reader users can move any
/// point by ±1% on the normalised axis.
library;

import 'package:flutter/material.dart';

import '../../../../core/camera/camera_coordinate_space.dart';
import '../../../../core/camera/preview_fit.dart';
import '../../application/guitar_calibration_controller.dart' show AnchorRole;

/// Two anchored handles exposed by the editor (SDD §13.3 — nut and
/// bridge/body). Shared with [GuitarGeometryPreview] via top-level export
/// through this file.
// AnchorRole lives in the controller so it can be a single source of
// truth across the application/presentation layers. This file re-uses it.

/// Returns the theme-resolved color used by both the editor and the preview
/// painter. Defined at top level so the preview can use the same color
/// without taking a dependency on the editor widget itself.
Color anchorPainterColor(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

class GuitarAnchorEditor extends StatefulWidget {
  const GuitarAnchorEditor({
    super.key,
    required this.fit,
    required this.nut,
    required this.bridge,
    required this.neckPolygon,
    required this.onAnchorChanged,
    required this.onPolygonVertexChanged,
    required this.semanticsNutLabel,
    required this.semanticsBridgeLabel,
  });

  /// The fit describing how the normalised-space canvas maps onto the
  /// preview rectangle (R07).
  final PreviewFit fit;

  /// Current draft anchors / polygon — the editor is purely presentational
  /// and stateless w.r.t. the canonical state.
  final NormalizedPoint nut;
  final NormalizedPoint bridge;
  final List<NormalizedPoint> neckPolygon;

  final void Function(AnchorRole role, NormalizedPoint point) onAnchorChanged;
  final void Function(int index, NormalizedPoint point) onPolygonVertexChanged;
  final String semanticsNutLabel;
  final String semanticsBridgeLabel;

  @override
  State<GuitarAnchorEditor> createState() => _GuitarAnchorEditorState();
}

class _GuitarAnchorEditorState extends State<GuitarAnchorEditor> {
  /// What the user is currently dragging. `null` means idle.
  /// Held here (and not in the parent) so the widget can ignore stale
  /// `onPanStart` events without touching the canonical state.
  _DragHandle? _drag;

  /// The currently clamped handle (during an active drag). `null` while
  /// the drag is at a valid point. Drives the visible clamp decoration
  /// on the handle (§5.4 — the point must not "stick" silently).
  Key? _clampedHandle;

  @override
  Widget build(BuildContext context) {
    final color = anchorPainterColor(context);
    final clampColor = Theme.of(context).colorScheme.error;
    return Semantics(
      container: true,
      child: SizedBox(
        key: const Key('guitar-anchor-editor'),
        width: widget.fit.viewport.width,
        height: widget.fit.viewport.height,
        child: Stack(
          children: [
            // Frame: a simple outlined rect making the editor's boundary
            // visible. R07's contentRect can extend outside the viewport in
            // fill mode, but we use fit mode here, so the rect *is* the
            // contentRect dimensions.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
            for (var i = 0; i < widget.neckPolygon.length; i++)
              _PolygonHandle(
                key: Key('guitar-polygon-vertex-$i'),
                index: i,
                vertex: widget.neckPolygon[i],
                fit: widget.fit,
                clamped: _clampedHandle == Key('guitar-polygon-vertex-$i'),
                onPointerDown: (p) => _onPolygonPointerDown(i, p),
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onApply: widget.onPolygonVertexChanged,
              ),
            _AnchorHandle(
              key: const Key('guitar-anchor-nut'),
              role: AnchorRole.nut,
              label: widget.semanticsNutLabel,
              point: widget.nut,
              fit: widget.fit,
              accentColor: clampColor,
              baseColor: color,
              clamped: _clampedHandle == const Key('guitar-anchor-nut'),
              onPointerDown: (p) => _onAnchorPointerDown(AnchorRole.nut, p),
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onApply: widget.onAnchorChanged,
            ),
            _AnchorHandle(
              key: const Key('guitar-anchor-bridge'),
              role: AnchorRole.bridge,
              label: widget.semanticsBridgeLabel,
              point: widget.bridge,
              fit: widget.fit,
              accentColor: clampColor,
              baseColor: color,
              clamped: _clampedHandle == const Key('guitar-anchor-bridge'),
              onPointerDown: (p) => _onAnchorPointerDown(AnchorRole.bridge, p),
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onApply: widget.onAnchorChanged,
            ),
          ],
        ),
      ),
    );
  }

  void _onAnchorPointerDown(AnchorRole role, NormalizedPoint p) {
    _drag = _DragHandle.anchor(role, p);
    _clampedHandle = null;
  }

  void _onPolygonPointerDown(int index, NormalizedPoint p) {
    _drag = _DragHandle.polygon(index, p);
    _clampedHandle = null;
  }

  void _onPointerMove(Offset localPosition, Size size) {
    final drag = _drag;
    if (drag == null) return;
    final normalized = widget.fit.toNormalized().apply(
      PreviewPoint(localPosition.dx, localPosition.dy),
    );
    final clamped = NormalizedPoint(
      normalized.x.clamp(0.0, 1.0).toDouble(),
      normalized.y.clamp(0.0, 1.0).toDouble(),
    );
    final wasClamped = clamped.x != normalized.x || clamped.y != normalized.y;
    switch (drag) {
      case _DragHandleAnchor(:final role):
        widget.onAnchorChanged(role, clamped);
      case _DragHandlePolygon(:final index):
        widget.onPolygonVertexChanged(index, clamped);
    }
    final handleKey = _keyForDrag(drag);
    final nextClamped = wasClamped ? handleKey : null;
    if (nextClamped != _clampedHandle) {
      setState(() {
        _clampedHandle = nextClamped;
      });
    }
  }

  void _onPointerUp() {
    if (_drag == null) return;
    setState(() {
      _drag = null;
      _clampedHandle = null;
    });
  }

  Key _keyForDrag(_DragHandle drag) => switch (drag) {
    _DragHandleAnchor(:final role) => role == AnchorRole.nut
        ? const Key('guitar-anchor-nut')
        : const Key('guitar-anchor-bridge'),
    _DragHandlePolygon(:final index) => Key('guitar-polygon-vertex-$index'),
  };
}

/// Which handle is being dragged. Carries enough state to drive the move
/// callbacks even if the parent rebuilds.
sealed class _DragHandle {
  const _DragHandle();

  factory _DragHandle.anchor(AnchorRole role, NormalizedPoint p) =
      _DragHandleAnchor;

  factory _DragHandle.polygon(int index, NormalizedPoint p) =
      _DragHandlePolygon;
}

class _DragHandleAnchor extends _DragHandle {
  const _DragHandleAnchor(this.role, this.point);
  final AnchorRole role;
  final NormalizedPoint point;
}

class _DragHandlePolygon extends _DragHandle {
  const _DragHandlePolygon(this.index, this.point);
  final int index;
  final NormalizedPoint point;
}

/// A draggable anchor with full a11y semantics + keyboard Δ-1% nudge.
class _AnchorHandle extends StatelessWidget {
  const _AnchorHandle({
    super.key,
    required this.role,
    required this.label,
    required this.point,
    required this.fit,
    required this.accentColor,
    required this.baseColor,
    required this.clamped,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onApply,
  });

  final AnchorRole role;
  final String label;
  final NormalizedPoint point;
  final PreviewFit fit;
  final Color accentColor;
  final Color baseColor;
  final bool clamped;
  final ValueChanged<NormalizedPoint> onPointerDown;
  final void Function(Offset, Size) onPointerMove;
  final VoidCallback onPointerUp;
  final void Function(AnchorRole, NormalizedPoint) onApply;

  @override
  Widget build(BuildContext context) {
    final preview = fit.toPreview().apply(point);
    final dx = (preview.x - 16).clamp(0.0, fit.viewport.width - 32).toDouble();
    final dy = (preview.y - 16).clamp(0.0, fit.viewport.height - 32).toDouble();
    // Clamp visibility (§5.4): the border switches to a thicker,
    // fully-opaque accent contour while the value is clamped so the
    // point does not "stick" silently at the boundary.
    final borderAlpha = clamped ? 0.95 : 0.2;
    final borderWidth = clamped ? 3.0 : 1.0;
    return Positioned(
      left: dx,
      top: dy,
      child: Semantics(
        label: label,
        button: true,
        onIncrease: () =>
            onApply(role, NormalizedPoint(_dx(point.x, 0.01), point.y)),
        onDecrease: () =>
            onApply(role, NormalizedPoint(_dx(point.x, -0.01), point.y)),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => onPointerDown(NormalizedPoint(point.x, point.y)),
          onPanUpdate: (d) => _forward(d.localPosition),
          onPanEnd: (_) => onPointerUp(),
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Container(
              key: const Key('guitar-anchor-handle-decor'),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: baseColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: accentColor.withValues(alpha: borderAlpha),
                  width: borderWidth,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.adjust, size: 16, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  void _forward(Offset localPosition) {
    // `localPosition` is relative to the GestureDetector's 32x32 box. The
    // editor's `_onPointerMove` expects coordinates in the editor's
    // Stack-space, so we add the anchor's own `Positioned` offset.
    final preview = fit.toPreview().apply(point);
    final anchorDx = (preview.x - 16)
        .clamp(0.0, fit.viewport.width - 32)
        .toDouble();
    final anchorDy = (preview.y - 16)
        .clamp(0.0, fit.viewport.height - 32)
        .toDouble();
    final editorSpace = localPosition + Offset(anchorDx, anchorDy);
    onPointerMove(editorSpace, Size(fit.viewport.width, fit.viewport.height));
  }

  double _dx(double v, double d) => (v + d).clamp(0.0, 1.0).toDouble();
}

/// A small draggable handle for a polygon vertex.
class _PolygonHandle extends StatelessWidget {
  const _PolygonHandle({
    super.key,
    required this.index,
    required this.vertex,
    required this.fit,
    required this.clamped,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onApply,
  });

  final int index;
  final NormalizedPoint vertex;
  final PreviewFit fit;
  final bool clamped;
  final ValueChanged<NormalizedPoint> onPointerDown;
  final void Function(Offset, Size) onPointerMove;
  final VoidCallback onPointerUp;
  final void Function(int, NormalizedPoint) onApply;

  @override
  Widget build(BuildContext context) {
    final color = anchorPainterColor(context);
    final preview = fit.toPreview().apply(vertex);
    final dx = (preview.x - 8).clamp(0.0, fit.viewport.width - 16).toDouble();
    final dy = (preview.y - 8).clamp(0.0, fit.viewport.height - 16).toDouble();
    // Clamp visibility (§5.4): the dashed border surrounds the vertex
    // handle while the value is clamped at the boundary.
    final clampColor = Theme.of(context).colorScheme.error;
    final borderColor = clamped
        ? clampColor
        : Theme.of(context).colorScheme.surface;
    final borderWidth = clamped ? 2.0 : 1.0;
    return Positioned(
      left: dx,
      top: dy,
      child: Semantics(
        label: 'Polygon vertex $index',
        button: true,
        onIncrease: () => onApply(
          index,
          NormalizedPoint(
            (vertex.x + 0.01).clamp(0.0, 1.0).toDouble(),
            vertex.y,
          ),
        ),
        onDecrease: () => onApply(
          index,
          NormalizedPoint(
            (vertex.x - 0.01).clamp(0.0, 1.0).toDouble(),
            vertex.y,
          ),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => onPointerDown(vertex),
          onPanUpdate: (d) => onPointerMove(
            d.localPosition + Offset(dx, dy),
            Size(fit.viewport.width, fit.viewport.height),
          ),
          onPanEnd: (_) => onPointerUp(),
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Container(
              key: const Key('guitar-polygon-handle-decor'),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: borderColor,
                  width: borderWidth,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
