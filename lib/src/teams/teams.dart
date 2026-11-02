import 'package:battle_rules/src/combat/seeded_random.dart';
import 'package:battle_rules/src/data/battle_settings.dart';
import 'package:battle_rules/src/data/medals_data.dart';
import 'package:battle_rules/src/progression/xp.dart';

/// {@template team_section}
/// A section as team balancing sees it: its [power] and its guild, a
/// trainee's included (decision 209).
/// {@endtemplate}
final class TeamSection {
  /// {@macro team_section}
  const new({required this.sectionId, required this.power, this.guildId});

  /// The section's id.
  final String sectionId;

  /// Its power (`TeamRules.sectionPower`).
  final double power;

  /// Its guild's id; null without a guild.
  final String? guildId;
}

/// {@template manager_candidate}
/// A player of a team as a candidate HQ manager: the [medals] he holds,
/// by tier, and the XP his commander of this battle has earned.
/// {@endtemplate}
final class ManagerCandidate {
  /// {@macro manager_candidate}
  const new({
    required this.playerId,
    required this.medals,
    required this.commanderXp,
  });

  /// The player's id.
  final String playerId;

  /// Medals held, by tier (`medals.yaml` `tiers`).
  final Map<String, int> medals;

  /// The earned XP of his commander (decision 197).
  final double commanderXp;
}

/// {@template team_rules}
/// Teams, newcomers and the HQ manager (SOC-01 to SOC-09, SOC-20, SOC-29,
/// SOC-30, HQ-05 to HQ-08, UNIT-12, UNIT-13), from `battle.yaml` `teams`
/// and `newcomers` and `medals.yaml` `points`.
///
/// Exact ties between newcomer teams or manager candidates are drawn with
/// the injected [SeededRandom] (decision 211). There is no catch-up for
/// late joiners besides joining the weakest team (UNIT-13).
/// {@endtemplate}
final class TeamRules {
  /// {@macro team_rules}
  const new({required this.battle, required this.medals});

  /// The `battle.yaml` data.
  final BattleSettings battle;

  /// The `medals.yaml` data.
  final MedalsData medals;

  /// A section's power: its section XP and the XP each unit it owns has
  /// earned, spent or not (SOC-05, UNIT-12, decisions 93, 197). A team's
  /// power is the sum of its sections'. There is no notion of active
  /// players.
  double sectionPower({
    required double sectionXp,
    required Iterable<UnitXp> units,
  }) => units.fold(sectionXp, (sum, unit) => sum + unit.earned);

  /// The `teams.count` teams of a battle start, balanced by power with the
  /// sections of each guild kept together (SOC-20, decision 103): the
  /// section ids of each team.
  ///
  /// Greedy, largest block first: each guild, and each section without a
  /// guild, is a block; blocks go by decreasing power to the weakest team
  /// so far. Worst case: the strongest team is ahead of the weakest by at
  /// most the power of the largest block. A guild stronger than an even
  /// share makes its team the strongest whatever the method; the others
  /// are then balanced among themselves. A team may stay empty when there
  /// are fewer blocks than teams; newcomers then join it first (SOC-02).
  List<List<String>> formTeams(Iterable<TeamSection> sections) {
    final blocks = <String, List<TeamSection>>{};
    for (final section in sections) {
      final key = switch (section.guildId) {
        final guild? => 'guild:$guild',
        null => 'section:${section.sectionId}',
      };
      (blocks[key] ??= []).add(section);
    }
    double powerOf(List<TeamSection> block) =>
        block.fold(0, (sum, section) => sum + section.power);
    final ordered = blocks.entries.toList()
      ..sort((a, b) {
        final byPower = powerOf(b.value).compareTo(powerOf(a.value));
        return byPower != 0 ? byPower : a.key.compareTo(b.key);
      });
    final teams = [
      for (var team = 0; team < battle.teamCount; team++) <String>[],
    ];
    final powers = List<double>.filled(battle.teamCount, 0);
    for (final MapEntry(value: block) in ordered) {
      var weakest = 0;
      for (var team = 1; team < powers.length; team++) {
        if (powers[team] < powers[weakest]) weakest = team;
      }
      teams[weakest].addAll(
        [for (final section in block) section.sectionId]..sort(),
      );
      powers[weakest] += powerOf(block);
    }
    return [for (final team in teams) List.unmodifiable(team)];
  }

  /// The team a newcomer joins: the one with the lowest of [teamPowers],
  /// by team; a tie is drawn with [random] (SOC-02, SOC-06, decision 211).
  /// Anyone joining is a newcomer, also into a running war (SOC-30).
  String newcomerTeam(Map<String, double> teamPowers, SeededRandom random) {
    final lowest = teamPowers.values.reduce((a, b) => a < b ? a : b);
    final tied = [
      for (final MapEntry(:key, :value) in teamPowers.entries)
        if (value == lowest) key,
    ]..sort();
    return tied[_index(tied.length, random)];
  }

