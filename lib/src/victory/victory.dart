import 'package:battle_rules/src/data/battle_settings.dart';

/// How a battle is won.
enum VictoryKind {
  /// Only its HQ remains (HQ-45).
  lastHq,

  /// It held `victory.relics_to_hold` relics for `victory.hold_s`
  /// (RELIC-14).
  relics,
}

/// Why a team is eliminated (HQ-18, HQ-23).
enum EliminationCause {
  /// Its HQ was destroyed (HQ-16).
  hqDestroyed,

  /// Its HQ was on a reinforced bridge that was destroyed (decision 116).
  hqLostWithBridge,
}

/// {@template relic_hold}
/// [team] has held `relics_to_hold` relics since [since]; it wins at
/// [winsAt] unless it drops below first (RELIC-14, RELIC-15). A start time,
/// not a countdown ticked every second.
/// {@endtemplate}
final class RelicHold {
  /// {@macro relic_hold}
  const new({required this.team, required this.since, required this.winsAt});

  /// The holding team.
  final String team;

  /// The battle time it reached `relics_to_hold` relics.
  final Duration since;

  /// The battle time it wins.
  final Duration winsAt;

  /// The countdown all players see at battle time [now] (RELIC-16).
  Duration remainingAt(Duration now) =>
      winsAt > now ? winsAt - now : Duration.zero;
}

/// What the victory rules tell the host, which logs it and alerts the
/// players (Observer, stack decision 7).
sealed class VictoryEvent {
  const new();
}

/// {@template relic_owner_changed}
/// [team] captured [relicId]; [previousOwner], when there was one, is
/// alerted at once (RELIC-10, RELIC-11).
/// {@endtemplate}
final class RelicOwnerChanged extends VictoryEvent {
  /// {@macro relic_owner_changed}
  const new({required this.relicId, required this.team, this.previousOwner});

  /// The relic.
  final String relicId;

  /// Its new owner.
  final String team;

  /// Its owner before; null when it had none.
  final String? previousOwner;
}

/// {@template relic_left_battle}
/// [relicId] was lost with a destroyed reinforced bridge and left the
/// battle (RELIC-26, decision 116).
/// {@endtemplate}
final class RelicLeftBattle extends VictoryEvent {
  /// {@macro relic_left_battle}
  const new({required this.relicId, this.previousOwner});

  /// The relic.
  final String relicId;

  /// Its owner when it was lost; null when it had none.
  final String? previousOwner;
}

/// {@template hold_started}
/// A team reached `relics_to_hold` relics: the countdown of [hold] starts.
/// {@endtemplate}
final class HoldStarted extends VictoryEvent {
  /// {@macro hold_started}
  const new(this.hold);

  /// The new hold.
  final RelicHold hold;
}

/// {@template hold_reset}
/// [team] dropped below `relics_to_hold` relics or left the battle: its
/// countdown resets fully (RELIC-15).
/// {@endtemplate}
final class HoldReset extends VictoryEvent {
  /// {@macro hold_reset}
  const new(this.team);

  /// The team that held.
  final String team;
}

/// {@template team_eliminated}
/// [team] is eliminated, for [cause] (HQ-18, HQ-23). Its units on the
/// field are stored and its stored units stay (HQ-19, HQ-20,
/// `StorageRules.atElimination`).
/// {@endtemplate}
final class TeamEliminated extends VictoryEvent {
  /// {@macro team_eliminated}
  const new({required this.team, required this.cause});

  /// The eliminated team.
  final String team;

  /// Why.
  final EliminationCause cause;
}

/// {@template battle_won}
/// [team] wins the battle, by [kind]: the battle ends.
/// {@endtemplate}
final class BattleWon extends VictoryEvent {
  /// {@macro battle_won}
  const new({required this.team, required this.kind});

  /// The winning team.
  final String team;

  /// How it won.
  final VictoryKind kind;
}

