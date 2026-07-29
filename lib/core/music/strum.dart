import 'package:meta/meta.dart';

/// Direction of a strum: a downstroke moves toward the floor, an upstroke
/// toward the ceiling. This is StrumSight's headline output.
enum StrumDirection { down, up }

/// A single detected strum.
@immutable
class Strum {
  const Strum({
    required this.direction,
    required this.confidence,
    this.accent = false,
    this.muted = false,
  }) : assert(confidence >= 0 && confidence <= 1);

  final StrumDirection direction;

  /// Detector confidence, 0..1.
  final double confidence;

  /// Accented (louder) stroke — notated ">".
  final bool accent;

  /// Muted / dampened stroke — notated "x".
  final bool muted;

  bool get isDown => direction == StrumDirection.down;
  bool get isUp => direction == StrumDirection.up;

  @override
  bool operator ==(Object other) =>
      other is Strum &&
      other.direction == direction &&
      other.confidence == confidence &&
      other.accent == accent &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(direction, confidence, accent, muted);
}
