import 'dart:math' as math;

import 'package:battle_rules/src/actions/action_result.dart';
import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/units_data.dart';
import 'package:battle_rules/src/movement/movement_cost.dart';

/// {@template push_pot}
/// A relic's push pot, for the team that owns the relic (COMBAT-08,
/// decisions 171, 173, 176). It keeps its AP until they are used up.
/// {@endtemplate}
final class PushPot {
  /// {@macro push_pot}
  const new({required this.owner, this.ap = 0});

  /// The team that owns the relic.
  final String owner;

  /// The AP in the pot.
  final double ap;

  /// The pot once [team] has captured the relic: another team's capture
  /// empties it, and the new owner starts with an empty pot (decision 176).
  PushPot capturedBy(String team) =>
      team == owner ? this : PushPot(owner: team);

  /// The pot once the relic has fallen from a floating island: empty
  /// (decision 176).
  PushPot fallen() => PushPot(owner: owner);
}

/// Why a push stops.
enum PushStop {
  /// The relic reached the end of the ordered path.
  pathEnd,

  /// The pot is empty (RELIC-24).
  potEmpty,

  /// A unit it cannot crush stands in its way (RELIC-25).
  blocked,

  /// The next stretch is impassable for the `push` profile.
  impassable,

  /// Fewer than `min_pushers` push (RELIC-24).
  tooFewPushers,
}

/// {@template push_move}
/// How far a pushed relic went: [distanceM] metres, arriving at [endsAt],
/// with [pot] left, [crushed] units killed, and why it stopped.
/// {@endtemplate}
final class PushMove {
  /// {@macro push_move}
  const new({
    required this.distanceM,
    required this.endsAt,
    required this.pot,
    required this.crushed,
    required this.stop,
  });

  /// Metres moved along the path.
  final double distanceM;

  /// The battle time it stops.
  final Duration endsAt;

  /// The pot after the push.
  final PushPot pot;

  /// How many of the units in its path it crushed: they die (RELIC-25).
  final int crushed;

  /// Why it stopped.
  final PushStop stop;
}

/// {@template pushing_rules}
/// Pushing a relic, from `combat.yaml` `push` and the `push` profile of
/// `terrain.yaml` (COMBAT-08, RELIC-24, RELIC-25).
/// {@endtemplate}
final class PushingRules {
  /// {@macro pushing_rules}
  const new({required this.push, required this.cost});

  /// The push values.
  final PushRules push;

  /// The movement cost (its `push` profile prices each metre).
  final MovementCost cost;

  /// [unit], of [team], adds `contribution_ap` to [pot], ordered at
  /// battle time [now], as often as it likes (decision 171). It must list
  /// `push` (UNIT-38) and belong to the team that owns the relic
  /// (RELIC-19, RELIC-24).
  ActionResult contribute({
    required UnitType unit,
    required String team,
    required PushPot pot,
    required ApPool pool,
    required Duration now,
  }) {
    if (!unit.actions.contains(UnitAction.push)) {
      return const ActionRefused(ActionRefusal.notInActions);
    }
    if (team != pot.owner) return const ActionRefused(ActionRefusal.notOwner);
    final paid = pool.payWhenReady(push.contributionAp, now);
    if (paid == null) return const ActionRefused(ActionRefusal.costAboveApMax);
    return PushContributed(
      at: paid.at,
      pool: paid.pool,
      pot: PushPot(owner: pot.owner, ap: pot.ap + push.contributionAp),
    );
  }

  /// Pushes the relic along [path] from battle time [start] with
  /// [pushers] pushers, paying from [pot] (RELIC-24).
  ///
  /// It needs `min_pushers`. It moves at `speed_m_per_h`; each metre costs
  /// `pot_ap_per_m` × the ground and slope multipliers of the `push`
  /// profile; it stops when the pot is empty, and the rest of a partly
  /// used pot stays (decision 173). [unitsInPathAtM] are the distances
  /// along the path of the units standing in its way: with `min_pushers +
  /// n` pushers it crushes the first `n` it meets and stops at the next
  /// one (RELIC-25, decision 185).
  PushMove move({
    required PushPot pot,
    required int pushers,
    required List<PathSample> path,
    required Duration start,
    List<double> unitsInPathAtM = const [],
  }) {
    if (pushers < push.minPushers) {
      return PushMove(
        distanceM: 0,
        endsAt: start,
        pot: pot,
        crushed: 0,
        stop: PushStop.tooFewPushers,
      );
    }
    final units = [...unitsInPathAtM]..sort();
    final canCrush =
        (pushers - push.minPushers) * push.crushUnitsPerExtraPusher;
    final blockedAt = units.length > canCrush ? units[canCrush] : null;
    final mover = Mover.relic(push);
    var distance = 0.0;
    var ap = pot.ap;
    var stop = PushStop.pathEnd;
    for (final sample in path) {
      final perMetre = cost.ofSample(mover, sample);
      if (perMetre == null) {
        stop = PushStop.impassable;
        break;
      }
      var length = sample.lengthM;
      var blocked = false;
      if (blockedAt != null && distance + length >= blockedAt) {
        length = blockedAt - distance;
        blocked = true;
      }
      // A free stretch divides by 0: infinitely affordable.
      final affordable = ap / perMetre;
      if (affordable < length) {
        distance += affordable;
        ap = 0;
        stop = PushStop.potEmpty;
        break;
      }
      distance += length;
      ap = math.max(0, ap - length * perMetre);
      if (blocked) {
        stop = PushStop.blocked;
        break;
      }
    }
    final hours = distance / push.speedMPerH;
    return PushMove(
      distanceM: distance,
      endsAt:
          start +
          Duration(
            microseconds: (hours * Duration.microsecondsPerHour).round(),
          ),
      pot: PushPot(owner: pot.owner, ap: ap),
      crushed: math.min(canCrush, units.where((at) => at <= distance).length),
      stop: stop,
    );
  }
}
