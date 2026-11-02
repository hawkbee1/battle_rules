/// The source of randomness of the rules core: a port injected by the host
/// (stack decision 7), so the same seed replays the same battle (stack
/// decision 1).
abstract interface class SeededRandom {
  /// A double in `[0, 1)`.
  double nextDouble();
}

/// {@template xorshift_random}
/// A [SeededRandom] with a fixed [seed]: xorshift128 (Marsaglia, 2003) on
/// four 32-bit words.
///
/// It uses only 32-bit shifts, xor and masks, so it draws the same numbers
/// on the Dart VM and on the web, and across Dart releases (`dart:math`
/// `Random` may change between releases): a battle log replays the same
/// battle after a host upgrade.
/// {@endtemplate}
final class XorshiftRandom implements SeededRandom {
  /// {@macro xorshift_random}
  new(this.seed)
    : _x = (seed ^ 0x9E3779B9) & _mask,
      _y = (seed >> 32 ^ 0x243F6A88) & _mask,
      _z = 0xB7E15162,
      _w = 0x6A09E667 {
    // Mixes the seed into every word before the first draw.
    for (var draw = 0; draw < 20; draw++) {
      _next32();
    }
  }

  static const _mask = 0xFFFFFFFF;

  /// The seed.
  final int seed;

  int _x;
  int _y;
  int _z;
  int _w;

  int _next32() {
    final t = (_x ^ (_x << 11)) & _mask;
    _x = _y;
    _y = _z;
    _z = _w;
    return _w = (_w ^ (_w >>> 19) ^ (t ^ (t >>> 8))) & _mask;
  }

  /// A double in `[0, 1)` with 53 random bits, from two draws.
  @override
  double nextDouble() {
    final high = _next32() >>> 5;
    final low = _next32() >>> 6;
    return (high * 67108864 + low) / 9007199254740992;
  }
}
