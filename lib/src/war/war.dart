import 'package:battle_rules/src/ap/ap_pool.dart';
import 'package:battle_rules/src/combat/damage.dart';
import 'package:battle_rules/src/data/battle_settings.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/units_data.dart';
import 'package:battle_rules/src/storage/unit_location.dart';

/// Why a war change is refused.
enum WarRefusal {
  /// The war has ended.
  warOver,

  /// The player has a section in this war already (SOC-45).
  alreadyInWar,

  /// A battle of the war is running: one at a time.
  battleRunning,

  /// No battle is planned.
  noBattlePlanned,

  /// No battle is running.
  noBattleRunning,
}

/// The outcome of a war change.
sealed class WarChange {
  const new();
}

/// {@template war_changed}
/// The war is now [war].
/// {@endtemplate}
final class WarChanged extends WarChange {
  /// {@macro war_changed}
  const new(this.war);

  /// The war after the change.
  final War war;
}

/// {@template war_refused}
/// Nothing changes, for [reason].
/// {@endtemplate}
final class WarRefused extends WarChange {
  /// {@macro war_refused}
  const new(this.reason);

  /// Why.
  final WarRefusal reason;
}

/// {@template war}
/// A war: a series of battles an admin plans, with its settings, among
/// them [minStartingMoney] (SOC-11, SOC-13, SOC-16). It has no winner
/// (SOC-21).
///
/// A player has one section in it (SOC-45), created when he joins and lost
/// when the war ends (SOC-18, SOC-43). Between its battles a section keeps
/// its units, XP, evolution, weapons, money and prisoners (UNIT-30): those
/// live in the section, which nothing here changes. At the end of the war
/// all is lost but logs, statistics, medals and cosmetics (UNIT-32,
/// COMBAT-45). Its guilds, made of its sections, end with it.
/// {@endtemplate}
final class War {
  /// {@macro war}
  const new({
    required this.id,
    required this.minStartingMoney,
    this.planned = const [],
    this.current,
    this.sections = const {},
    this.over = false,
  });

  /// The war's id.
  final String id;

  /// The money floor of its sections and a new section's money (SOC-10,
  /// SOC-15).
  final int minStartingMoney;

  /// The battles planned, in order.
  final List<String> planned;

  /// The battle running; null between battles.
  final String? current;

  /// Each player's section, by player id.
  final Map<String, String> sections;

  /// Whether the war has ended (SOC-17).
  final bool over;

  /// The admin plans the battle [battleId] after the others (SOC-16).
  WarChange plan(String battleId) {
    if (over) return const WarRefused(WarRefusal.warOver);
    return WarChanged(
      _with(
        planned: List.unmodifiable([...planned, battleId]),
        current: current,
        sections: sections,
      ),
    );
  }

  /// The next planned battle starts. Battles of a war run one at a time,
  /// so a section, which follows its commander, is in one battle at a time
  /// and a player brings one commander to it (SOC-42, SOC-43).
  WarChange startBattle() {
    if (over) return const WarRefused(WarRefusal.warOver);
    if (current != null) return const WarRefused(WarRefusal.battleRunning);
    if (planned.isEmpty) return const WarRefused(WarRefusal.noBattlePlanned);
    return WarChanged(
      _with(
        planned: List.unmodifiable(planned.skip(1)),
        current: planned.first,
        sections: sections,
      ),
    );
  }

  /// The running battle ends. With no other battle planned, the war ends
  /// and its sections are lost (SOC-17, SOC-18, UNIT-32).
  WarChange endBattle() {
    if (current == null) return const WarRefused(WarRefusal.noBattleRunning);
    if (planned.isEmpty) {
      return WarChanged(
        War(id: id, minStartingMoney: minStartingMoney, over: true),
      );
    }
    return WarChanged(
      _with(planned: planned, current: null, sections: sections),
    );
  }

  /// [playerId] joins with his new section [sectionId], at any time, into
  /// the battle running if any (SOC-18, SOC-30, SOC-45, decision 122). The
  /// section starts with its commander (UNIT-24, UNIT-41) and
  /// `MoneyRules.startingMoney(minStartingMoney)`; in a battle it joins
  /// the weakest team (`TeamRules.newcomerTeam`).
  WarChange join({required String playerId, required String sectionId}) {
    if (over) return const WarRefused(WarRefusal.warOver);
    if (sections.containsKey(playerId)) {
      return const WarRefused(WarRefusal.alreadyInWar);
    }
    return WarChanged(
      _with(
        planned: planned,
        current: current,
        sections: Map.unmodifiable({...sections, playerId: sectionId}),
      ),
    );
  }

  War _with({
    required List<String> planned,
    required String? current,
    required Map<String, String> sections,
  }) => War(
    id: id,
    minStartingMoney: minStartingMoney,
    planned: planned,
    current: current,
    sections: sections,
  );
}

/// A unit's place, AP, HP and morale.
typedef UnitStart = ({
  UnitLocation location,
  ApPool pool,
  Health health,
  double morale,
});

/// {@template war_rules}
/// What every battle of a war gives back (UNIT-31, decisions 83, 212),
/// from `battle.yaml` `battle_start` and `ap` and the morale of
/// `combat.yaml`.
/// {@endtemplate}
final class WarRules {
  /// {@macro war_rules}
  const new({required this.battle, required this.morale});

  /// The `battle.yaml` data.
  final BattleSettings battle;

  /// The morale values (`morale.base`).
  final MoraleRules morale;

  /// A unit of [type] at the start of a battle: in storage, the guild camp
  /// too, with full AP and HP and its morale at base (`battle_start`: the
  /// values `GameData.parse` accepts). Units deploy from their portal;
  /// until the guild chief deploys the camp next to the HQ, his guild uses
  /// the HQ portal (decision 212).
  UnitStart atBattleStart(UnitType type) => (
    location: const Stored(),
    pool: ApPool.full(
      max: type.stats.apMax,
      recoveryPerHour: battle.ap.recoveryPerHour,
      at: Duration.zero,
    ),
    health: Health.full(type.stats.hp),
    morale: morale.base,
  );
}