  /// The guilds offered to a newcomer in his team, drawn with [random]:
  /// `newcomers.guilds_offered` among those [optedIn], filled with
  /// [others] when fewer opted in; all of them when the team has fewer
  /// (SOC-03, SOC-07). Only guilds with room are given: a full guild is
  /// not offered (`GuildRules.hasRoom`, decision 213). He picks one and his
  /// section joins it as a trainee (decision 129). His commander arrives
  /// next to its portal, never blocked by an enemy (decision 210).
  List<String> guildOffer({
    required Iterable<String> optedIn,
    required Iterable<String> others,
    required SeededRandom random,
  }) {
    final wanted = battle.guildsOffered;
    final opted = _draw(optedIn, wanted, random);
    return List.unmodifiable([
      ...opted,
      ..._draw(others, wanted - opted.length, random),
    ]);
  }

  /// The medal points of a player holding [held] medals, by tier
  /// (SOC-29, decision 121). Throws an [ArgumentError] for an unknown tier.
  int medalPoints(Map<String, int> held) => held.entries.fold(
    0,
    (sum, medal) =>
        sum +
        medal.value *
            (medals.points[medal.key] ??
                (throw ArgumentError.value(medal.key, 'tier', 'unknown'))),
  );

  /// The HQ manager of a team at the battle start, among its [candidates]
  /// (HQ-05 to HQ-07, SOC-29): the most medal points, then the commander
  /// with the most XP, then a draw with [random] (decision 211). He stays
  /// manager until he delegates, online or not (HQ-07, HQ-08). Throws an
  /// [ArgumentError] for a team with no player.
  HqManager hqManager(
    Iterable<ManagerCandidate> candidates,
    SeededRandom random,
  ) {
    int compare(ManagerCandidate a, ManagerCandidate b) {
      final byPoints = medalPoints(b.medals).compareTo(medalPoints(a.medals));
      return byPoints != 0 ? byPoints : b.commanderXp.compareTo(a.commanderXp);
    }

    if (candidates.isEmpty) {
      throw ArgumentError.value(candidates, 'candidates', 'is empty');
    }
    final ranked = candidates.toList()
      ..sort((a, b) {
        final byRank = compare(a, b);
        return byRank != 0 ? byRank : a.playerId.compareTo(b.playerId);
      });
    final tied = [
      for (final candidate in ranked)
        if (compare(candidate, ranked.first) == 0) candidate.playerId,
    ];
    return HqManager(tied[_index(tied.length, random)]);
  }
}

/// Why a delegation is refused.
enum DelegationRefusal {
  /// Only the HQ manager delegates his role (HQ-05).
  notManager,

  /// The new manager must be another player of the team.
  notInTeam,
}

/// The outcome of a delegation.
sealed class Delegation {
  const new();
}

/// {@template delegated}
/// The role passes to [manager].
/// {@endtemplate}
final class Delegated extends Delegation {
  /// {@macro delegated}
  const new(this.manager);

  /// The new manager.
  final HqManager manager;
}

/// {@template delegation_refused}
/// The role stays where it is, for [reason].
/// {@endtemplate}
final class DelegationRefused extends Delegation {
  /// {@macro delegation_refused}
  const new(this.reason);

  /// Why.
  final DelegationRefusal reason;
}

/// {@template hq_manager}
/// The player who manages a team's HQ: he posts team orders and map
/// markers and moves the HQ (HQ-05, HQ-09). The role changes only when he
/// delegates it; nobody takes it over while he is offline (HQ-07, HQ-08).
/// {@endtemplate}
final class HqManager {
  /// {@macro hq_manager}
  const new(this.playerId);

  /// The manager's player id.
  final String playerId;

  /// [by] delegates the role to [to], another of the [teamPlayers]
  /// (HQ-05).
  Delegation delegate({
    required String by,
    required String to,
    required Set<String> teamPlayers,
  }) {
    if (by != playerId) {
      return const DelegationRefused(DelegationRefusal.notManager);
    }
    if (to == playerId || !teamPlayers.contains(to)) {
      return const DelegationRefused(DelegationRefusal.notInTeam);
    }
    return Delegated(HqManager(to));
  }
}

/// [count] of [ids], sorted first so that a seed always draws the same.
List<String> _draw(Iterable<String> ids, int count, SeededRandom random) {
  final pool = ids.toSet().toList()..sort();
  final drawn = count < pool.length ? count : pool.length;
  for (var slot = 0; slot < drawn; slot++) {
    final pick = slot + _index(pool.length - slot, random);
    final picked = pool[pick];
    pool[pick] = pool[slot];
    pool[slot] = picked;
  }
  return pool.sublist(0, drawn);
}

/// An index below [length], drawn with [random].
int _index(int length, SeededRandom random) =>
    (random.nextDouble() * length).floor();
