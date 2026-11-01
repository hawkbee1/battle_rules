import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// {@template weapon_state}
/// A unit's one weapon slot (COMBAT-26): the weapon in it, the rounds in
/// its magazine, whether it is loaded, and when it is free again.
///
/// A reload, an unload or a swap takes effect at once in the state, but
/// the weapon is busy until [busyUntil]: nothing fires before.
/// {@endtemplate}
final class WeaponState {
  /// {@macro weapon_state}
  const new({
    required this.weapon,
    required this.rounds,
    required this.loaded,
    required this.busyUntil,
    required this.nextShotAt,
  });

  /// An empty slot: the unit cannot attack (COMBAT-13).
  const new unarmed()
    : weapon = null,
      rounds = 0,
      loaded = false,
      busyUntil = Duration.zero,
      nextShotAt = Duration.zero;

  /// [weapon], loaded with a full magazine, free at once.
  new ready(WeaponType this.weapon)
    : rounds = weapon.magazineCapacity,
      loaded = true,
      busyUntil = Duration.zero,
      nextShotAt = Duration.zero;

  /// A newly bought unit's slot: its type's default weapon, ready to fire,
  /// or nothing for an unarmed type (COMBAT-27, decision 52).
  factory forNewUnit(UnitType unit, CombatData combat) {
    final id = unit.weapons.defaultWeapon;
    return id == null
        ? const WeaponState.unarmed()
        : WeaponState.ready(combat.weaponTypes[id]!);
  }

  /// The weapon in the slot; null when empty.
  final WeaponType? weapon;

  /// Rounds left in the magazine.
  final int rounds;

  /// Whether a magazine is in: set by a reload, cleared by an unload.
  final bool loaded;

  /// The battle time until which a reload, an unload or a swap goes on.
  final Duration busyUntil;

  /// The earliest battle time of the next shot, from the rate of fire.
  final Duration nextShotAt;

  /// Whether the unit may move at battle time [time]: not while its weapon
  /// is loaded, or being handled, when `move_while_loaded` is false.
  bool canMoveAt(Duration time) {
    final weapon = this.weapon;
    return weapon == null ||
        weapon.moveWhileLoaded ||
        (!loaded && time >= busyUntil);
  }

  WeaponState _with({
    required WeaponType? weapon,
    required int rounds,
    required bool loaded,
    Duration? busyUntil,
    Duration? nextShotAt,
  }) => WeaponState(
    weapon: weapon,
    rounds: rounds,
    loaded: loaded,
    busyUntil: busyUntil ?? this.busyUntil,
    nextShotAt: nextShotAt ?? this.nextShotAt,
  );
}

/// {@template dropped_weapon}
/// A weapon lying on the ground (COMBAT-29), until [goneAt] (COMBAT-31).
/// {@endtemplate}
final class DroppedWeapon {
  /// {@macro dropped_weapon}
  const new({required this.weapon, required this.goneAt});

  /// The weapon.
  final WeaponType weapon;

  /// The battle time at which it vanishes.
  final Duration goneAt;

  /// Whether it has vanished at battle time [time].
  bool isGoneAt(Duration time) => time >= goneAt;
}

/// {@template stored_weapons}
/// The spare weapons in a section's storage, by weapon type id: bought or
/// swapped out, until a unit takes one (COMBAT-27, decision 151).
/// {@endtemplate}
final class StoredWeapons {
  /// {@macro stored_weapons}
  const new(this.weapons);

  /// The stored weapons' type ids, one entry per weapon.
  final List<String> weapons;

  /// These weapons with one more [weaponId].
  StoredWeapons added(String weaponId) =>
      StoredWeapons(List.unmodifiable([...weapons, weaponId]));

  /// These weapons without one [weaponId].
  StoredWeapons removed(String weaponId) =>
      StoredWeapons(List.unmodifiable([...weapons]..remove(weaponId)));
}

/// Why a weapon order is refused.
enum WeaponRefusal {
  /// The slot is empty (COMBAT-13).
  noWeapon,

  /// No magazine is in: reload first.
  notLoaded,

  /// The magazine is empty: reload first.
  emptyMagazine,

