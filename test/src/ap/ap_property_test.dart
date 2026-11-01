import 'dart:math';

import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/plan_data.dart';

void main() {
  test('COMBAT-01 AP stay within [0, ap_max] for any sequence of actions '
      'and time steps', () {
    final data = parsePlanData();
    final weapons = data.combat.weaponTypes.values.toList();
    final units = data.units.unitTypes.values.toList();

    for (var seed = 0; seed < 50; seed++) {
      final random = Random(seed);
      final unit = units[random.nextInt(units.length)];
      final max = unit.stats.apMax;
      var pool = ApPool.full(
        max: max,
        recoveryPerHour: data.battle.ap.recoveryPerHour,
        at: Duration.zero,
      );
      var now = Duration.zero;

      for (var step = 0; step < 200; step++) {
        now += Duration(seconds: random.nextInt(3 * 3600));
        // A null activity stands for a move, which goes through moveAlong.
        final activity = switch (random.nextInt(5)) {
          0 => Shot(weapons[random.nextInt(weapons.length)]),
          1 => WeaponPickup(data.combat.droppedWeapons),
          2 => RoleActionStart(
            UnitAction.values[random.nextInt(UnitAction.values.length)],
            random.nextDouble() * (max + 5),
          ),
          3 =>
            TimeOnlyAction.values[random.nextInt(TimeOnlyAction.values.length)],
          _ => null as Activity?,
        };
        if (activity == null) {
          final move = moveAlong(
            pool: pool,
            start: now,
            lengthM: random.nextDouble() * 50,
            apPerM: unit.stats.apPerM * (0.5 + random.nextDouble() * 3),
            speedMps: unit.stats.moveSpeed,
          );
          expect(move.arrivesAt, greaterThanOrEqualTo(now));
          (pool, now) = (move.pool, move.arrivesAt);
        } else if (startActivity(
              unit: unit,
              pool: pool,
              activity: activity,
              now: now,
            )
            case ActivityStarts(:final at, pool: final after)) {
          expect(at, greaterThanOrEqualTo(now));
          (pool, now) = (after, at);
        }
        for (final time in [now, now + const Duration(hours: 100)]) {
          expect(
            pool.apAt(time),
            inInclusiveRange(0, max),
            reason: 'seed $seed, step $step',
          );
        }
      }
    }
  });
}
