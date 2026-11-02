import 'dart:math' as math;

import 'package:battle_rules/src/data/units_data.dart';

/// Rounding margin when counting the steps that fit under the cap, so that
/// `(3.0 − 1) / 0.1` counts 20 steps, not 19.
const _epsilon = 1e-9;

/// A stat a skill tree can raise (UNIT-20, UNIT-23). AP maximum and AP
/// recovery are not among them (UNIT-22, decision 167).
enum EvolvableStat {
  /// Hit points.
  hp('hp', role: false),

  /// Accuracy.
  attack('attack', role: false),

  /// Evasion.
  defense('defense', role: false),

  /// Speed.
  moveSpeed('move_speed', role: false),

  /// Vision range.
  visionRange('vision_range', role: false),

  /// A radio's relay range (UNIT-36, COMBAT-52).
  relayRange('relay_range', role: true),

  /// A commander's aura radius.
  auraRadius('aura_radius', role: true),

  /// The total weight a transport carries.
  maxTotalWeight('max_total_weight', role: true),

  /// The HP one heal restores.
  heal('heal', role: true);

  new(this.key, {required this.role});

  /// Its name in `units.yaml` `trees`.
  final String key;

  /// Whether it is a role value, which only some types have and add with
  /// `overrides` (UNIT-23).
  final bool role;

  /// The stat named [key], or null when no stat has that name.
  static EvolvableStat? byKey(String key) =>
      values.where((stat) => stat.key == key).firstOrNull;
}

/// {@template skill_tree}
/// The nodes one unit bought on its type's tree: how many steps of each
/// stat (UNIT-18, UNIT-23). Nodes are permanent: [Evolution.buy] returns a
/// larger tree and never a smaller one (UNIT-21).
/// {@endtemplate}
final class SkillTree {
  /// {@macro skill_tree}
  new([Map<EvolvableStat, int> steps = const {}])
    : steps = Map.unmodifiable({
        for (final MapEntry(:key, :value) in steps.entries)
          if (value != 0) key: value,
      });

  /// The steps bought, by stat; a stat with none is absent.
  final Map<EvolvableStat, int> steps;

  /// How many steps of [stat] are bought.
  int stepsOf(EvolvableStat stat) => steps[stat] ?? 0;
}

/// Why a node is not bought.
enum NodeRefusal {
  /// The stat is not on the unit type's tree (UNIT-23).
  notInTree,

  /// The unit already has that step.
  alreadyBought,

  /// The step before it is not bought (UNIT-19).
  prerequisiteMissing,

  /// The step would raise the stat over `stat_cap_of_base` × base (UNIT-22).
  aboveCap,

  /// The unit's unspent XP does not pay for it (UNIT-18).
  notEnoughXp,
}

/// The outcome of a node purchase.
sealed class NodePurchase {
  const new();
}

/// {@template node_bought}
/// The node is bought: the unit now has [tree] and [xpLeft] unspent XP.
/// {@endtemplate}
final class NodeBought extends NodePurchase {
  /// {@macro node_bought}
  const new({required this.tree, required this.xpLeft});

  /// The unit's tree with the new node.
  final SkillTree tree;

  /// Its unspent XP after paying.
  final double xpLeft;
}

/// {@template node_refused}
/// The node is not bought, for [reason]; nothing changes.
/// {@endtemplate}
final class NodeRefused extends NodePurchase {
  /// {@macro node_refused}
  const new(this.reason);

  /// Why.
  final NodeRefusal reason;
}

/// {@template evolution}
/// Skill trees and effective stats (UNIT-18 to UNIT-23): which stats a unit
/// type's tree raises, what each node costs, and the stats a unit plays
/// with once its nodes are applied.
/// {@endtemplate}
final class Evolution {
  /// {@macro evolution}
  const new(this.trees);

  /// The `trees` of `units.yaml`.
  final EvolutionTrees trees;

