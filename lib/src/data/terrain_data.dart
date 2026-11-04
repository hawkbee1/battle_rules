import 'package:battle_rules/src/data/data_reader.dart';

/// The name of the terrain data file in messages.
const terrainFile = 'terrain.yaml';

/// A movement profile: not a movement class, but a way of moving that has
/// its own `ap_multiplier` column and `slope` row in `terrain.yaml`.
enum MovementProfile {
  /// A unit with the flying capability, while flying.
  flying,

  /// A unit with the sail capability, on water (decision 86).
  sail,

  /// A pushed relic and the moving HQ (decisions 175, 177).
  push,
}

/// {@template terrain_data}
/// The `terrain.yaml` game data file: movement cost, slope, vision,
/// weather, terrain types and objects (MAP-21, MAP-35).
/// {@endtemplate}
final class TerrainData {
  /// {@macro terrain_data}
  const new({
    required this.version,
    required this.movementClasses,
    required this.flyingMaxAboveHighestTerrainM,
    required this.slope,
    required this.vision,
    required this.weather,
    required this.terrainTypes,
    required this.craters,
    required this.objects,
  });

  /// Parses the text of `terrain.yaml`. Checks types and required keys
  /// only; `GameData.parse` checks the rules between values.
  factory parse(String text) {
    final reader = DataReader.parse(terrainFile, text);
    final vision = reader.map('vision');
    final craters = reader.map('craters');
    return TerrainData(
      version: reader.integer('version'),
      movementClasses: reader.strings('movement_classes'),
      flyingMaxAboveHighestTerrainM: reader.number(
        'flying_max_above_highest_terrain_m',
      ),
      slope: Map.unmodifiable({
        for (final MapEntry(:key, :value) in reader.map('slope').maps().entries)
          key: SlopeRule(
            factor: value.number('factor'),
            maxDegrees: value.number('max_degrees'),
            minMultiplier: value.number('min_multiplier'),
          ),
      }),
      vision: VisionRules(
        heightBonusMPerM: vision.number('height_bonus_m_per_m'),
        heightBonusMaxM: vision.number('height_bonus_max_m'),
        forestVisionCostPerM: vision.number('forest_vision_cost_per_m'),
        destroyedObjectsBlock: vision.boolean('destroyed_objects_block'),
      ),
      weather: Map.unmodifiable({
        for (final MapEntry(:key, :value)
            in reader.map('weather').maps().entries)
          key: value.number('vision_factor'),
      }),
      terrainTypes: Map.unmodifiable({
        for (final MapEntry(:key, :value)
            in reader.map('terrain').maps().entries)
          key: TerrainType(
            id: key,
            blocksLos: value.boolean('blocks_los'),
            visionFactor: value.number('vision_factor'),
            apMultiplier: value.map('ap_multiplier').numberOrNullEntries(),
            crossableBy: value.optionalStrings('crossable_by'),
            access: value.optionalStrings('access'),
          ),
      }),
      craters: Craters(
        maxDepthM: craters.number('max_depth_m'),
        fillableByEngineers: craters.boolean('fillable_by_engineers'),
        depthPerShotM: craters.number('depth_per_shot_m'),
      ),
      objects: Map.unmodifiable({
        for (final MapEntry(:key, :value)
            in reader.map('objects').maps().entries)
          key: _readObject(key, value),
      }),
    );
  }

  /// The file's `version`.
  final int version;

  /// The ground movement classes (`movement_classes`).
  final List<String> movementClasses;

  /// Flying altitude limit above the map's highest point, in metres
  /// (decision 142).
  final double flyingMaxAboveHighestTerrainM;

  /// The slope rule of each movement class and profile (`slope`,
  /// decision 133).
  final Map<String, SlopeRule> slope;

  /// Vision values (`vision`, MAP-35, decisions 59, 87).
  final VisionRules vision;

  /// Vision factor of each weather state (`weather`, MAP-35).
  final Map<String, double> weather;

  /// Every terrain type, by id (`terrain`).
  final Map<String, TerrainType> terrainTypes;

  /// Craters (decision 85).
  final Craters craters;

  /// Every object type, by id (`objects`, MAP-40, decisions 89, 113, 137).
  final Map<String, TerrainObject> objects;

  /// The movement classes, then the movement profiles: every column of
  /// `ap_multiplier` and every row of `slope` (MAP-15).
  List<String> get movementModes => [
    ...movementClasses,
    for (final profile in MovementProfile.values) profile.name,
  ];
}

/// {@template slope_rule}
/// The slope rule of a movement class or profile (decision 133): cost
/// multiplier `max(minMultiplier, 1 + slope degrees × factor)`, with a
/// signed slope; impassable beyond [maxDegrees], up or down.
/// {@endtemplate}
final class SlopeRule {
  /// {@macro slope_rule}
  const new({
    required this.factor,
    required this.maxDegrees,
    required this.minMultiplier,
  });

