import 'dart:math' as math;

import 'package:battle_rules/src/actions/capture.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// {@template unit_xp}
/// A unit's XP: what it has [earned], which target scaling and team power
/// count (decision 197), and what it has [unspent] for its own tree
/// (UNIT-18).
/// {@endtemplate}
final class UnitXp {
  /// {@macro unit_xp}
  const new({this.earned = 0, this.unspent = 0});

  /// Every XP point the unit has kept, spent or not.
  final double earned;

  /// What it has left to spend on its tree.
  final double unspent;

  /// The unit after it keeps [xp] more (its share, UNIT-14).
  UnitXp gained(double xp) =>
      UnitXp(earned: earned + xp, unspent: unspent + xp);

  /// The unit after it spends [xp] on its tree: its earned XP stays
  /// (decision 197). Throws an [ArgumentError] when it has less unspent.
  UnitXp spent(double xp) {
    if (xp > unspent) {
      throw ArgumentError.value(xp, 'xp', 'above the unspent $unspent');
    }
    return UnitXp(earned: earned, unspent: unspent - xp);
  }
}

/// What an XP award comes from, for anti-farming (UNIT-10).
sealed class XpOrigin {
  const new();
}

/// {@template from_target}
/// A unit hit, killed, healed, repaired or spotted.
/// {@endtemplate}
final class FromTarget extends XpOrigin {
  /// {@macro from_target}
  const new(this.targetId);

  /// The target's unit id.
  final String targetId;
}

/// {@template from_build}
/// A build at a ground position, in metres.
/// {@endtemplate}
final class FromBuild extends XpOrigin {
  /// {@macro from_build}
  const new({required this.xM, required this.yM});

  /// East position, in metres.
  final double xM;

  /// South position, in metres.
  final double yM;
}

/// {@template xp_history}
/// One unit's XP awards still inside the anti-farming window, with what
/// each came from (UNIT-10).
/// {@endtemplate}
final class XpHistory {
  /// {@macro xp_history}
  new([List<(XpOrigin, Duration)> awards = const []])
    : awards = List.unmodifiable(awards);

  /// Each award's origin and battle time, oldest first.
  final List<(XpOrigin, Duration)> awards;
}

/// One event that earns a unit XP (UNIT-05 to UNIT-07).
sealed class XpEvent {
  const new();
}

/// {@template hit_xp}
/// The unit hit [targetId], a unit with [targetXp] earned XP, while it had
/// [attackerXp] itself (UNIT-05, UNIT-09).
/// {@endtemplate}
final class HitXp extends XpEvent {
  /// {@macro hit_xp}
  const new({
    required this.targetId,
    required this.attackerXp,
    required this.targetXp,
    this.friendly = false,
  });

  /// The unit hit.
  final String targetId;

  /// The XP the attacker has earned (decision 197).
  final double attackerXp;

  /// The XP the target has earned (decision 197).
  final double targetXp;

  /// Whether the target is on the attacker's team.
  final bool friendly;
}

/// {@template kill_xp}
/// The unit killed [targetId] (UNIT-05, UNIT-09).
/// {@endtemplate}
final class KillXp extends XpEvent {
  /// {@macro kill_xp}
  const new({
    required this.targetId,
    required this.attackerXp,
    required this.targetXp,
    this.friendly = false,
  });

  /// The unit killed.
  final String targetId;

  /// The XP the attacker has earned (decision 197).
  final double attackerXp;

  /// The XP the target has earned (decision 197).
  final double targetXp;

  /// Whether the target was on the attacker's team.
  final bool friendly;
}

/// {@template role_action_xp}
/// The unit completed a build, a repair, a heal or a spotting report
/// (UNIT-06): [origin] is the build's position or the unit it served.
/// {@endtemplate}
final class RoleActionXp extends XpEvent {
  /// {@macro role_action_xp}
  const new(this.origin);

  /// Where the XP comes from.
  final XpOrigin origin;
}

/// {@template xp_award}
/// What an [XpEvent] earns: [xp] before the section share, and the unit's
/// [history] with this award in it.
/// {@endtemplate}
final class XpAward {
  /// {@macro xp_award}
  const new({required this.xp, required this.history});

  /// XP earned, before the section takes its share (UNIT-14).
  final double xp;

  /// The unit's history after the award.
  final XpHistory history;
}