  /// The stats [type]'s tree raises: those of the default tree, then the
  /// type's extra stats (UNIT-23). `GameData.parse` checks every name.
  List<EvolvableStat> statsOf(UnitType type) => [
    for (final key in [
      ...trees.defaultTree.stats,
      ...?trees.extraStats[type.id],
    ])
      EvolvableStat.byKey(key)!,
  ];

  /// The most steps one stat can take: one more would raise it over
  /// `stat_cap_of_base` × base (UNIT-22).
  int get maxSteps =>
      ((trees.statCapOfBase - 1) / trees.defaultTree.stepBonus + _epsilon)
          .floor();

  /// The XP that step [step] of any stat costs: `cost_base` × [step]
  /// (UNIT-23).
  double stepCost(int step) => trees.defaultTree.costBase * step;

  /// What [steps] steps multiply a stat by: `1 + steps × step_bonus`
  /// (UNIT-20, UNIT-23).
  double factor(int steps) => 1 + steps * trees.defaultTree.stepBonus;

  /// A unit of [type] with [tree] and [unspentXp] buys step [step] of
  /// [stat] with its own XP (UNIT-18). Steps are bought in any order as long
  /// as each one has the step before it (UNIT-19), and no node excludes
  /// another (UNIT-21).
  NodePurchase buy({
    required UnitType type,
    required SkillTree tree,
    required EvolvableStat stat,
    required int step,
    required double unspentXp,
  }) {
    final have = tree.stepsOf(stat);
    final cost = stepCost(step);
    final refusal = switch (step) {
      _ when !statsOf(type).contains(stat) => NodeRefusal.notInTree,
      _ when step <= have => NodeRefusal.alreadyBought,
      _ when step > have + 1 => NodeRefusal.prerequisiteMissing,
      _ when step > maxSteps => NodeRefusal.aboveCap,
      _ when cost > unspentXp => NodeRefusal.notEnoughXp,
      _ => null,
    };
    if (refusal != null) return NodeRefused(refusal);
    return NodeBought(
      tree: SkillTree({...tree.steps, stat: step}),
      xpLeft: unspentXp - cost,
    );
  }

  /// [type] as a unit with [tree] plays it: each stat of its tree times
  /// [factor] of its steps (UNIT-20), never over `stat_cap_of_base` × base
  /// (UNIT-22). The rules of M4 read these values from the returned type.
  /// AP maximum and AP per metre stay the base ones (decision 167). With no
  /// node, [type] itself. Throws an [ArgumentError] for a stat that is not
  /// on [type]'s tree.
  UnitType evolve(UnitType type, SkillTree tree) {
    if (tree.steps.isEmpty) return type;
    final own = statsOf(type);
    for (final stat in tree.steps.keys) {
      if (!own.contains(stat)) {
        throw ArgumentError.value(stat.key, 'tree', 'not on ${type.id} tree');
      }
    }
    double raised(EvolvableStat stat, double base) =>
        base * math.min(factor(tree.stepsOf(stat)), trees.statCapOfBase);
    double? raisedRole(EvolvableStat stat, double? base) =>
        base == null ? null : raised(stat, base);
    final UnitType(:stats, :role) = type;
    return type.withValues(
      stats: stats.withEvolvable(
        hp: raised(EvolvableStat.hp, stats.hp),
        attack: raised(EvolvableStat.attack, stats.attack),
        defense: raised(EvolvableStat.defense, stats.defense),
        moveSpeed: raised(EvolvableStat.moveSpeed, stats.moveSpeed),
        visionRange: raised(EvolvableStat.visionRange, stats.visionRange),
      ),
      role: role.withEvolvable(
        auraRadius: raisedRole(EvolvableStat.auraRadius, role.auraRadius),
        heal: raisedRole(EvolvableStat.heal, role.heal),
        relayRange: raisedRole(EvolvableStat.relayRange, role.relayRange),
        maxTotalWeight: raisedRole(
          EvolvableStat.maxTotalWeight,
          role.maxTotalWeight,
        ),
      ),
    );
  }
}
