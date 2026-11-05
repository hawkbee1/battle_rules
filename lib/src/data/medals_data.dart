import 'package:battle_rules/src/data/data_reader.dart';

/// The name of the medals data file in messages.
const _medalsFile = 'medals.yaml';

/// {@template medals_data}
/// The `medals.yaml` game data file: medal tiers, their points, the
/// thresholds of each track (decisions 105, 121, 231) and the flag of hit
/// rates far above the norm (decision 230).
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
    required this.friendlyKillThresholds,
    required this.hitRateFlag,
  });

  /// Parses the text of `medals.yaml`.
  factory parse(String text) {
    final reader = DataReader.parse(_medalsFile, text);
    final actions = reader.map('actions');
    final flag = reader.map('hit_rate_flag');
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
      friendlyKillThresholds: reader.map('friendly_kills').integerEntries(),
      hitRateFlag: HitRateFlag(
        sigmas: flag.number('sigmas'),
        minShots: flag.integer('min_shots'),
      ),
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

  /// Friendly kills needed per tier: a track of their own (decision 231).
  final Map<String, int> friendlyKillThresholds;

  /// When a hit rate is far above the norm (decision 230).
  final HitRateFlag hitRateFlag;
}

/// {@template hit_rate_flag}
/// When a player's hit rate with a weapon over a battle-day, on
/// first-person shots, is far above the norm (`hit_rate_flag`, decision
/// 230): [sigmas] standard deviations above the mean of all players with
/// that weapon that day, after at least [minShots] shots.
/// {@endtemplate}
final class HitRateFlag {
  /// {@macro hit_rate_flag}
  const new({required this.sigmas, required this.minShots});

  /// Standard deviations above the mean.
  final double sigmas;

  /// Shots a player fires with the weapon that day before a flag.
  final int minShots;
}
