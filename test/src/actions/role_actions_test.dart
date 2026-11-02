import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

/// A pool with [ap] AP at time 0, recovering 1 AP per hour.
ApPool _pool(double ap, {double max = 20}) =>
    ApPool(max: max, recoveryPerHour: 1, value: ap, updatedAt: Duration.zero);

const _friend = ActionTarget(friendly: true);

void main() {
  late RoleActionRules rules;
  late UnitsData units;

  setUp(() {
    rules = RoleActionRules(
      combat: CombatData.parse(readFixture('combat.yaml')),
      terrain: TerrainData.parse(readFixture('terrain.yaml')),
    );
    units = UnitsData.parse(readFixture('units.yaml'));
  });

  TimedActionStarted started(ActionResult result) =>
      result as TimedActionStarted;
  ActionRefusal refusal(ActionResult result) =>
      (result as ActionRefused).reason;

  group('build', () {
    test('COMBAT-07 UNIT-33 an engineer pays the structure AP up front, then '
        'builds for its build time', () {
      final build = started(
        rules.startBuild(
          unit: units.unitTypes['engineer']!,
          structure: 'wall',
          pool: _pool(20),
          now: const Duration(seconds: 5),
        ),
      );

      expect(build.at, const Duration(seconds: 5));
      expect(build.pool.value, 13);
      expect(build.action.endsAt, const Duration(seconds: 205));
    });

    test('UNIT-33 an engineer builds only the structures of its role', () {
      expect(
        refusal(
          rules.startBuild(
            unit: units.unitTypes['engineer']!,
            structure: 'trap',
            pool: _pool(20),
            now: Duration.zero,
          ),
        ),
        ActionRefusal.notBuildable,
      );
    });

    test('COMBAT-06 a build waits until the unit has the AP', () {
      final build = started(
        rules.startBuild(
          unit: units.unitTypes['engineer']!,
          structure: 'wall',
          pool: _pool(2),
          now: Duration.zero,
        ),
      );

      expect(build.at, const Duration(hours: 5));
      expect(build.pool.value, 0);
    });

    test('refuses a build that costs more than the pool can hold', () {
      expect(
        refusal(
          rules.startBuild(
            unit: units.unitTypes['engineer']!,
            structure: 'wall',
            pool: _pool(5, max: 5),
            now: Duration.zero,
          ),
        ),
        ActionRefusal.costAboveApMax,
      );
    });
  });

  group('interruption', () {
    test('COMBAT-09 an interrupted build loses its AP and keeps its progress; '
        'resuming costs the part left', () {
      final build = started(
        rules.startBuild(
          unit: units.unitTypes['engineer']!,
          structure: 'wall',
          pool: _pool(20),
          now: Duration.zero,
        ),
      );
      // Half of its 200 s.
      final paused = build.action.interruptedAt(const Duration(seconds: 100));

      expect(paused.progress, 0.5);
      expect(paused.endsAt, isNull);
      expect(paused.remainingAp, 3.5);
      expect(paused.progressAt(const Duration(hours: 1)), 0.5);

      final resumed = started(
        rules.resume(
          action: paused,
          pool: _pool(10),
          now: const Duration(seconds: 1000),
        ),
      );
      // 10 AP and 1000 s of recovery, less the 3.5 AP of the half left.
      expect(resumed.pool.value, closeTo(10 + 1000 / 3600 - 3.5, 1e-9));
      expect(resumed.action.endsAt, const Duration(seconds: 1100));
      expect(resumed.action.progressAt(const Duration(hours: 1)), 1);
    });
  });

  test('an action of no duration is done at once', () {
    const action = TimedAction(
      ap: 1,
      duration: Duration.zero,
      startedAt: Duration.zero,
    );

    expect(action.progressAt(Duration.zero), 1);
  });

  group('repair', () {
    test(
      'COMBAT-07 a repair costs its AP up front, then takes its duration',
      () {
        final repair = started(
          rules.startRepair(
            unit: units.unitTypes['engineer']!,
            target: _friend,
            pool: _pool(20),
            now: Duration.zero,
          ),
        );

        expect(repair.pool.value, 11);
        expect(repair.action.endsAt, const Duration(seconds: 12));
        expect(rules.repairHp, 40);
      },
    );

    test('UNIT-33 decision 139 repairs friendly units only, never the HQ', () {
      ActionResult repair(ActionTarget target) => rules.startRepair(
        unit: units.unitTypes['engineer']!,
        target: target,
        pool: _pool(20),
        now: Duration.zero,
      );

      expect(
        refusal(repair(const ActionTarget(friendly: false))),
        ActionRefusal.targetNotFriendly,
      );
      expect(
        refusal(repair(const ActionTarget(friendly: true, isHq: true))),
        ActionRefusal.targetIsHq,
      );
    });
  });

  group('heal', () {
    late UnitType medic;

    setUp(() {
      medic = units.unitTypes['medic']!;
    });

    ActionResult heal(
      Health health, {
      ActionTarget target = _friend,
      ApPool? pool,
    }) => rules.heal(
      unit: medic,
      target: target,
      health: health,
      pool: pool ?? _pool(20),
      now: const Duration(minutes: 3),
    );

    test('UNIT-35 healing is instant: heal_ap restores heal HP', () {
      final healed = heal(const Health(current: 50, max: 70)) as Healed;

      expect(healed.at, const Duration(minutes: 3));
      // A full pool stays at its maximum: 20 − 6.
      expect(healed.pool.value, 14);
      expect(healed.health.current, 65);
    });

    test('UNIT-35 healing stops at the maximum HP', () {
      final healed = heal(const Health(current: 60, max: 70)) as Healed;

      expect(healed.health.current, 70);
    });

    test('UNIT-35 decision 139 heals friendly units only, never the HQ', () {
      const health = Health(current: 1, max: 9);

      expect(
        refusal(heal(health, target: const ActionTarget(friendly: false))),
        ActionRefusal.targetNotFriendly,
      );
      expect(
        refusal(
          heal(health, target: const ActionTarget(friendly: true, isHq: true)),
        ),
        ActionRefusal.targetIsHq,
      );
    });

    test('refuses a heal that costs more than the pool can hold', () {
      expect(
        refusal(heal(const Health(current: 1, max: 9), pool: _pool(1, max: 5))),
        ActionRefusal.costAboveApMax,
      );
    });
  });

  test('UNIT-38 refuses a role action the unit type does not list', () {
    final commander = units.unitTypes['commander']!;

    expect(
      refusal(
        rules.startBuild(
          unit: commander,
          structure: 'wall',
          pool: _pool(20),
          now: Duration.zero,
        ),
      ),
      ActionRefusal.notInActions,
    );
    expect(
      refusal(
        rules.startRepair(
          unit: commander,
          target: _friend,
          pool: _pool(20),
          now: Duration.zero,
        ),
      ),
      ActionRefusal.notInActions,
    );
    expect(
      refusal(
        rules.heal(
          unit: commander,
          target: _friend,
          health: const Health(current: 1, max: 2),
          pool: _pool(20),
          now: Duration.zero,
        ),
      ),
      ActionRefusal.notInActions,
    );
  });
}
