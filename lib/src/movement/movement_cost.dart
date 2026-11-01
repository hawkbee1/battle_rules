import 'dart:math' as math;

import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/ap/movement.dart';
import 'package:battle_rules/src/data/battle_settings.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/terrain_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// {@template path_sample}
/// One stretch of a path: its terrain type, its signed slope in degrees
/// (positive uphill, decision 133) and its length in metres. M3's path
/// search returns paths as these samples.
/// {@endtemplate}
final class PathSample {
  /// {@macro path_sample}
  const new({
    required this.terrainType,
    required this.slopeDegrees,
    required this.lengthM,
  });

  /// A key of `terrain.yaml` `terrain`, for example `grass`.
  final String terrainType;

  /// Signed slope in degrees: positive uphill, negative downhill.
  final double slopeDegrees;

  /// Length in metres.
  final double lengthM;
}

/// {@template mover}
/// What moves along a path: its AP per metre on flat grass, the movement
/// classes or profiles it can use, and its speed.
/// {@endtemplate}
final class Mover {
  /// {@macro mover}
  const new({
    required this.apPerM,
    required this.modes,
    required this.speedMps,
  });

  /// A unit, on the ground or, for a flying unit, in the air
  /// (MAP-11 to MAP-19, UNIT-01, UNIT-02).
  ///
  /// A flying unit in the air uses the `flying` profile; landed, it uses
  /// its ground class (MAP-18). A unit with `sail` uses the `sail` profile
  /// on water: with no ground class it is a boat and cannot enter land;
  /// with one it is amphibious (MAP-19). Throws an [ArgumentError] when
  /// [flying] is true for a unit that cannot fly.
  factory unit(UnitType unit, {bool flying = false}) {
    if (flying && !unit.canFly) {
      throw ArgumentError.value(unit.id, 'unit', 'cannot fly');
    }
    return Mover(
      apPerM: unit.stats.apPerM,
      speedMps: unit.stats.moveSpeed,
      modes: flying
          ? [MovementProfile.flying.name]
          : [?unit.movementClass, if (unit.canSail) MovementProfile.sail.name],
    );
  }

  /// The moving HQ: `hq.ap_per_m` from its own AP, with the `push` profile
  /// (decision 177).
  factory hq(HqSettings hq) => Mover(
    apPerM: hq.apPerM,
    speedMps: hq.speedMPerH / Duration.secondsPerHour,
    modes: [MovementProfile.push.name],
  );

  /// A pushed relic: `push.pot_ap_per_m` from its push pot, with the `push`
  /// profile (COMBAT-08, decision 175).
  factory relic(PushRules push) => Mover(
    apPerM: push.potApPerM,
    speedMps: push.speedMPerH / Duration.secondsPerHour,
    modes: [MovementProfile.push.name],
  );

  /// AP per metre on flat grass (`ap_per_m`, decision 169).
  final double apPerM;

  /// The movement classes or profiles it can use; the cheapest passable one
  /// prices each sample.
  final List<String> modes;

  /// Speed in metres per second, on any terrain and slope (decision 180).
  final double speedMps;
}

/// {@template movement_cost}
/// The AP cost of moving over the terrain of `terrain.yaml` (COMBAT-03,
/// MAP-15, MAP-16).
///
/// Strategy (stack decision 7): [call] has the shape of the movement cost
/// that M3's path search takes, so a caller wires one into the other.
/// {@endtemplate}
final class MovementCost {
  /// {@macro movement_cost}
  const new(this.terrain);

  /// The terrain tables.
  final TerrainData terrain;

  /// The AP per metre of a mover whose flat-grass cost is [apPerM], moving
  /// with movement class or profile [mode] on [terrainType] at the signed
  /// [slopeDegrees]; null when impassable.
  ///
  /// `apPerM × ap_multiplier[mode] × max(min_multiplier, 1 + slope ×
  /// factor)`. Impassable when the table says null (MAP-15, MAP-22) or the
  /// slope, up or down, is steeper than `max_degrees` (MAP-16).
  ///
  /// Throws an [ArgumentError] for a terrain type or mode the tables do not
  /// have.
  double? call(
    double apPerM,
    String mode,
    String terrainType,
    double slopeDegrees,
  ) {
    final type =
        terrain.terrainTypes[terrainType] ??
        (throw ArgumentError.value(terrainType, 'terrainType', 'unknown'));
    final slope = terrain.slope[mode];
    if (slope == null || !type.apMultiplier.containsKey(mode)) {
      throw ArgumentError.value(mode, 'mode', 'unknown');
    }
    final multiplier = type.apMultiplier[mode];
    if (multiplier == null || slopeDegrees.abs() > slope.maxDegrees) {
      return null;
    }
    final slopeFactor = math.max(
      slope.minMultiplier,
      1 + slopeDegrees * slope.factor,
    );
    return apPerM * multiplier * slopeFactor;
  }

  /// The AP per metre of [mover] on [sample], with its cheapest passable
  /// mode; null when no mode passes.
  double? ofSample(Mover mover, PathSample sample) {
    double? cheapest;
    for (final mode in mover.modes) {
      final cost = call(
        mover.apPerM,
        mode,
        sample.terrainType,
        sample.slopeDegrees,
      );
      if (cost != null && (cheapest == null || cost < cheapest)) {
        cheapest = cost;
      }
    }
    return cheapest;
  }

  /// The AP of moving [mover] along [path]; null when a sample is
  /// impassable.
  double? ofPath(Mover mover, List<PathSample> path) {
    var total = 0.0;
    for (final sample in path) {
      final perMetre = ofSample(mover, sample);
      if (perMetre == null) return null;
      total += perMetre * sample.lengthM;
    }
    return total;
  }

  /// Moves [mover] along [path] from battle time [start], paying from its
  /// AP [pool]; null when a sample is impassable, and then it does not
  /// move.
  ///
  /// It goes at its speed on any terrain and slope (decision 180); with no
  /// AP left it goes as fast as its AP come back (COMBAT-06).
  Movement? move({
    required Mover mover,
    required ApPool pool,
    required Duration start,
    required List<PathSample> path,
  }) {
    final perMetre = [for (final sample in path) ofSample(mover, sample)];
    if (perMetre.contains(null)) return null;
    var movement = Movement(arrivesAt: start, pool: pool);
    for (final (index, sample) in path.indexed) {
      movement = moveAlong(
        pool: movement.pool,
        start: movement.arrivesAt,
        lengthM: sample.lengthM,
        apPerM: perMetre[index]!,
        speedMps: mover.speedMps,
      );
    }
    return movement;
  }
}
