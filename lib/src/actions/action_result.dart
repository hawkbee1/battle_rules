import 'package:battle_rules/src/actions/capture.dart';
import 'package:battle_rules/src/actions/push.dart';
import 'package:battle_rules/src/actions/role_actions.dart';
import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/combat/damage.dart';

/// Why a role action is refused.
enum ActionRefusal {
  /// The unit's type does not list the action (UNIT-38).
  notInActions,

  /// The unit's type cannot build that structure (UNIT-33).
  notBuildable,

  /// Heal and repair work on friendly units only (decision 139).
  targetNotFriendly,

  /// Heal and repair never work on the HQ (decision 139).
  targetIsHq,

  /// The unit is outside the capture radius (RELIC-05).
  outsideRadius,

  /// An enemy is inside the capture radius (RELIC-06).
  enemyInRadius,

  /// The capture pot is already full.
  potFull,

  /// Fewer than `min_pushers` push (RELIC-24).
  tooFewPushers,

  /// It costs more AP than the unit's pool can ever hold.
  costAboveApMax,
}

/// The outcome of a role action order.
sealed class ActionResult {
  const new();
}

/// {@template action_refused}
/// The order is refused, for [reason].
/// {@endtemplate}
final class ActionRefused extends ActionResult {
  /// {@macro action_refused}
  const new(this.reason);

  /// Why.
  final ActionRefusal reason;
}

/// {@template timed_action_started}
/// A build or a repair starts at [at]: [pool] after paying, [action]
/// running.
/// {@endtemplate}
final class TimedActionStarted extends ActionResult {
  /// {@macro timed_action_started}
  const new({required this.at, required this.pool, required this.action});

  /// The battle time it starts.
  final Duration at;

  /// The unit's AP pool after paying.
  final ApPool pool;

  /// The running action.
  final TimedAction action;
}

/// {@template healed}
/// A heal done at [at]: the healer's [pool] after paying, the target's
/// [health] after it.
/// {@endtemplate}
final class Healed extends ActionResult {
  /// {@macro healed}
  const new({required this.at, required this.pool, required this.health});

  /// The battle time of the heal.
  final Duration at;

  /// The healer's AP pool after paying.
  final ApPool pool;

  /// The target's health after the heal.
  final Health health;
}

/// {@template capture_contributed}
/// A contribution made at [at]: the unit's [pool] after paying, the [pot]
/// after it.
/// {@endtemplate}
final class CaptureContributed extends ActionResult {
  /// {@macro capture_contributed}
  const new({required this.at, required this.pool, required this.pot});

  /// The battle time of the contribution.
  final Duration at;

  /// The unit's AP pool after paying.
  final ApPool pool;

  /// The pot after the contribution.
  final CapturePot pot;
}

/// {@template push_contributed}
/// A push contribution made at [at]: the unit's [pool] after paying, the
/// [pot] after it.
/// {@endtemplate}
final class PushContributed extends ActionResult {
  /// {@macro push_contributed}
  const new({required this.at, required this.pool, required this.pot});

  /// The battle time of the contribution.
  final Duration at;

  /// The unit's AP pool after paying.
  final ApPool pool;

  /// The pot after the contribution.
  final PushPot pot;
}
