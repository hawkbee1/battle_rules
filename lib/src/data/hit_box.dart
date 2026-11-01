import 'package:battle_rules/src/data/data_reader.dart';

/// {@template hit_box}
/// The hit volume of a unit or the HQ for first-person shots, in metres
/// (`hit_box_m`, decision 183).
/// {@endtemplate}
final class HitBox {
  /// {@macro hit_box}
  const new({required this.width, required this.length, required this.height});

  /// Side to side, in metres.
  final double width;

  /// Front to back, in metres.
  final double length;

  /// Ground to top, in metres.
  final double height;
}

/// Reads the `hit_box_m` map of [reader].
HitBox readHitBox(DataReader reader) {
  final box = reader.map('hit_box_m');
  return HitBox(
    width: box.number('width'),
    length: box.number('length'),
    height: box.number('height'),
  );
}