/// {@template xp_rules}
/// How units earn XP (UNIT-05 to UNIT-11, UNIT-14, UNIT-43), from
/// `units.yaml` `progression`.
/// {@endtemplate}
final class XpRules {
  /// {@macro xp_rules}
  const new(this.progression);

  /// The `progression` of `units.yaml`.
  final Progression progression;

  /// What hit and kill XP is multiplied by:
  /// `min(cap, 1 + target XP / max(attacker XP, 1))`, with earned XP
  /// (UNIT-09, decision 197).
  double targetScaling({
    required double attackerXp,
    required double targetXp,
  }) => math.min(
    progression.targetScalingCap,
    1 + targetXp / math.max(attackerXp, 1),
  );

  /// The XP [event] earns a unit whose recent awards are [history], at
  /// battle time [at].
  ///
  /// Hits and kills earn their XP times [targetScaling]; hitting or killing
  /// an ally earns nothing unless `friendly_hits_give_xp` (UNIT-10). Each
  /// earlier award from the same origin inside `diminishing.window_s`
  /// multiplies the XP by `factor_per_repeat`: the same target, or a build
  /// within `same_spot_radius_m` of an earlier one (UNIT-10,
  /// decision 198). An award that earns nothing is not recorded.
  XpAward earn(
    XpEvent event, {
    required XpHistory history,
    required Duration at,
  }) {
    final sources = progression.xpSources;
    final (base, origin, friendly) = switch (event) {
      HitXp(
        :final targetId,
        :final attackerXp,
        :final targetXp,
        :final friendly,
      ) =>
        (
          sources.hit *
              targetScaling(attackerXp: attackerXp, targetXp: targetXp),
          FromTarget(targetId),
          friendly,
        ),
      KillXp(
        :final targetId,
        :final attackerXp,
        :final targetXp,
        :final friendly,
      ) =>
        (
          sources.kill *
              targetScaling(attackerXp: attackerXp, targetXp: targetXp),
          FromTarget(targetId),
          friendly,
        ),
      RoleActionXp(:final origin) => (sources.roleAction, origin, false),
    };
    final recent = _inWindow(history, at);
    if (friendly && !progression.friendlyHitsGiveXp) {
      return XpAward(xp: 0, history: XpHistory(recent));
    }
    final repeats = recent
        .where((award) => _sameOrigin(award.$1, origin))
        .length;
    return XpAward(
      xp:
          base *
          math.pow(progression.diminishing.factorPerRepeat, repeats).toDouble(),
      history: XpHistory([...recent, (origin, at)]),
    );
  }

  /// The XP of a completed capture, by unit id: `xp_sources.capture` shared
  /// in proportion to the AP each unit put into [pot], units that died or
  /// left the radius included (UNIT-43, decision 179). A lost pot is empty
  /// (RELIC-08), so it pays nothing.
  Map<String, double> captureShares(CapturePot pot) {
    final total = pot.ap;
    if (total == 0) return const {};
    return {
      for (final MapEntry(key: unit, value: ap) in pot.contributions.entries)
        unit: progression.xpSources.capture * ap / total,
    };
  }

  /// The XP every unit of the winning team earns at the end of a battle
  /// (UNIT-11, decision 92). The section share applies to it like any XP.
  double get victoryXp => progression.victoryXp;

  /// [xp] earned by a unit, split into the share it keeps and the share
  /// moved to its section's XP: `section_xp_share` (UNIT-14). The section's
  /// share never goes back to the unit (UNIT-16).
  ({double unit, double section}) split(double xp) {
    final section = xp * progression.sectionXpShare;
    return (unit: xp - section, section: section);
  }

  List<(XpOrigin, Duration)> _inWindow(XpHistory history, Duration at) {
    final windowUs =
        progression.diminishing.windowS * Duration.microsecondsPerSecond;
    return [
      for (final award in history.awards)
        if ((at - award.$2).inMicroseconds < windowUs) award,
    ];
  }

  bool _sameOrigin(XpOrigin earlier, XpOrigin origin) => switch ((
    earlier,
    origin,
  )) {
    (FromTarget(targetId: final a), FromTarget(targetId: final b)) => a == b,
    (
      FromBuild(xM: final x1, yM: final y1),
      FromBuild(xM: final x2, yM: final y2),
    ) =>
      math.sqrt(math.pow(x1 - x2, 2) + math.pow(y1 - y2, 2)) <=
          progression.diminishing.sameSpotRadiusM,
    _ => false,
  };
}
