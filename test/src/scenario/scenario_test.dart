import 'dart:io';

import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

/// A scenario with [units] and [orders] (YAML lines), on grass in clear
/// weather.
String _scenario(String units, String orders, {int seed = 1}) =>
    '''
name: test
seed: $seed
weather: clear
terrain: grass
units:
$units
orders:
$orders
''';

void main() {
  late ScenarioRunner runner;

  setUpAll(() {
    runner = ScenarioRunner(parsePlanData());
  });

  ScenarioReport play(String text) => runner.run(Scenario.parse(text));

  ScenarioReport playFile(String name) =>
      play(File('scenarios/$name.yaml').readAsStringSync());

  group('the committed scenarios', () {
    // Expected summaries on the current plan data. When a value of
    // plan/data is tuned, update them in the same change.
    test('rifle squad vs jeep', () {
      final report = playFile('rifle_squad_vs_jeep');

      expect(
        report.summary.line,
        'shots=90 hits=39 damage=194.40 deaths=0 spared=0 crushed=0 '
        'ap_used=150.00',
      );
      expect(report.events.last, 't=33.5s j1 fires at s1: miss');
    });

    test('artillery with a radio-relayed target', () {
      final report = playFile('artillery_radio_relay');

      expect(
        report.summary.line,
        'shots=2 hits=1 damage=38.50 deaths=0 spared=0 crushed=0 '
        'ap_used=30.00',
      );
      expect(report.events, contains('t=10.0s a1 hits t2 for 10.50 HP'));
    });

    test('relic push with crushing', () {
      final report = playFile('relic_push_crushing');

      expect(
        report.summary.line,
        'shots=0 hits=0 damage=0.00 deaths=2 spared=0 crushed=2 '
        'ap_used=120.00',
      );
      const stop =
          't=4320.0s the relic moves 6.0 m with 12 pushers and stops: '
          'blocked, 60.0 AP left in its pot';
      expect(report.events, [
        't=4320.0s e1 is crushed',
        't=4320.0s e2 is crushed',
        stop,
      ]);
    });

    test('a report prints its log and one machine-readable line', () {
      final report = playFile('relic_push_crushing');

      expect(report.text, startsWith('Scenario: relic push with crushing'));
      expect(report.text, endsWith('Summary: ${report.summary.line}'));
      expect(
        report.machineLine,
        'scenario="relic push with crushing" seed=5 ${report.summary.line} '
        'ends_at_s=4320.0',
      );
      expect(report.endsAt, const Duration(seconds: 4320));
    });
  });

  group('runner', () {
    test("COMBAT-38 a commander's final blow can spare the enemy", () {
      final report = play(
        _scenario(
          '  c1: { type: commander, team: red, position: 0 }\n'
              '  s1: { type: soldier, team: blue, position: 50 }',
          '  - { at_s: 0, order: fire, unit: s1, target: c1, shots: 15 }\n'
              '  - { at_s: 30, order: fire, unit: c1, target: s1, shots: 15 }',
          seed: 9,
        ),
      );

      expect(report.summary.spared, 1);
      expect(
        report.events.last,
        matches(RegExp(r's1 is at 0 HP: (defection|prisoner)$')),
      );
    });

    test('COMBAT-36 a unit brought to 0 HP by a non-commander dies', () {
      final report = play(
        _scenario(
          '  j1: { type: jeep, team: red, position: 0 }\n'
              '  j2: { type: jeep, team: red, position: 2 }\n'
              '  s1: { type: soldier, team: blue, position: 50 }',
          '  - { at_s: 0, order: fire, unit: j1, target: s1, shots: 30 }\n'
              '  - { at_s: 0, order: fire, unit: j2, target: s1, shots: 30 }',
        ),
      );

      expect(report.summary.deaths, 1);
      expect(report.events.last, endsWith('s1 is at 0 HP: death'));
    });

    test('COMBAT-11 a unit does not fire at what it cannot see', () {
      final report = play(
        _scenario(
          '  s1: { type: soldier, team: red, position: 0 }\n'
              '  s2: { type: soldier, team: blue, position: 300 }',
          '  - { at_s: 0, order: fire, unit: s1, target: s2, shots: 3 }',
        ),
      );

      expect(report.events, ['t=0.0s s1 cannot fire at s2']);
      expect(report.summary.shots, 0);
    });

    test('COMBAT-13 a unit without a weapon does not fire', () {
      final report = play(
        _scenario(
          '  r1: { type: radio, team: red, position: 0 }\n'
              '  s2: { type: soldier, team: blue, position: 10 }',
          '  - { at_s: 0, order: fire, unit: r1, target: s2, shots: 1 }',
        ),
      );

      expect(report.events, ['t=0.0s r1 cannot fire at s2']);
    });

    test('a weapon that refuses a shot ends the order', () {
      final fixtureRunner = ScenarioRunner(
        parseFixtures(combat: {'ap_per_shot: 2,': 'ap_per_shot: 25,'}),
      );
      final report = fixtureRunner.run(
        Scenario.parse(
          _scenario(
            '  c1: { type: commander, team: red, position: 0 }\n'
                '  j1: { type: jeep, team: blue, position: 10 }',
            '  - { at_s: 0, order: fire, unit: c1, target: j1, shots: 1 }',
          ),
        ),
      );

      expect(report.events, ['t=0.0s c1 cannot fire: costAboveApMax']);
    });

    test('COMBAT-12 artillery cannot target a position nobody reports', () {
      final report = play(
        _scenario(
          '  a1: { type: artillery, team: red, position: 0 }\n'
              '  sc1: { type: scout, team: red, section: s, position: 700 }\n'
              '  s2: { type: soldier, team: red, position: 600 }\n'
              '  t1: { type: tank, team: blue, position: 900 }',
          // A soldier is no radio: nothing relays the scout's report.
          '  - { at_s: 0, order: artillery, unit: a1, target: t1, '
              'spotter: sc1, radio: s2, shots: 1 }\n'
              '  - { at_s: 1, order: artillery, unit: a1, target: t1, '
              'shots: 1 }',
        ),
      );

      expect(report.events, [
        't=0.0s a1 cannot target t1',
        't=1.0s a1 cannot target t1',
      ]);
    });

    test('COMBAT-03 a move pays the path cost; an impassable one fails', () {
      final report = play(
        _scenario(
          '  s1: { type: soldier, team: red, position: 0 }',
          '  - { at_s: 0, order: move, unit: s1, path: '
              '[{ terrain: grass, length: 10 }, '
              '{ terrain: mud, slope: 5, length: 2 }] }\n'
              '  - { at_s: 60, order: move, unit: s1, path: '
              '[{ terrain: lake, length: 1 }] }',
        ),
      );

      expect(report.events.first, endsWith('s1 moves 12.0 m for 15.00 AP'));
      expect(report.events.last, 't=60.0s s1 cannot move: impassable');
      expect(report.summary.apUsed, 15);
    });

    test('a unit with a loaded weapon that forbids moving does not move', () {
      final report = play(
        _scenario(
          '  a1: { type: artillery, team: red, position: 0 }',
          '  - { at_s: 0, order: move, unit: a1, path: '
              '[{ terrain: grass, length: 10 }] }',
        ),
      );

      expect(report.events, ['t=0.0s a1 cannot move: its weapon is loaded']);
    });

    test('RELIC-19 a unit of another team cannot push the relic', () {
      final report = play(
        _scenario(
          '  s1: { type: soldier, team: blue, position: 0 }',
          '  - { at_s: 0, order: push, owner: red, pushers: [s1], '
              'contributions: 1, path: [{ terrain: grass, length: 1 }] }',
        ),
      );

      expect(report.events.first, 't=0.0s s1 cannot push');
    });

    test('UNIT-38 a unit that cannot push does not add to the pot', () {
      final report = play(
        _scenario(
          '  h1: { type: helicopter, team: red, position: 0 }',
          '  - { at_s: 0, order: push, owner: red, pushers: [h1], '
              'contributions: 1, path: [{ terrain: grass, length: 1 }] }',
        ),
      );

      expect(report.events.first, 't=0.0s h1 cannot push');
      expect(report.events.last, contains('stops: tooFewPushers'));
    });

    test('rejects a unit type the data does not have', () {
      expect(
        () => play(
          _scenario('  x1: { type: dragon, team: red, position: 0 }', '  []'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Scenario.parse', () {
    test('reads units with their section and orders in time order', () {
      final scenario = Scenario.parse(
        _scenario(
          '  s1: { type: soldier, team: red, position: 0 }\n'
              '  s2: { type: soldier, team: red, section: b, position: 5, '
              'flying: true }',
          '  - { at_s: 5, order: fire, unit: s1, target: s2, shots: 1 }\n'
              '  - { at_s: 0, order: fire, unit: s2, target: s1, shots: 1 }\n'
              '  - { at_s: 5, order: fire, unit: s2, target: s1, shots: 2 }',
        ),
      );

      expect(scenario.name, 'test');
      expect(scenario.seed, 1);
      expect(scenario.weather, 'clear');
      expect(scenario.terrain, 'grass');
      expect(scenario.units['s1']!.section, 'red');
      expect(scenario.units['s2']!.section, 'b');
      expect(scenario.units['s2']!.flying, isTrue);
      expect(
        [for (final order in scenario.orders) (order as FireOrder).unit],
        ['s2', 's1', 's2'],
      );
      expect((scenario.orders.last as FireOrder).shots, 2);
    });

    test('rejects an unknown order', () {
      expect(
        () => Scenario.parse(
          _scenario(
            '  s1: { type: soldier, team: red, position: 0 }',
            '  - { at_s: 0, order: dance, unit: s1 }',
          ),
        ),
        throwsDataError(
          'scenario',
          'orders[0].order',
          'dance',
          'unknown, expected fire, artillery, move or push',
        ),
      );
    });

    test('rejects a reference to a unit the scenario does not have', () {
      const s1 = '  s1: { type: soldier, team: red, position: 0 }';
      expect(
        () => Scenario.parse(
          _scenario(
            s1,
            '  - { at_s: 0, order: fire, unit: s1, target: x, '
            'shots: 1 }',
          ),
        ),
        throwsDataError('scenario', 'orders[0].target', 'x', 'no such unit'),
      );
      expect(
        () => Scenario.parse(
          _scenario(
            s1,
            '  - { at_s: 0, order: push, owner: red, '
            'pushers: [s1, x], contributions: 1, path: [] }',
          ),
        ),
        throwsDataError(
          'scenario',
          'orders[0].pushers[1]',
          'x',
          'no such unit',
        ),
      );
      expect(
        () => Scenario.parse(
          _scenario(
            s1,
            '  - { at_s: 0, order: push, owner: red, '
            'pushers: [s1], contributions: 1, path: [], in_path: { y: 2 } }',
          ),
        ),
        throwsDataError('scenario', 'orders[0].in_path.y', 'y', 'no such unit'),
      );
    });
  });
}
