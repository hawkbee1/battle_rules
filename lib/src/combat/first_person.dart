import 'dart:math' as math;

import 'package:battle_rules/src/combat/hit_chance.dart';
import 'package:battle_rules/src/combat/seeded_random.dart';
import 'package:battle_rules/src/combat/vec3.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/hit_box.dart';

/// {@template shot_target}
/// A hit volume a first-person shot may meet: a unit or the HQ, as it is
/// at fire time and as it moves during the flight (COMBAT-14).
/// {@endtemplate}
final class ShotTarget {
  /// {@macro shot_target}
  const new({
    required this.id,
    required this.position,
    required this.hitBox,
    this.headingRad = 0,
    this.velocity = Vec3.zero,
  });

  /// Who it is, for the caller.
  final String id;

  /// The centre of the bottom of its hit volume at fire time.
  final Vec3 position;

  /// Its hit volume (`hit_box_m`, decision 183): `length` along its
  /// heading, `width` across, `height` up.
  final HitBox hitBox;

  /// The way it faces in the horizontal plane, in radians from east toward
  /// north.
  final double headingRad;

  /// Its velocity during the flight, in metres per second.
  final Vec3 velocity;
}

/// What stops a shot before any hit volume: terrain and objects, given by
/// the host from the map (COMBAT-53). Full cover blocks completely.
abstract interface class ObstacleQuery {
  /// The distance along the line from [origin] in the unit [direction] to
  /// the first obstacle, within [maxDistanceM]; null when the line is clear.
  double? firstObstacle(Vec3 origin, Vec3 direction, double maxDistanceM);
}

/// Where a first-person shot ends.
sealed class ShotOutcome {
  const new();
}

/// {@template shot_hits_target}
/// The shot hits the target [targetId] at [at], at [point].
/// {@endtemplate}
final class ShotHitsTarget extends ShotOutcome {
  /// {@macro shot_hits_target}
  const new({required this.targetId, required this.at, required this.point});

  /// The target hit.
  final String targetId;

  /// The battle time of the hit.
  final Duration at;

  /// Where the projectile meets the hit volume.
  final Vec3 point;
}

/// {@template shot_hits_obstacle}
/// The shot hits an obstacle at [at], at [point].
/// {@endtemplate}
final class ShotHitsObstacle extends ShotOutcome {
  /// {@macro shot_hits_obstacle}
  const new({required this.at, required this.point});

  /// The battle time of the impact.
  final Duration at;

  /// Where the projectile meets the obstacle.
  final Vec3 point;
}

/// The shot flies its whole range and hits nothing.
final class ShotMisses extends ShotOutcome {
  /// The shot that hits nothing.
  const new();
}

/// {@template first_person_shots}
/// First-person shots (COMBAT-14, decision 183): the player gives the aim
/// direction and the fire time; the rules core deviates the direction by
/// the spread with the seeded random, flies the projectile in a straight
/// line at `projectile_speed_mps`, and returns the first hit volume or
/// obstacle on its path. The host runs this; a client only draws it
/// (stack decision 8).
/// {@endtemplate}
final class FirstPersonShots {
  /// {@macro first_person_shots}
  const new(this.combat);

  /// The combat tables (`aim`, `hit_chance.morale_factor`).
  final CombatData combat;

  /// The spread of a shooter with [attack] and [morale], in degrees:
  /// `base_spread_deg × (1 − spread_reduction_per_attack × attack)`,
  /// divided by the morale factor (decision 95), not below
  /// `min_spread_deg` (COMBAT-17, COMBAT-49).
  double spreadDeg({required double attack, required double morale}) {
    final aim = combat.aim;
    final spread =
        aim.baseSpreadDeg *
        (1 - aim.spreadReductionPerAttack * attack) /
        HitChance(combat).moraleFactor(morale);
    return math.max(aim.minSpreadDeg, spread);
  }