/// {@template victory_state}
/// Who owns the relics still in the battle, which teams are still in, the
/// running hold and the winner.
/// {@endtemplate}
final class VictoryState {
  /// {@macro victory_state}
  const new({
    required this.relicOwners,
    required this.teams,
    this.hold,
    this.winner,
  });

  /// The owner team of each relic still in the battle, by relic id; null
  /// for a relic never captured.
  final Map<String, String?> relicOwners;

  /// The teams still in the battle.
  final Set<String> teams;

  /// The running hold; null when no team holds `relics_to_hold` relics.
  final RelicHold? hold;

  /// The end of the battle; null while it runs.
  final BattleWon? winner;
}

/// The state after a change, and what happened.
typedef VictoryUpdate = ({VictoryState state, List<VictoryEvent> events});

/// {@template victory_rules}
/// Relic ownership, elimination and victory (RELIC-10 to RELIC-18,
/// RELIC-26, RELIC-27, HQ-18 to HQ-23, HQ-45), from `battle.yaml`
/// `victory`.
///
/// A relic changes owner only by a capture (M4 `CaptureRules`) and leaves
/// the battle only with a reinforced bridge: it is indestructible
/// (RELIC-27). Owning one gives nothing but the hold (RELIC-13). An
/// eliminated team's relics keep their owner until another team captures
/// them; that team never holds again.
///
/// Every change at a battle time at or after the running hold's `winsAt`
/// ends the battle on the hold instead: the host calls [at] at `winsAt`.
/// {@endtemplate}
final class VictoryRules {
  /// {@macro victory_rules}
  const new(this.victory);

  /// The victory settings.
  final VictorySettings victory;

  /// The state when a battle starts with [relics] on its map, all without
  /// an owner, and [teams].
  ///
  /// Throws an [ArgumentError] with fewer than two teams, or with so many
  /// relics that two teams could hold `relics_to_hold` at once: no tie is
  /// possible (RELIC-17).
  VictoryState start({
    required Iterable<String> relics,
    required Iterable<String> teams,
  }) {
    final teamSet = Set<String>.unmodifiable(teams);
    if (teamSet.length < 2) {
      throw ArgumentError.value(teamSet, 'teams', 'needs two teams or more');
    }
    final owners = Map<String, String?>.unmodifiable({
      for (final relic in relics) relic: null,
    });
    if (owners.length >= 2 * victory.relicsToHold) {
      throw ArgumentError.value(
        owners.length,
        'relics',
        'lets two teams hold ${victory.relicsToHold} at once (RELIC-17)',
      );
    }
    return VictoryState(relicOwners: owners, teams: teamSet);
  }

  /// Whether a team can still win by holding relics: as many as
  /// `relics_to_hold` remain (RELIC-26, decision 116).
  bool relicVictoryPossible(VictoryState state) =>
      state.relicOwners.length >= victory.relicsToHold;

  /// [state] at battle time [now]: the holding team wins once its hold
  /// reaches `winsAt` (RELIC-14).
  VictoryUpdate at(VictoryState state, Duration now) {
    _checkRunning(state);
    final hold = state.hold;
    if (hold == null || now < hold.winsAt) return (state: state, events: []);
    final won = BattleWon(team: hold.team, kind: VictoryKind.relics);
    return (
      state: VictoryState(
        relicOwners: state.relicOwners,
        teams: state.teams,
        hold: hold,
        winner: won,
      ),
      events: [won],
    );
  }

  /// [team] completed the capture of [relicId] at battle time [at]: it
  /// owns it at once, with no protection time (RELIC-10 to RELIC-12). A
  /// capture by its owner changes nothing.
  ///
  /// Throws an [ArgumentError] for a relic not in the battle or a team
  /// out of it.
  VictoryUpdate captured(
    VictoryState state, {
    required String relicId,
    required String team,
    required Duration at,
  }) {
    final due = _due(state, at);
    if (due != null) return due;
    final previous = _ownerOf(state, relicId);
    if (!state.teams.contains(team)) {
      throw ArgumentError.value(team, 'team', 'not in the battle');
    }
    if (previous == team) return (state: state, events: []);
    return _update(
      state,
      relicOwners: Map.unmodifiable({...state.relicOwners, relicId: team}),
      teams: state.teams,
      at: at,
      events: [
        RelicOwnerChanged(
          relicId: relicId,
          team: team,
          previousOwner: previous,
        ),
      ],
    );
  }

