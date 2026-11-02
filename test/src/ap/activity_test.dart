import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/plan_data.dart';

void main() {
  late GameData data;
  late UnitType soldier;
  late UnitType engineer;
  late UnitType radio;
  late WeaponType rifle;

  ApPool fullPool(UnitType unit) => ApPool.full(
    max: unit.stats.apMax,
    recoveryPerHour: data.battle.ap.recoveryPerHour,
    at: Duration.zero,
  );

  setUpAll(() {
    data = parsePlanData();
    soldier = data.units.unitTypes['soldier']!;
    engineer = data.units.unitTypes['engineer']!;
    radio = data.units.unitTypes['radio']!;
    rifle = data.combat.weaponTypes[soldier.weapons.defaultWeapon]!;
  });

  ActivityStarts started(ActivityStart start) => start as ActivityStarts;

  group('startActivity', () {
    test('COMBAT-05 time-only actions start at once and leave the AP', () {
      final pool = fullPool(soldier).withValue(3, Duration.zero);
      const now = Duration(minutes: 5);

      for (final action in TimeOnlyAction.values) {
        final start = started(
          startActivity(unit: soldier, pool: pool, activity: action, now: now),
        );

        expect(start.at, now, reason: action.name);
        expect(start.pool, same(pool), reason: action.name);
      }
    });

    test('COMBAT-04 a shot costs the weapon ap_per_shot', () {
      final start = started(
        startActivity(
          unit: soldier,
          pool: fullPool(soldier),
          activity: Shot(rifle),
          now: Duration.zero,
        ),
      );

      expect(start.at, Duration.zero);
      expect(start.pool.value, soldier.stats.apMax - rifle.apPerShot);
    });

    test('COMBAT-04 picking up a weapon costs pickup_ap', () {
      final start = started(
        startActivity(
          unit: soldier,
          pool: fullPool(soldier),
          activity: WeaponPickup(data.combat.droppedWeapons),
          now: Duration.zero,
        ),
      );

      expect(
        start.pool.value,
        soldier.stats.apMax - data.combat.droppedWeapons.pickupAp,
      );
    });

    test('COMBAT-04 a role action costs its AP up front', () {
      final repairAp = data.combat.actions.repair.ap;
      final start = started(
        startActivity(
          unit: engineer,
          pool: fullPool(engineer),
          activity: RoleActionStart(UnitAction.repair, repairAp),
          now: Duration.zero,
        ),
      );

      expect(start.pool.value, engineer.stats.apMax - repairAp);
    });

    test('COMBAT-01 every paid action draws from the one pool', () {
      var pool = fullPool(soldier);
      final activities = <PaidAction>[
        Shot(rifle),
        WeaponPickup(data.combat.droppedWeapons),
        RoleActionStart(UnitAction.capture, data.battle.capture.contributionAp),
      ];
      for (final activity in activities) {
        pool = started(
          startActivity(
            unit: soldier,
            pool: pool,
            activity: activity,
            now: Duration.zero,
          ),
        ).pool;
      }

      expect(
        pool.value,
        soldier.stats.apMax -
            activities.fold<double>(0, (sum, action) => sum + action.ap),
      );
    });

    test('COMBAT-06 a paid action waits until the unit has enough AP', () {
      final rate = data.battle.ap.recoveryPerHour;
      final empty = fullPool(soldier).withValue(0, Duration.zero);
      final start = started(
        startActivity(
          unit: soldier,
          pool: empty,
          activity: Shot(rifle),
          now: Duration.zero,
        ),
      );
      final wait = Duration(
        microseconds: (rifle.apPerShot / rate * Duration.microsecondsPerHour)
            .ceil(),
      );

      expect(start.at, wait);
      expect(start.pool.value, 0);
    });

    test('UNIT-38 refuses a role action the unit type does not list', () {
      final capture = startActivity(
        unit: radio,
        pool: fullPool(radio),
        activity: RoleActionStart(
          UnitAction.capture,
          data.battle.capture.contributionAp,
        ),
        now: Duration.zero,
      );
      final build = startActivity(
        unit: soldier,
        pool: fullPool(soldier),
        activity: const RoleActionStart(UnitAction.build, 0),
        now: Duration.zero,
      );

      expect((capture as ActivityRefused).reason, Refusal.notInActions);
      expect((build as ActivityRefused).reason, Refusal.notInActions);
    });

    test('refuses an action that costs more than the pool can hold', () {
      final start = startActivity(
        unit: soldier,
        pool: fullPool(soldier),
        activity: RoleActionStart(UnitAction.capture, soldier.stats.apMax + 1),
        now: Duration.zero,
      );

      expect((start as ActivityRefused).reason, Refusal.costAboveApMax);
    });
  });
}
