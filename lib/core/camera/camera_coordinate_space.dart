/// The coordinate systems used by the platform-independent camera pipeline.
///
/// Points are deliberately separate types for each space so a caller cannot
/// accidentally pass preview pixels to a model expecting normalized input.
enum CameraCoordinateSpace {
  sensor,
  buffer,
  upright,
  normalized,
  preview,
  overlay,
}

/// Base interface for every typed camera point.
abstract interface class CameraPoint {
  double get x;
  double get y;
  CameraCoordinateSpace get space;
}

final class SensorPoint implements CameraPoint {
  const SensorPoint(this.x, this.y);

  @override
  final double x;
  @override
  final double y;
  @override
  CameraCoordinateSpace get space => CameraCoordinateSpace.sensor;

  @override
  bool operator ==(Object other) =>
      other is SensorPoint && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

final class BufferPoint implements CameraPoint {
  const BufferPoint(this.x, this.y);

  @override
  final double x;
  @override
  final double y;
  @override
  CameraCoordinateSpace get space => CameraCoordinateSpace.buffer;

  @override
  bool operator ==(Object other) =>
      other is BufferPoint && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

final class UprightPoint implements CameraPoint {
  const UprightPoint(this.x, this.y);

  @override
  final double x;
  @override
  final double y;
  @override
  CameraCoordinateSpace get space => CameraCoordinateSpace.upright;

  @override
  bool operator ==(Object other) =>
      other is UprightPoint && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

/// A point in the model's non-mirrored, resolution-independent frame space.
final class NormalizedPoint implements CameraPoint {
  const NormalizedPoint(this.x, this.y)
    : assert(x >= 0 && x <= 1),
      assert(y >= 0 && y <= 1);

  @override
  final double x;
  @override
  final double y;
  @override
  CameraCoordinateSpace get space => CameraCoordinateSpace.normalized;

  @override
  bool operator ==(Object other) =>
      other is NormalizedPoint && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

final class PreviewPoint implements CameraPoint {
  const PreviewPoint(this.x, this.y);

  @override
  final double x;
  @override
  final double y;
  @override
  CameraCoordinateSpace get space => CameraCoordinateSpace.preview;

  @override
  bool operator ==(Object other) =>
      other is PreviewPoint && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

final class OverlayPoint implements CameraPoint {
  const OverlayPoint(this.x, this.y);

  @override
  final double x;
  @override
  final double y;
  @override
  CameraCoordinateSpace get space => CameraCoordinateSpace.overlay;

  @override
  bool operator ==(Object other) =>
      other is OverlayPoint && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

final class SensorSize {
  const SensorSize({required this.width, required this.height})
    : assert(width > 0),
      assert(height > 0);

  final double width;
  final double height;

  UprightSize rotated(CameraRotation rotation) => switch (rotation) {
    CameraRotation.degrees0 ||
    CameraRotation.degrees180 => UprightSize(width: width, height: height),
    CameraRotation.degrees90 ||
    CameraRotation.degrees270 => UprightSize(width: height, height: width),
  };
}

final class UprightSize {
  const UprightSize({required this.width, required this.height})
    : assert(width > 0),
      assert(height > 0);

  final double width;
  final double height;
}

/// An unnormalised rectangle in sensor pixels.
final class SensorRect {
  const SensorRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(left >= 0),
       assert(top >= 0),
       assert(width > 0),
       assert(height > 0);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is SensorRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;
  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// A concrete preview/overlay rectangle in presentation pixels.
final class PreviewRect {
  const PreviewRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(width > 0),
       assert(height > 0);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  bool contains(PreviewPoint point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;

  @override
  bool operator ==(Object other) =>
      other is PreviewRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;
  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// A typed source rectangle in the non-mirrored normalized frame space.
final class NormalizedRect {
  const NormalizedRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(left >= 0 && left <= right && right <= 1),
       assert(top >= 0 && top <= bottom && bottom <= 1);

  const NormalizedRect.full() : left = 0, top = 0, right = 1, bottom = 1;

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  bool operator ==(Object other) =>
      other is NormalizedRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;
  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

enum CameraRotation {
  degrees0(0),
  degrees90(90),
  degrees180(180),
  degrees270(270);

  const CameraRotation(this.degrees);

  final int degrees;

  static CameraRotation fromDegrees(int degrees) => switch (degrees) {
    0 => CameraRotation.degrees0,
    90 => CameraRotation.degrees90,
    180 => CameraRotation.degrees180,
    270 => CameraRotation.degrees270,
    _ => throw ArgumentError.value(
      degrees,
      'degrees',
      'Rotation must be one of 0, 90, 180, or 270.',
    ),
  };
}
