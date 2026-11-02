import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

void main() {
  group(UnitsData, () {
    late UnitsData units;

    setUp(() {
      units = UnitsData.parse(readFixture('units.yaml'));
    });

    test('reads the version and every unit type in file order', () {
      expect(units.version, 3);
      expect(units.unitTypes.keys, [
        'commander',
        'engineer',
        'scout',
        'medic',
        'radio',
        'camp',
        'jeep',
        'tank',
        'helicopter',
        'boat',
      ]);
    });

    test('reads the stats, hit box and weapons of a unit type', () {
      final jeep = units.unitTypes['jeep']!;

      expect(jeep.id, 'jeep');
      expect(jeep.category, 'vehicle');
      expect(jeep.movementClass, 'wheeled');
      expect(jeep.armorType, 'light_vehicle');
      expect(
        [jeep.hitBox.width, jeep.hitBox.length, jeep.hitBox.height],
        [2, 4, 1.5],
      );
      final stats = jeep.stats;
      expect(stats.weight, 4);
      expect(stats.hp, 150);
      expect(stats.apMax, 20);
      expect(stats.apPerM, 0.25);
      expect(stats.attack, 8);
      expect(stats.defense, 6);
      expect(stats.moveSpeed, 25);
      expect(stats.visionRange, 120);
      expect(jeep.weapons.defaultWeapon, 'rifle');
      expect(jeep.weapons.allowed, ['rifle']);
      expect(jeep.actions, {UnitAction.capture, UnitAction.push});
    });

    test('reads the defaults of a unit type without role or flags', () {
      final jeep = units.unitTypes['jeep']!;

      expect(jeep.capabilities, isEmpty);
      expect(jeep.canFly, isFalse);
      expect(jeep.canSail, isFalse);
      expect(jeep.flight, isNull);
      expect(jeep.permadeath, isTrue);
      expect(jeep.purchasableBy, isNull);
      expect(jeep.owner, isNull);
      expect(jeep.countsInSectionCap, isTrue);
      expect(jeep.storable, isTrue);
      expect(jeep.role.build, isEmpty);
      expect(jeep.role.repair, isFalse);
      expect(jeep.role.transportable, isTrue);
    });

    test('reads a flying unit and its flight times', () {
      final helicopter = units.unitTypes['helicopter']!;

      expect(helicopter.canFly, isTrue);
      expect(helicopter.canSail, isFalse);
      expect(helicopter.flight?.landTimeS, 6);
      expect(helicopter.flight?.takeOffTimeS, 7);
    });

    test('reads a water-only unit with no ground movement class', () {
      final boat = units.unitTypes['boat']!;

      expect(boat.canSail, isTrue);
      expect(boat.movementClass, isNull);
      expect(boat.role.maxTotalWeight, 4);
      expect(boat.role.maxUnitWeight, 2);
    });

    test('UNIT-03 reads an unarmed unit: no default, nothing allowed', () {
      final radio = units.unitTypes['radio']!;

      expect(radio.weapons.defaultWeapon, isNull);
      expect(radio.weapons.allowed, isEmpty);
      expect(radio.actions, isEmpty);
      expect(radio.purchasableBy, 'commander');
      expect(radio.role.relayRange, 120);
      expect(radio.role.sharesWith, 'all_sections_of_team');
      expect(radio.role.transportable, isFalse);
    });

    test('UNIT-38 reads the actions and role values of each unit type', () {
      final types = units.unitTypes;
      final engineer = types['engineer']!;
      final observe = types['scout']!.role.observe!;
      final medic = types['medic']!.role;

      expect(engineer.actions, {UnitAction.build, UnitAction.repair});
      expect(engineer.role.build, ['wall', 'bridge']);
      expect(engineer.role.repair, isTrue);
      expect(types['scout']!.role.reportsToRadio, isTrue);
      expect(observe.visionBonusM, 20);
      expect(observe.durationS, 600);
      expect(observe.ap, 8);
      expect(observe.canMove, isFalse);
      expect(medic.heal, 15);
      expect(medic.healAp, 6);
      expect(medic.earnsMoneyWhenHealing, isTrue);
      expect(types['commander']!.role.auraRadius, 25);
      expect(types['commander']!.permadeath, isFalse);
    });

    test('reads the section and storage flags of the guild camp', () {
      final camp = units.unitTypes['camp']!;

      expect(camp.owner, 'guild_commander');
      expect(camp.countsInSectionCap, isFalse);
      expect(camp.storable, isFalse);
      expect(camp.actions, isEmpty);
      expect(camp.role.heal, isNull);
    });

    test('UNIT-17 reads the commander levels and the section size rule', () {
      final progression = units.progression;

      expect(progression.commanderLevels.maxLevel, 4);
      expect(progression.commanderLevels.sectionXp, [0, 100, 300, 600]);
      expect(progression.sectionSize.capAtLevel1, 4);
      expect(progression.sectionSize.extraUnitEveryLevels, 3);
      expect(progression.sectionSize.maxUnitsFactor, 2);
      expect(progression.guildSize.sectionsAtLevel1, 2);
      expect(progression.guildSize.extraSectionEveryLevels, 2);
      expect(progression.guildCreationMinLevel, 3);
    });

    test('reads the XP rules', () {
      final progression = units.progression;
      final xp = progression.xpSources;

      expect([xp.hit, xp.kill, xp.roleAction, xp.capture], [1, 10, 3, 40]);
      expect(progression.targetScalingCap, 2.5);
      expect(progression.diminishing.windowS, 300);
      expect(progression.diminishing.factorPerRepeat, 0.25);
      expect(progression.diminishing.sameSpotRadiusM, 5);
      expect(progression.friendlyHitsGiveXp, isFalse);
      expect(progression.victoryXp, 4);
      expect(progression.sectionXpShare, 0.1);
    });

    test('UNIT-23 reads the default evolution tree and extra stats', () {
      final trees = units.trees;

      expect(trees.statCapOfBase, 2);
      expect(trees.defaultTree.stats, ['hp', 'attack']);
      expect(trees.defaultTree.stepBonus, 0.25);
      expect(trees.defaultTree.costBase, 50);
      expect(trees.extraStats, {
        'radio': ['relay_range'],
      });
    });

    test('UNIT-23 reads no extra stats when there are no overrides', () {
      final text = readFixture('units.yaml', {
        '  overrides:\n    radio: { extra_stats: [relay_range] }\n': '',
      });

      expect(UnitsData.parse(text).trees.extraStats, isEmpty);
    });

    test('rejects an unknown capability', () {
      final text = readFixture('units.yaml', {
        'capabilities: [flying]': 'capabilities: [digging]',
      });

      expect(
        () => UnitsData.parse(text),
        throwsDataError(
          'units.yaml',
          'units.helicopter.capabilities[0]',
          'digging',
          'unknown, expected one of flying, sail',
        ),
      );
    });
  });
}
