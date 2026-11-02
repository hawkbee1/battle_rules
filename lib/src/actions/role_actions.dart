import 'dart:math' as math;

import 'package:battle_rules/src/actions/action_result.dart';
import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/combat/damage.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/terrain_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// {@template action_target}
/// Who a heal or a repair is for: whether it is friendly and whether it is
/// the HQ.
/// {@endtemplate}
final class ActionTarget {
  /// {@macro action_target}
  const new({required this.friendly, this.isHq = false});

  /// Whether it is on the acting unit's side.
  final bool friendly;

  /// Whether it is an HQ.
  final bool isHq;
}

/// {@template timed_action}
/// A build or a repair: [ap] paid up front, then [duration] (COMBAT-07),
/// with the [progress] made so far (COMBAT-09).
///
/// While it runs, [startedAt] is the battle time its running part started.
/// {@endtemplate}
final class TimedAction {
  /// {@macro timed_action}
  const new({
    required this.ap,
    required this.duration,
    this.progress = 0,
    this.startedAt,
  });

  /// The AP of the whole action.
  final double ap;

  /// The duration of the whole action.
  final Duration duration;

  /// The share already done, from 0 to 1.
  final double progress;

  /// The battle time the running part started; null while it is not
  /// running.
  final Duration? startedAt;

  /// The AP of the part left to do: what starting or resuming it costs.
  double get remainingAp => ap * (1 - progress);

  /// The time of the part left to do.
  Duration get remainingDuration => duration * (1 - progress);

  /// The battle time it ends; null while it is not running.
  Duration? get endsAt {
    final startedAt = this.startedAt;
    return startedAt == null ? null : startedAt + remainingDuration;
  }

  /// The share done at battle time [time].
  double progressAt(Duration time) {
    final startedAt = this.startedAt;
    if (startedAt == null) return progress;
    if (duration == Duration.zero) return 1;
    final elapsed = (time - startedAt).inMicroseconds / duration.inMicroseconds;
    return math.min(1, progress + elapsed);
  }

  /// This action interrupted at battle time [time]: the AP paid are lost,
  /// the progress is kept (COMBAT-09).
  TimedAction interruptedAt(Duration time) =>
      TimedAction(ap: ap, duration: duration, progress: progressAt(time));

  TimedAction _startedAt(Duration time) => TimedAction(
    ap: ap,
    duration: duration,
    progress: progress,
    startedAt: time,
  );
}

/// {@template role_action_rules}
/// Build, repair and heal (COMBAT-07, UNIT-33, UNIT-35, decisions 66, 91,
/// 113, 139).
/// {@endtemplate}
final class RoleActionRules {
  /// {@macro role_action_rules}
  const new({required this.combat, required this.terrain});

  /// The combat tables (`actions`).
  final CombatData combat;

  /// The terrain tables (`objects`: construction AP and time).
  final TerrainData terrain;

  /// [unit] starts building [structure], ordered at battle time [now]: the
  /// structure's AP up front, then its build time (COMBAT-07,
  /// decision 113). Only a unit that lists `build` and whose role lists
  /// the structure (UNIT-33).
  ActionResult startBuild({
    required UnitType unit,
    required String structure,
    required ApPool pool,
    required Duration now,
  }) {
    if (!unit.actions.contains(UnitAction.build)) {
      return const ActionRefused(ActionRefusal.notInActions);
    }
    final construction = terrain.objects[structure]?.construction;
    if (!unit.role.build.contains(structure) || construction == null) {
      return const ActionRefused(ActionRefusal.notBuildable);
    }
    return resume(
      action: TimedAction(
        ap: construction.ap,
        duration: _seconds(construction.buildTimeS),
      ),
      pool: pool,
      now: now,
    );
  }

  /// [unit] starts repairing [target], ordered at battle time [now]:
  /// `actions.repair.ap` up front, then its duration; it restores
  /// [repairHp] at the end (COMBAT-07). Friendly units only, never the HQ
  /// (decision 139).
  ActionResult startRepair({
    required UnitType unit,
    required ActionTarget target,
    required ApPool pool,
    required Duration now,
  }) {
    if (!unit.actions.contains(UnitAction.repair)) {
      return const ActionRefused(ActionRefusal.notInActions);
    }
    final refusal = _targetRefusal(target);
    if (refusal != null) return ActionRefused(refusal);
    final repair = combat.actions.repair;
    return resume(
      action: TimedAction(ap: repair.ap, duration: _seconds(repair.durationS)),
      pool: pool,
      now: now,
    );
  }

  /// HP a finished repair restores (`actions.repair.hp_restored`).
  double get repairHp => combat.actions.repair.hpRestored;

  /// Starts or resumes [action], ordered at battle time [now]: it waits
  /// for the AP of the part left, pays them, then runs (COMBAT-06,
  /// COMBAT-09). Any unit may resume it.
  ActionResult resume({
    required TimedAction action,
    required ApPool pool,
    required Duration now,
  }) {
    final paid = pool.payWhenReady(action.remainingAp, now);
    if (paid == null) return const ActionRefused(ActionRefusal.costAboveApMax);
    return TimedActionStarted(
      at: paid.at,
      pool: paid.pool,
      action: action._startedAt(paid.at),
    );
  }

  /// [unit] heals [target], whose health is [health], ordered at battle
  /// time [now]: at once, its role's `heal_ap` restores its `heal` HP
  /// (UNIT-35, decision 91). Friendly units only, never the HQ
  /// (decision 139).
  ActionResult heal({
    required UnitType unit,
    required ActionTarget target,
    required Health health,
    required ApPool pool,
    required Duration now,
  }) {
    if (!unit.actions.contains(UnitAction.heal)) {
      return const ActionRefused(ActionRefusal.notInActions);
    }
    final refusal = _targetRefusal(target);
    if (refusal != null) return ActionRefused(refusal);
    final paid = pool.payWhenReady(unit.role.healAp!, now);
    if (paid == null) return const ActionRefused(ActionRefusal.costAboveApMax);
    return Healed(
      at: paid.at,
      pool: paid.pool,
      health: health.healed(unit.role.heal!),
    );
  }

  ActionRefusal? _targetRefusal(ActionTarget target) {
    if (!target.friendly) return ActionRefusal.targetNotFriendly;
    if (target.isHq) return ActionRefusal.targetIsHq;
    return null;
  }
}

Duration _seconds(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
