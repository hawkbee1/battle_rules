import 'dart:math' as math;

/// The source of randomness of the rules core: a port injected by the host
/// (stack decision 7), so the same seed replays the same battle (stack
/// decision 1).
abstract interface class SeededRandom {
  /// A double in `[0, 1)`.
  double nextDouble();
}

/// {@template dart_seeded_random}
/// A [SeededRandom] on `dart:math` [math.Random] with a fixed [seed].
/// {@endtemplate}
final class DartSeededRandom implements SeededRandom {
  /// {@macro dart_seeded_random}
  new(this.seed) : _random = math.Random(seed);

  /// The seed.
  final int seed;

  final math.Random _random;

  @override
  double nextDouble() => _random.nextDouble();
}
