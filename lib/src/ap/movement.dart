import 'dart:math' as math;

import 'package:battle_rules/src/ap/ap_pool.dart';

/// {@template movement}
/// The end of a move: the unit arrives at [arrivesAt] with the AP [pool].
/// {@endtemplate}
final class Movement {
  /// {@macro movement}
  const new({required this.arrivesAt, required this.pool});

  /// The battle time at which the unit arrives.
  final Duration arrivesAt;

  /// The AP pool at arrival.
  final ApPool pool;
}

/// Moves a unit [lengthM] metres from battle time [start], at [speedMps]
/// metres per second, paying [apPerM] AP per metre from its [pool]
/// (COMBAT-03, COMBAT-04).
///
/// The pool recovers on the way (COMBAT-02). A unit with no AP left is
/// never frozen: it goes on as fast as its AP come back, `recoveryPerHour
/// / apPerM` metres per hour (COMBAT-06, MAP-20). So it arrives at the
/// later of `lengthM / speedMps` and the time its pool has recovered the
/// whole cost: `(lengthM × apPerM − AP at start) / recoveryPerHour`.
Movement moveAlong({
  required ApPool pool,
  required Duration start,
  required double lengthM,
  required double apPerM,
  required double speedMps,
}) {
  if (lengthM < 0 || apPerM < 0 || speedMps <= 0) {
    throw ArgumentError(
      'lengthM and apPerM must not be negative, speedMps must be positive',
    );
  }
  // Paid actions run one after another: a move starts after the last
  // payment of the pool.
  final begin = start < pool.updatedAt ? pool.updatedAt : start;
  final cost = lengthM * apPerM;
  final apAtStart = pool.apAt(begin);
  final fullSpeedS = lengthM / speedMps;
  final apLimitedS =
      (cost - apAtStart) / pool.recoveryPerHour * Duration.secondsPerHour;
  final seconds = math.max(fullSpeedS, apLimitedS);
  final arrivesAt =
      begin +
      Duration(microseconds: (seconds * Duration.microsecondsPerSecond).ceil());
  final rest = apAtStart + _hours(arrivesAt - begin) * pool.recoveryPerHour;
  return Movement(
    arrivesAt: arrivesAt,
    pool: pool.withValue(
      math.min(pool.max, math.max(0, rest - cost)),
      arrivesAt,
    ),
  );
}

double _hours(Duration duration) =>
    duration.inMicroseconds / Duration.microsecondsPerHour;
