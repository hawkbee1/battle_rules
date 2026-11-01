import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

void main() {
  late CombatData combat;
  late Damage damage;
  late WeaponType rifle;
  late WeaponType cannon;

  setUp(() {
    combat = CombatData.parse(readFixture('combat.yaml'));
    damage = Damage(combat);
    rifle = combat.weaponTypes['rifle']!;
    cannon = combat.weaponTypes['cannon']!;
  });

  const infantry = DamageTarget(armorType: 'infantry');

  group('the current plan data', () {
    late GameData data;
    late Damage planDamage;

    setUpAll(() {
      data = parsePlanData();
      planDamage = Damage(data.combat);
    });

    test('COMBAT-21 every weapon against every armor type deals base damage '
        'times the table multiplier', () {
      // Read the table without battle_rules, so the test does not mirror it.
      final raw = loadYaml(readPlanData('combat.yaml')) as Map;
      final weapons = raw['weapon_types'] as Map;
      final table = raw['multipliers'] as Map;
      for (final weapon in data.combat.weaponTypes.values) {
        final baseDamage = (weapons[weapon.id] as Map)['base_damage'] as num;
        for (final armor in raw['armor_types'] as List) {
          final multiplier = (table[weapon.id] as Map)[armor] as num;

          expect(
            planDamage.hit(weapon, DamageTarget(armorType: armor as String)),
            closeTo(baseDamage * multiplier, 1e-9),
            reason: '${weapon.id} on $armor',
          );
        }
      }
    });

    test('COMBAT-22 relics take no damage', () {
      for (final weapon in data.combat.weaponTypes.values) {
        expect(
          planDamage.hit(weapon, const DamageTarget(armorType: 'relic')),
          0,
          reason: weapon.id,
        );
      }
    });

    test('COMBAT-34 friendly fire deals full damage', () {
      for (final weapon in data.combat.weaponTypes.values) {
        expect(
          planDamage.hit(
            weapon,
            const DamageTarget(armorType: 'infantry', friendly: true),
          ),
          planDamage.hit(weapon, infantry),
          reason: weapon.id,
        );
      }
    });

    test('HQ-22 the HQ has the battle HP and armor type hq', () {
      final hq = Health.full(data.battle.hq.hp);

      expect(hq.current, data.battle.hq.hp);
      expect(data.combat.armorTypes, contains('hq'));
      expect(data.combat.multipliers['rifle'], contains('hq'));
    });

    test('HQ-16 the HQ takes hits through armor type hq until its HP '
        'are gone', () {
      final rifle = data.combat.weaponTypes['rifle']!;
      final perHit = planDamage.hit(rifle, const DamageTarget(armorType: 'hq'));
      var hq = Health.full(data.battle.hq.hp);
      var hits = 0;
      while (!hq.isZero) {
        hq = hq.damaged(perHit);
        hits++;
      }

      expect(hits, (data.battle.hq.hp / perHit).ceil());
      expect(hq.current, 0);
    });
  });

  group('hit', () {
    test('COMBAT-20 uses the weapon type and the target armor type', () {
      expect(damage.hit(rifle, infantry), 10);
      expect(
        damage.hit(rifle, const DamageTarget(armorType: 'heavy_vehicle')),
        1,
      );
    });

    test('COMBAT-24 COMBAT-25 a flying target takes the airborne factor '
        'on top of its armor type', () {
      const flying = DamageTarget(armorType: 'light_vehicle', flying: true);

      // 10 × 0.5 × 0.25.
      expect(damage.hit(rifle, flying), 1.25);
    });

    test('COMBAT-25 a weapon with an airborne factor of 0 cannot hurt a '
        'flying unit', () {
      const flying = DamageTarget(armorType: 'light_vehicle', flying: true);

      expect(damage.hit(cannon, flying), 0);
      expect(
        damage.hit(cannon, const DamageTarget(armorType: 'light_vehicle')),
        50,
      );
    });

    test('COMBAT-34 friendly fire takes the friendly-fire factor', () {
      expect(
        damage.hit(
          rifle,
          const DamageTarget(armorType: 'infantry', friendly: true),
        ),
        5,
      );
    });

    test('friendly fire switched off spares friends', () {
      final off = Damage(
        CombatData.parse(
          readFixture('combat.yaml', {
            'friendly_fire: { enabled: true,':
                'friendly_fire: { enabled: false,',
          }),
        ),
      );

      expect(
        off.hit(
          rifle,
          const DamageTarget(armorType: 'infantry', friendly: true),
        ),
        0,
      );
      expect(off.hit(rifle, infantry), 10);
    });

    test('MAP-40 a terrain object takes damage through its armor type', () {
      final terrain = TerrainData.parse(readFixture('terrain.yaml'));
      final wall = terrain.objects['wall']!;

      expect(damage.hit(rifle, DamageTarget(armorType: wall.armorType)), 2);
    });

    test('rejects an unknown armor type', () {
      expect(
        () => damage.hit(rifle, const DamageTarget(armorType: 'titanium')),
        throwsArgumentError,
      );
    });
  });

  group('splash', () {
    test('COMBAT-55 damage falls off linearly from the impact point to the '
        'edge', () {
      expect(damage.splashFactor(cannon, 0), 1);
      expect(damage.splashFactor(cannon, 3), 0.625);
      expect(damage.splashFactor(cannon, 6), 0.25);
      expect(damage.splash(cannon, infantry, 3), 31.25);
    });

    test('COMBAT-55 a unit beyond the radius is not hit', () {
      expect(damage.splashFactor(cannon, 6.1), 0);
      expect(damage.splash(cannon, infantry, 6.1), 0);
    });

    test('COMBAT-55 friend and foe are hit alike, without a roll', () {
      const friend = DamageTarget(armorType: 'infantry', friendly: true);

      expect(damage.splash(cannon, friend, 0), damage.hit(cannon, friend));
    });

    test('a weapon without splash hits nothing around the impact', () {
      expect(damage.splashFactor(rifle, 0), 0);
    });

    test('rejects a falloff other than linear', () {
      final curved = Damage(
        CombatData.parse(
          readFixture('combat.yaml', {'falloff: linear': 'falloff: square'}),
        ),
      );

      expect(() => curved.splashFactor(cannon, 1), throwsUnsupportedError);
    });
  });

  group('transports', () {
    test('UNIT-37 a carried unit takes its share of each hit, with its own '
        'armor type', () {
      // The truck (light vehicle) takes 10 × 0.5; the carried infantry
      // takes 0.2 × 10 × 1.
      expect(
        damage.hit(rifle, const DamageTarget(armorType: 'light_vehicle')),
        5,
      );
      expect(damage.carriedHit(rifle, infantry), 2);
    });

    test('COMBAT-54 an ejected unit loses a share of its maximum HP', () {
      final units = UnitsData.parse(readFixture('units.yaml'));
      final commander = units.unitTypes['commander']!;

      // 0.4 × 100 HP.
      expect(damage.ejection(commander.stats), 40);
    });
  });

  group(Health, () {
    test('COMBAT-36 loses HP down to 0, not below', () {
      final health = Health.full(30).damaged(12);

      expect(health.current, 18);
      expect(health.max, 30);
      expect(health.isZero, isFalse);
      expect(health.damaged(25).current, 0);
      expect(health.damaged(25).isZero, isTrue);
    });
  });
}
