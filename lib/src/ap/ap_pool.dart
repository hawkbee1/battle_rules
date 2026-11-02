import 'dart:math' as math;

/// {@template ap_pool}
/// A pool of AP that recovers lazily (COMBAT-01, COMBAT-02, stack
/// decision 1).
///
/// It keeps its [value] at [updatedAt], its last update. AP at a later time
/// is `min(max, value + hours since × recoveryPerHour)`: nothing runs per
/// tick. It recovers whatever its owner does, stored or not (HQ-34). A unit
/// and the HQ each have one.
///
/// Times are battle times: the time elapsed since the battle started.
/// {@endtemplate}
final class ApPool {
  /// {@macro ap_pool}
  ///
  /// Throws an [ArgumentError] unless `max` and `recoveryPerHour` are
  /// positive and `value` is within `[0, max]`.
  new({
    required this.max,
    required this.recoveryPerHour,
    required this.value,
    required this.updatedAt,
  }) {
    if (max <= 0) throw ArgumentError.value(max, 'max', 'must be positive');
    if (recoveryPerHour <= 0) {
      throw ArgumentError.value(
        recoveryPerHour,
        'recoveryPerHour',
        'must be positive: a unit at 0 AP is never frozen (COMBAT-06)',
      );
    }
    if (value < 0 || value > max) {
      throw ArgumentError.value(value, 'value', 'must be within [0, $max]');
    }
  }

  /// A full pool at [at], as every battle starts (decision 83).
  factory full({
    required double max,
    required double recoveryPerHour,
    required Duration at,
  }) => ApPool(
    max: max,
    recoveryPerHour: recoveryPerHour,
    value: max,
    updatedAt: at,
  );

  /// The AP maximum (`ap_max`, decision 167).
  final double max;

  /// AP recovered per hour (`battle.yaml` `ap.recovery_per_hour`).
  final double recoveryPerHour;

  /// AP at [updatedAt].
  final double value;

  /// The battle time of the last update.
  final Duration updatedAt;

  /// AP at battle time [time] (COMBAT-02).
  ///
  /// Before [updatedAt] (a payment that waited for its AP dates the pool
  /// in the future), it is what the pool can spare then without taking
  /// from that payment: never below 0.
  double apAt(Duration time) {
    if (time < updatedAt) {
      return math.max(0, value - _hours(updatedAt - time) * recoveryPerHour);
    }
    return math.min(max, value + _hours(time - updatedAt) * recoveryPerHour);
  }

  /// The earliest battle time from [from] at which the pool holds [cost];
  /// null when [cost] is above [max], so it never will (COMBAT-06).
  ///
  /// Paid actions run one after another: nothing starts before the last
  /// payment ([updatedAt]).
  Duration? readyAt(double cost, Duration from) {
    if (cost > max) return null;
    final start = from > updatedAt ? from : updatedAt;
    final missing = cost - apAt(start);
    if (missing <= 0) return start;
    return start + _durationOfHours(missing / recoveryPerHour);
  }

  /// Pays [cost] at the earliest battle time from [from] at which the pool
  /// holds it: the paid action waits for its AP and the pool never goes
  /// negative (COMBAT-06). Returns that time and the pool after paying;
  /// null when [cost] is above [max].
  ({Duration at, ApPool pool})? payWhenReady(double cost, Duration from) {
    final at = readyAt(cost, from);
    if (at == null) return null;
    final available = apAt(at);
    // After a wait the pool holds exactly [cost]: it is left empty.
    final rest = available > cost ? available - cost : 0.0;
    return (at: at, pool: withValue(rest, at));
  }

  /// This pool holding [newValue] at battle time [time].
  ApPool withValue(double newValue, Duration time) => ApPool(
    max: max,
    recoveryPerHour: recoveryPerHour,
    value: newValue,
    updatedAt: time,
  );
}

double _hours(Duration duration) =>
    duration.inMicroseconds / Duration.microsecondsPerHour;

/// [hours] as a duration, rounded up to the microsecond so that the AP it
/// waits for are there at its end.
Duration _durationOfHours(double hours) =>
    Duration(microseconds: (hours * Duration.microsecondsPerHour).ceil());
