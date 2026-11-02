import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// Something a unit starts that costs AP or only time (COMBAT-04,
/// COMBAT-05). Movement, paid metre by metre, is `moveAlong`.
sealed class Activity {
  const new();
}

/// An action whose AP are paid at once when it starts (COMBAT-04).
sealed class PaidAction extends Activity {
  const new();

  /// The AP it costs.
  double get ap;
}

/// {@template shot}
/// One shot of [weapon]: `ap_per_shot` AP.
/// {@endtemplate}
final class Shot extends PaidAction {
  /// {@macro shot}
  const new(this.weapon);

  /// The weapon fired.
  final WeaponType weapon;

  @override
  double get ap => weapon.apPerShot;
}

/// {@template weapon_pickup}
/// Picking up a weapon from the ground: `dropped_weapons.pickup_ap` AP
/// (decision 63).
/// {@endtemplate}
final class WeaponPickup extends PaidAction {
  /// {@macro weapon_pickup}
  const new(this.rules);

  /// The dropped-weapon rules of `combat.yaml`.
  final DroppedWeapons rules;

  @override
  double get ap => rules.pickupAp;
}

/// {@template role_action_start}
/// The start of a role action ([action]), with the [ap] it costs up front
/// (COMBAT-07). Only a unit whose type lists [action] can do it (UNIT-38).
/// {@endtemplate}
final class RoleActionStart extends PaidAction {
  /// {@macro role_action_start}
  const new(this.action, this.ap);

  /// The role action.
  final UnitAction action;

  @override
  final double ap;
}

/// What costs only time (COMBAT-05, decisions 55, 68, 134).
enum TimeOnlyAction implements Activity {
  /// Loading a full magazine.
  reload,

  /// Unloading the weapon.
  unload,

  /// Swapping weapons at storage.
  swapWeapon,

  /// Landing a flying unit.
  land,

  /// Taking off.
  takeOff,
}

/// Why an activity is refused.
enum Refusal {
  /// The unit's type does not list the role action (UNIT-38).
  notInActions,

  /// It costs more AP than the pool can ever hold.
  costAboveApMax,
}

/// When an activity starts, or why it does not.
sealed class ActivityStart {
  const new();
}

/// {@template activity_starts}
/// The activity starts at [at]; [pool] is the AP pool after paying.
/// {@endtemplate}
final class ActivityStarts extends ActivityStart {
  /// {@macro activity_starts}
  const new({required this.at, required this.pool});

  /// The battle time at which it starts.
  final Duration at;

  /// The AP pool after paying.
  final ApPool pool;
}

/// {@template activity_refused}
/// The activity is refused, for [reason].
/// {@endtemplate}
final class ActivityRefused extends ActivityStart {
  /// {@macro activity_refused}
  const new(this.reason);

  /// Why.
  final Refusal reason;
}

/// Starts [activity] of [unit], ordered at battle time [now], against its
/// AP [pool].
///
/// A time-only action starts at once and leaves the pool as it is
/// (COMBAT-05). A paid action waits until the pool holds its AP, then pays
/// them (COMBAT-04, COMBAT-06). A role action the unit's type does not list
/// is refused (UNIT-38), and so is an action that costs more than the
/// pool's maximum.
ActivityStart startActivity({
  required UnitType unit,
  required ApPool pool,
  required Activity activity,
  required Duration now,
}) {
  switch (activity) {
    case TimeOnlyAction():
      return ActivityStarts(at: now, pool: pool);
    case RoleActionStart(:final action) when !unit.actions.contains(action):
      return const ActivityRefused(Refusal.notInActions);
    case PaidAction(:final ap):
      final paid = pool.payWhenReady(ap, now);
      if (paid == null) return const ActivityRefused(Refusal.costAboveApMax);
      return ActivityStarts(at: paid.at, pool: paid.pool);
  }
}
