import 'package:battle_rules/src/combat/seeded_random.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// What happens to a unit at 0 HP (COMBAT-36 to COMBAT-43).
enum ZeroHpOutcome {
  /// It dies: permadeath; a commander resurrects in storage (COMBAT-36).
  death,

  /// It switches to the attacker's section, keeping its XP, evolution and
  /// weapon (COMBAT-40, COMBAT-41).
  defection,

  /// It goes to the captor section's prisoner storage with its weapon
  /// (COMBAT-43).
  prisoner;

  /// Whether the unit drops its weapon: only when it dies (COMBAT-29).
  bool get dropsWeapon => this == death;
}

/// {@template prisoner_storage}
/// A section's prisoners, by unit id: separate from its unit storage,
/// unlimited, never counted in storage capacity (COMBAT-43, decision 94).
/// {@endtemplate}
final class PrisonerStorage {
  /// {@macro prisoner_storage}
  const new([this.prisoners = const []]);

  /// The prisoners' unit ids.
  final List<String> prisoners;

  /// This storage with [unitId] taken prisoner. There is no limit.
  PrisonerStorage added(String unitId) =>
      PrisonerStorage(List.unmodifiable([...prisoners, unitId]));
}

/// {@template zero_hp_rules}
/// The outcome of a unit brought to 0 HP, from `combat.yaml` `zero_hp`
/// (decisions 37f, 72, 131, 149).
/// {@endtemplate}
final class ZeroHp {
  /// {@macro zero_hp_rules}
  const new({required this.rules, required this.morale});

  /// The 0-HP values.
  final ZeroHpRules rules;

  /// The morale values (`morale.range`).
  final MoraleRules morale;

  /// The chance a unit with [moraleValue] and [ap] of [apMax] AP is spared
  /// (COMBAT-39, decision 72): `k × ((max − morale) / (max − min) + (1 −
  /// ap / apMax)) / 2`, with the morale range. Low morale and low AP raise
  /// it.
  double sparedChance({
    required double moraleValue,
    required double ap,
    required double apMax,
  }) {
    final lowMorale = (morale.max - moraleValue) / (morale.max - morale.min);
    return rules.k * (lowMorale + (1 - ap / apMax)) / 2;
  }

  /// Whether [target] may be spared when [attacker] deals the final blow
  /// (COMBAT-37): the attacker's category is `only_when_final_blow_by`
  /// (a commander), the target is an enemy (decision 131), and its type is
  /// not in `never_spared` (decision 149).
  bool maySpare({
    required UnitType attacker,
    required UnitType target,
    required bool targetIsEnemy,
  }) =>
      attacker.category == rules.onlyWhenFinalBlowBy &&
      targetIsEnemy &&
      !rules.neverSpared.contains(target.id);

  /// What happens to [target], with [moraleValue] and [ap] AP, brought to
  /// 0 HP by [attacker] (COMBAT-36 to COMBAT-39).
  ///
  /// It dies unless it may be spared. Then [random] decides: spared with
  /// the [sparedChance]; a spared unit defects with `defection_share`, if
  /// the attacker's section has room under its size cap
  /// ([attackerSectionHasRoom], UNIT-39), and is taken prisoner otherwise.
  ZeroHpOutcome resolve({
    required UnitType attacker,
    required UnitType target,
    required bool targetIsEnemy,
    required double moraleValue,
    required double ap,
    required bool attackerSectionHasRoom,
    required SeededRandom random,
  }) {
    if (!maySpare(
      attacker: attacker,
      target: target,
      targetIsEnemy: targetIsEnemy,
    )) {
      return ZeroHpOutcome.death;
    }
    final spared =
        random.nextDouble() <
        sparedChance(
          moraleValue: moraleValue,
          ap: ap,
          apMax: target.stats.apMax,
        );
    if (!spared) return ZeroHpOutcome.death;
    final defects = random.nextDouble() < rules.defectionShare;
    return defects && attackerSectionHasRoom
        ? ZeroHpOutcome.defection
        : ZeroHpOutcome.prisoner;
  }
}