  /// [relicId] was lost with a destroyed reinforced bridge at battle time
  /// [at]: it leaves the battle (RELIC-26, decision 116).
  ///
  /// Throws an [ArgumentError] for a relic not in the battle.
  VictoryUpdate relicLost(
    VictoryState state, {
    required String relicId,
    required Duration at,
  }) {
    final due = _due(state, at);
    if (due != null) return due;
    final previous = _ownerOf(state, relicId);
    return _update(
      state,
      relicOwners: Map.unmodifiable({...state.relicOwners}..remove(relicId)),
      teams: state.teams,
      at: at,
      events: [RelicLeftBattle(relicId: relicId, previousOwner: previous)],
    );
  }

  /// [team]'s HQ was destroyed or lost with a bridge ([cause]) at battle
  /// time [at]: the team is eliminated (HQ-18, HQ-23), and the last team
  /// left wins (HQ-45).
  ///
  /// Throws an [ArgumentError] for a team out of the battle.
  VictoryUpdate hqLost(
    VictoryState state, {
    required String team,
    required EliminationCause cause,
    required Duration at,
  }) {
    final due = _due(state, at);
    if (due != null) return due;
    if (!state.teams.contains(team)) {
      throw ArgumentError.value(team, 'team', 'not in the battle');
    }
    final teams = Set<String>.unmodifiable({...state.teams}..remove(team));
    final update = _update(
      state,
      relicOwners: state.relicOwners,
      teams: teams,
      at: at,
      events: [TeamEliminated(team: team, cause: cause)],
    );
    if (teams.length > 1) return update;
    final won = BattleWon(team: teams.single, kind: VictoryKind.lastHq);
    return (
      state: VictoryState(
        relicOwners: update.state.relicOwners,
        teams: teams,
        hold: update.state.hold,
        winner: won,
      ),
      events: [...update.events, won],
    );
  }

  /// The win of a hold due by battle time [now], or null.
  VictoryUpdate? _due(VictoryState state, Duration now) {
    final update = at(state, now);
    return update.state.winner == null ? null : update;
  }

  static void _checkRunning(VictoryState state) {
    if (state.winner != null) throw StateError('The battle is over.');
  }

  static String? _ownerOf(VictoryState state, String relicId) {
    if (!state.relicOwners.containsKey(relicId)) {
      throw ArgumentError.value(relicId, 'relicId', 'not in the battle');
    }
    return state.relicOwners[relicId];
  }

  /// [state] with [relicOwners] and [teams], its hold kept, started or
  /// reset at [at] (RELIC-15), after [events].
  VictoryUpdate _update(
    VictoryState state, {
    required Map<String, String?> relicOwners,
    required Set<String> teams,
    required Duration at,
    required List<VictoryEvent> events,
  }) {
    final counts = <String, int>{};
    for (final owner in relicOwners.values) {
      if (owner != null && teams.contains(owner)) {
        counts.update(owner, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final holder = [
      for (final MapEntry(:key, :value) in counts.entries)
        if (value >= victory.relicsToHold) key,
    ].firstOrNull;
    final previous = state.hold;
    final hold = previous != null && previous.team == holder
        ? previous
        : holder == null
        ? null
        : RelicHold(
            team: holder,
            since: at,
            winsAt: at + _seconds(victory.holdS),
          );
    return (
      state: VictoryState(relicOwners: relicOwners, teams: teams, hold: hold),
      events: [
        ...events,
        if (previous != null && previous != hold) HoldReset(previous.team),
        if (hold != null && hold != previous) HoldStarted(hold),
      ],
    );
  }
}

Duration _seconds(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
