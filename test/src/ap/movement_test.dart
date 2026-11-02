import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/plan_data.dart';

/// A synthetic pool: 10 AP at most, [perHour] AP per hour, [value] AP at
/// time 0.
ApPool _pool(double value, {double perHour = 2}) => ApPool(
  max: 10,
  recoveryPerHour: perHour,
  value: value,
  updatedAt: Duration.zero,
);

Duration _hours(double hours) =>
    Duration(microseconds: (hours * Duration.microsecondsPerHour).round());

Matcher _closeToDuration(Duration expected) => predicate<Duration>(
  (actual) => (actual - expected).inMicroseconds.abs() <= 1,
  'within 1 µs of $expected',
);

void main() {
  group('moveAlong', () {
    test('COMBAT-06 an infantry unit covers 30 m on grass, then moves 1 m '
        'per hour', () {
      final data = parsePlanData();
      final soldier = data.units.unitTypes['soldier']!;
      final rate = data.battle.ap.recoveryPerHour;
      final UnitStats(:apMax, :apPerM, :moveSpeed) = soldier.stats;
      final pool = ApPool.full(
        max: apMax,
        recoveryPerHour: rate,
        at: Duration.zero,
      );
      // The AP of a full pool pay this far on flat grass.
      final freeMetres = apMax / apPerM;

      final free = moveAlong(
        pool: pool,
        start: Duration.zero,
        lengthM: freeMetres,
        apPerM: apPerM,
        speedMps: moveSpeed,
      );
      final twoMore = moveAlong(
        pool: pool,
        start: Duration.zero,
        lengthM: freeMetres + 2,
        apPerM: apPerM,
        speedMps: moveSpeed,
      );

      expect(
        free.arrivesAt,
        _closeToDuration(_hours(freeMetres / moveSpeed / 3600)),
      );
      expect(free.pool.value, greaterThanOrEqualTo(0));
      // Each metre past those costs apPerM AP, which come back at `rate`.
      expect(twoMore.arrivesAt, _closeToDuration(_hours(2 * apPerM / rate)));
      expect(twoMore.pool.value, 0);
    });

    test('MAP-20 a unit at 0 AP moves as fast as its AP come back', () {
      final move = moveAlong(
        pool: _pool(0),
        start: Duration.zero,
        lengthM: 3,
        apPerM: 0.5,
        speedMps: 5,
      );

      // 3 m × 0.5 AP per metre at 2 AP per hour.
      expect(move.arrivesAt, _hours(0.75));
      expect(move.pool.value, 0);
      expect(move.pool.updatedAt, move.arrivesAt);
    });

    test('moves at full speed while the AP suffice', () {
      final move = moveAlong(
        pool: _pool(10, perHour: 3600),
        start: const Duration(seconds: 10),
        lengthM: 4,
        apPerM: 1,
        speedMps: 2,
      );

      expect(move.arrivesAt, const Duration(seconds: 12));
      // 10 AP − 4 AP + 2 s at 1 AP per second.
      expect(move.pool.value, closeTo(8, 1e-9));
    });

    test('COMBAT-02 the pool recovers on the way, up to its maximum', () {
      final move = moveAlong(
        pool: _pool(8, perHour: 3600),
        start: Duration.zero,
        lengthM: 10,
        apPerM: 0.5,
        speedMps: 1,
      );

      // 8 AP + 10 s at 1 AP per second − 5 AP, capped at 10.
      expect(move.arrivesAt, const Duration(seconds: 10));
      expect(move.pool.value, 10);
    });

    test('a move ordered before a pending payment starts after it', () {
      final pending = _pool(4).withValue(0, const Duration(hours: 1));
      final move = moveAlong(
        pool: pending,
        start: Duration.zero,
        lengthM: 1,
        apPerM: 1,
        speedMps: 1,
      );

      // From 1 h, the metre's AP come back in half an hour.
      expect(move.arrivesAt, const Duration(minutes: 90));
    });

    test('a move of 0 m arrives at once', () {
      final move = moveAlong(
        pool: _pool(4),
        start: Duration.zero,
        lengthM: 0,
        apPerM: 1,
        speedMps: 1,
      );

      expect(move.arrivesAt, Duration.zero);
      expect(move.pool.value, 4);
    });

    test('rejects a negative length or cost, or a speed of 0', () {
      Movement move({
        double lengthM = 1,
        double apPerM = 1,
        double speed = 1,
      }) => moveAlong(
        pool: _pool(4),
        start: Duration.zero,
        lengthM: lengthM,
        apPerM: apPerM,
        speedMps: speed,
      );

      expect(() => move(lengthM: -1), throwsArgumentError);
      expect(() => move(apPerM: -1), throwsArgumentError);
      expect(() => move(speed: 0), throwsArgumentError);
    });
  });
}