  /// Multiplier change per degree of signed slope.
  final double factor;

  /// Steepest passable slope, up or down, in degrees.
  final double maxDegrees;

  /// Lowest multiplier (the downhill floor).
  final double minMultiplier;
}

/// {@template vision_rules}
/// Vision values of `terrain.yaml` (`vision`, MAP-35).
/// {@endtemplate}
final class VisionRules {
  /// {@macro vision_rules}
  const new({
    required this.heightBonusMPerM,
    required this.heightBonusMaxM,
    required this.forestVisionCostPerM,
    required this.destroyedObjectsBlock,
  });

  /// Vision metres gained per metre the observer stands above the target.
  final double heightBonusMPerM;

  /// Largest height bonus, in metres.
  final double heightBonusMaxM;

  /// Vision metres lost per metre of forest crossed (decision 87).
  final double forestVisionCostPerM;

  /// Whether destroyed objects block the line of sight.
  final bool destroyedObjectsBlock;
}

/// {@template terrain_type}
/// One terrain type of `terrain.yaml` (`terrain`).
/// {@endtemplate}
final class TerrainType {
  /// {@macro terrain_type}
  const new({
    required this.id,
    required this.blocksLos,
    required this.visionFactor,
    required this.apMultiplier,
    required this.crossableBy,
    required this.access,
  });

  /// The terrain type's key in `terrain`, for example `grass`.
  final String id;

  /// Whether it blocks the line of sight.
  final bool blocksLos;

  /// Vision factor of an observer standing on it (MAP-35).
  final double visionFactor;

  /// Factor on the unit's AP per metre, by movement class or profile;
  /// null means impassable (MAP-15).
  final Map<String, double?> apMultiplier;

  /// Movement profiles that can cross it, when the file lists them.
  final List<String> crossableBy;

  /// How it can be reached, when the file lists it.
  final List<String> access;
}

/// {@template craters}
/// Craters (`craters`, decision 85).
/// {@endtemplate}
final class Craters {
  /// {@macro craters}
  const new({
    required this.maxDepthM,
    required this.fillableByEngineers,
    required this.depthPerShotM,
  });

  /// Deepest crater, in metres.
  final double maxDepthM;

  /// Whether engineers can fill a crater.
  final bool fillableByEngineers;

  /// How deep, at its centre, the crater of one shot of a weapon that
  /// `deforms_terrain` is; it is as wide as the weapon's splash (MAP-46;
  /// assumed, Q-MAP-19).
  final double depthPerShotM;
}

/// {@template terrain_object}
/// One object type of `terrain.yaml` (`objects`, MAP-40).
/// {@endtemplate}
final class TerrainObject {
  /// {@macro terrain_object}
  const new({
    required this.id,
    required this.armorType,
    required this.blocksLos,
    required this.conceals,
    required this.destructible,
    required this.hp,
    required this.construction,
    required this.relicCrossable,
    required this.hiddenFromEnemies,
  });

  /// The object's key in `objects`, for example `wall`.
  final String id;

  /// Its armor type for the damage table (MAP-40, decision 137).
  final String armorType;

  /// Whether it blocks the line of sight.
  final bool blocksLos;

  /// What concealment it gives, for example `forest`; null for none.
  final String? conceals;

  /// Whether it can be destroyed.
  final bool destructible;

  /// Hit points (decision 89).
  final double hp;

  /// How it is built, for a construction; null otherwise (decision 113).
  final Construction? construction;

  /// Whether a relic can cross it, when the file says so (decision 99).
  final bool? relicCrossable;

  /// Whether enemies cannot see it.
  final bool hiddenFromEnemies;
}

/// {@template construction}
/// How a construction is built (decision 113): AP paid up front, then a
/// build time, no money (COMBAT-10).
/// {@endtemplate}
final class Construction {
  /// {@macro construction}
  const new({
    required this.builtBy,
    required this.ap,
    required this.buildTimeS,
  });

  /// The unit type that builds it.
  final String builtBy;

  /// AP paid up front.
  final double ap;

  /// Seconds to build it.
  final double buildTimeS;
}

TerrainObject _readObject(String id, DataReader object) {
  final builtBy = object.optionalString('built_by');
  return TerrainObject(
    id: id,
    armorType: object.string('armor_type'),
    blocksLos: object.boolean('blocks_los'),
    conceals: object.optionalString('conceals'),
    destructible: object.boolean('destructible'),
    hp: object.number('hp'),
    construction: builtBy == null
        ? null
        : Construction(
            builtBy: builtBy,
            ap: object.number('ap'),
            buildTimeS: object.number('build_time_s'),
          ),
    relicCrossable: object.has('relic_crossable')
        ? object.boolean('relic_crossable')
        : null,
    hiddenFromEnemies: object.optionalBoolean(
      'hidden_from_enemies',
      absent: false,
    ),
  );
}
