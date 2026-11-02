import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

War changed(WarChange change) => (change as WarChanged).war;

WarRefusal? refusal(WarChange change) => switch (change) {
  WarRefused(:final reason) => reason,
  WarChanged() => null,
};

void main() {
  group('War', () {
    War planned(List<String> battles) {
      var war = const War(id: 'w1', minStartingMoney: 400);
      for (final battle in battles) {
        war = changed(war.plan(battle));
      }
      return war;
    }

    test('SOC-13 SOC-16 an admin starts a war and plans its battles', () {
      final war = planned(['b1', 'b2']);

      expect(war.planned, ['b1', 'b2']);
      expect(war.minStartingMoney, 400);
      expect(war.current, isNull);
      expect(war.over, isFalse);
    });

    test('SOC-42 SOC-43 its battles run one at a time, in order', () {
      final first = changed(planned(['b1', 'b2']).startBattle());

      expect(first.current, 'b1');
      expect(first.planned, ['b2']);
      expect(refusal(first.startBattle()), WarRefusal.battleRunning);
      final between = changed(first.endBattle());
      expect(between.current, isNull);
      expect(between.over, isFalse);
      expect(changed(between.startBattle()).current, 'b2');
    });

    test('a battle starts only when planned and ends only when running', () {
      final war = planned(const []);

      expect(refusal(war.startBattle()), WarRefusal.noBattlePlanned);
      expect(refusal(war.endBattle()), WarRefusal.noBattleRunning);
    });

    test('SOC-17 SOC-18 UNIT-32 the war ends when no battle is left planned; '
        'its sections are lost', () {
      final running = changed(
        changed(planned(['b1']).startBattle())
            .join(playerId: 'p1', sectionId: 's1'),
      );

      final over = changed(running.endBattle());
      expect(over.over, isTrue);
      expect(over.sections, isEmpty);
      expect(over.current, isNull);
      expect(refusal(over.plan('b2')), WarRefusal.warOver);
      expect(refusal(over.startBattle()), WarRefusal.warOver);
      expect(
        refusal(over.join(playerId: 'p2', sectionId: 's2')),
        WarRefusal.warOver,
      );
    });

    test('SOC-30 SOC-45 decision 122 a player joins at any time, with one '
        'section per war', () {
      final running = changed(planned(['b1']).startBattle());
      final joined = changed(running.join(playerId: 'p1', sectionId: 's1'));

      expect(joined.sections, {'p1': 's1'});
      expect(joined.current, 'b1');
      expect(
        refusal(joined.join(playerId: 'p1', sectionId: 's9')),
        WarRefusal.alreadyInWar,
      );
    });

    test('SOC-41 SOC-44 SOC-45 a player takes part in several wars, with a '
        'section in each', () {
      final a = changed(
        const War(
          id: 'wa',
          minStartingMoney: 500,
        ).join(playerId: 'p1', sectionId: 's-a'),
      );
      final b = changed(
        const War(
          id: 'wb',
          minStartingMoney: 700,
        ).join(playerId: 'p1', sectionId: 's-b'),
      );

      expect((a.sections['p1'], b.sections['p1']), ('s-a', 's-b'));
    });
  });

  group('WarRules on the fixtures', () {
    // Fixture: AP at most 20, 2 per hour; morale base 40.
    late GameData data;
    late WarRules rules;

    setUp(() {
      data = parseFixtures();
      rules = WarRules(battle: data.battle, morale: data.combat.morale);
    });

    test('UNIT-31 decisions 83 212 each battle starts with every unit '
        'stored, full AP and HP, morale at base', () {
      final jeep = rules.atBattleStart(data.units.unitTypes['jeep']!);

      expect(jeep.location, isA<Stored>());
      expect(jeep.pool.apAt(Duration.zero), 20);
      expect((jeep.health.current, jeep.health.max), (150, 150));
      expect(jeep.morale, 40);
    });

    test('decision 212 the guild camp starts stored too', () {
      expect(
        rules.atBattleStart(data.units.unitTypes['camp']!).location,
        isA<Stored>(),
      );
    });

    test("SOC-15 UNIT-41 a new section starts with its war's minimum", () {
      const war = War(id: 'w1', minStartingMoney: 400);

      expect(MoneyRules(data.economy).startingMoney(war.minStartingMoney), 400);
    });
  });

  group('A war on the plan data', () {
    test('UNIT-30 SOC-19 a section carried through three battles of a war, '
        'and lost at its end', () {
      final data = parsePlanData();
      final rules = WarRules(battle: data.battle, morale: data.combat.morale);
      final xp = XpRules(data.units.progression);
      final soldier = data.units.unitTypes['soldier']!;
      var war = const War(id: 'w1', minStartingMoney: 500);
      for (final battle in ['b1', 'b2', 'b3']) {
        war = changed(war.plan(battle));
      }
      war = changed(war.join(playerId: 'p1', sectionId: 's1'));
      // What the section keeps from battle to battle.
      var unitXp = const UnitXp();
      var sectionXp = 0.0;

      for (var battle = 0; battle < 3; battle++) {
        war = changed(war.startBattle());
        final start = rules.atBattleStart(soldier);
        expect(start.location, isA<Stored>());
        expect(start.pool.apAt(Duration.zero), 30);
        expect(start.morale, 50);
        // Its team wins: every unit gains victoryXp (SOC-19).
        final share = xp.split(xp.victoryXp);
        unitXp = unitXp.gained(share.unit);
        sectionXp += share.section;
        war = changed(war.endBattle());
      }

      expect(unitXp.earned, closeTo(3 * 0.8, 1e-9));
      expect(sectionXp, closeTo(3 * 0.2, 1e-9));
      expect(war.over, isTrue);
      expect(war.sections, isEmpty);
    });
  });
}