  /// [aim] deviated at random within a cone of [spreadDeg] degrees around
  /// it, uniformly over the cone's opening.
  static Vec3 deviate(Vec3 aim, double spreadDeg, SeededRandom random) {
    final forward = aim.normalized;
    final angle = spreadDeg * math.pi / 180 * math.sqrt(random.nextDouble());
    final around = 2 * math.pi * random.nextDouble();
    var side = forward.cross(const Vec3(0, 0, 1));
    if (side.length < 1e-9) side = forward.cross(const Vec3(1, 0, 0));
    side = side.normalized;
    final up = side.cross(forward);
    final offset = side * math.cos(around) + up * math.sin(around);
    return forward * math.cos(angle) + offset * math.sin(angle);
  }

  /// Fires [weapon] from [origin] toward [aim] at battle time [fireTime].
  ///
  /// The direction is deviated by the shooter's spread with [random]. The
  /// projectile flies at the weapon's speed up to its range; the first of
  /// the [targets] (moving as they do during the flight) or of the
  /// obstacles of [obstacles] on its path is hit; a target that leaves the
  /// line before the projectile arrives is missed. A target whose hit
  /// volume holds [origin] is the shooter itself and is never hit. Throws an
  /// [ArgumentError] for a weapon that does not fly (artillery, the
  /// explosive charge).
  ShotOutcome fire({
    required WeaponType weapon,
    required Vec3 origin,
    required Vec3 aim,
    required Duration fireTime,
    required double attack,
    required double morale,
    required SeededRandom random,
    required List<ShotTarget> targets,
    required ObstacleQuery obstacles,
  }) {
    final speed =
        weapon.projectileSpeedMps ??
        (throw ArgumentError.value(weapon.id, 'weapon', 'does not fly'));
    final direction = deviate(
      aim,
      spreadDeg(attack: attack, morale: morale),
      random,
    );
    final maxTime = weapon.rangeM / speed;
    final obstacleAt = obstacles.firstObstacle(
      origin,
      direction,
      weapon.rangeM,
    );
    var bestTime = obstacleAt == null ? double.infinity : obstacleAt / speed;
    ShotTarget? best;
    for (final target in targets) {
      final time = _entryTime(origin, direction * speed, target, maxTime);
      // A hit volume that holds the muzzle is the shooter's own: skipped.
      if (time == 0) continue;
      if (time != null && time < bestTime) {
        bestTime = time;
        best = target;
      }
    }
    if (bestTime == double.infinity) return const ShotMisses();
    final at =
        fireTime +
        Duration(
          microseconds: (bestTime * Duration.microsecondsPerSecond).round(),
        );
    final point = origin + direction * (speed * bestTime);
    return best == null
        ? ShotHitsObstacle(at: at, point: point)
        : ShotHitsTarget(targetId: best.id, at: at, point: point);
  }

  /// The time, in seconds after firing, at which a projectile from
  /// [origin] with [velocity] enters [target]'s moving box; null when it
  /// does not within [maxTime]. Slab test in the box's own axes.
  static double? _entryTime(
    Vec3 origin,
    Vec3 velocity,
    ShotTarget target,
    double maxTime,
  ) {
    final box = target.hitBox;
    final centre = target.position + Vec3(0, 0, box.height / 2);
    final start = origin - centre;
    final relative = velocity - target.velocity;
    final heading = target.headingRad;
    final axes = [
      (Vec3(math.cos(heading), math.sin(heading), 0), box.length / 2),
      (Vec3(-math.sin(heading), math.cos(heading), 0), box.width / 2),
      (const Vec3(0, 0, 1), box.height / 2),
    ];
    var enter = 0.0;
    var leave = maxTime;
    for (final (axis, half) in axes) {
      final position = start.dot(axis);
      final speed = relative.dot(axis);
      if (speed.abs() < 1e-12) {
        if (position.abs() > half) return null;
        continue;
      }
      final a = (-half - position) / speed;
      final b = (half - position) / speed;
      enter = math.max(enter, math.min(a, b));
      leave = math.min(leave, math.max(a, b));
    }
    return enter <= leave ? enter : null;
  }
}
