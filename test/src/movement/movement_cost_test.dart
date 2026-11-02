import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

const _modes = ['foot', 'wheeled', 'tracked', 'flying', 'sail', 'push'];

/// AP per metre on the fixture terrain for a mover paying 2 AP per metre on
/// flat grass, per mode in [_modes] order; null is impassable.
const _flatTable = <String, List<double?>>{
  'grass': [2, 2, 2, 1, null, 2],
  'mountain': [5, null, null, 1, null, null],
  'lake': [null, null, null, 1, 1.5, null],
  'island': [2, 2, 2, 1, null, 2],
  'mud': [4, 8, 4, 1, null, 6],
  'road': [1.5, 0.5, 1, 1, null, 1],
};

PathSample _sample(String terrain, {double slope = 0, double length = 1}) =>
    PathSample(terrainType: terrain, slopeDegrees: slope, lengthM: length);

void main() {
  late MovementCost cost;
  late UnitsData units;

  setUp(() {
    cost = MovementCost(TerrainData.parse(readFixture('terrain.yaml')));
    units = UnitsData.parse(readFixture('units.yaml'));
  });

  group(MovementCost, () {
    group('on flat ground', () {
      for (final MapEntry(key: terrain, value: row) in _flatTable.entries) {
        for (final (index, mode) in _modes.indexed) {
          final expected = row[index];
          final rule = switch (mode) {
            'foot' => 'MAP-11',
            'wheeled' => 'MAP-12',
            'tracked' => 'MAP-13',
            'flying' => 'MAP-17',
            'sail' => 'MAP-14',
            _ => 'MAP-15',
          };
          test('$rule $mode on $terrain costs '
              '${expected ?? 'nothing: impassable'}', () {
            final perMetre = cost(2, mode, terrain, 0);

            expect(
              perMetre,
              expected == null ? isNull : closeTo(expected, 1e-9),
            );
          });
        }
      }
    });

    group('on a slope', () {
      // (mode, terrain, signed slope, AP per metre for 1 AP per metre).
      const cases = <(String, String, double, double?)>[
        ('foot', 'grass', 10, 1.4),
        ('foot', 'grass', -5, 0.8),
        ('foot', 'grass', -20, 0.6),
        ('foot', 'grass', 40, 2.6),
        ('foot', 'grass', 40.5, null),
        ('foot', 'grass', -40.5, null),
        ('wheeled', 'grass', 10, 1.8),
        ('wheeled', 'grass', -2.5, 0.8),
        ('wheeled', 'grass', -10, 0.6),
        ('wheeled', 'grass', 20, 2.6),
        ('wheeled', 'grass', 20.5, null),
        ('wheeled', 'grass', -20.5, null),
        ('tracked', 'mud', 10, 3.2),
        ('tracked', 'mud', -5, 1.4),
        ('tracked', 'mud', -10, 1.2),
        ('tracked', 'mud', 30, 5.6),
        ('tracked', 'mud', 30.5, null),
        ('tracked', 'mud', -30.5, null),
        ('push', 'road', 10, 0.8),
        ('push', 'road', -10, 0.3),
        ('push', 'road', 31, null),
        ('flying', 'mountain', 60, 0.5),
        ('sail', 'lake', -45, 0.75),
      ];
      for (final (mode, terrain, slope, expected) in cases) {
        final direction = slope > 0 ? 'uphill' : 'downhill';
        test('MAP-16 $mode on $terrain ${slope.abs()}° $direction costs '
            '${expected ?? 'nothing: impassable'}', () {
          final perMetre = cost(1, mode, terrain, slope);

          expect(perMetre, expected == null ? isNull : closeTo(expected, 1e-9));
        });
      }
    });

    test('COMBAT-03 scales with the mover AP per metre', () {
      expect(cost(0.5, 'foot', 'mud', 10), closeTo(0.5 * 2 * 1.4, 1e-9));
      expect(cost(0, 'foot', 'mud', 10), 0);
    });

    test('rejects an unknown terrain type or mode', () {
      expect(() => cost(1, 'foot', 'lava', 0), throwsArgumentError);
      expect(() => cost(1, 'hover', 'grass', 0), throwsArgumentError);
    });
  });

  group(Mover, () {
    test('UNIT-01 a flying unit in the air uses the flying profile', () {
      final helicopter = units.unitTypes['helicopter']!;
      final flying = Mover.unit(helicopter, flying: true);

      expect(flying.modes, ['flying']);
      expect(flying.apPerM, helicopter.stats.apPerM);
      expect(flying.speedMps, helicopter.stats.moveSpeed);
    });

    test('MAP-17 a flying unit flies over the mountain and the lake', () {
      final flying = Mover.unit(units.unitTypes['helicopter']!, flying: true);

      expect(cost.ofSample(flying, _sample('mountain', slope: 60)), 0.125);
      expect(cost.ofSample(flying, _sample('lake')), 0.125);
    });

    test('MAP-18 a landed flying unit moves with its ground class', () {
      final landed = Mover.unit(units.unitTypes['helicopter']!);

      expect(landed.modes, ['wheeled']);
      expect(cost.ofSample(landed, _sample('mountain')), isNull);
      expect(cost.ofSample(landed, _sample('grass')), 0.25);
    });

    test('rejects flying for a unit that cannot fly', () {
      expect(
        () => Mover.unit(units.unitTypes['jeep']!, flying: true),
        throwsArgumentError,
      );
    });

    test('MAP-19 UNIT-02 a boat sails on water and cannot enter land', () {
      final boat = Mover.unit(units.unitTypes['boat']!);

      expect(boat.modes, ['sail']);
      expect(cost.ofSample(boat, _sample('lake')), 0.1875);
      expect(cost.ofSample(boat, _sample('grass')), isNull);
    });

    test('UNIT-02 MAP-19 an amphibious unit sails on water and drives on '
        'land', () {
      final amphibious = UnitsData.parse(
        readFixture('units.yaml', {
          'movement_class: null':
              'movement_class: '
              'wheeled',
        }),
      ).unitTypes['boat']!;
      final mover = Mover.unit(amphibious);

      expect(mover.modes, ['wheeled', 'sail']);
      expect(cost.ofSample(mover, _sample('lake')), 0.1875);
      expect(cost.ofSample(mover, _sample('road')), 0.0625);
    });

    test('MAP-22 rivers and lakes stop units on foot, wheels or tracks', () {
      for (final id in ['commander', 'jeep', 'tank']) {
        final mover = Mover.unit(units.unitTypes[id]!);

        expect(cost.ofSample(mover, _sample('lake')), isNull, reason: id);
      }
    });

    test('MAP-23 boats, amphibious and flying units cross water', () {
      final crossers = [
        Mover.unit(units.unitTypes['boat']!),
        Mover.unit(units.unitTypes['helicopter']!, flying: true),
      ];

      for (final mover in crossers) {
        expect(cost.ofSample(mover, _sample('lake')), isNotNull);
      }
    });

    test('the cheapest passable mode prices a sample', () {
      const mover = Mover(apPerM: 1, modes: ['wheeled', 'foot'], speedMps: 1);

      expect(cost.ofSample(mover, _sample('road')), 0.25);
      expect(cost.ofSample(mover, _sample('mountain')), 2.5);
    });
  });

  group('paths', () {
    const walker = Mover(apPerM: 1, modes: ['foot'], speedMps: 2);

    test('COMBAT-03 a path costs the sum of its samples', () {
      final path = [
        _sample('grass', length: 10),
        _sample('mud', slope: 10, length: 5),
        _sample('road', slope: -5, length: 4),
      ];

      // 10 × 1 + 5 × 2 × 1.4 + 4 × 0.75 × 0.8.
      expect(cost.ofPath(walker, path), closeTo(10 + 14 + 2.4, 1e-9));
    });

    test('MAP-15 a path with an impassable sample has no cost', () {
      final path = [_sample('grass', length: 10), _sample('lake')];

      expect(cost.ofPath(walker, path), isNull);
    });

    test('decision 180 ground and slope change the AP, not the time', () {
      final pool = ApPool.full(max: 100, recoveryPerHour: 1, at: Duration.zero);
      final grass = cost.move(
        mover: walker,
        pool: pool,
        start: Duration.zero,
        path: [_sample('grass', length: 20)],
      )!;
      final mud = cost.move(
        mover: walker,
        pool: pool,
        start: Duration.zero,
        path: [_sample('mud', slope: 20, length: 20)],
      )!;

      expect(grass.arrivesAt, const Duration(seconds: 10));
      expect(mud.arrivesAt, const Duration(seconds: 10));
      expect(mud.pool.value, lessThan(grass.pool.value));
    });

    test('COMBAT-06 with no AP left a mover goes as fast as its AP come '
        'back', () {
      final empty = ApPool(
        max: 10,
        recoveryPerHour: 4,
        value: 0,
        updatedAt: Duration.zero,
      );
      final moved = cost.move(
        mover: walker,
        pool: empty,
        start: Duration.zero,
        path: [_sample('grass'), _sample('mud')],
      )!;

      // 1 AP, then 2 AP, at 4 AP per hour.
      expect(moved.arrivesAt, const Duration(minutes: 45));
      expect(moved.pool.value, 0);
    });

    test('an impassable path does not move', () {
      final pool = ApPool.full(max: 10, recoveryPerHour: 1, at: Duration.zero);

      expect(
        cost.move(
          mover: walker,
          pool: pool,
          start: Duration.zero,
          path: [_sample('grass'), _sample('lake')],
        ),
        isNull,
      );
    });
  });

  group('the current plan data', () {
    late GameData data;
    late MovementCost planCost;

    setUpAll(() {
      data = parsePlanData();
      planCost = MovementCost(data.terrain);
    });

    test('COMBAT-03 infantry, tank and jeep pay their own ap_per_m times the '
        'terrain multiplier', () {
      for (final id in ['soldier', 'tank', 'jeep']) {
        final unit = data.units.unitTypes[id]!;
        final mover = Mover.unit(unit);
        for (final terrain in data.terrain.terrainTypes.values) {
          final multiplier = terrain.apMultiplier[unit.movementClass];
          final perMetre = planCost.ofSample(mover, _sample(terrain.id));

          expect(
            perMetre,
            multiplier == null
                ? isNull
                : closeTo(unit.stats.apPerM * multiplier, 1e-9),
            reason: '$id on ${terrain.id}',
          );
        }
      }
    });

    test('decision 169 flat grass costs exactly ap_per_m for every unit', () {
      for (final unit in data.units.unitTypes.values) {
        if (unit.movementClass == null) continue;

        expect(
          planCost.ofSample(Mover.unit(unit), _sample('grass')),
          unit.stats.apPerM,
          reason: unit.id,
        );
      }
    });

    test('decisions 175, 177 a pushed relic and the HQ pay the push profile '
        'on grass, mud, road and a slope', () {
      final terrain = data.terrain;
      final slope = terrain.slope['push']!;
      final uphill = slope.maxDegrees / 2;
      for (final mover in [
        Mover.relic(data.combat.push),
        Mover.hq(data.battle.hq),
      ]) {
        double expected(String type) =>
            mover.apPerM * terrain.terrainTypes[type]!.apMultiplier['push']!;

        expect(mover.modes, ['push']);
        for (final type in ['grass', 'mud', 'road']) {
          expect(
            planCost.ofSample(mover, _sample(type)),
            closeTo(expected(type), 1e-9),
            reason: type,
          );
        }
        expect(
          planCost.ofSample(mover, _sample('grass', slope: uphill)),
          closeTo(expected('grass') * (1 + uphill * slope.factor), 1e-9),
        );
        expect(planCost.ofSample(mover, _sample('forest_floor')), isNull);
      }
    });

    test('the HQ and a pushed relic move at their speed per hour', () {
      expect(
        Mover.hq(data.battle.hq).speedMps * Duration.secondsPerHour,
        closeTo(data.battle.hq.speedMPerH, 1e-9),
      );
      expect(
        Mover.relic(data.combat.push).speedMps * Duration.secondsPerHour,
        closeTo(data.combat.push.speedMPerH, 1e-9),
      );
    });
  });
}
