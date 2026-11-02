import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

/// The keys of the map at [key] in the plan file [text], read without
/// `battle_rules`.
List<String> _rawKeys(String text, String key) => [
  for (final name in ((loadYaml(text) as Map)[key] as Map).keys) '$name',
];

Object? _rawVersion(String text) => (loadYaml(text) as Map)['version'];

void main() {
  group('the current plan data', () {
    late GameData data;

    setUpAll(() {
      data = parsePlanData();
    });

    test('loads without error', () {
      expect(data.units.unitTypes, isNotEmpty);
      expect(data.combat.weaponTypes, isNotEmpty);
      expect(data.terrain.terrainTypes, isNotEmpty);
    });

    test("keeps each file's version", () {
      expect(data.units.version, _rawVersion(readPlanData('units.yaml')));
      expect(data.combat.version, _rawVersion(readPlanData('combat.yaml')));
      expect(data.terrain.version, _rawVersion(readPlanData('terrain.yaml')));
      expect(data.battle.version, _rawVersion(readPlanData('battle.yaml')));
      expect(data.economy.version, _rawVersion(readPlanEconomy()));
      expect(data.medals.version, _rawVersion(readPlanData('medals.yaml')));
    });

    test('reads every unit type, weapon type, terrain type and object', () {
      final units = readPlanData('units.yaml');
      final combat = readPlanData('combat.yaml');
      final terrain = readPlanData('terrain.yaml');

      expect(data.units.unitTypes.keys, _rawKeys(units, 'units'));
      expect(data.combat.weaponTypes.keys, _rawKeys(combat, 'weapon_types'));
      expect(data.terrain.terrainTypes.keys, _rawKeys(terrain, 'terrain'));
      expect(data.terrain.objects.keys, _rawKeys(terrain, 'objects'));
    });

    test('COMBAT-22 has the armor types of the spec', () {
      expect(
        data.combat.armorTypes,
        unorderedEquals([
          'infantry',
          'light_vehicle',
          'heavy_vehicle',
          'structure',
          'relic',
          'hq',
        ]),
      );
    });
  });

  group('GameData.parse', () {
    test('loads the fixtures without error', () {
      final data = parseFixtures();

      expect(data.units.unitTypes, hasLength(10));
      expect(data.combat.weaponTypes, hasLength(3));
      expect(data.terrain.terrainTypes, hasLength(6));
      expect(data.battle.ap.max, 20);
      expect(data.economy.currency, 'w€');
      expect(data.medals.tiers, hasLength(3));
    });

    group('armor and weapons', () {
      test('COMBAT-20 rejects a unit armor type not in armor_types', () {
        expect(
          () => parseFixtures(
            units: {'armor_type: heavy_vehicle': 'armor_type: titanium'},
          ),
          throwsDataError(
            'units.yaml',
            'units.tank.armor_type',
            'titanium',
            'not in combat.yaml armor_types '
                '[infantry, light_vehicle, heavy_vehicle, structure]',
          ),
        );
      });

      test('UNIT-03 rejects an unarmed unit that allows a weapon', () {
        expect(
          () => parseFixtures(
            units: {
              'weapons: { default: null, allowed: [] }\n    actions: []':
                  'weapons: { default: null, allowed: [rifle] }\n'
                  '    actions: []',
            },
          ),
          throwsDataError(
            'units.yaml',
            'units.radio.weapons.default',
            null,
            'an unarmed unit allows no weapon, but allowed is [rifle]',
          ),
        );
      });

      test('UNIT-03 rejects a default weapon not in the allowed list', () {
        expect(
          () => parseFixtures(
            units: {
              'default: cannon, allowed: [cannon]':
                  'default: rifle, allowed: [cannon]',
            },
          ),
          throwsDataError(
            'units.yaml',
            'units.tank.weapons.default',
            'rifle',
            'not in its allowed list [cannon]',
          ),
        );
      });

      test('UNIT-03 rejects an allowed weapon not in weapon_types', () {
        expect(
          () => parseFixtures(
            units: {'allowed: [rifle, charge]': 'allowed: [rifle, laser]'},
          ),
          throwsDataError(
            'units.yaml',
            'units.engineer.weapons.allowed[1]',
            'laser',
            'not in combat.yaml weapon_types',
          ),
        );
      });

      test('COMBAT-23 rejects a weapon without a multipliers row', () {
        expect(
          () => parseFixtures(
            combat: {
              '  charge: { infantry: 2, light_vehicle: 1.5, heavy_vehicle: 1, '
                      'structure: 2.5 }\n':
                  '',
            },
          ),
          throwsDataError('combat.yaml', 'multipliers.charge', null, 'missing'),
        );
      });

      test('COMBAT-23 rejects a multipliers row missing an armor type', () {
        expect(
          () => parseFixtures(
            combat: {
              'heavy_vehicle: 0.75, structure: 1.5 }': 'heavy_vehicle: 0.75 }',
            },
          ),
          throwsDataError(
            'combat.yaml',
            'multipliers.cannon.structure',
            null,
            'missing',
          ),
        );
      });

      test('COMBAT-15 rejects a size factor table missing an armor type', () {
        expect(
          () => parseFixtures(
            combat: {
              'heavy_vehicle: 1.25, structure: 1.5 }': 'heavy_vehicle: 1.25 }',
            },
          ),
          throwsDataError(
            'combat.yaml',
            'hit_chance.size_factor.structure',
            null,
            'missing',
          ),
        );
      });
    });

    group('terrain and movement', () {
      test('MAP-15 rejects a terrain missing a movement column', () {
        expect(
          () => parseFixtures(
            terrain: {
              'sail: null, push: 1 }\n    access': 'sail: null }\n    access',
            },
          ),
          throwsDataError(
            'terrain.yaml',
            'terrain.island.ap_multiplier.push',
            null,
            'missing: null means impassable',
          ),
        );
      });

      test('MAP-15 rejects a unit movement class not in movement_classes', () {
        expect(
          () => parseFixtures(
            units: {
              'movement_class: wheeled\n    armor_type: light_vehicle\n'
                      '    hit_box_m: { width: 2,':
                  'movement_class: wheel\n    armor_type: light_vehicle\n'
                  '    hit_box_m: { width: 2,',
            },
          ),
          throwsDataError(
            'units.yaml',
            'units.jeep.movement_class',
            'wheel',
            'not in terrain.yaml movement_classes [foot, wheeled, tracked]',
          ),
        );
      });

      test('MAP-21 rejects a movement profile without a slope row', () {
        expect(
          () => parseFixtures(
            terrain: {
              '  push:    { factor: 0.06, max_degrees: 30, '
                      'min_multiplier: 0.6 }\n':
                  '',
            },
          ),
          throwsDataError('terrain.yaml', 'slope.push', null, 'missing'),
        );
      });

      test('COMBAT-03 rejects a unit without ap_per_m', () {
        expect(
          () => parseFixtures(units: {'ap_per_m: 0.5, attack: 9': 'attack: 9'}),
          throwsDataError(
            'units.yaml',
            'units.tank.base.ap_per_m',
            null,
            'missing',
          ),
        );
      });

      test('decisions 174, 178 reject a flyer faster than the jeep', () {
        expect(
          () => parseFixtures(
            units: {
              'move_speed: 25, vision_range: 250':
                  'move_speed: 26, vision_range: 250',
            },
          ),
          throwsDataError(
            'units.yaml',
            'units.helicopter.base.move_speed',
            26.0,
            'a flying unit is not faster than the jeep (25.0)',
          ),
        );
      });

      test('decisions 174, 178 reject a sailing unit faster than the tank', () {
        expect(
          () => parseFixtures(
            units: {
              'move_speed: 12, vision_range: 130':
                  'move_speed: 13, vision_range: 130',
            },
          ),
          throwsDataError(
            'units.yaml',
            'units.boat.base.move_speed',
            13.0,
            'a sailing unit is not faster than the tank (12.0)',
          ),
        );
      });

      test('decision 174 needs the jeep as the flying speed cap', () {
        expect(
          () => parseFixtures(units: {'  jeep:\n': '  car:\n'}),
          throwsDataError(
            'units.yaml',
            'units.jeep',
            null,
            'it caps the base speed of other units',
          ),
        );
      });

      test('decision 174 needs the tank as the sailing speed cap', () {
        expect(
          () => parseFixtures(units: {'  tank:\n': '  heavy:\n'}),
          throwsDataError(
            'units.yaml',
            'units.tank',
            null,
            'it caps the base speed of other units',
          ),
        );
      });
    });

    group('AP maximum and hit volumes', () {
      test("COMBAT-01 rejects a unit's ap_max other than ap.max", () {
        expect(
          () => parseFixtures(
            units: {
              'ap_max: 20, ap_per_m: 0.5, attack: 9':
                  'ap_max: 21, ap_per_m: 0.5, attack: 9',
            },
          ),
          throwsDataError(
            'units.yaml',
            'units.tank.base.ap_max',
            21.0,
            'differs from battle.yaml ap.max 20.0',
          ),
        );
      });

      test('COMBAT-01 checks every unit against battle.yaml ap.max', () {
        expect(
          () => parseFixtures(battle: {'ap:\n  max: 20': 'ap:\n  max: 25'}),
          throwsDataError(
            'units.yaml',
            'units.commander.base.ap_max',
            20.0,
            'differs from battle.yaml ap.max 25.0',
          ),
        );
      });

      test('COMBAT-14 rejects a unit without a hit box', () {
        expect(
          () => parseFixtures(
            units: {
              '    hit_box_m: { width: 3, length: 7, height: 2.5 }\n': '',
            },
          ),
          throwsDataError(
            'units.yaml',
            'units.tank.hit_box_m',
            null,
            'missing',
          ),
        );
      });

      test('HQ-22 rejects an HQ without a hit box', () {
        expect(
          () => parseFixtures(
            battle: {'  hit_box_m: { width: 15, length: 18, height: 6 }\n': ''},
          ),
          throwsDataError('battle.yaml', 'hq.hit_box_m', null, 'missing'),
        );
      });

      test('COMBAT-14 rejects a direct-fire weapon without a projectile '
          'speed', () {
        expect(
          () => parseFixtures(combat: {'projectile_speed_mps: 800, ': ''}),
          throwsDataError(
            'combat.yaml',
            'weapon_types.rifle.projectile_speed_mps',
            null,
            'missing: a direct-fire weapon needs it for first-person shots',
          ),
        );
      });
    });

    group('commander levels', () {
      test('UNIT-17 rejects a level table without max_level values', () {
        expect(
          () => parseFixtures(units: {'max_level: 4': 'max_level: 5'}),
          throwsDataError(
            'units.yaml',
            'progression.commander_levels.section_xp',
            4,
            'has 4 values, but max_level is 5',
          ),
        );
      });

      test('UNIT-17 rejects a level table that is not increasing', () {
        expect(
          () => parseFixtures(
            units: {
              'section_xp: [0, 100, 300, 600]':
                  'section_xp: [0, 100, 100, 600]',
            },
          ),
          throwsDataError(
            'units.yaml',
            'progression.commander_levels.section_xp[2]',
            100,
            'not above the previous value 100',
          ),
        );
      });
    });

    group('objects', () {
      test('MAP-40 rejects an object armor type not in armor_types', () {
        expect(
          () => parseFixtures(
            terrain: {
              'armor_type: structure, blocks_los: true':
                  'armor_type: stone, blocks_los: true',
            },
          ),
          throwsDataError(
            'terrain.yaml',
            'objects.wall.armor_type',
            'stone',
            'not in combat.yaml armor_types',
          ),
        );
      });
    });

    group('actions', () {
      test('UNIT-38 rejects an unknown action', () {
        expect(
          () =>
              parseFixtures(units: {'actions: [heal]': 'actions: [heal, fly]'}),
          throwsDataError(
            'units.yaml',
            'units.medic.actions[1]',
            'fly',
            'unknown, expected one of capture, push, build, repair, heal, '
                'observe',
          ),
        );
      });

      test('UNIT-38 accepts an action that costs exactly ap_max', () {
        expect(
          () => parseFixtures(
            battle: {'contribution_ap: 4': 'contribution_ap: 20'},
          ),
          returnsNormally,
        );
      });

      test('UNIT-38 rejects a capture contribution above ap_max', () {
        expect(
          () => parseFixtures(
            battle: {'contribution_ap: 4': 'contribution_ap: 21'},
          ),
          throwsDataError(
            'units.yaml',
            'units.commander.actions',
            'capture',
            'costs 21.0 AP up front, more than its ap_max 20.0',
          ),
        );
      });

      test('UNIT-38 rejects a push contribution above ap_max', () {
        expect(
          () => parseFixtures(
            combat: {'contribution_ap: 3': 'contribution_ap: 21'},
          ),
          throwsDataError(
            'units.yaml',
            'units.commander.actions',
            'push',
            'costs 21.0 AP up front, more than its ap_max 20.0',
          ),
        );
      });

      test('UNIT-38 rejects a repair above ap_max', () {
        expect(
          () => parseFixtures(
            combat: {'repair:  { ap: 9,': 'repair:  { ap: 25,'},
          ),
          throwsDataError(
            'units.yaml',
            'units.engineer.actions',
            'repair',
            'costs 25.0 AP up front, more than its ap_max 20.0',
          ),
        );
      });

      test('UNIT-38 rejects a heal above ap_max', () {
        expect(
          () => parseFixtures(units: {'heal_ap: 6': 'heal_ap: 30'}),
          throwsDataError(
            'units.yaml',
            'units.medic.actions',
            'heal',
            'costs 30.0 AP up front, more than its ap_max 20.0',
          ),
        );
      });

      test('UNIT-38 rejects an observe above ap_max', () {
        expect(
          () => parseFixtures(units: {'ap: 8, can_move': 'ap: 28, can_move'}),
          throwsDataError(
            'units.yaml',
            'units.scout.actions',
            'observe',
            'costs 28.0 AP up front, more than its ap_max 20.0',
          ),
        );
      });

      test('UNIT-38 rejects a construction above ap_max', () {
        expect(
          () => parseFixtures(
            terrain: {'ap: 9, build_time_s: 250': 'ap: 22, build_time_s: 250'},
          ),
          throwsDataError(
            'units.yaml',
            'units.engineer.actions',
            'build',
            'costs 22.0 AP up front, more than its ap_max 20.0',
          ),
        );
      });

      test('UNIT-38 rejects a healer without heal_ap', () {
        expect(
          () => parseFixtures(units: {'heal: 15, heal_ap: 6, ': 'heal: 15, '}),
          throwsDataError(
            'units.yaml',
            'units.medic.role.heal_ap',
            null,
            'missing: it lists heal',
          ),
        );
      });

      test('UNIT-38 rejects a scout without an observe role', () {
        expect(
          () => parseFixtures(
            units: {
              'reports_to_radio: true, observe: { vision_bonus_m: 20, '
                      'duration_s: 600, ap: 8, can_move: false } }':
                  'reports_to_radio: true }',
            },
          ),
          throwsDataError(
            'units.yaml',
            'units.scout.role.observe',
            null,
            'missing: it lists observe',
          ),
        );
      });

      test('UNIT-38 rejects a builder without constructions', () {
        expect(
          () => parseFixtures(
            units: {
              'role: { build: [wall, bridge], repair: true }':
                  'role: { repair: true }',
            },
          ),
          throwsDataError(
            'units.yaml',
            'units.engineer.role.build',
            null,
            'missing: it lists build',
          ),
        );
      });

      test('UNIT-38 rejects a build that is not a construction', () {
        expect(
          () => parseFixtures(
            units: {'build: [wall, bridge]': 'build: [wall, tree]'},
          ),
          throwsDataError(
            'units.yaml',
            'units.engineer.role.build[1]',
            'tree',
            'not a construction of terrain.yaml objects',
          ),
        );
      });

      test('UNIT-38 rejects a build of an unknown object', () {
        expect(
          () => parseFixtures(
            units: {'build: [wall, bridge]': 'build: [tower, bridge]'},
          ),
          throwsDataError(
            'units.yaml',
            'units.engineer.role.build[0]',
            'tower',
            'not a construction of terrain.yaml objects',
          ),
        );
      });
    });
  });
}
