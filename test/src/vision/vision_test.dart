import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

void main() {
  late Vision vision;
  late UnitsData units;
  late WeaponType rifle;

  setUp(() {
    vision = Vision(TerrainData.parse(readFixture('terrain.yaml')));
    units = UnitsData.parse(readFixture('units.yaml'));
    rifle = CombatData.parse(readFixture('combat.yaml')).weaponTypes['rifle']!;
  });

  /// The effective vision of an observer with 100 m of vision range.
  double range(
    SightLine line, {
    String weather = 'clear',
    double observeBonusM = 0,
  }) => vision.effectiveRange(
    visionRange: 100,
    weather: weather,
    line: line,
    observeBonusM: observeBonusM,
  );

  bool sees(SightLine line) =>
      vision.sees(visionRange: 100, weather: 'clear', line: line);

  const flat = SightLine(distanceM: 50, observerTerrain: 'grass');

  group('effectiveRange', () {
    test('is the vision range in clear weather on flat grass', () {
      expect(range(flat), 100);
    });

    test('MAP-31 the weather factor scales the vision range', () {
      expect(range(flat, weather: 'fog'), 50);
    });

    test('MAP-32 the terrain under the observer scales it', () {
      expect(
        range(const SightLine(distanceM: 50, observerTerrain: 'island')),
        90,
      );
    });

    test('MAP-33 standing higher adds a height bonus, up to its cap', () {
      SightLine above(double metres) => SightLine(
        distanceM: 50,
        observerTerrain: 'grass',
        heightAboveTargetM: metres,
      );

      expect(range(above(10)), 115);
      expect(range(above(100)), 200);
      expect(range(above(-10)), 100);
    });

    test('MAP-27 each metre of forest crossed removes vision', () {
      expect(
        range(
          const SightLine(
            distanceM: 50,
            observerTerrain: 'grass',
            forestCrossedM: 10,
          ),
        ),
        70,
      );
    });

    test('UNIT-34 observing adds its bonus to the vision range, before the '
        'factors', () {
      expect(range(flat, weather: 'fog', observeBonusM: 20), 60);
    });

    test('MAP-34 combines every factor', () {
      const line = SightLine(
        distanceM: 50,
        observerTerrain: 'island',
        heightAboveTargetM: 10,
        forestCrossedM: 5,
      );

      // (100 + 20) × 0.5 × 0.9 + 15 − 15.
      expect(range(line, weather: 'fog', observeBonusM: 20), closeTo(54, 1e-9));
    });

    test('rejects an unknown weather state or terrain type', () {
      expect(() => range(flat, weather: 'hail'), throwsArgumentError);
      expect(
        () => range(const SightLine(distanceM: 1, observerTerrain: 'lava')),
        throwsArgumentError,
      );
    });
  });

  group('sees', () {
    test('MAP-34 sees a target within its effective vision, not beyond', () {
      expect(
        sees(const SightLine(distanceM: 100, observerTerrain: 'grass')),
        isTrue,
      );
      expect(
        sees(const SightLine(distanceM: 101, observerTerrain: 'grass')),
        isFalse,
      );
    });

    test('MAP-27 a flying observer sees a forest target a ground observer '
        'cannot', () {
      // The target stands 60 m away, 20 m deep in a forest.
      const ground = SightLine(
        distanceM: 60,
        observerTerrain: 'grass',
        forestCrossedM: 20,
      );
      // From above, the line enters the canopy much closer to the target.
      const flying = SightLine(
        distanceM: 60,
        observerTerrain: 'grass',
        forestCrossedM: 5,
      );

      expect(sees(ground), isFalse);
      expect(sees(flying), isTrue);
    });

    test('MAP-26 mountains and buildings block the line of sight', () {
      SightLine through(SightObstacle obstacle) => SightLine(
        distanceM: 10,
        observerTerrain: 'grass',
        obstacles: [obstacle],
      );

      expect(sees(through(const TerrainObstacle('mountain'))), isFalse);
      expect(sees(through(const ObjectObstacle('wall'))), isFalse);
      expect(sees(through(const ObjectObstacle('tree'))), isTrue);
      expect(sees(through(const TerrainObstacle('grass'))), isTrue);
    });

    test('MAP-28 destroyed objects stop blocking', () {
      expect(
        sees(
          const SightLine(
            distanceM: 10,
            observerTerrain: 'grass',
            obstacles: [ObjectObstacle('wall', destroyed: true)],
          ),
        ),
        isTrue,
      );
    });

    test('MAP-28 destroyed objects block when the data says so', () {
      final blocking = Vision(
        TerrainData.parse(
          readFixture('terrain.yaml', {
            'destroyed_objects_block: false': 'destroyed_objects_block: true',
          }),
        ),
      );

      expect(
        blocking.blocks(const ObjectObstacle('wall', destroyed: true)),
        isTrue,
      );
    });

    test('rejects an unknown obstacle', () {
      expect(
        () => vision.blocks(const TerrainObstacle('lava')),
        throwsArgumentError,
      );
      expect(
        () => vision.blocks(const ObjectObstacle('tower')),
        throwsArgumentError,
      );
    });
  });

  group('units', () {
    test('UNIT-34 a scout sees farther while it observes, for its '
        'duration', () {
      final scout = units.unitTypes['scout']!;
      final observation = Observation(
        role: scout.role.observe!,
        startedAt: const Duration(minutes: 1),
      );
      // Just past the scout's own vision range in clear weather.
      final line = SightLine(
        distanceM: scout.stats.visionRange + 10,
        observerTerrain: 'grass',
      );

      bool seesAt(Duration time) => vision.unitSees(
        unit: scout,
        weather: 'clear',
        line: line,
        time: time,
        observation: observation,
      );

      expect(seesAt(Duration.zero), isFalse);
      expect(seesAt(const Duration(minutes: 1)), isTrue);
      expect(seesAt(observation.endsAt), isFalse);
      expect(observation.endsAt, const Duration(minutes: 11));
    });

    test('UNIT-34 a scout cannot move while it observes', () {
      final role = units.unitTypes['scout']!.role.observe!;
      final observation = Observation(role: role, startedAt: Duration.zero);

      expect(observation.allowsMovingAt(const Duration(minutes: 5)), isFalse);
      expect(observation.allowsMovingAt(observation.endsAt), isTrue);
    });

    test('a unit without an observation sees with its own vision range', () {
      final jeep = units.unitTypes['jeep']!;
      final line = SightLine(
        distanceM: jeep.stats.visionRange,
        observerTerrain: 'grass',
      );

      expect(
        vision.unitSees(
          unit: jeep,
          weather: 'clear',
          line: line,
          time: Duration.zero,
        ),
        isTrue,
      );
    });

    test('COMBAT-11 MAP-30 a unit fires only at what it sees, within its '
        'weapon range', () {
      final jeep = units.unitTypes['jeep']!;
      bool canFire(SightLine line) => vision.canFireAt(
        unit: jeep,
        weapon: rifle,
        weather: 'clear',
        line: line,
        time: Duration.zero,
      );

      expect(
        canFire(const SightLine(distanceM: 100, observerTerrain: 'grass')),
        isTrue,
      );
      // Within rifle range, but past the jeep's vision.
      expect(
        canFire(const SightLine(distanceM: 200, observerTerrain: 'grass')),
        isFalse,
      );
      // Seen, but behind a wall.
      expect(
        canFire(
          const SightLine(
            distanceM: 100,
            observerTerrain: 'grass',
            obstacles: [ObjectObstacle('wall')],
          ),
        ),
        isFalse,
      );
    });

    test('COMBAT-11 a unit does not fire beyond its weapon range', () {
      final scout = units.unitTypes['scout']!;
      final observation = Observation(
        role: scout.role.observe!,
        startedAt: Duration.zero,
      );
      // Seen from high above, one metre past the rifle range.
      final line = SightLine(
        distanceM: rifle.rangeM + 1,
        observerTerrain: 'grass',
        heightAboveTargetM: 100,
      );

      expect(
        vision.unitSees(
          unit: scout,
          weather: 'clear',
          line: line,
          time: Duration.zero,
          observation: observation,
        ),
        isTrue,
      );
      expect(
        vision.canFireAt(
          unit: scout,
          weapon: rifle,
          weather: 'clear',
          line: line,
          time: Duration.zero,
          observation: observation,
        ),
        isFalse,
      );
    });

    test('MAP-29 a section sees what any of its units sees', () {
      expect(Vision.sectionSees([false, true, false]), isTrue);
      expect(Vision.sectionSees([false, false]), isFalse);
      expect(Vision.sectionSees(const []), isFalse);
    });
  });

  test('MAP-35 the plan data gives the vision values', () {
    final data = parsePlanData();
    final planVision = Vision(data.terrain);
    final soldier = data.units.unitTypes['soldier']!;
    final range = soldier.stats.visionRange;

    for (final MapEntry(key: weather, value: factor)
        in data.terrain.weather.entries) {
      expect(
        planVision.effectiveRange(
          visionRange: range,
          weather: weather,
          line: const SightLine(distanceM: 1, observerTerrain: 'grass'),
        ),
        closeTo(
          range * factor * data.terrain.terrainTypes['grass']!.visionFactor,
          1e-9,
        ),
        reason: weather,
      );
    }
    expect(planVision.blocks(const TerrainObstacle('mountain')), isTrue);
    expect(planVision.blocks(const ObjectObstacle('building')), isTrue);
    expect(
      planVision.blocks(const ObjectObstacle('building', destroyed: true)),
      isFalse,
    );
  });
}
