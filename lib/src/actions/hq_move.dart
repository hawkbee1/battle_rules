import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/ap/movement.dart';
import 'package:battle_rules/src/data/battle_settings.dart';
import 'package:battle_rules/src/movement/movement_cost.dart';

/// {@template hq_move}
/// The end of an HQ move order: the HQ arrives as [movement] says; the
/// order was [endedByUnit] when a unit stood in its path.
/// {@endtemplate}
final class HqMove {
  /// {@macro hq_move}
  const new({required this.movement, required this.endedByUnit});

  /// Where the HQ's move ends: when, and its AP pool then.
  final Movement movement;

  /// Whether a unit in its path ended the order (HQ-12).
  final bool endedByUnit;
}

/// Moves the HQ along [path] from battle time [start], on the manager's
/// order (HQ-10, decision 177): it is not pushed, it pays from its own AP
/// [pool] (HQ-14).
///
/// Each metre costs `hq.ap_per_m` × the ground and slope multipliers of the
/// `push` profile, at `hq.speed_m_per_h`; with no AP left it moves as fast
/// as its AP come back (COMBAT-06). It never crushes: a unit in its path,
/// friend or enemy, at [unitInPathAtM] metres along it, ends the order
/// there (HQ-12). Null when the path is impassable before that point.
HqMove? moveHq({
  required HqSettings hq,
  required MovementCost cost,
  required ApPool pool,
  required Duration start,
  required List<PathSample> path,
  double? unitInPathAtM,
}) {
  final route = unitInPathAtM == null ? path : pathUpTo(path, unitInPathAtM);
  final movement = cost.move(
    mover: Mover.hq(hq),
    pool: pool,
    start: start,
    path: route,
  );
  if (movement == null) return null;
  return HqMove(movement: movement, endedByUnit: unitInPathAtM != null);
}

/// The first [distanceM] metres of [path].
List<PathSample> pathUpTo(List<PathSample> path, double distanceM) {
  final route = <PathSample>[];
  var left = distanceM;
  for (final sample in path) {
    if (left <= 0) break;
    final length = sample.lengthM < left ? sample.lengthM : left;
    route.add(
      PathSample(
        terrainType: sample.terrainType,
        slopeDegrees: sample.slopeDegrees,
        lengthM: length,
      ),
    );
    left -= length;
  }
  return route;
}