  /// The unit's type may not use that weapon type (COMBAT-26).
  notAllowed,

  /// The unit is neither stored nor next to its storage place (COMBAT-28).
  notAtStorage,

  /// The section's storage holds no such weapon (decision 151).
  notInStorage,

  /// The dropped weapon has vanished (COMBAT-31).
  weaponGone,

  /// It costs more AP than the unit's pool can ever hold.
  costAboveApMax,
}

/// The outcome of a weapon order.
sealed class WeaponResult {
  const new();
}

/// {@template weapon_refused}
/// The order is refused, for [reason].
/// {@endtemplate}
final class WeaponRefused extends WeaponResult {
  /// {@macro weapon_refused}
  const new(this.reason);

  /// Why.
  final WeaponRefusal reason;
}

/// {@template weapon_done}
/// The order starts at [at] and leaves the weapon [state] and the AP
/// [pool]; a swap also changes the section's [storage], a pick-up leaves
/// the unit's former weapon [dropped].
/// {@endtemplate}
final class WeaponDone extends WeaponResult {
  /// {@macro weapon_done}
  const new({
    required this.at,
    required this.state,
    required this.pool,
    this.storage,
    this.dropped,
  });

  /// The battle time it starts.
  final Duration at;

  /// The weapon slot after it.
  final WeaponState state;

  /// The AP pool after it.
  final ApPool pool;

  /// The section's spare weapons after a swap; null otherwise.
  final StoredWeapons? storage;

  /// The weapon the unit dropped to pick another up; null otherwise.
  final DroppedWeapon? dropped;
}

/// {@template armory}
/// Weapon handling, from `combat.yaml` (COMBAT-26 to COMBAT-33,
/// COMBAT-56).
/// {@endtemplate}
final class Armory {
  /// {@macro armory}
  const new(this.combat);

  /// The combat tables.
  final CombatData combat;

  /// Fires one shot, ordered at battle time [now] (COMBAT-04, COMBAT-32).
  ///
  /// The shot waits for the weapon to be free, for its rate of fire
  /// (`rate_of_fire_rpm`, except a 1-round weapon) and for `ap_per_shot`
  /// AP. A 1-round weapon needs
  /// a reload after each shot, so it fires once per `reload_time_s`
  /// (COMBAT-56). Refused with no weapon (COMBAT-13), no magazine in, an
  /// empty magazine, or a cost above the pool's maximum.
  WeaponResult fire({
    required WeaponState state,
    required ApPool pool,
    required Duration now,
  }) {
    final weapon = state.weapon;
    if (weapon == null) return const WeaponRefused(WeaponRefusal.noWeapon);
    if (!state.loaded) return const WeaponRefused(WeaponRefusal.notLoaded);
    if (state.rounds == 0) {
      return const WeaponRefused(WeaponRefusal.emptyMagazine);
    }
    final free = _latest([now, state.busyUntil, state.nextShotAt]);
    final paid = pool.payWhenReady(weapon.apPerShot, free);
    if (paid == null) {
      return const WeaponRefused(WeaponRefusal.costAboveApMax);
    }
    return WeaponDone(
      at: paid.at,
      pool: paid.pool,
      state: state._with(
        weapon: weapon,
        rounds: state.rounds - 1,
        loaded: true,
        // A 1-round weapon does not use its rate of fire: its reload sets
        // the time between shots (COMBAT-56).
        nextShotAt: weapon.magazineCapacity == 1
            ? paid.at
            : paid.at +
                  _seconds(Duration.secondsPerMinute / weapon.rateOfFireRpm),
      ),
    );
  }

  /// Reloads, ordered at battle time [now]: a full magazine after
  /// `reload_time_s`, the rounds left in it discarded (COMBAT-33). Time
  /// only, no AP (COMBAT-05).
  WeaponResult reload({
    required WeaponState state,
    required ApPool pool,
    required Duration now,
  }) {
    final weapon = state.weapon;
    if (weapon == null) return const WeaponRefused(WeaponRefusal.noWeapon);
    final at = _latest([now, state.busyUntil]);
    return WeaponDone(
      at: at,
      pool: pool,
      state: state._with(
        weapon: weapon,
        rounds: weapon.magazineCapacity,
        loaded: true,
        busyUntil: at + _seconds(weapon.reloadTimeS),
      ),
    );
  }

