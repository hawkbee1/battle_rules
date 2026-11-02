import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixed_random.dart';
import '../../helpers/plan_data.dart';

void main() {
  late GameData data;
  late ZeroHp zeroHp;
  late UnitType commander;
  late UnitType soldier;

  setUpAll(() {
    data = parsePlanData();
    zeroHp = ZeroHp(rules: data.combat.zeroHp, morale: data.combat.morale);
    commander = data.units.unitTypes['commander']!;
    soldier = data.units.unitTypes['soldier']!;
  });

  ZeroHpOutcome resolve({
    UnitType? attacker,
    UnitType? target,
    bool targetIsEnemy = true,
    double morale = 0,
    double ap = 0,
    bool room = true,
    List<double> rolls = const [0, 0],
  }) => zeroHp.resolve(
    attacker: attacker ?? commander,
    target: target ?? soldier,
    targetIsEnemy: targetIsEnemy,
    moraleValue: morale,
    ap: ap,
    attackerSectionHasRoom: room,
    random: FixedRandom(rolls),
  );

  group('sparedChance', () {
    test('COMBAT-38 spec example: morale 20 and 10 % AP give 51 %', () {
      final apMax = soldier.stats.apMax;

      expect(
        zeroHp.sparedChance(moraleValue: 20, ap: apMax * 0.1, apMax: apMax),
        closeTo(0.51, 1e-9),
      );
    });

    test('COMBAT-39 spec example: morale 50 and full AP give 15 %', () {
      final apMax = soldier.stats.apMax;

      expect(
        zeroHp.sparedChance(moraleValue: 50, ap: apMax, apMax: apMax),
        closeTo(0.15, 1e-9),
      );
    });

    test('COMBAT-39 low morale and low AP raise the odds', () {
      double chance(double morale, double ap) =>
          zeroHp.sparedChance(moraleValue: morale, ap: ap, apMax: 30);

      expect(chance(10, 15), greaterThan(chance(60, 15)));
      expect(chance(50, 3), greaterThan(chance(50, 27)));
    });
  });

  group('resolve', () {
    test('COMBAT-36 a unit brought to 0 HP by a non-commander dies', () {
      expect(resolve(attacker: soldier), ZeroHpOutcome.death);
    });

    test("COMBAT-37 a commander's final blow on an ally always kills", () {
      expect(resolve(targetIsEnemy: false), ZeroHpOutcome.death);
    });

    test('COMBAT-37 decision 149 an enemy commander or a guild camp is never '
        'spared', () {
      expect(resolve(target: commander), ZeroHpOutcome.death);
      expect(
        resolve(target: data.units.unitTypes['encampment']),
        ZeroHpOutcome.death,
      );
    });

    test("COMBAT-38 a commander's final blow on an enemy may spare it", () {
      expect(
        zeroHp.maySpare(
          attacker: commander,
          target: soldier,
          targetIsEnemy: true,
        ),
        isTrue,
      );
      // Spared (0 < 0.6), then 0 < defection_share: it defects.
      expect(resolve(), ZeroHpOutcome.defection);
    });

    test('COMBAT-38 a roll at or above the chance kills', () {
      // Morale 0 and 0 AP: the chance is k.
      expect(resolve(rolls: [data.combat.zeroHp.k, 0]), ZeroHpOutcome.death);
    });

    test('COMBAT-38 a spared unit is taken prisoner by defection_share', () {
      expect(
        resolve(rolls: [0, data.combat.zeroHp.defectionShare]),
        ZeroHpOutcome.prisoner,
      );
    });

    test('UNIT-39 a defector needs room in the section, otherwise it is taken '
        'prisoner', () {
      expect(resolve(room: false), ZeroHpOutcome.prisoner);
    });

    test('COMBAT-41 a defector can defect again under the same rules', () {
      // The former defector, now on the other side, falls to a commander.
      expect(resolve(), ZeroHpOutcome.defection);
      expect(resolve(), ZeroHpOutcome.defection);
    });
  });

  test('COMBAT-40 COMBAT-43 a defector and a prisoner keep their weapon; a '
      'dead unit drops it', () {
    expect(ZeroHpOutcome.defection.dropsWeapon, isFalse);
    expect(ZeroHpOutcome.prisoner.dropsWeapon, isFalse);
    expect(ZeroHpOutcome.death.dropsWeapon, isTrue);
  });

  test('COMBAT-43 prisoner storage is separate and unlimited', () {
    var storage = const PrisonerStorage();
    for (var prisoner = 0; prisoner < 500; prisoner++) {
      storage = storage.added('p$prisoner');
    }

    expect(storage.prisoners, hasLength(500));
    expect(() => storage.prisoners.add('x'), throwsUnsupportedError);
  });

  test('UNIT-39 the section size cap grows by one every few commander '
      'levels', () {
    final size = data.units.progression.sectionSize;
    final maxLevel = data.units.progression.commanderLevels.maxLevel;

    // The spec examples: 5 at levels 1 to 5, 6 at levels 6 to 10, 16 at 60.
    expect(size.capAt(1), 5);
    expect(size.capAt(5), 5);
    expect(size.capAt(6), 6);
    expect(size.capAt(maxLevel), 16);
    expect(size.hasRoom(level: 1, activeUnits: 4), isTrue);
    expect(size.hasRoom(level: 1, activeUnits: 5), isFalse);
  });
}
