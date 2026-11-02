import 'package:battle_rules/battle_rules.dart';

/// A [SeededRandom] that returns [values] in turn, round and round.
final class FixedRandom implements SeededRandom {
  /// Returns [values] in turn.
  new(this.values);

  /// The values returned, in order.
  final List<double> values;

  var _next = 0;

  @override
  double nextDouble() => values[_next++ % values.length];
}
