import 'camera_coordinate_space.dart';

/// Maximum permitted normalized round-trip drift for [CameraTransform].
const double cameraTransformRoundTripTolerance = 1e-6;

typedef CameraPointFactory<T extends CameraPoint> =
    T Function(double x, double y);

/// A typed, composable 2D affine coordinate transform.
///
/// The source and target spaces are encoded in [From] and [To]. This makes a
/// direct sensor-to-preview mapping possible while preventing accidental use
/// of a preview point as model input.
final class CameraTransform<From extends CameraPoint, To extends CameraPoint> {
  factory CameraTransform.affine({
    required double a,
    required double b,
    required double c,
    required double d,
    required double tx,
    required double ty,
    required CameraPointFactory<From> fromPoint,
    required CameraPointFactory<To> toPoint,
  }) => CameraTransform._(a, b, c, d, tx, ty, fromPoint, toPoint);

  const CameraTransform._(
    this._a,
    this._b,
    this._c,
    this._d,
    this._tx,
    this._ty,
    this._fromPoint,
    this._toPoint,
  );

  final double _a;
  final double _b;
  final double _c;
  final double _d;
  final double _tx;
  final double _ty;
  final CameraPointFactory<From> _fromPoint;
  final CameraPointFactory<To> _toPoint;

  To apply(From point) => _toPoint(
    _a * point.x + _b * point.y + _tx,
    _c * point.x + _d * point.y + _ty,
  );

  /// Returns the transform obtained by applying this transform, then [next].
  CameraTransform<From, Next> compose<Next extends CameraPoint>(
    CameraTransform<To, Next> next,
  ) => CameraTransform<From, Next>.affine(
    a: next._a * _a + next._b * _c,
    b: next._a * _b + next._b * _d,
    c: next._c * _a + next._d * _c,
    d: next._c * _b + next._d * _d,
    tx: next._a * _tx + next._b * _ty + next._tx,
    ty: next._c * _tx + next._d * _ty + next._ty,
    fromPoint: _fromPoint,
    toPoint: next._toPoint,
  );

  CameraTransform<To, From> inverse() {
    final determinant = _a * _d - _b * _c;
    if (determinant == 0) {
      throw StateError('A singular camera transform cannot be inverted.');
    }
    return CameraTransform<To, From>.affine(
      a: _d / determinant,
      b: -_b / determinant,
      c: -_c / determinant,
      d: _a / determinant,
      tx: (_b * _ty - _d * _tx) / determinant,
      ty: (_c * _tx - _a * _ty) / determinant,
      fromPoint: _toPoint,
      toPoint: _fromPoint,
    );
  }

  static bool isRoundTripErrorWithinTolerance(double normalizedError) =>
      normalizedError >= 0 &&
      normalizedError <= cameraTransformRoundTripTolerance;

  /// Maps full sensor pixels (or a platform crop) into an upright image.
  static CameraTransform<SensorPoint, UprightPoint> sensorToUpright({
    required SensorSize sensorSize,
    required CameraRotation rotation,
    SensorRect? crop,
  }) {
    final effectiveCrop =
        crop ??
        SensorRect(
          left: 0,
          top: 0,
          width: sensorSize.width,
          height: sensorSize.height,
        );
    if (effectiveCrop.right > sensorSize.width ||
        effectiveCrop.bottom > sensorSize.height) {
      throw ArgumentError.value(
        crop,
        'crop',
        'Crop must be inside sensor bounds.',
      );
    }
    final width = effectiveCrop.width;
    final height = effectiveCrop.height;
    return switch (rotation) {
      CameraRotation.degrees0 => CameraTransform.affine(
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        tx: -effectiveCrop.left,
        ty: -effectiveCrop.top,
        fromPoint: SensorPoint.new,
        toPoint: UprightPoint.new,
      ),
      CameraRotation.degrees90 => CameraTransform.affine(
        a: 0,
        b: -1,
        c: 1,
        d: 0,
        tx: height + effectiveCrop.top,
        ty: -effectiveCrop.left,
        fromPoint: SensorPoint.new,
        toPoint: UprightPoint.new,
      ),
      CameraRotation.degrees180 => CameraTransform.affine(
        a: -1,
        b: 0,
        c: 0,
        d: -1,
        tx: width + effectiveCrop.left,
        ty: height + effectiveCrop.top,
        fromPoint: SensorPoint.new,
        toPoint: UprightPoint.new,
      ),
      CameraRotation.degrees270 => CameraTransform.affine(
        a: 0,
        b: 1,
        c: -1,
        d: 0,
        tx: -effectiveCrop.top,
        ty: width + effectiveCrop.left,
        fromPoint: SensorPoint.new,
        toPoint: UprightPoint.new,
      ),
    };
  }

  static CameraTransform<UprightPoint, NormalizedPoint> uprightToNormalized({
    required UprightSize uprightSize,
  }) => CameraTransform.affine(
    a: 1 / uprightSize.width,
    b: 0,
    c: 0,
    d: 1 / uprightSize.height,
    tx: 0,
    ty: 0,
    fromPoint: UprightPoint.new,
    toPoint: NormalizedPoint.new,
  );

  /// One clockwise sensor rotation, for the four-turn identity property.
  static CameraTransform<SensorPoint, UprightPoint> sensorQuarterTurn(
    SensorSize sensorSize,
  ) => sensorToUpright(
    sensorSize: sensorSize,
    rotation: CameraRotation.degrees90,
  );

  /// One clockwise upright rotation, with the result expressed as sensor space.
  static CameraTransform<UprightPoint, SensorPoint> uprightQuarterTurn(
    UprightSize uprightSize,
  ) => CameraTransform.affine(
    a: 0,
    b: -1,
    c: 1,
    d: 0,
    tx: uprightSize.height,
    ty: 0,
    fromPoint: UprightPoint.new,
    toPoint: SensorPoint.new,
  );

  /// Mirrors only presentation pixels; normalized/model space stays unchanged.
  static CameraTransform<PreviewPoint, PreviewPoint> previewMirror(
    PreviewRect viewport,
  ) => CameraTransform.affine(
    a: -1,
    b: 0,
    c: 0,
    d: 1,
    tx: viewport.left * 2 + viewport.width,
    ty: 0,
    fromPoint: PreviewPoint.new,
    toPoint: PreviewPoint.new,
  );
}
