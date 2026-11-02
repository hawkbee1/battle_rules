import 'dart:math' as math;

import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/combat/damage.dart';
import 'package:battle_rules/src/data/battle_settings.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/units_data.dart';
import 'package:battle_rules/src/progression/xp.dart';
import 'package:battle_rules/src/storage/unit_location.dart';

/// A section's portal: where it stores its units, deploys them, and where
/// its new units arrive (HQ-27, HQ-28, HQ-46).
enum StoragePlace {
  /// Its guild's camp (HQ-27).
  guildCamp,

  /// The team's HQ (HQ-03, HQ-28, HQ-38).
  hq,
}

/// Why a store or recall order is refused.
enum StoreRefusal {
  /// Only a unit on the field is stored or recalled.
  notOnField,

  /// The guild camp is never stored by order (HQ-30, HQ-47).
  neverStored,

  /// A transport is stored empty: unload it first (HQ-49, decision 206).
  carriesUnits,

  /// Its recall runs already.
  alreadyRecalled,
}

/// The outcome of a store order (HQ-31, HQ-32).
sealed class StoreOrder {
  const new();
}

/// {@template stored_at_once}
/// The unit is [Stored] at once (HQ-31).
/// {@endtemplate}
final class StoredAtOnce extends StoreOrder {
  /// {@macro stored_at_once}
  const new();
}

/// {@template recall_started}
/// The unit is recalled: it stays on the field as [location] until its
/// recall is done, and nothing stops it (HQ-32).
/// {@endtemplate}
final class RecallStarted extends StoreOrder {
  /// {@macro recall_started}
  const new(this.location);

  /// The unit's location during its recall.
  final OnField location;
}

/// {@template store_refused}
/// The order is refused, for [reason]; nothing changes.
/// {@endtemplate}
final class StoreRefused extends StoreOrder {
  /// {@macro store_refused}
  const new(this.reason);

  /// Why.
  final StoreRefusal reason;
}

/// Why a deployment is refused.
enum DeployRefusal {
  /// Only a stored unit deploys.
  notStored,

  /// The section is under its 24-hour lock (HQ-35).
  sectionLocked,

  /// An enemy is near the storage place, and nothing deploys elsewhere
  /// instead (HQ-36, HQ-39).
  blockedByEnemy,

  /// It costs more AP than the unit's pool can ever hold.
  costAboveApMax,
}

/// The outcome of a deployment order (HQ-33).
sealed class DeployOrder {
  const new();
}

/// {@template deploy_starts}
/// The unit is [Deployed] next to its storage place at [at], fully
/// operational, with the AP [pool] left after paying (HQ-33).
/// {@endtemplate}
final class DeployStarts extends DeployOrder {
  /// {@macro deploy_starts}
  const new({required this.at, required this.pool});

  /// The battle time it deploys.
  final Duration at;

  /// The AP pool after paying.
  final ApPool pool;
}

/// {@template deploy_refused}
/// The deployment is refused, for [reason]; nothing changes.
/// {@endtemplate}
final class DeployRefused extends DeployOrder {
  /// {@macro deploy_refused}
  const new(this.reason);

  /// Why.
  final DeployRefusal reason;
}

/// A unit's place, AP and morale.
typedef UnitCondition = ({UnitLocation location, ApPool pool, double morale});

/// {@template storage_rules}
/// Storage, deployment and the commander's death (HQ-02, HQ-03, HQ-13,
/// HQ-19, HQ-20, HQ-24 to HQ-42, HQ-44, HQ-46, HQ-47, HQ-49, UNIT-28,
/// UNIT-29), from `battle.yaml` `storage`, `commander_death` and
/// `section_redeploy_lock_s` and the morale range of `combat.yaml`.
///
/// Positions stay abstract: the caller gives the distances to the storage
/// place. Nothing here depends on the HQ standing still, so storage and
/// resurrection work while it moves (HQ-13).
/// {@endtemplate}
final class StorageRules {
  /// {@macro storage_rules}
  const new({required this.battle, required this.morale});

  /// The `battle.yaml` data.
  final BattleSettings battle;

  /// The morale values (`morale.range`).
  final MoraleRules morale;

  StorageSettings get _storage => battle.storage;

  /// The portal of a section [inGuild] whose guild has a camp or not
  /// ([guildHasCamp]): the camp, or the HQ (HQ-27, HQ-28, HQ-38, HQ-41).
  /// New units arrive there too (HQ-46, ECO-07).
  StoragePlace placeOf({required bool inGuild, required bool guildHasCamp}) =>
      inGuild && guildHasCamp ? StoragePlace.guildCamp : StoragePlace.hq;

  /// A store order at battle time [now] for a unit of [type] at
  /// [location], [distanceM] from its storage place (HQ-31, HQ-32).
  ///
  /// Within `store_radius_m` it is stored at once; elsewhere it is recalled
  /// for `recall_s`. A transport that [carriesUnits] is refused, and so is
  /// a recall of a unit already recalled (HQ-49, decision 206).
  StoreOrder store({
    required UnitType type,
    required UnitLocation location,
    required double distanceM,
    required bool carriesUnits,
    required Duration now,
  }) {
    if (location is! OnField) {
      return const StoreRefused(StoreRefusal.notOnField);
    }
    if (!type.storable) return const StoreRefused(StoreRefusal.neverStored);
    if (carriesUnits) return const StoreRefused(StoreRefusal.carriesUnits);
    if (distanceM <= _storage.storeRadiusM) return const StoredAtOnce();
    if (location.recallDoneAt != null) {
      return const StoreRefused(StoreRefusal.alreadyRecalled);
    }
    return RecallStarted(
      location.recalledUntil(now + _seconds(_storage.recallS)),
    );
  }

