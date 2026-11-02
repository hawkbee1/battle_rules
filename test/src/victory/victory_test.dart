import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

const _hour = Duration(hours: 1);
const _second = Duration(seconds: 1);

void main() {
  group('VictoryRules on the fixtures', () {
    // Fixture victory: hold 3 relics for 1 hour.
    late VictoryRules rules;
    late VictoryState state;

    setUp(() {
      rules = VictoryRules(parseFixtures().battle.victory);
      state = rules.start(
        relics: ['r1', 'r2', 'r3', 'r4', 'r5'],
        teams: ['a', 'b', 'c'],
      );
    });

    VictoryUpdate captureAll(
      VictoryState from,
      String team,
      List<String> relics, {
      Duration at = Duration.zero,
    }) {
      var update = (state: from, events: <VictoryEvent>[]);
      for (final relic in relics) {
        final next = rules.captured(
          update.state,
          relicId: relic,
          team: team,
          at: at,
        );
        update = (
          state: next.state,
          events: [...update.events, ...next.events],
        );
      }
      return update;
    }

    test('RELIC-11 RELIC-17 a battle starts with no relic owned, two teams '
        'or more, and no possible tie', () {
      expect(state.relicOwners.values, everyElement(isNull));
      expect(state.teams, {'a', 'b', 'c'});
      expect(state.hold, isNull);
      expect(state.winner, isNull);
      expect(
        () => rules.start(relics: ['r1'], teams: ['a']),
        throwsArgumentError,
      );
      // Six relics would let two teams hold three each.
      expect(
        () => rules.start(
          relics: ['r1', 'r2', 'r3', 'r4', 'r5', 'r6'],
          teams: ['a', 'b'],
        ),
        throwsArgumentError,
      );
    });

    test('RELIC-10 RELIC-11 a capture changes the owner at once and alerts '
        'the previous owner', () {
      final first = rules.captured(state, relicId: 'r1', team: 'a', at: _hour);
      final second = rules.captured(
        first.state,
        relicId: 'r1',
        team: 'b',
        at: _hour * 2,
      );

      final changed = first.events.single as RelicOwnerChanged;
      expect(
        (changed.relicId, changed.team, changed.previousOwner),
        ('r1', 'a', null),
      );
      expect((second.events.single as RelicOwnerChanged).previousOwner, 'a');
      expect(second.state.relicOwners['r1'], 'b');
    });

    test('RELIC-12 no protection time: a relic is retaken at once', () {
      final taken = rules.captured(state, relicId: 'r1', team: 'a', at: _hour);
      final retaken = rules.captured(
        taken.state,
        relicId: 'r1',
        team: 'c',
        at: _hour,
      );

      expect(retaken.state.relicOwners['r1'], 'c');
    });

    test('a capture by the owner changes nothing', () {
      final taken = rules.captured(state, relicId: 'r1', team: 'a', at: _hour);
      final again = rules.captured(
        taken.state,
        relicId: 'r1',
        team: 'a',
        at: _hour * 2,
      );

      expect(again.state, same(taken.state));
      expect(again.events, isEmpty);
    });

    test('RELIC-14 RELIC-16 the hold starts at relics_to_hold; its countdown '
        'is visible', () {
      final two = captureAll(state, 'a', ['r1', 'r2']);
      final three = rules.captured(
        two.state,
        relicId: 'r3',
        team: 'a',
        at: _hour,
      );

      expect(two.state.hold, isNull);
      final hold = (three.events.last as HoldStarted).hold;
      expect((hold.team, hold.since, hold.winsAt), ('a', _hour, _hour * 2));
      expect(three.state.hold, same(hold));
      expect(hold.remainingAt(_hour * 1.5), const Duration(minutes: 30));
      expect(hold.remainingAt(_hour * 3), Duration.zero);
    });

    test('RELIC-14 a team holding for hold_s wins; the battle is then '
        'over', () {
      final held = captureAll(state, 'a', ['r1', 'r2', 'r3']).state;

      expect(rules.at(held, _hour - _second).events, isEmpty);
      final won = rules.at(held, _hour);
      final event = won.events.single as BattleWon;
      expect((event.team, event.kind), ('a', VictoryKind.relics));
      expect(won.state.winner, same(event));
      expect(() => rules.at(won.state, _hour * 2), throwsStateError);
      expect(
        () => rules.captured(won.state, relicId: 'r4', team: 'b', at: _hour),
        throwsStateError,
      );
    });

    test('RELIC-14 a capture at or after the hold ends the battle on the '
        'hold first', () {
      final held = captureAll(state, 'a', ['r1', 'r2', 'r3']).state;

      final afterHold = rules.captured(
        held,
        relicId: 'r1',
        team: 'b',
        at: _hour,
      );
      expect(afterHold.state.winner?.team, 'a');
      expect(afterHold.state.relicOwners['r1'], 'a');
      expect(
        rules.relicLost(held, relicId: 'r1', at: _hour).state.winner,
        isNotNull,
      );
      expect(
        rules
            .hqLost(
              held,
              team: 'b',
              cause: EliminationCause.hqDestroyed,
              at: _hour,
            )
            .state
            .winner
            ?.kind,
        VictoryKind.relics,
      );
    });

    test('RELIC-15 RELIC-18 one capture resets the hold fully', () {
      final held = captureAll(state, 'a', ['r1', 'r2', 'r3']).state;
      final dropped = rules.captured(
        held,
        relicId: 'r1',
        team: 'b',
        at: _hour * 0.5,
      );
      final back = rules.captured(
        dropped.state,
        relicId: 'r1',
        team: 'a',
        at: _hour * 0.5 + _second,
      );

      expect((dropped.events.last as HoldReset).team, 'a');
      expect(dropped.state.hold, isNull);
      expect(back.state.hold?.since, _hour * 0.5 + _second);
      expect(rules.at(back.state, _hour).events, isEmpty);
    });

    test('RELIC-15 the hold passes from one team to another', () {
      final a = captureAll(state, 'a', ['r1', 'r2', 'r3']).state;
      final b = captureAll(a, 'b', ['r1', 'r4', 'r5'], at: _hour * 0.5);

      expect(b.events.whereType<HoldReset>().single.team, 'a');
      expect(b.events.whereType<HoldStarted>().single.hold.team, 'b');
      expect(b.state.hold?.since, _hour * 0.5);
    });

    test('RELIC-26 decision 116 a relic lost with a bridge leaves the battle; '
        'below relics_to_hold only the HQ victory remains', () {
      final held = captureAll(state, 'a', ['r1', 'r2', 'r3']).state;
      final lost = rules.relicLost(held, relicId: 'r1', at: _hour * 0.5);
      final fewer = rules.relicLost(lost.state, relicId: 'r2', at: _hour * 0.5);
      final unowned = rules.relicLost(
        fewer.state,
        relicId: 'r4',
        at: _hour * 0.5,
      );

      final left = lost.events.first as RelicLeftBattle;
      expect((left.relicId, left.previousOwner), ('r1', 'a'));
      expect(lost.events.last, isA<HoldReset>());
      expect(rules.relicVictoryPossible(fewer.state), isTrue);
      expect((unowned.events.single as RelicLeftBattle).previousOwner, isNull);
      expect(unowned.state.relicOwners.keys, ['r3', 'r5']);
      expect(rules.relicVictoryPossible(unowned.state), isFalse);
    });

    test('HQ-18 HQ-23 HQ-45 eliminated teams leave the battle; the last HQ '
        'wins', () {
      final first = rules.hqLost(
        state,
        team: 'a',
        cause: EliminationCause.hqDestroyed,
        at: _hour,
      );
      final second = rules.hqLost(
        first.state,
        team: 'b',
        cause: EliminationCause.hqLostWithBridge,
        at: _hour * 2,
      );

      final eliminated = first.events.single as TeamEliminated;
      expect(
        (eliminated.team, eliminated.cause),
        ('a', EliminationCause.hqDestroyed),
      );
      expect(first.state.teams, {'b', 'c'});
      expect(first.state.winner, isNull);
      expect(
        (second.events.first as TeamEliminated).cause,
        EliminationCause.hqLostWithBridge,
      );
      final won = second.events.last as BattleWon;
      expect((won.team, won.kind), ('c', VictoryKind.lastHq));
      expect(second.state.winner, same(won));
    });

    test('RELIC-11 an eliminated team keeps its relics until they are '
        'captured, and never holds', () {
      final held = captureAll(state, 'a', ['r1', 'r2', 'r3']).state;
      final out = rules.hqLost(
        held,
        team: 'a',
        cause: EliminationCause.hqDestroyed,
        at: _hour * 0.5,
      );
      final taken = rules.captured(
        out.state,
        relicId: 'r1',
        team: 'c',
        at: _hour * 0.5,
      );

      expect(out.events.last, isA<HoldReset>());
      expect(out.state.relicOwners['r1'], 'a');
      expect(out.state.hold, isNull);
      expect((taken.events.single as RelicOwnerChanged).previousOwner, 'a');
    });

    test('a relic or a team not in the battle is an error', () {
      expect(
        () => rules.captured(state, relicId: 'r9', team: 'a', at: _hour),
        throwsArgumentError,
      );
      expect(
        () => rules.captured(state, relicId: 'r1', team: 'z', at: _hour),
        throwsArgumentError,
      );
      expect(
        () => rules.relicLost(state, relicId: 'r9', at: _hour),
        throwsArgumentError,
      );
      expect(
        () => rules.hqLost(
          state,
          team: 'z',
          cause: EliminationCause.hqDestroyed,
          at: _hour,
        ),
        throwsArgumentError,
      );
    });
  });

  group('VictoryRules on the plan data', () {
    // Plan victory: hold 5 of the 8 relics for 24 hours.
    late GameData data;
    late VictoryRules rules;
    const relics = ['r1', 'r2', 'r3', 'r4', 'r5', 'r6', 'r7', 'r8'];

    setUp(() {
      data = parsePlanData();
      rules = VictoryRules(data.battle.victory);
    });

    VictoryState captureAll(
      VictoryState from,
      String team,
      Iterable<String> ids, {
      Duration at = Duration.zero,
    }) {
      var state = from;
      for (final relic in ids) {
        state = rules.captured(state, relicId: relic, team: team, at: at).state;
      }
      return state;
    }

    test('RELIC-14 a 24-hour hold that wins', () {
      final held = captureAll(
        rules.start(relics: relics, teams: ['a', 'b']),
        'a',
        relics.take(5),
      );

      expect(
        rules.at(held, const Duration(hours: 24) - _second).events,
        isEmpty,
      );
      expect(
        (rules.at(held, const Duration(hours: 24)).events.single as BattleWon)
            .team,
        'a',
      );
    });

    test('RELIC-15 a hold that drops to 4 relics for one second starts again '
        'from zero', () {
      final held = captureAll(
        rules.start(relics: relics, teams: ['a', 'b']),
        'a',
        relics.take(5),
      );
      final dropped = rules
          .captured(held, relicId: 'r1', team: 'b', at: _hour * 20)
          .state;
      final back = rules
          .captured(dropped, relicId: 'r1', team: 'a', at: _hour * 20 + _second)
          .state;

      expect(rules.at(back, _hour * 24).events, isEmpty);
      expect(back.hold?.winsAt, _hour * 44 + _second);
    });

    test('HQ-45 three teams, two eliminated one after the other', () {
      final start = rules.start(relics: relics, teams: ['a', 'b', 'c']);
      final first = rules.hqLost(
        start,
        team: 'b',
        cause: EliminationCause.hqDestroyed,
        at: _hour * 30,
      );
      final second = rules.hqLost(
        first.state,
        team: 'a',
        cause: EliminationCause.hqLostWithBridge,
        at: _hour * 50,
      );

      expect(first.events.single, isA<TeamEliminated>());
      expect(second.state.winner?.team, 'c');
      expect(second.state.winner?.kind, VictoryKind.lastHq);
    });

    test('RELIC-26 a battle where 4 relics remain and only the HQ victory is '
        'possible', () {
      var state = rules.start(relics: relics, teams: ['a', 'b']);
      for (final relic in relics.take(4)) {
        state = rules.relicLost(state, relicId: relic, at: _hour).state;
      }
      state = captureAll(state, 'a', relics.skip(4), at: _hour * 2);

      expect(state.relicOwners.values, everyElement('a'));
      expect(rules.relicVictoryPossible(state), isFalse);
      expect(state.hold, isNull);
    });

    test('RELIC-27 relics are indestructible: no weapon damages them', () {
      final damage = Damage(data.combat);

      for (final weapon in data.combat.weaponTypes.values) {
        expect(
          damage.hit(weapon, const DamageTarget(armorType: 'relic')),
          0,
          reason: weapon.id,
        );
      }
    });
  });
}
