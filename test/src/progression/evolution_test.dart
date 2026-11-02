import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

void main() {
  group('Evolution on the fixtures', () {
    // Fixture tree: hp and attack, +25 % a step up to ×2 (4 steps), step n
    // costs 50 × n XP; the radio adds relay_range.
    late Evolution evolution;
    late UnitsData units;

    setUp(() {
      units = UnitsData.parse(readFixture('units.yaml'));
      evolution = Evolution(units.trees);
    });

    UnitType type(String id) => units.unitTypes[id]!;

    NodePurchase buy(
      EvolvableStat stat,
      int step, {
      SkillTree? tree,
      double xp = 1000,
      String unit = 'jeep',
    }) => evolution.buy(
      type: type(unit),
      tree: tree ?? SkillTree(),
      stat: stat,
      step: step,
      unspentXp: xp,
    );

    NodeRefusal? refusal(NodePurchase purchase) => switch (purchase) {
      NodeRefused(:final reason) => reason,
      NodeBought() => null,
    };

    test(
      "UNIT-23 a type's tree is the default stats, then its extra stats",
      () {
        expect(evolution.statsOf(type('jeep')), [
          EvolvableStat.hp,
          EvolvableStat.attack,
        ]);
        expect(evolution.statsOf(type('radio')), [
          EvolvableStat.hp,
          EvolvableStat.attack,
          EvolvableStat.relayRange,
        ]);
      },
    );

    test('UNIT-23 step n costs cost_base × n and adds step_bonus of base', () {
      expect(evolution.stepCost(1), 50);
      expect(evolution.stepCost(3), 150);
      expect(evolution.factor(2), 1.5);
    });

    test('UNIT-18 a unit pays a node with its own unspent XP', () {
      final bought = buy(EvolvableStat.hp, 1, xp: 70) as NodeBought;

      expect(bought.xpLeft, 20);
      expect(bought.tree.stepsOf(EvolvableStat.hp), 1);
      expect(
        refusal(buy(EvolvableStat.hp, 1, xp: 49)),
        NodeRefusal.notEnoughXp,
      );
    });

    test('UNIT-19 a step needs the step before it', () {
      expect(
        refusal(buy(EvolvableStat.hp, 2)),
        NodeRefusal.prerequisiteMissing,
      );
      final first = buy(EvolvableStat.hp, 1) as NodeBought;
      final second = buy(EvolvableStat.hp, 2, tree: first.tree) as NodeBought;

      expect(second.tree.stepsOf(EvolvableStat.hp), 2);
    });

    test('UNIT-21 nodes stay bought and never exclude each other', () {
      final hp = buy(EvolvableStat.hp, 1) as NodeBought;
      final both = buy(EvolvableStat.attack, 1, tree: hp.tree) as NodeBought;

      expect(both.tree.steps, {EvolvableStat.hp: 1, EvolvableStat.attack: 1});
      expect(hp.tree.steps, {EvolvableStat.hp: 1});
      expect(
        refusal(buy(EvolvableStat.hp, 1, tree: both.tree)),
        NodeRefusal.alreadyBought,
      );
      expect(both.tree.steps.clear, throwsUnsupportedError);
    });

    test('UNIT-22 a stat stops at stat_cap_of_base × base', () {
      expect(evolution.maxSteps, 4);
      final capped = SkillTree({EvolvableStat.hp: 4});

      expect(
        refusal(buy(EvolvableStat.hp, 5, tree: capped)),
        NodeRefusal.aboveCap,
      );
      expect(evolution.evolve(type('jeep'), capped).stats.hp, 2 * 150);
      expect(
        evolution
            .evolve(type('jeep'), SkillTree({EvolvableStat.hp: 9}))
            .stats
            .hp,
        2 * 150,
      );
    });

    test('UNIT-23 a stat off the type tree is refused', () {
      expect(refusal(buy(EvolvableStat.relayRange, 1)), NodeRefusal.notInTree);
      expect(refusal(buy(EvolvableStat.defense, 1)), NodeRefusal.notInTree);
      expect(refusal(buy(EvolvableStat.relayRange, 1, unit: 'radio')), isNull);
    });

    test('UNIT-22 AP maximum and AP per metre never evolve', () {
      expect(EvolvableStat.byKey('ap_max'), isNull);
      expect(EvolvableStat.byKey('ap_per_m'), isNull);
      final evolved = evolution.evolve(
        type('jeep'),
        SkillTree({EvolvableStat.hp: 4, EvolvableStat.attack: 4}),
      );

      expect(evolved.stats.apMax, type('jeep').stats.apMax);
      expect(evolved.stats.apPerM, type('jeep').stats.apPerM);
      expect(evolved.stats.attack, 2 * type('jeep').stats.attack);
    });

    test('UNIT-20 a unit with no node plays its base type', () {
      final jeep = type('jeep');

      expect(identical(evolution.evolve(jeep, SkillTree()), jeep), isTrue);
      expect(SkillTree({EvolvableStat.hp: 0}).steps, isEmpty);
    });

    test('UNIT-20 evolving keeps everything but the stats it raises', () {
      final radio = type('radio');
      final evolved = evolution.evolve(
        radio,
        SkillTree({EvolvableStat.relayRange: 1}),
      );

      expect(evolved.id, radio.id);
      expect(evolved.stats.hp, radio.stats.hp);
      expect(evolved.stats.moveSpeed, radio.stats.moveSpeed);
      expect(evolved.role.relayRange, 1.25 * 120);
      expect(evolved.role.transportable, isFalse);
      expect(evolved.role.heal, isNull);
    });

    test('rejects a tree with a stat off the type tree', () {
      expect(
        () => evolution.evolve(
          type('jeep'),
          SkillTree({EvolvableStat.relayRange: 1}),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Evolution on the plan data', () {
    late GameData data;
    late Evolution evolution;

    setUp(() {
      data = parsePlanData();
      evolution = Evolution(data.units.trees);
    });

    UnitType type(String id) => data.units.unitTypes[id]!;

    UnitType evolved(String id, EvolvableStat stat, [int steps = 1]) =>
        evolution.evolve(type(id), SkillTree({stat: steps}));

    test('UNIT-23 the plan tree reaches ×3 in 20 steps of 10 %', () {
      expect(evolution.maxSteps, 20);
      expect(evolution.factor(20), closeTo(3, 1e-9));
      expect(evolution.stepCost(20), 2000);
    });

    test('UNIT-22 the evolved hp is the maximum HP the rules use', () {
      final tank = evolved('tank', EvolvableStat.hp, 20);
      final damage = Damage(data.combat);

      expect(tank.stats.hp, closeTo(3 * type('tank').stats.hp, 1e-9));
      expect(
        damage.ejection(tank.stats),
        closeTo(3 * damage.ejection(type('tank').stats), 1e-9),
      );
    });

    test('UNIT-22 an evolved attack hits more, an evolved defense less', () {
      final rifle = data.combat.weaponTypes['rifle']!;
      double chance(UnitType shooter, UnitType target) =>
          HitChance(data.combat).of(
            weapon: rifle,
            attack: shooter.stats.attack,
            morale: 50,
            defense: target.stats.defense,
            targetArmor: target.armorType,
            targetSpeedMps: 0,
            distanceM: rifle.rangeM,
          );
      final base = chance(type('soldier'), type('soldier'));

      expect(
        chance(evolved('soldier', EvolvableStat.attack, 10), type('soldier')),
        greaterThan(base),
      );
      expect(
        chance(type('soldier'), evolved('soldier', EvolvableStat.defense, 10)),
        lessThan(base),
      );
    });

    test('UNIT-22 an evolved speed is the speed a move uses', () {
      final scout = evolved('scout', EvolvableStat.moveSpeed, 5);

      expect(
        Mover.unit(scout).speedMps,
        closeTo(1.5 * type('scout').stats.moveSpeed, 1e-9),
      );
    });

    test('UNIT-22 an evolved vision range sees farther', () {
      final vision = Vision(data.terrain);
      final line = SightLine(
        distanceM: type('scout').stats.visionRange + 10,
        observerTerrain: 'grass',
      );
      bool sees(UnitType unit) => vision.unitSees(
        unit: unit,
        weather: 'clear',
        line: line,
        time: Duration.zero,
      );

      expect(sees(type('scout')), isFalse);
      expect(sees(evolved('scout', EvolvableStat.visionRange)), isTrue);
    });

    test('UNIT-23 an evolved heal restores more HP', () {
      final rules = RoleActionRules(combat: data.combat, terrain: data.terrain);
      Healed heal(UnitType medic) => rules.heal(
        unit: medic,
        target: const ActionTarget(friendly: true),
        health: const Health(current: 1, max: 1000),
        pool: ApPool(
          max: 30,
          recoveryPerHour: 1,
          value: 30,
          updatedAt: Duration.zero,
        ),
        now: Duration.zero,
      ) as Healed;

      expect(
        heal(evolved('medic', EvolvableStat.heal, 5)).health.current,
        closeTo(1 + 1.5 * type('medic').role.heal!, 1e-9),
      );
      expect(heal(type('medic')).health.current, 1 + type('medic').role.heal!);
    });

    test('UNIT-36 COMBAT-52 a radio relay range grows through its tree', () {
      expect(
        evolved('radio', EvolvableStat.relayRange, 2).role.relayRange,
        closeTo(1.2 * type('radio').role.relayRange!, 1e-9),
      );
    });

    test('UNIT-23 aura radius and transport weight grow on their types', () {
      expect(
        evolved('commander', EvolvableStat.auraRadius).role.auraRadius,
        closeTo(1.1 * type('commander').role.auraRadius!, 1e-9),
      );
      expect(
        evolved('truck', EvolvableStat.maxTotalWeight).role.maxTotalWeight,
        closeTo(1.1 * type('truck').role.maxTotalWeight!, 1e-9),
      );
    });

    test('decision 178 an evolved helicopter outruns a jeep that has not '
        'evolved', () {
      final helicopter = evolved('helicopter', EvolvableStat.moveSpeed);

      expect(
        Mover.unit(helicopter, flying: true).speedMps,
        greaterThan(Mover.unit(type('jeep')).speedMps),
      );
      expect(
        type('helicopter').stats.moveSpeed,
        lessThanOrEqualTo(type('jeep').stats.moveSpeed),
      );
    });
  });
}
