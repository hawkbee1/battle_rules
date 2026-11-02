import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/plan_data.dart';

const _hour = Duration(hours: 1);

/// A synthetic pool: 10 AP at most, 2 AP per hour, [value] AP at time 0.
ApPool _pool(double value) =>
    ApPool(max: 10, recoveryPerHour: 2, value: value, updatedAt: Duration.zero);

void main() {
  group(ApPool, () {
    test('rejects a non-positive maximum or recovery rate', () {
      expect(
        () => ApPool(max: 0, recoveryPerHour: 1, value: 0, updatedAt: _hour),
        throwsArgumentError,
      );
      expect(
        () => ApPool(max: 5, recoveryPerHour: 0, value: 0, updatedAt: _hour),
        throwsArgumentError,
      );
    });

    test('COMBAT-01 rejects a value outside [0, max]', () {
      expect(() => _pool(-1), throwsArgumentError);
      expect(() => _pool(10.5), throwsArgumentError);
    });

    test('full starts at the maximum', () {
      final pool = ApPool.full(max: 10, recoveryPerHour: 2, at: _hour);

      expect(pool.value, 10);
      expect(pool.updatedAt, _hour);
      expect(pool.max, 10);
      expect(pool.recoveryPerHour, 2);
    });

    test('COMBAT-02 recovers at a constant rate, up to the maximum', () {
      final pool = _pool(1);

      expect(pool.apAt(Duration.zero), 1);
      expect(pool.apAt(const Duration(minutes: 30)), 2);
      expect(pool.apAt(_hour), 3);
      expect(pool.apAt(_hour * 10), 10);
    });

    test('HQ-34 a stored unit recovers at the battle rate, up to its '
        'maximum', () {
      final data = parsePlanData();
      final soldier = data.units.unitTypes['soldier']!;
      final rate = data.battle.ap.recoveryPerHour;
      final empty = ApPool(
        max: soldier.stats.apMax,
        recoveryPerHour: rate,
        value: 0,
        updatedAt: Duration.zero,
      );

      expect(empty.apAt(_hour), rate);
      expect(empty.apAt(_hour * 1000), soldier.stats.apMax);
    });

    test('rejects a time before its last update', () {
      expect(
        () => ApPool.full(
          max: 10,
          recoveryPerHour: 2,
          at: _hour,
        ).apAt(Duration.zero),
        throwsArgumentError,
      );
    });

    group('readyAt', () {
      test('is now when the pool holds the cost', () {
        expect(_pool(4).readyAt(4, Duration.zero), Duration.zero);
      });

      test('COMBAT-06 waits for the missing AP to come back', () {
        expect(_pool(1).readyAt(4, Duration.zero), _hour * 1.5);
        // At 1 h the pool holds 3 AP: half an hour more for the fourth.
        expect(_pool(1).readyAt(4, _hour), const Duration(minutes: 90));
      });

      test('is null for a cost above the maximum', () {
        expect(_pool(10).readyAt(10.5, Duration.zero), isNull);
      });
    });

    group('payWhenReady', () {
      test('pays at once and keeps the rest', () {
        final paid = _pool(6).payWhenReady(4, Duration.zero)!;

        expect(paid.at, Duration.zero);
        expect(paid.pool.value, 2);
        expect(paid.pool.updatedAt, Duration.zero);
      });

      test('COMBAT-06 waits, then pays and leaves the pool empty', () {
        final paid = _pool(1).payWhenReady(4, Duration.zero)!;

        expect(paid.at, _hour * 1.5);
        expect(paid.pool.value, 0);
        expect(paid.pool.updatedAt, _hour * 1.5);
      });

      test('is null for a cost above the maximum', () {
        expect(_pool(10).payWhenReady(11, Duration.zero), isNull);
      });
    });

    test('withValue keeps the maximum and the rate', () {
      final pool = _pool(3).withValue(7, _hour);

      expect(pool.value, 7);
      expect(pool.updatedAt, _hour);
      expect(pool.max, 10);
      expect(pool.recoveryPerHour, 2);
    });
  });
}
