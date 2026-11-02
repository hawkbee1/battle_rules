import 'package:battle_rules/src/data/data_reader.dart';
import 'package:battle_rules/src/data/game_data_exception.dart';
import 'package:battle_rules/src/movement/movement_cost.dart';

/// The name of a scenario file in messages.
const scenarioFile = 'scenario';

/// {@template scenario_unit}
/// A unit of a scenario: its type, team and position on the scenario's
/// line, in metres (positions stay abstract, M4 Issue 11).
/// {@endtemplate}
final class ScenarioUnit {
  /// {@macro scenario_unit}
  const new({
    required this.id,
    required this.type,
    required this.team,
    required this.position,
    String? section,
    this.flying = false,
  }) : section = section ?? team;

  /// Its id in the scenario.
  final String id;

  /// A key of `units.yaml` `units`.
  final String type;

  /// Its team.
  final String team;

  /// Its section, which shares its sight (MAP-29); its team by default.
  final String section;

  /// Where it stands on the line, in metres.
  final double position;

  /// Whether it is flying (a unit with the flying capability).
  final bool flying;
}

/// An order of a scenario, given at [atS] seconds.
sealed class ScenarioOrder {
  const new(this.atS);

  /// When it is given, in seconds after the start.
  final double atS;
}

/// {@template fire_order}
/// [unit] fires [shots] shots at [target], under orders (hit chance).
/// {@endtemplate}
final class FireOrder extends ScenarioOrder {
  /// {@macro fire_order}
  const new(
    super.atS, {
    required this.unit,
    required this.target,
    required this.shots,
  });

  /// The shooter.
  final String unit;

  /// The target.
  final String target;

  /// How many shots.
  final int shots;
}

/// {@template artillery_order}
/// [unit] fires [shots] indirect shots at the position of [target], seen
/// by its section or reported by [spotter] through [radio].
/// {@endtemplate}
final class ArtilleryOrder extends ScenarioOrder {
  /// {@macro artillery_order}
  const new(
    super.atS, {
    required this.unit,
    required this.target,
    required this.shots,
    this.spotter,
    this.radio,
  });

  /// The artillery.
  final String unit;

  /// The unit whose position is aimed at.
  final String target;

  /// How many shots.
  final int shots;

  /// The scout reporting the target, if any.
  final String? spotter;

  /// The radio relaying the report, if any.
  final String? radio;
}

/// {@template move_order}
/// [unit] moves along [path], toward the growing positions.
/// {@endtemplate}
final class MoveOrder extends ScenarioOrder {
  /// {@macro move_order}
  const new(super.atS, {required this.unit, required this.path});

  /// The unit.
  final String unit;

  /// The path.
  final List<PathSample> path;
}

/// {@template push_order}
/// [pushers] each add [contributions] contributions to the push pot of a
/// relic owned by [owner], then push it along [path]; [inPath] gives the
/// units standing on the path and how far along it.
/// {@endtemplate}
final class PushOrder extends ScenarioOrder {
  /// {@macro push_order}
  const new(
    super.atS, {
    required this.owner,
    required this.pushers,
    required this.contributions,
    required this.path,
    required this.inPath,
  });

  /// The team that owns the relic.
  final String owner;

  /// The pushing units.
  final List<String> pushers;

  /// Contributions per pusher.
  final int contributions;

  /// The path.
  final List<PathSample> path;

  /// Distance along the path, by unit id.
  final Map<String, double> inPath;
}

/// {@template scenario}
/// A scripted scenario for the harness (M4 Issue 11): units, orders, a
/// seed, the weather and the terrain the units stand on. It is a test
/// tool, not the game's map format.
/// {@endtemplate}
final class Scenario {
  /// {@macro scenario}
  const new({
    required this.name,
    required this.seed,
    required this.weather,
    required this.terrain,
    required this.units,
    required this.orders,
  });

  /// Parses the text of a scenario file. Throws a [GameDataException] for
  /// a missing key, a wrong type, an unknown order or a reference to a
  /// unit the scenario does not have.
  factory parse(String text) {
    final reader = DataReader.parse(scenarioFile, text);
    final units = Map<String, ScenarioUnit>.unmodifiable({
      for (final MapEntry(:key, :value) in reader.map('units').maps().entries)
        key: ScenarioUnit(
          id: key,
          type: value.string('type'),
          team: value.string('team'),
          position: value.number('position'),
          section: value.optionalString('section'),
          flying: value.optionalBoolean('flying', absent: false),
        ),
    });
    String unitRef(DataReader order, String key) {
      final id = order.string(key);
      return units.containsKey(id) ? id : order.fail(key, id, 'no such unit');
    }

    String? optionalUnitRef(DataReader order, String key) =>
        order.has(key) ? unitRef(order, key) : null;

    final orders = [
      for (final order in reader.mapList('orders'))
        switch (order.string('order')) {
          'fire' => FireOrder(
            order.number('at_s'),
            unit: unitRef(order, 'unit'),
            target: unitRef(order, 'target'),
            shots: order.integer('shots'),
          ),
          'artillery' => ArtilleryOrder(
            order.number('at_s'),
            unit: unitRef(order, 'unit'),
            target: unitRef(order, 'target'),
            shots: order.integer('shots'),
            spotter: optionalUnitRef(order, 'spotter'),
            radio: optionalUnitRef(order, 'radio'),
          ),
          'move' => MoveOrder(
            order.number('at_s'),
            unit: unitRef(order, 'unit'),
            path: _path(order),
          ),
          'push' => PushOrder(
            order.number('at_s'),
            owner: order.string('owner'),
            pushers: order
                .strings('pushers')
                .indexed
                .map(
                  (entry) => units.containsKey(entry.$2)
                      ? entry.$2
                      : order.fail(
                          'pushers[${entry.$1}]',
                          entry.$2,
                          'no such unit',
                        ),
                )
                .toList(),
            contributions: order.integer('contributions'),
            path: _path(order),
            inPath: {
              for (final MapEntry(:key, :value)
                  in (order.optionalMap('in_path')?.numberEntries() ??
                          const <String, double>{})
                      .entries)
                (units.containsKey(key)
                        ? key
                        : order.fail('in_path.$key', key, 'no such unit')):
                    value,
            },
          ),
          final other => order.fail(
            'order',
            other,
            'unknown, expected fire, artillery, move or push',
          ),
        },
    ];
    // By time, then in file order (List.sort is not stable).
    final byTime = [...orders.indexed]
      ..sort(
        (a, b) => a.$2.atS == b.$2.atS
            ? a.$1.compareTo(b.$1)
            : a.$2.atS.compareTo(b.$2.atS),
      );
    return Scenario(
      name: reader.string('name'),
      seed: reader.integer('seed'),
      weather: reader.string('weather'),
      terrain: reader.string('terrain'),
      units: units,
      orders: List.unmodifiable([for (final (_, order) in byTime) order]),
    );
  }

  /// The scenario's name.
  final String name;

  /// The seed of its random draws.
  final int seed;

  /// The weather state of the battle.
  final String weather;

  /// The terrain type every unit stands on.
  final String terrain;

  /// Its units, by id.
  final Map<String, ScenarioUnit> units;

  /// Its orders, by time.
  final List<ScenarioOrder> orders;
}

List<PathSample> _path(DataReader order) => [
  for (final sample in order.mapList('path'))
    PathSample(
      terrainType: sample.string('terrain'),
      slopeDegrees: sample.optionalNumber('slope') ?? 0,
      lengthM: sample.number('length'),
    ),
];
