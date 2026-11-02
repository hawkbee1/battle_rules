import 'dart:math' as math;

import 'package:battle_rules/src/combat/seeded_random.dart';
import 'package:battle_rules/src/combat/vec3.dart';
import 'package:battle_rules/src/data/combat_data.dart';

/// Cover between the attacker and its target (COMBAT-53, decision 135).
enum Cover {
  /// In the open.
  none,

  /// Behind trees, in a crater, behind a low wall: lowers the chance.
  partial,

  /// Hidden: a cover factor of 0, so only the minimum chance is left.
  full,
}

/// {@template hit_roll}
/// One hit roll: the [roll] drawn, against the [chance].
/// {@endtemplate}
final class HitRoll {
  /// {@macro hit_roll}
  const new({required this.roll, required this.chance});

  /// The number drawn, in `[0, 1)`.
  final double roll;

  /// The hit chance it was rolled against.
  final double chance;

  /// Whether it hits: the roll is below the chance.
  bool get hits => roll < chance;

  /// How badly it missed, from 0 (a near miss) to 1 (the worst miss):
  /// `(roll − chance) / (1 − chance)` (decision 154); 0 for a hit.
  double get missImportance => hits ? 0 : (roll - chance) / (1 - chance);
}

/// {@template hit_chance}
/// Hit chance under orders and section AI, and where artillery shots land
/// (COMBAT-12, COMBAT-15 to COMBAT-19, COMBAT-49, COMBAT-53,
/// decisions 62, 65, 71, 135, 154).
/// {@endtemplate}
final class HitChance {
  /// {@macro hit_chance}
  const new(this.combat);

  /// The combat tables.
  final CombatData combat;

  /// The morale factor of an attacker with [morale]: linear from
  /// `morale_factor.at_0` at the lowest morale to `at_100` at the highest
  /// (`morale.range`, decision 71). It also scales first-person spread
  /// (decision 95).
  double moraleFactor(double morale) {
    final factor = combat.hitChance;
    final range = combat.morale;
    final share = (morale - range.min) / (range.max - range.min);
    return factor.moraleAt0 + (factor.moraleAt100 - factor.moraleAt0) * share;
  }

  /// The chance that [weapon] hits (COMBAT-15):
  /// `base_accuracy × (1 + (attack − defense) / 100) × distance × cover ×
  /// size × speed × morale factors (× indirect factor)`, clamped to
  /// `[min, max]`.
  ///
  /// `attack` raises it and `defense` lowers it (COMBAT-17, COMBAT-18);
  /// the distance factor goes linearly from `at_zero` to `at_max_range` at
  /// the weapon's range; full cover leaves the minimum (decision 135).
  /// Throws an [ArgumentError] for a weapon that never misses
  /// (decision 152) and for an armor type the size table does not have.
  double of({
    required WeaponType weapon,
    required double attack,
    required double morale,
    required double defense,
    required String targetArmor,
    required double targetSpeedMps,
    required double distanceM,
    Cover cover = Cover.none,
  }) {
    final baseAccuracy =
        weapon.baseAccuracy ??
        (throw ArgumentError.value(weapon.id, 'weapon', 'never misses'));
    final rules = combat.hitChance;
    final size =
        rules.sizeFactor[targetArmor] ??
        (throw ArgumentError.value(targetArmor, 'targetArmor', 'unknown'));
    final reach = math.min(1, distanceM / weapon.rangeM);
    final distance =
        rules.distanceAtZero +
        (rules.distanceAtMaxRange - rules.distanceAtZero) * reach;
    final coverFactor = switch (cover) {
      Cover.none => rules.coverNone,
      Cover.partial => rules.coverPartial,
      Cover.full => rules.coverFull,
    };
    final speed = math.max(
      rules.speedMin,
      1 - rules.speedPerMps * targetSpeedMps,
    );
    final indirect = weapon.indirectFire ? rules.indirectFactor : 1;
    final chance =
        baseAccuracy *
        (1 + (attack - defense) / 100) *
        distance *
        coverFactor *
        size *
        speed *
        moraleFactor(morale) *
        indirect;
    return chance.clamp(rules.clampMin, rules.clampMax);
  }

  /// Rolls [chance] with [random] (COMBAT-15).
  static HitRoll roll(double chance, SeededRandom random) =>
      HitRoll(roll: random.nextDouble(), chance: chance);

  /// Whether [weapon], with indirect fire, may target a ground position at
  /// [distanceM]: one a unit of its section sees ([seenBySection]) or a
  /// scout reports through a radio in range ([relayedByRadio]), within its
  /// range (COMBAT-12, decision 62). Other weapons need their unit's own
  /// sight (`Vision.canFireAt`), so they never target a position.
  static bool canTargetPosition({
    required WeaponType weapon,
    required double distanceM,
    required bool seenBySection,
    required bool relayedByRadio,
  }) =>
      weapon.indirectFire &&
      distanceM <= weapon.rangeM &&
      (seenBySection || relayedByRadio);

  /// Where an artillery shot from [artillery] aimed at [aimed] lands
  /// (decision 154): on the aimed point when [roll] hits; otherwise in a
  /// random direction from it, drawn from [random], at `miss_scatter.max_m`
  /// × the miss importance. A point beyond the weapon's range from the
  /// artillery is moved back toward it, to the range. Positions are on the
  /// ground: only x and y move.
  Vec3 landingPoint({
    required WeaponType weapon,
    required Vec3 artillery,
    required Vec3 aimed,
    required HitRoll roll,
    required SeededRandom random,
  }) {
    if (roll.hits) return aimed;
    final angle = random.nextDouble() * 2 * math.pi;
    final distance = combat.missScatterMaxM * roll.missImportance;
    final landed = Vec3(
      aimed.x + math.cos(angle) * distance,
      aimed.y + math.sin(angle) * distance,
      aimed.z,
    );
    final offset = Vec3(landed.x - artillery.x, landed.y - artillery.y, 0);
    if (offset.length <= weapon.rangeM) return landed;
    final back = offset.normalized * weapon.rangeM;
    return Vec3(artillery.x + back.x, artillery.y + back.y, aimed.z);
  }
}
