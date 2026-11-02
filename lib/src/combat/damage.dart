import 'dart:math' as math;

import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// {@template damage_target}
/// What a hit lands on, as far as damage cares: its armor type, whether it
/// is flying and whether it is on the attacker's side.
/// {@endtemplate}
final class DamageTarget {
  /// {@macro damage_target}
  const new({
    required this.armorType,
    this.flying = false,
    this.friendly = false,
  });

  /// A key of `combat.yaml` `armor_types`: a unit's, an object's (MAP-40),
  /// `hq` for the HQ, `relic` for a relic.
  final String armorType;

  /// Whether it is flying when hit (COMBAT-24, COMBAT-25).
  final bool flying;

  /// Whether it is on the attacker's side (COMBAT-34).
  final bool friendly;
}

/// {@template health}
/// Hit points: [current] out of [max] (COMBAT-36, HQ-16).
/// {@endtemplate}
final class Health {
  /// {@macro health}
  const new({required this.current, required this.max});

  /// Full health.
  factory full(double max) => Health(current: max, max: max);

  /// HP left.
  final double current;

  /// Maximum HP.
  final double max;

  /// Whether no HP are left: a unit dies or is spared (M4 Issue 9), the HQ
  /// is destroyed (HQ-16).
  bool get isZero => current == 0;

  /// This health after losing [amount] HP, not below 0.
  Health damaged(double amount) =>
      Health(current: math.max(0, current - amount), max: max);

  /// This health after gaining [amount] HP, not above [max] (heal, repair).
  Health healed(double amount) =>
      Health(current: math.min(max, current + amount), max: max);
}

/// {@template damage}
/// The damage of hits, from `combat.yaml` (COMBAT-20 to COMBAT-25,
/// COMBAT-34, COMBAT-54, COMBAT-55).
/// {@endtemplate}
final class Damage {
  /// {@macro damage}
  const new(this.combat);

  /// The combat tables.
  final CombatData combat;

  /// The damage of one hit of [weapon] on [target]:
  /// `base_damage × multipliers[weapon][armor]`, `× airborne_factor` when
  /// the target is flying, `× friendly_fire.damage_factor` (or 0 when
  /// friendly fire is off) when it is friendly. Nothing else changes it
  /// (COMBAT-21). A relic's multiplier is 0.
  ///
  /// Throws an [ArgumentError] for an armor type the table does not have.
  double hit(WeaponType weapon, DamageTarget target) {
    final multiplier =
        combat.multipliers[weapon.id]?[target.armorType] ??
        (throw ArgumentError.value(target.armorType, 'armorType', 'unknown'));
    final airborne = target.flying ? weapon.airborneFactor : 1;
    final friendlyFire = combat.friendlyFire;
    final friendly = !target.friendly
        ? 1
        : friendlyFire.enabled
        ? friendlyFire.damageFactor
        : 0;
    return weapon.baseDamage * multiplier * airborne * friendly;
  }

  /// The share of a hit of [weapon] that a unit within the splash takes,
  /// at [distanceM] from the impact point (COMBAT-55, decision 136): from 1
  /// at the impact point to `damage_factor_at_edge` at `splash_radius_m`,
  /// linearly; 0 beyond the radius or for a weapon without splash.
  ///
  /// Throws an [UnsupportedError] for a falloff other than `linear`.
  double splashFactor(WeaponType weapon, double distanceM) {
    final radius = weapon.splashRadiusM;
    if (radius == null || distanceM > radius) return 0;
    final splash = combat.splash;
    if (splash.falloff != 'linear') {
      throw UnsupportedError('splash falloff ${splash.falloff}');
    }
    return 1 + (splash.damageFactorAtEdge - 1) * distanceM / radius;
  }

  /// The damage a unit within the splash of [weapon] takes, at
  /// [distanceM] from the impact point: hit at once, without its own hit
  /// roll, friend or foe (COMBAT-55).
  double splash(WeaponType weapon, DamageTarget target, double distanceM) =>
      hit(weapon, target) * splashFactor(weapon, distanceM);

  /// The damage a unit carried by a transport takes when the transport is
  /// hit by [weapon]: `carried_damage_share` of the hit, computed with the
  /// carried unit's own armor type (UNIT-37, decision 81). [carried] is
  /// flying when its transport is.
  double carriedHit(WeaponType weapon, DamageTarget carried) =>
      combat.transport.carriedDamageShare * hit(weapon, carried);

  /// The damage a carried unit with [stats] takes when its transport is
  /// destroyed and it is ejected: `ejection_damage_share_of_max_hp` of its
  /// maximum HP (COMBAT-54, decision 137).
  double ejection(UnitStats stats) =>
      combat.transport.ejectionDamageShareOfMaxHp * stats.hp;
}
