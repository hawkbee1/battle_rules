import 'dart:math' as math;

/// {@template vec3}
/// A point or a direction in metres: x east, y north, z up. Plain vector
/// maths for shots; the rules core has no 3D engine.
/// {@endtemplate}
final class Vec3 {
  /// {@macro vec3}
  const new(this.x, this.y, this.z);

  /// The origin.
  static const zero = Vec3(0, 0, 0);

  /// East.
  final double x;

  /// North.
  final double y;

  /// Up.
  final double z;

  /// The sum.
  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);

  /// The difference.
  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);

  /// Scaled by [factor].
  Vec3 operator *(double factor) => Vec3(x * factor, y * factor, z * factor);

  /// The dot product.
  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  /// The cross product.
  Vec3 cross(Vec3 other) => Vec3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  /// The length.
  double get length => math.sqrt(dot(this));

  /// The same direction with length 1. Throws a [StateError] for the zero
  /// vector, which has no direction.
  Vec3 get normalized {
    final size = length;
    if (size == 0) throw StateError('the zero vector has no direction');
    return this * (1 / size);
  }

  @override
  String toString() => 'Vec3($x, $y, $z)';
}
