import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

/// A pool with [ap] AP at time 0, recovering 1 AP per hour.
ApPool _pool(double ap, {double max = 20}) =>
    ApPool(max: max, recoveryPerHour: 1, value: ap, updatedAt: Duration.zero);

PathSample _sample(String terrain, double length) =>
    PathSample(terrainType: terrain, slopeDegrees: 0, lengthM: length);

void main() {
  late PushingRules pushing;
  late UnitsData units;

  setUp(() {
    pushing = PushingRules(
      push: CombatData.parse(readFixture('combat.yaml')).push,
      cost: MovementCost(TerrainData.parse(readFixture('terrain.yaml'))),
    );
    units = UnitsData.parse(readFixture('units.yaml'));
  });

  ActionRefusal refusal(ActionResult result) =>
      (result as ActionRefused).reason;

  group('push pot', () {
    test('COMBAT-08 a pusher adds contribution_ap to its team push pot', () {
      final added = pushing.contribute(
        unit: units.unitTypes['commander']!,
        pot: const PushPot(owner: 'red', ap: 5),
        pool: _pool(20),
        now: Duration.zero,
      ) as PushContributed;

      expect(added.pot.ap, 8);
      expect(added.pot.owner, 'red');
      expect(added.pool.value, 17);
      expect(added.at, Duration.zero);
    });

    test('UNIT-38 a unit that does not list push cannot push', () {
      expect(
        refusal(
          pushing.contribute(
            unit: units.unitTypes['tank']!,
            pot: const PushPot(owner: 'red'),
            pool: _pool(20),
            now: Duration.zero,
          ),
        ),
        ActionRefusal.notInActions,
      );
    });

    test('refuses a contribution that costs more than the pool can hold', () {
      expect(
        refusal(
          pushing.contribute(
            unit: units.unitTypes['commander']!,
            pot: const PushPot(owner: 'red'),
            pool: _pool(2, max: 2),
            now: Duration.zero,
          ),
        ),
        ActionRefusal.costAboveApMax,
      );
    });

    test("decision 176 another team's capture or a fall empties the pot", () {
      const pot = PushPot(owner: 'red', ap: 12);

      expect(pot.capturedBy('red'), same(pot));
      expect(pot.capturedBy('blue').ap, 0);
      expect(pot.capturedBy('blue').owner, 'blue');
      expect(pot.fallen().ap, 0);
      expect(pot.fallen().owner, 'red');
    });
  });

  group('push', () {
    PushMove push({
      double ap = 80,
      int pushers = 6,
      List<PathSample>? path,
      List<double> units = const [],
    }) => pushing.move(
      pot: PushPot(owner: 'red', ap: ap),
      pushers: pushers,
      path: path ?? [_sample('grass', 5), _sample('mud', 1)],
      start: Duration.zero,
      unitsInPathAtM: units,
    );

    test('RELIC-24 each metre costs pot_ap_per_m times the push profile, at '
        'speed_m_per_h', () {
      final moved = push();

      // 5 m × 8 AP + 1 m × 8 AP × 3; 6 m at 4 m per hour.
      expect(moved.distanceM, 6);
      expect(moved.pot.ap, 16);
      expect(moved.endsAt, const Duration(minutes: 90));
      expect(moved.stop, PushStop.pathEnd);
    });

    test('decision 173 a partly filled pot stays after the push stops', () {
      expect(push().pot.ap, 16);
    });

    test('RELIC-24 an empty pot stops the relic', () {
      final moved = push(ap: 20);

      expect(moved.distanceM, 2.5);
      expect(moved.pot.ap, 0);
      expect(moved.stop, PushStop.potEmpty);
    });

    test('RELIC-24 the relic moves only with min_pushers pushers', () {
      final moved = push(pushers: 5);

      expect(moved.distanceM, 0);
      expect(moved.pot.ap, 80);
      expect(moved.stop, PushStop.tooFewPushers);
    });

    test('a pushed relic stops before impassable ground', () {
      final moved = push(path: [_sample('grass', 1), _sample('mountain', 1)]);

      expect(moved.distanceM, 1);
      expect(moved.stop, PushStop.impassable);
    });

    test('RELIC-25 a relic crushes only the units it reaches', () {
      // 7 pushers crush 2 units here; the pot runs dry at 2.5 m.
      final moved = push(ap: 20, pushers: 7, units: [2, 4]);

      expect(moved.crushed, 1);
      expect(moved.stop, PushStop.potEmpty);
    });

    test('RELIC-25 the crush rule with 10, 11 and 13 pushers', () {
      final push = parsePlanData().combat.push;
      final real = PushingRules(
        push: push,
        cost: MovementCost(parsePlanData().terrain),
      );
      PushMove withPushers(int extra) => real.move(
        pot: const PushPot(owner: 'red', ap: 1000),
        pushers: push.minPushers + extra,
        path: [_sample('grass', 10)],
        start: Duration.zero,
        unitsInPathAtM: const [6, 2, 4],
      );

      final atMinimum = withPushers(0);
      final oneMore = withPushers(1);
      final threeMore = withPushers(3);

      expect(atMinimum.crushed, 0);
      expect(atMinimum.distanceM, 2);
      expect(atMinimum.stop, PushStop.blocked);
      expect(oneMore.crushed, 1);
      expect(oneMore.distanceM, 4);
      expect(oneMore.stop, PushStop.blocked);
      expect(threeMore.crushed, 3);
      expect(threeMore.distanceM, 10);
      expect(threeMore.stop, PushStop.pathEnd);
    });
  });

  group('HQ move', () {
    late GameData data;
    late MovementCost cost;

    setUpAll(() {
      data = parsePlanData();
      cost = MovementCost(data.terrain);
    });

    ApPool hqPool({double? ap}) => ApPool(
      max: data.battle.hq.apMax,
      recoveryPerHour: data.battle.ap.recoveryPerHour,
      value: ap ?? data.battle.hq.apMax,
      updatedAt: Duration.zero,
    );

    HqMove move(List<PathSample> path, {ApPool? pool, double? unitAt}) =>
        moveHq(
          hq: data.battle.hq,
          cost: cost,
          pool: pool ?? hqPool(),
          start: Duration.zero,
          path: path,
          unitInPathAtM: unitAt,
        )!;

    test('HQ-14 the HQ drains its own AP faster in mud than on grass', () {
      final hq = data.battle.hq;
      final mudFactor = data.terrain.terrainTypes['mud']!.apMultiplier['push']!;
      final hours = 10 / hq.speedMPerH;
      final mud = move([_sample('mud', 10)]);
      final grass = move([_sample('grass', 10)]);

      expect(mud.movement.arrivesAt, grass.movement.arrivesAt);
      expect(
        mud.movement.pool.value,
        closeTo(
          hq.apMax -
              10 * hq.apPerM * mudFactor +
              hours * data.battle.ap.recoveryPerHour,
          1e-6,
        ),
      );
      expect(mud.movement.pool.value, lessThan(grass.movement.pool.value));
      expect(mud.endedByUnit, isFalse);
    });

    test('HQ-14 with no AP left the HQ moves as fast as its AP come back', () {
      final hq = data.battle.hq;
      final mudFactor = data.terrain.terrainTypes['mud']!.apMultiplier['push']!;
      final moved = move([_sample('mud', 10)], pool: hqPool(ap: 0));
      final hours = 10 * hq.apPerM * mudFactor / data.battle.ap.recoveryPerHour;

      expect(
        moved.movement.arrivesAt.inMicroseconds,
        closeTo(hours * Duration.microsecondsPerHour, 1),
      );
      expect(moved.movement.pool.value, 0);
    });

    test('HQ-12 a unit in its path ends the order there', () {
      final hq = data.battle.hq;
      final moved = move([_sample('grass', 5), _sample('road', 5)], unitAt: 7);

      expect(moved.endedByUnit, isTrue);
      expect(
        moved.movement.arrivesAt.inMicroseconds,
        closeTo(7 / hq.speedMPerH * Duration.microsecondsPerHour, 1),
      );
    });

    test('HQ-10 the HQ moves on its own with the push profile, so a forest '
        'stops it', () {
      expect(
        moveHq(
          hq: data.battle.hq,
          cost: cost,
          pool: hqPool(),
          start: Duration.zero,
          path: [_sample('forest_floor', 3)],
        ),
        isNull,
      );
    });

    test('pathUpTo keeps the first metres of a path', () {
      final route = pathUpTo([_sample('grass', 5), _sample('road', 5)], 7);

      expect(route.map((sample) => sample.lengthM), [5, 2]);
      expect(route.last.terrainType, 'road');
      expect(pathUpTo([_sample('grass', 5)], 0), isEmpty);
    });
  });
}