  /// Unloads, ordered at battle time [now], in `unload_time_s`: the
  /// magazine comes out, rounds and all. Time only, no AP (COMBAT-05).
  WeaponResult unload({
    required WeaponState state,
    required ApPool pool,
    required Duration now,
  }) {
    final weapon = state.weapon;
    if (weapon == null) return const WeaponRefused(WeaponRefusal.noWeapon);
    final at = _latest([now, state.busyUntil]);
    return WeaponDone(
      at: at,
      pool: pool,
      state: state._with(
        weapon: weapon,
        rounds: 0,
        loaded: false,
        busyUntil: at + _seconds(weapon.unloadTimeS),
      ),
    );
  }

  /// Puts the stored weapon [weaponId] in [unit]'s slot, ordered at battle
  /// time [now], and puts its former weapon, if any, in the section's
  /// [storage] (COMBAT-28, decisions 53, 151). Only while the unit is stored
  /// or next to its storage place ([atStorage]), only an allowed type
  /// (COMBAT-26). Takes `weapon_swap.time_s`, no AP (decision 134). The new
  /// weapon arrives unloaded.
  WeaponResult swap({
    required UnitType unit,
    required WeaponState state,
    required ApPool pool,
    required StoredWeapons storage,
    required String weaponId,
    required bool atStorage,
    required Duration now,
  }) {
    if (!atStorage) return const WeaponRefused(WeaponRefusal.notAtStorage);
    if (!unit.weapons.allowed.contains(weaponId)) {
      return const WeaponRefused(WeaponRefusal.notAllowed);
    }
    if (!storage.weapons.contains(weaponId)) {
      return const WeaponRefused(WeaponRefusal.notInStorage);
    }
    final at = _latest([now, state.busyUntil]);
    final former = state.weapon;
    return WeaponDone(
      at: at,
      pool: pool,
      storage: former == null
          ? storage.removed(weaponId)
          : storage.removed(weaponId).added(former.id),
      state: state._with(
        weapon: combat.weaponTypes[weaponId],
        rounds: 0,
        loaded: false,
        busyUntil: at + _seconds(combat.weaponSwapTimeS),
      ),
    );
  }

  /// The weapon a unit killed at battle time [at] drops; null when it had
  /// none (COMBAT-29). It vanishes after `despawn_after_s` (COMBAT-31).
  DroppedWeapon? drop(WeaponState state, Duration at) {
    final weapon = state.weapon;
    if (weapon == null) return null;
    return DroppedWeapon(
      weapon: weapon,
      goneAt: at + _seconds(combat.droppedWeapons.despawnAfterS),
    );
  }

  /// [unit] picks up [dropped] on the spot, ordered at battle time [now],
  /// for `pickup_ap` AP, dropping its own weapon in its place (COMBAT-30,
  /// decision 63). Any team's unit can, if its type may use the weapon. The
  /// picked-up weapon arrives unloaded.
  WeaponResult pickUp({
    required UnitType unit,
    required WeaponState state,
    required ApPool pool,
    required DroppedWeapon dropped,
    required Duration now,
  }) {
    if (dropped.isGoneAt(now)) {
      return const WeaponRefused(WeaponRefusal.weaponGone);
    }
    if (!unit.weapons.allowed.contains(dropped.weapon.id)) {
      return const WeaponRefused(WeaponRefusal.notAllowed);
    }
    final paid = pool.payWhenReady(combat.droppedWeapons.pickupAp, now);
    if (paid == null) {
      return const WeaponRefused(WeaponRefusal.costAboveApMax);
    }
    return WeaponDone(
      at: paid.at,
      pool: paid.pool,
      dropped: drop(state, paid.at),
      state: state._with(weapon: dropped.weapon, rounds: 0, loaded: false),
    );
  }
}

Duration _latest(List<Duration> times) => times.reduce((a, b) => a > b ? a : b);

Duration _seconds(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
