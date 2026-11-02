import 'package:battle_rules/src/actions/action_result.dart';
import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/data/battle_settings.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// How a unit inside a capture radius is present. Stored units are not on
/// the map, so they are never inside (RELIC-07).
enum Presence {
  /// On the ground, under its player's control.
  onField,

  /// Carried by a transport.
  carried,

  /// Flying.
  flying,

  /// Its player is offline.
  offline,

  /// Passive, under section AI.
  passive,
}

/// {@template radius_occupant}
/// A unit inside a relic's capture radius: its [team] and how it is
/// present.
/// {@endtemplate}
final class RadiusOccupant {
  /// {@macro radius_occupant}
  const new({required this.team, this.presence = Presence.onField});

  /// Its team.
  final String team;

  /// How it is present. Every unit inside counts, whatever this is
  /// (RELIC-07).
  final Presence presence;
}

/// {@template capture_pot}
/// A team's capture pot on one relic (RELIC-05, decisions 170, 173).
///
/// It keeps each contributor's AP: capture XP is shared by them
/// (decision 179). The capture timer starts when the pot is full.
/// {@endtemplate}
final class CapturePot {
  /// {@macro capture_pot}
  const new({required this.team, this.contributions = const {}, this.fullAt});

  /// The capturing team.
  final String team;

  /// AP put in, by contributing unit id.
  final Map<String, double> contributions;

  /// The battle time the pot became full: the capture timer started then;
  /// null while it fills.
  final Duration? fullAt;

  /// The AP in the pot.
  double get ap => contributions.values.fold(0, (sum, ap) => sum + ap);

  /// Whether a capture is under way: from the first AP put in, even while
  /// no unit of its team is inside the radius (decision 176).
  bool get isUnderWay => ap > 0;
}

/// {@template capture_rules}
/// Relic capture, from `battle.yaml` `capture` (RELIC-05 to RELIC-09,
/// RELIC-29).
/// {@endtemplate}
final class CaptureRules {
  /// {@macro capture_rules}
  const new(this.settings);

  /// The capture settings of the battle (RELIC-09).
  final CaptureSettings settings;

  /// Whether a unit of another team than [team] is inside the radius,
  /// whatever its state (RELIC-06, RELIC-07).
  static bool enemyInRadius(Iterable<RadiusOccupant> occupants, String team) =>
      occupants.any((occupant) => occupant.team != team);

  /// [unit] (id [unitId]) puts `contribution_ap` into [pot], ordered at
  /// battle time [now] (RELIC-05, COMBAT-07). It must list `capture`
  /// (UNIT-38) and be inside the radius; no enemy may be inside
  /// (RELIC-06). Any unit of the team can add, so another one resumes a
  /// capture its first contributor left (RELIC-29). The pot is full at
  /// `pot_ap`, and the capture timer starts.
  ActionResult contribute({
    required UnitType unit,
    required String unitId,
    required CapturePot pot,
    required ApPool pool,
    required bool insideRadius,
    required Iterable<RadiusOccupant> occupants,
    required Duration now,
  }) {
    if (!unit.actions.contains(UnitAction.capture)) {
      return const ActionRefused(ActionRefusal.notInActions);
    }
    if (!insideRadius) return const ActionRefused(ActionRefusal.outsideRadius);
    if (enemyInRadius(occupants, pot.team)) {
      return const ActionRefused(ActionRefusal.enemyInRadius);
    }
    if (pot.fullAt != null) return const ActionRefused(ActionRefusal.potFull);
    final paid = pool.payWhenReady(settings.contributionAp, now);
    if (paid == null) return const ActionRefused(ActionRefusal.costAboveApMax);
    final contributions = Map<String, double>.of(pot.contributions)
      ..update(
        unitId,
        (ap) => ap + settings.contributionAp,
        ifAbsent: () => settings.contributionAp,
      );
    final filled = CapturePot(
      team: pot.team,
      contributions: Map.unmodifiable(contributions),
    );
    return CaptureContributed(
      at: paid.at,
      pool: paid.pool,
      pot: filled.ap >= settings.potAp
          ? CapturePot(
              team: pot.team,
              contributions: filled.contributions,
              fullAt: paid.at,
            )
          : filled,
    );
  }

  /// [pot] once [occupants] are inside the radius: an enemy inside empties
  /// it, progress and AP, from the first AP put in (RELIC-08,
  /// decision 176).
  CapturePot withOccupants(
    CapturePot pot,
    Iterable<RadiusOccupant> occupants,
  ) => enemyInRadius(occupants, pot.team) ? CapturePot(team: pot.team) : pot;

  /// The battle time the relic is captured: `duration_s` after the pot
  /// became full (decision 173); null while it fills.
  Duration? capturedAt(CapturePot pot) {
    final fullAt = pot.fullAt;
    return fullAt == null
        ? null
        : fullAt +
              Duration(
                microseconds:
                    (settings.durationS * Duration.microsecondsPerSecond)
                        .round(),
              );
  }
}