  /// Whether an enemy at [nearestEnemyM] metres from a storage place
  /// blocks deployment and the arrival of bought units there: within
  /// `deploy_block_radius_m` (HQ-36, HQ-46, decision 147). A new section's
  /// commander is never blocked (decision 210). Null: no enemy.
  bool blocks(double? nearestEnemyM) =>
      nearestEnemyM != null && nearestEnemyM <= _storage.deployBlockRadiusM;

  /// Whether a section locked until [lockedUntil] is locked at battle time
  /// [now] (HQ-35). Null: not locked.
  bool isLocked({required Duration? lockedUntil, required Duration now}) =>
      lockedUntil != null && now < lockedUntil;

  /// The battle time until which a section cannot deploy, when at [at] a
  /// unit of it left the field and its alive [units] remain; null when no
  /// lock starts (HQ-35, decisions 120, 125, 204).
  ///
  /// The lock starts once no storable unit of the section is on the field:
  /// the guild camp, never stored, does not count, nor do its units held
  /// prisoner, which it cannot store. The last unit may leave the field by
  /// a storage, a finished recall, a death, a capture or a defection: the
  /// lock runs `section_redeploy_lock_s` from that moment. A storage forced
  /// by the commander's death ([byCommanderDeath]) never starts it.
  Duration? lockAfter({
    required Duration at,
    required Iterable<(UnitType, UnitLocation)> units,
    required bool byCommanderDeath,
  }) {
    if (byCommanderDeath) return null;
    final onField = units.any((unit) => unit.$1.storable && unit.$2.onField);
    return onField ? null : at + _seconds(battle.sectionRedeployLockS);
  }

  /// A deployment order at battle time [now] for a unit at [location] with
  /// the AP [pool] (HQ-33 to HQ-36, HQ-39).
  ///
  /// Only a stored unit deploys, next to its storage place, paying
  /// `deploy_ap`. A locked section ([lockedUntil]) or an enemy at
  /// [nearestEnemyM] within `deploy_block_radius_m` blocks it, with no
  /// fallback to another portal. Like any paid action it waits until the
  /// pool holds its AP (COMBAT-06); the host checks the block and the lock
  /// again when the wait ends.
  DeployOrder deploy({
    required UnitLocation location,
    required ApPool pool,
    required Duration now,
    required double? nearestEnemyM,
    required Duration? lockedUntil,
  }) {
    if (location is! Stored) {
      return const DeployRefused(DeployRefusal.notStored);
    }
    if (isLocked(lockedUntil: lockedUntil, now: now)) {
      return const DeployRefused(DeployRefusal.sectionLocked);
    }
    if (blocks(nearestEnemyM)) {
      return const DeployRefused(DeployRefusal.blockedByEnemy);
    }
    final paid = pool.payWhenReady(_storage.deployAp, now);
    if (paid == null) return const DeployRefused(DeployRefusal.costAboveApMax);
    return DeployStarts(at: paid.at, pool: paid.pool);
  }

  /// A unit of [type] of a dead commander's section, at battle time [at]
  /// (UNIT-29, decisions 80, 125).
  ///
  /// On the field, carried or not, it is stored at once and loses
  /// `ap_loss_share` of its `ap_max` and `morale_loss` morale. A unit
  /// already stored, a prisoner and the guild camp, never stored, stay as
  /// they are. The units of other sections his transports carry are set
  /// down where they are (`Carried.setDown`, decision 206).
  UnitCondition atCommanderDeath({
    required UnitType type,
    required UnitLocation location,
    required ApPool pool,
    required double morale,
    required Duration at,
  }) => location.onField && type.storable
      ? _storedWithLosses(pool: pool, morale: morale, at: at)
      : (location: location, pool: pool, morale: morale);

  /// The [commander] killed at battle time [at], with [pool], [morale]
  /// and [xp] (UNIT-28, UNIT-29, decisions 80, 125, 207).
  ///
  /// He resurrects at once, in storage, with full HP and the AP and morale
  /// losses of his section's units. He loses `xp_loss_share` of his unspent
  /// XP, from his earned XP too; his level, set by section XP, never drops.
  /// Throws an [ArgumentError] for a type whose death is final.
  ({UnitCondition condition, Health health, UnitXp xp}) resurrect({
    required UnitType commander,
    required ApPool pool,
    required double morale,
    required UnitXp xp,
    required Duration at,
  }) {
    if (commander.permadeath) {
      throw ArgumentError.value(commander.id, 'commander', 'never resurrects');
    }
    final lost = xp.unspent * battle.commanderDeath.xpLossShare;
    return (
      condition: _storedWithLosses(pool: pool, morale: morale, at: at),
      health: Health.full(commander.stats.hp),
      xp: UnitXp(earned: xp.earned - lost, unspent: xp.unspent - lost),
    );
  }

  /// A unit of a team eliminated (HQ-19, HQ-20, decision 208): on the
  /// field, carried or not, it is stored for the next battle of the war,
  /// with no AP or morale loss. The guild camp too, the one time it is
  /// stored. A unit already stored or a prisoner stays where it is.
  UnitLocation atElimination(UnitLocation location) =>
      location.onField ? const Stored() : location;

  UnitCondition _storedWithLosses({
    required ApPool pool,
    required double morale,
    required Duration at,
  }) {
    final death = battle.commanderDeath;
    final ap = math.max(0, pool.apAt(at) - death.apLossShare * pool.max);
    return (
      location: const Stored(),
      pool: pool.withValue(ap.toDouble(), at),
      morale: (morale - death.moraleLoss).clamp(
        this.morale.min,
        this.morale.max,
      ),
    );
  }
}

Duration _seconds(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
