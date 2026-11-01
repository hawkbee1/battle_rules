import 'package:battle_rules/src/data/combat_data.dart';

/// What changes a unit's morale (COMBAT-48). Morale changes only through
/// these: there is no drift (COMBAT-47).
enum MoraleEvent {
  /// A minute inside its own commander's aura.
  commanderAuraMinute,

  /// An enemy killed nearby.
  nearbyEnemyKilled,

  /// An ally killed nearby.
  nearbyAllyKilled,

  /// A minute outnumbered.
  outnumberedMinute,
}

/// {@template morale}
/// Morale, from `combat.yaml` `morale` (COMBAT-46 to COMBAT-48,
/// decision 70).
/// {@endtemplate}
final class Morale {
  /// {@macro morale}
  const new(this.rules);

  /// The morale values.
  final MoraleRules rules;

  /// A new unit's morale (COMBAT-46).
  double get base => rules.base;

  /// [morale] after [event] happened [times] times, within
  /// `morale.range`.
  double after(double morale, MoraleEvent event, {int times = 1}) {
    final events = rules.events;
    final change = switch (event) {
      MoraleEvent.commanderAuraMinute => events.commanderAuraPerMin,
      MoraleEvent.nearbyEnemyKilled => events.nearbyEnemyKilled,
      MoraleEvent.nearbyAllyKilled => events.nearbyAllyKilled,
      MoraleEvent.outnumberedMinute => events.outnumberedPerMin,
    };
    return (morale + change * times).clamp(rules.min, rules.max);
  }

  /// Whether a kill at [distanceM] is nearby (`nearby_radius_m`).
  bool isNearby(double distanceM) => distanceM <= rules.nearbyRadiusM;

  /// Whether a unit with [enemies] and [allies] around it is outnumbered:
  /// the local enemy to ally ratio is above `outnumbered_ratio`.
  bool isOutnumbered({required int enemies, required int allies}) =>
      enemies > rules.outnumberedRatio * allies;
}
