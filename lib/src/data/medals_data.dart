import 'package:battle_rules/src/data/data_reader.dart';

/// The name of the medals data file in messages.
const medalsFile = 'medals.yaml';

/// {@template medals_data}
/// The `medals.yaml` game data file: medal tiers, their points and the
/// thresholds of each track (decisions 105, 121).
/// {@endtemplate}
final class MedalsData {
  /// {@macro medals_data}
  const new({
    required this.version,
    required this.tiers,
    required this.points,
    required this.killThresholds,
    required this.actionThresholds,
    required this.actionKinds,
  });

  /// Parses the text of `medals.yaml`.
  factory parse(String text) {
    final reader = DataReader.parse(medalsFile, text);
    final actions = reader.map('actions');
    return MedalsData(
      version: reader.integer('version'),
      tiers: reader.strings('tiers'),
      points: reader.map('points').integerEntries(),
      killThresholds: Map.unmodifiable({
        for (final MapEntry(:key, :value) in reader.map('kills').maps().entries)
          key: value.integerEntries(),
      }),
      actionThresholds: actions.map('default').integerEntries(),
      actionKinds: actions.strings('kinds'),
    );
  }

  /// The file's `version`.
  final int version;

  /// The tiers, lowest first.
  final List<String> tiers;

  /// Points per tier.
  final Map<String, int> points;

  /// Kills needed per tier, by target unit type; `default` for every other
  /// unit type.
  final Map<String, Map<String, int>> killThresholds;

  /// Actions needed per tier, for every kind of action.
  final Map<String, int> actionThresholds;

  /// The kinds of action that have a medal track.
  final List<String> actionKinds;
}
