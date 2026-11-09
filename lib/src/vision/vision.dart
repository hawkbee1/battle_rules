import 'dart:math' as math;

import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/terrain_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// Something on a sight line that may block it (MAP-26, MAP-28).
sealed class SightObstacle {
  const new();
}

/// {@template terrain_obstacle}
/// Terrain the sight line runs into, for example a mountain.
/// {@endtemplate}
final class TerrainObstacle extends SightObstacle {
  /// {@macro terrain_obstacle}
  const new(this.terrainType);

  /// A key of `terrain.yaml` `terrain`.
  final String terrainType;
}

/// {@template ground_obstacle}
/// The ground itself, rising above the sight line between the observer and
/// the target: a hill (MAP-26, vision is computed in 3D). It always blocks.
/// {@endtemplate}
final class GroundObstacle extends SightObstacle {
  /// {@macro ground_obstacle}
  const new();
}

/// {@template object_obstacle}
/// An object on the sight line, for example a building, intact or
/// [destroyed].
/// {@endtemplate}
final class ObjectObstacle extends SightObstacle {
  /// {@macro object_obstacle}
  const new(this.objectType, {this.destroyed = false});

  /// A key of `terrain.yaml` `objects`.
  final String objectType;

  /// Whether it is destroyed.
  final bool destroyed;
}

/// {@template sight_line}
/// An abstract sight line from an observer to a target: no geometry, only
/// what vision needs. The host builds these from the map.
/// {@endtemplate}
final class SightLine {
  /// {@macro sight_line}
  const new({
    required this.distanceM,
    required this.observerTerrain,
    this.heightAboveTargetM = 0,
    this.forestCrossedM = 0,
    this.obstacles = const [],
  });

  /// Distance to the target, in metres.
  final double distanceM;

  /// The terrain type the observer stands on (MAP-32).
  final String observerTerrain;

  /// How far the observer stands above the target, in metres; negative
  /// when it stands lower (MAP-33).
  final double heightAboveTargetM;

  /// Metres of forest the line crosses (MAP-27). A flying observer's line
  /// crosses less of it.
  final double forestCrossedM;

  /// Terrain and objects on the line that may block it.
  final List<SightObstacle> obstacles;
}

/// {@template observation}
/// A scout's observe action, started at [startedAt] (UNIT-34,
/// decisions 119, 184).
/// {@endtemplate}
final class Observation {
  /// {@macro observation}
  const new({required this.role, required this.startedAt});

  /// The scout's observe values.
  final ObserveRole role;

  /// The battle time it started.
  final Duration startedAt;

  /// The battle time it ends.
  Duration get endsAt =>
      startedAt +
      Duration(
        microseconds: (role.durationS * Duration.microsecondsPerSecond).round(),
      );

  /// Whether it is under way at battle time [time].
  bool isActiveAt(Duration time) => time >= startedAt && time < endsAt;

  /// The vision bonus at battle time [time]: `vision_bonus_m` while it is
  /// under way, 0 otherwise.
  double bonusAt(Duration time) => isActiveAt(time) ? role.visionBonusM : 0;

  /// Whether the scout may move at battle time [time]: not while observing,
  /// unless `can_move` says so.
  bool allowsMovingAt(Duration time) => !isActiveAt(time) || role.canMove;
}

/// {@template vision}
/// Who sees what, from the vision values of `terrain.yaml` (decisions 59,
/// 87, MAP-26 to MAP-35).
/// {@endtemplate}
final class Vision {
  /// {@macro vision}
  const new(this.terrain);

  /// The terrain tables.
  final TerrainData terrain;

  /// The effective vision, in metres, of an observer with [visionRange] on
  /// [line] in [weather]:
  /// `(visionRange + observeBonusM) × weather factor × terrain factor +
  /// height bonus − forest metres × forest_vision_cost_per_m` (MAP-31 to
  /// MAP-34, decision 184). The height bonus counts only when the observer
  /// stands higher, up to `height_bonus_max_m`.
  ///
  /// Throws an [ArgumentError] for a weather state or terrain type the
  /// tables do not have.
  double effectiveRange({
    required double visionRange,
    required String weather,
    required SightLine line,
    double observeBonusM = 0,
  }) {
    final weatherFactor =
        terrain.weather[weather] ??
        (throw ArgumentError.value(weather, 'weather', 'unknown'));
    final standing =
        terrain.terrainTypes[line.observerTerrain] ??
        (throw ArgumentError.value(
          line.observerTerrain,
          'line.observerTerrain',
          'unknown',
        ));
    final rules = terrain.vision;
    final heightBonus = math.min(
      rules.heightBonusMaxM,
      math.max(0, line.heightAboveTargetM) * rules.heightBonusMPerM,
    );
    return (visionRange + observeBonusM) *
            weatherFactor *
            standing.visionFactor +
        heightBonus -
        line.forestCrossedM * rules.forestVisionCostPerM;
  }

  /// Whether [obstacle] blocks the line: the ground rising above it, and
  /// terrain and objects that block the line of sight (MAP-26), unless
  /// destroyed (MAP-28).
  ///
  /// Throws an [ArgumentError] for a terrain or object type the tables do
  /// not have.
  bool blocks(SightObstacle obstacle) => switch (obstacle) {
    GroundObstacle() => true,
    TerrainObstacle(:final terrainType) =>
      (terrain.terrainTypes[terrainType] ??
              (throw ArgumentError.value(
                terrainType,
                'terrainType',
                'unknown',
              )))
          .blocksLos,
    ObjectObstacle(:final objectType, :final destroyed) =>
      (terrain.objects[objectType] ??
                  (throw ArgumentError.value(
                    objectType,
                    'objectType',
                    'unknown',
                  )))
              .blocksLos &&
          (!destroyed || terrain.vision.destroyedObjectsBlock),
  };

  /// Whether an observer with [visionRange] sees the target of [line] in
  /// [weather]: within its effective vision and with nothing on the line
  /// that blocks it (MAP-34).
  bool sees({
    required double visionRange,
    required String weather,
    required SightLine line,
    double observeBonusM = 0,
  }) =>
      line.distanceM <=
          effectiveRange(
            visionRange: visionRange,
            weather: weather,
            line: line,
            observeBonusM: observeBonusM,
          ) &&
      !line.obstacles.any(blocks);

  /// Whether [unit], observing or not, sees the target of [line] in
  /// [weather] at battle time [time].
  bool unitSees({
    required UnitType unit,
    required String weather,
    required SightLine line,
    required Duration time,
    Observation? observation,
  }) => sees(
    visionRange: unit.stats.visionRange,
    weather: weather,
    line: line,
    observeBonusM: observation?.bonusAt(time) ?? 0,
  );

  /// Whether [unit] can fire [weapon] at the target of [line]: it sees the
  /// target itself and the target is within the weapon's range (COMBAT-11,
  /// MAP-30). What other units see does not count.
  bool canFireAt({
    required UnitType unit,
    required WeaponType weapon,
    required String weather,
    required SightLine line,
    required Duration time,
    Observation? observation,
  }) =>
      line.distanceM <= weapon.rangeM &&
      unitSees(
        unit: unit,
        weather: weather,
        line: line,
        time: time,
        observation: observation,
      );

  /// Whether a section sees a target: one of its units does, each with its
  /// own sight line ([sightings], MAP-29). A section's fog of war is shared
  /// by its units.
  static bool sectionSees(Iterable<bool> sightings) =>
      sightings.any((seen) => seen);
}
