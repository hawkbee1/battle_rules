import 'dart:math' as math;

import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixed_random.dart';
import '../../helpers/fixtures.dart';

/// Obstacles at a fixed distance along any line, or none.
final class _Wall implements ObstacleQuery {
  const new([this.distance]);

  final double? distance;

  @override
  double? firstObstacle(Vec3 origin, Vec3 direction, double maxDistanceM) {
    final distance = this.distance;
    return distance != null && distance <= maxDistanceM ? distance : null;
  }
}

const _soldierBox = HitBox(width: 0.6, length: 0.6, height: 1.8);
const _tankBox = HitBox(width: 3, length: 7, height: 2.5);

void main() {
  late CombatData combat;
  late FirstPersonShots shots;
  late WeaponType rifle;

  setUp(() {
    combat = CombatData.parse(readFixture('combat.yaml'));
    shots = FirstPersonShots(combat);
    rifle = combat.weaponTypes['rifle']!;
  });

  /// A rifle shot from 1 m above the origin toward east, with no deviation.
  ShotOutcome fire(
    List<ShotTarget> targets, {
    ObstacleQuery obstacles = const _Wall(),
    Vec3 origin = const Vec3(0, 0, 1),
  }) => shots.fire(
    weapon: rifle,
    origin: origin,
    aim: const Vec3(1, 0, 0),
    fireTime: const Duration(seconds: 10),
    attack: 10,
    morale: 40,
    random: FixedRandom([0]),
    targets: targets,
    obstacles: obstacles,
  );

  ShotTarget soldier(String id, double x, {double y = 0, Vec3? velocity}) =>
      ShotTarget(
        id: id,
        position: Vec3(x, y, 0),
        hitBox: _soldierBox,
        velocity: velocity ?? Vec3.zero,
      );

  group('spreadDeg', () {
    test('COMBAT-17 attack tightens the spread, down to its minimum', () {
      expect(shots.spreadDeg(attack: 10, morale: 40), closeTo(2.4, 1e-9));
      expect(shots.spreadDeg(attack: 45, morale: 40), 0.5);
    });

    test('COMBAT-49 morale scales the spread', () {
      expect(shots.spreadDeg(attack: 10, morale: 80), closeTo(2, 1e-9));
      expect(shots.spreadDeg(attack: 10, morale: 0), closeTo(3, 1e-9));
    });

    test('COMBAT-16 attack and morale move first-person spread and the order '
        'hit chance the same way', () {
      final hitChance = HitChance(combat);
      double chance(double attack, double morale) => hitChance.of(
        weapon: rifle,
        attack: attack,
        morale: morale,
        defense: 10,
        targetArmor: 'infantry',
        targetSpeedMps: 0,
        distanceM: 100,
      );

      expect(chance(20, 40), greaterThan(chance(10, 40)));
      expect(
        shots.spreadDeg(attack: 20, morale: 40),
        lessThan(shots.spreadDeg(attack: 10, morale: 40)),
      );
      expect(chance(10, 60), greaterThan(chance(10, 40)));
      expect(
        shots.spreadDeg(attack: 10, morale: 60),
        lessThan(shots.spreadDeg(attack: 10, morale: 40)),
      );
    });
  });

  group('deviate', () {
    double angleDeg(Vec3 a, Vec3 b) =>
        math.acos(a.normalized.dot(b.normalized).clamp(-1, 1)) * 180 / math.pi;

    test('stays on the aim with a draw of 0', () {
      final direction = FirstPersonShots.deviate(
        const Vec3(2, 0, 0),
        3,
        FixedRandom([0, 0.4]),
      );

      expect(angleDeg(direction, const Vec3(1, 0, 0)), closeTo(0, 1e-6));
    });

    test('deviates by the whole spread at most', () {
      for (final aim in [const Vec3(1, 2, 0.5), const Vec3(0, 0, 1)]) {
        final direction = FirstPersonShots.deviate(
          aim,
          3,
          FixedRandom([1, 0.3]),
        );

        expect(angleDeg(direction, aim), closeTo(3, 1e-6));
        expect(direction.length, closeTo(1, 1e-9));
      }
    });

    test('COMBAT-14 the same seed gives the same spread', () {
      final first = FirstPersonShots.deviate(
        const Vec3(1, 0, 0),
        2,
        XorshiftRandom(42),
      );
      final second = FirstPersonShots.deviate(
        const Vec3(1, 0, 0),
        2,
        XorshiftRandom(42),
      );

      expect(first.toString(), second.toString());
    });
  });

  group('fire', () {
    test('COMBAT-14 the projectile flies at its speed and hits the first hit '
        'volume on its path', () {
      final outcome = fire([soldier('far', 200), soldier('near', 100)]);

      final hit = outcome as ShotHitsTarget;
      expect(hit.targetId, 'near');
      // The front of the box, 99.7 m away, at 800 m/s.
      expect(hit.point.x, closeTo(99.7, 1e-9));
      expect(
        hit.at,
        const Duration(seconds: 10) +
            Duration(microseconds: (99.7 / 800 * 1e6).round()),
      );
    });

    test('COMBAT-53 an obstacle before the target stops the shot', () {
      final outcome = fire([soldier('a', 100)], obstacles: const _Wall(50));

      final hit = outcome as ShotHitsObstacle;
      expect(hit.point.x, closeTo(50, 1e-9));
      expect(hit.at, const Duration(seconds: 10, microseconds: 62500));
    });

    test('COMBAT-14 a target before the obstacle is hit', () {
      expect(
        fire([soldier('a', 100)], obstacles: const _Wall(150)),
        isA<ShotHitsTarget>(),
      );
    });

    test('COMBAT-14 a target that moves out of the line during the flight is '
        'missed', () {
      // 0.3 s of flight: it moves 3 m north, far out of its 0.6 m box.
      final outcome = fire([
        soldier('runner', 240, velocity: const Vec3(0, 10, 0)),
      ]);

      expect(outcome, isA<ShotMisses>());
    });

    test('COMBAT-14 a target that moves into the line during the flight is '
        'hit', () {
      // 2 m south of the line, 16 m/s north: there after 0.125 s.
      final outcome = fire([
        soldier('crosser', 100, y: -2, velocity: const Vec3(0, 16, 0)),
      ]);

      expect((outcome as ShotHitsTarget).targetId, 'crosser');
    });

    test('the shooter never hits its own hit volume', () {
      final outcome = fire([soldier('me', -0.1), soldier('target', 100)]);

      expect((outcome as ShotHitsTarget).targetId, 'target');
    });

    test('a shot over a target misses it', () {
      expect(
        fire([soldier('a', 100)], origin: const Vec3(0, 0, 5)),
        isA<ShotMisses>(),
      );
    });

    test('a target beyond the weapon range is not hit', () {
      expect(fire([soldier('a', 400)]), isA<ShotMisses>());
    });

    test('the hit volume turns with its heading', () {
      ShotTarget tank(double heading) => ShotTarget(
        id: 'tank',
        position: const Vec3(100, 2, 0),
        hitBox: _tankBox,
        headingRad: heading,
      );

      // 2 m off the line: missed lengthwise across it, hit when it faces
      // north.
      expect(fire([tank(0)]), isA<ShotMisses>());
      expect(fire([tank(math.pi / 2)]), isA<ShotHitsTarget>());
    });

    test('artillery and the explosive charge do not fly', () {
      expect(
        () => shots.fire(
          weapon: combat.weaponTypes['cannon']!,
          origin: Vec3.zero,
          aim: const Vec3(1, 0, 0),
          fireTime: Duration.zero,
          attack: 0,
          morale: 40,
          random: FixedRandom([0]),
          targets: const [],
          obstacles: const _Wall(),
        ),
        throwsArgumentError,
      );
    });
  });

  group(Vec3, () {
    test('adds, subtracts, scales and measures', () {
      const a = Vec3(1, 2, 2);

      expect((a + a).toString(), 'Vec3(2.0, 4.0, 4.0)');
      expect((a - a).length, 0);
      expect((a * 2).length, 6);
      expect(a.normalized.length, closeTo(1, 1e-12));
      expect(
        const Vec3(1, 0, 0).cross(const Vec3(0, 1, 0)).toString(),
        'Vec3(0.0, 0.0, 1.0)',
      );
    });

    test('the zero vector has no direction', () {
      expect(() => Vec3.zero.normalized, throwsStateError);
    });
  });
}
