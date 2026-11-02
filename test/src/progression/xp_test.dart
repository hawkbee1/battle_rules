import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

void main() {
  group('XpRules on the fixtures', () {
    // Fixture progression: hit 1, kill 10, role action 3, capture 40;
    // scaling cap 2.5; window 300 s, × 0.25 per repeat, same spot within
    // 5 m; victory 4; section share 0.1.
    late XpRules rules;

    setUp(() {
      rules = XpRules(UnitsData.parse(readFixture('units.yaml')).progression);
    });

    XpAward earn(
      XpEvent event, {
      XpHistory? history,
      Duration at = Duration.zero,
    }) => rules.earn(event, history: history ?? XpHistory(), at: at);

    HitXp hit(String target, {double attacker = 0, double targetXp = 0}) =>
        HitXp(targetId: target, attackerXp: attacker, targetXp: targetXp);

    test('UNIT-05 a hit and a kill earn their XP', () {
      expect(earn(hit('t1')).xp, 1);
      expect(
        earn(const KillXp(targetId: 't1', attackerXp: 0, targetXp: 0)).xp,
        10,
      );
    });

    test('UNIT-06 a completed role action earns its XP', () {
      expect(earn(const RoleActionXp(FromTarget('wounded'))).xp, 3);
      expect(earn(const RoleActionXp(FromBuild(xM: 0, yM: 0))).xp, 3);
    });

    test('UNIT-09 a stronger target gives more XP, up to the cap', () {
      expect(rules.targetScaling(attackerXp: 100, targetXp: 0), 1);
      expect(rules.targetScaling(attackerXp: 100, targetXp: 50), 1.5);
      expect(rules.targetScaling(attackerXp: 100, targetXp: 150), 2.5);
      expect(rules.targetScaling(attackerXp: 100, targetXp: 1000), 2.5);
      // A unit with no XP counts as 1 XP.
      expect(rules.targetScaling(attackerXp: 0, targetXp: 1), 2);
      expect(earn(hit('t1', attacker: 100, targetXp: 50)).xp, 1.5);
      expect(
        earn(const KillXp(targetId: 't1', attackerXp: 100, targetXp: 50)).xp,
        15,
      );
    });

    test('UNIT-10 repeated XP from one target shrinks within the window', () {
      var history = XpHistory();
      final earned = <double>[];
      for (final seconds in [0, 10, 20, 299]) {
        final award = earn(
          hit('t1'),
          history: history,
          at: Duration(seconds: seconds),
        );
        earned.add(award.xp);
        history = award.history;
      }

      expect(earned, [1, 0.25, 0.0625, 0.015625]);
      // 300 s after the first award, only three are left in the window.
      expect(
        earn(hit('t1'), history: history, at: const Duration(seconds: 300)).xp,
        0.015625,
      );
      expect(
        earn(hit('t1'), history: history, at: const Duration(seconds: 900)).xp,
        1,
      );
      expect(earn(hit('t2'), history: history).xp, 1);
    });

    test('UNIT-10 decision 198 a build near an earlier build is a repeat', () {
      final first = earn(const RoleActionXp(FromBuild(xM: 0, yM: 0)));
      XpAward build(double x, double y) => earn(
        RoleActionXp(FromBuild(xM: x, yM: y)),
        history: first.history,
        at: const Duration(seconds: 60),
      );

      expect(build(3, 4).xp, 0.75);
      expect(build(3, 4.1).xp, 3);
      // A build and a target are never the same origin.
      expect(
        earn(const RoleActionXp(FromTarget('t1')), history: first.history).xp,
        3,
      );
    });

    test('UNIT-10 hitting or killing an ally gives no XP', () {
      final award = earn(
        const HitXp(
          targetId: 'ally',
          attackerXp: 0,
          targetXp: 0,
          friendly: true,
        ),
      );

      expect(award.xp, 0);
      expect(award.history.awards, isEmpty);
      expect(
        earn(
          const KillXp(
            targetId: 'ally',
            attackerXp: 0,
            targetXp: 0,
            friendly: true,
          ),
        ).xp,
        0,
      );
    });

    test('UNIT-10 friendly hits earn XP when the data allows it', () {
      final allowing = XpRules(
        UnitsData.parse(
          readFixture('units.yaml', {
            'friendly_hits_give_xp: false': 'friendly_hits_give_xp: true',
          }),
        ).progression,
      );

      expect(
        allowing
            .earn(
              const HitXp(
                targetId: 'ally',
                attackerXp: 0,
                targetXp: 0,
                friendly: true,
              ),
              history: XpHistory(),
              at: Duration.zero,
            )
            .xp,
        1,
      );
    });

    test('UNIT-11 the winning team earns victory_xp, split like any XP', () {
      expect(rules.victoryXp, 4);
      expect(rules.split(rules.victoryXp), (unit: 3.6, section: 0.4));
    });

    test('UNIT-14 UNIT-16 a share of each XP point goes to the section', () {
      final (:unit, :section) = rules.split(10);

      expect(unit, 9);
      expect(section, 1);
      expect(const UnitXp().gained(unit).unspent, 9);
    });

    test('UNIT-07 UNIT-43 capture XP is shared by the AP each unit put in', () {
      const pot = CapturePot(team: 'red', contributions: {'a': 15, 'b': 5});

      expect(rules.captureShares(pot), {'a': 30, 'b': 10});
      expect(rules.captureShares(const CapturePot(team: 'red')), isEmpty);
    });
  });

  group('UnitXp', () {
    test('decision 197 spending XP keeps the earned XP', () {
      final xp = const UnitXp().gained(300).spent(100);

      expect(xp.earned, 300);
      expect(xp.unspent, 200);
    });

    test('UNIT-18 a unit cannot spend more than it has left', () {
      expect(
        () => const UnitXp(earned: 50, unspent: 50).spent(51),
        throwsArgumentError,
      );
    });
  });

  group('XpRules on the plan data', () {
    late XpRules rules;
    late CaptureRules capture;

    setUp(() {
      final data = parsePlanData();
      rules = XpRules(data.units.progression);
      capture = CaptureRules(data.battle.capture);
    });

    test('UNIT-09 the plan caps target scaling at ×3', () {
      expect(rules.targetScaling(attackerXp: 100, targetXp: 100), 2);
      expect(rules.targetScaling(attackerXp: 100, targetXp: 500), 3);
    });

    test('UNIT-43 decision 179 a pot filled 30/20 pays 30 and 20 XP', () {
      const pot = CapturePot(
        team: 'red',
        contributions: {'alive': 30, 'dead since': 20},
      );

      expect(rules.captureShares(pot), {'alive': 30, 'dead since': 20});
    });

    test('UNIT-43 RELIC-08 a lost pot pays nothing', () {
      const pot = CapturePot(team: 'red', contributions: {'a': 30});
      final lost = capture.withOccupants(pot, [
        const RadiusOccupant(team: 'blue'),
      ]);

      expect(rules.captureShares(lost), isEmpty);
    });

    test('UNIT-10 the plan halves each repeat within 10 minutes', () {
      var history = XpHistory();
      final earned = <double>[];
      for (final minutes in [0, 1, 2, 12]) {
        final award = rules.earn(
          const HitXp(targetId: 't', attackerXp: 1, targetXp: 0),
          history: history,
          at: Duration(minutes: minutes),
        );
        earned.add(award.xp);
        history = award.history;
      }

      expect(earned, [2, 1, 0.5, 2]);
    });
  });
}
