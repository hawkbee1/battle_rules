import 'package:battle_rules/src/combat/seeded_random.dart';
import 'package:battle_rules/src/data/battle_settings.dart';

/// {@template server_fire_check}
/// The fire check of a server-managed unit (AI-07, decisions 160, 196,
/// 228, 229): every [interval] from the battle start, a unit that sees an
/// enemy unit within its weapon's range fires at the nearest with
/// `fire_chance`, the same at each check. The check is not made when an
/// enemy comes into range. The shot then follows the normal rules (AI-08).
/// {@endtemplate}
final class ServerFireCheck {
  /// {@macro server_fire_check}
  const new(this.settings);

  /// The `server_managed` settings of the battle.
  final ServerManagedSettings settings;

  /// The time from one check of a unit to its next.
  Duration get interval => Duration(
    microseconds: (settings.checkIntervalS * Duration.microsecondsPerSecond)
        .round(),
  );

  /// The first check after the battle time [time]: checks fall every
  /// [interval] from the battle start, for every unit (decision 229).
  Duration nextAfter(Duration time) {
    final every = interval.inMicroseconds;
    return Duration(microseconds: (time.inMicroseconds ~/ every + 1) * every);
  }

  /// Whether the unit fires at this check, drawn with [random].
  bool fires(SeededRandom random) => random.nextDouble() < settings.fireChance;
}
