import 'dart:math' as math;

/// {@template ap_pool}
/// A pool of AP that recovers lazily (COMBAT-01, COMBAT-02, stack
/// decision 1).
///
/// It keeps its [value] at [updatedAt], its last update. AP at a later time
/// is `min(max, value + seconds since / recoveryDelayS)`: nothing runs per
/// tick (decision 238). It recovers whatever its owner does, stored or not
/// (HQ-34). A unit and the HQ each have one.
///
/// All the AP recovery math is here: [recoveredIn] and [timeToRecover] are
/// the two directions of the rate, and movement uses them too.
///
/// Times are battle times: the time elapsed since the battle started.
/// {@endtemplate}
final class ApPool {
  /// {@macro ap_pool}
  ///
  /// Throws an [ArgumentError] unless `max` is positive, `recoveryDelayS` is
  /// at least 1 and `value` is within `[0, max]`.
  new({
    required this.max,
    required this.recoveryDelayS,
    required this.value,
    required this.updatedAt,
  }) {
    if (max <= 0) throw ArgumentError.value(max, 'max', 'must be positive');
    if (recoveryDelayS < 1) {
      throw ArgumentError.value(
        recoveryDelayS,
        'recoveryDelayS',
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
    required int recoveryDelayS,
    required Duration at,
  }) => ApPool(
    max: max,
    recoveryDelayS: recoveryDelayS,
    value: max,
    updatedAt: at,
  );

  /// The AP maximum (`ap_max`, decision 167).
  final double max;

  /// Seconds to recover one AP (`battle.yaml` `ap.recovery_delay_s`,
  /// decision 238).
  final int recoveryDelayS;

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
      return math.max(0, value - recoveredIn(updatedAt - time));
    }
    return math.min(max, value + recoveredIn(time - updatedAt));
  }

  /// The AP this pool recovers in [elapsed] (COMBAT-02).
  double recoveredIn(Duration elapsed) =>
      elapsed.inMicroseconds /
      (recoveryDelayS * Duration.microsecondsPerSecond);

  /// The time this pool needs to recover [ap], rounded up to the microsecond
  /// so that the AP it waits for are there at its end; zero for no AP.
  Duration timeToRecover(double ap) {
    if (ap <= 0) return Duration.zero;
    return Duration(
      microseconds: (ap * recoveryDelayS * Duration.microsecondsPerSecond)
          .ceil(),
    );
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
    return start + timeToRecover(missing);
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
    recoveryDelayS: recoveryDelayS,
    value: newValue,
    updatedAt: time,
  );
}
