import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixed_random.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

void main() {
  group('TeamRules on the fixtures', () {
    // Fixture: 3 teams, 3 guilds offered; medal points 1, 2 and 5.
    late TeamRules rules;

    setUp(() {
      final data = parseFixtures();
      rules = TeamRules(battle: data.battle, medals: data.medals);
    });

    test('SOC-05 UNIT-12 decision 197 a section is worth its section XP and '
        'the XP its units earned, spent or not', () {
      expect(
        rules.sectionPower(
          sectionXp: 100,
          units: const [UnitXp(earned: 50, unspent: 10), UnitXp(earned: 30)],
        ),
        180,
      );
    });

    test('SOC-20 decision 103 teams.count teams balanced by power, each '
        'guild kept together', () {
      final teams = rules.formTeams(const [
        TeamSection(sectionId: 's1', power: 100, guildId: 'g1'),
        TeamSection(sectionId: 's2', power: 50, guildId: 'g1'),
        TeamSection(sectionId: 's3', power: 120),
        TeamSection(sectionId: 's4', power: 80),
        TeamSection(sectionId: 's5', power: 40, guildId: 'g2'),
        TeamSection(sectionId: 's6', power: 20, guildId: 'g2'),
      ]);

      // g1 150, s3 120, s4 80, then g2 60 to the weakest team.
      expect(teams, [
        ['s1', 's2'],
        ['s3'],
        ['s4', 's5', 's6'],
      ]);
    });

    test('decision 209 a trainee section stays with its guild', () {
      final teams = rules.formTeams(const [
        TeamSection(sectionId: 'chief', power: 300, guildId: 'g1'),
        TeamSection(sectionId: 'trainee', power: 0, guildId: 'g1'),
        TeamSection(sectionId: 'other', power: 10),
      ]);

      expect(teams.first, ['chief', 'trainee']);
    });

    test('the same sections form the same teams in any order', () {
      const sections = [
        TeamSection(sectionId: 'a', power: 50),
        TeamSection(sectionId: 'b', power: 50),
        TeamSection(sectionId: 'c', power: 50, guildId: 'g'),
        TeamSection(sectionId: 'd', power: 50),
      ];

      expect(rules.formTeams(sections.reversed), rules.formTeams(sections));
    });

    test('a team stays empty with fewer blocks than teams', () {
      final teams = rules.formTeams(const [
        TeamSection(sectionId: 'a', power: 10),
        TeamSection(sectionId: 'b', power: 5),
      ]);

      expect(teams, [
        ['a'],
        ['b'],
        <String>[],
      ]);
    });

    test('SOC-02 SOC-06 decision 211 a newcomer joins the weakest team; a '
        'tie is drawn', () {
      expect(
        rules.newcomerTeam({'a': 100, 'b': 50, 'c': 70}, FixedRandom([0.5])),
        'b',
      );
      const tied = {'b': 50.0, 'a': 50.0, 'c': 70.0};
      expect(rules.newcomerTeam(tied, FixedRandom([0])), 'a');
      expect(rules.newcomerTeam(tied, FixedRandom([0.99])), 'b');
    });

    test('SOC-03 guilds_offered guilds drawn among those that opted in', () {
      final offer = rules.guildOffer(
        optedIn: ['g5', 'g4', 'g3', 'g2', 'g1'],
        others: ['h1'],
        random: FixedRandom([0]),
      );

      expect(offer, ['g1', 'g2', 'g3']);
      expect(() => offer.add('x'), throwsUnsupportedError);
    });

    test('SOC-03 the draw changes with the random and is replayed with its '
        'seed', () {
      List<String> draw(int seed) => rules.guildOffer(
        optedIn: ['g1', 'g2', 'g3', 'g4', 'g5', 'g6'],
        others: const [],
        random: XorshiftRandom(seed),
      );

      expect(draw(7), draw(7));
      expect(draw(7).toSet(), hasLength(3));
      expect(
        {for (var seed = 0; seed < 20; seed++) draw(seed).join()}.length,
        greaterThan(1),
      );
    });

    test('SOC-07 fewer opted in: filled with other guilds; fewer in the team: '
        'all of them', () {
      final filled = rules.guildOffer(
        optedIn: ['g1'],
        others: ['h3', 'h2', 'h1'],
        random: FixedRandom([0]),
      );
      final all = rules.guildOffer(
        optedIn: ['g1'],
        others: ['h1'],
        random: FixedRandom([0.5]),
      );

      expect(filled, ['g1', 'h1', 'h2']);
      expect(all, ['g1', 'h1']);
    });

    test('SOC-29 decision 121 medal points by tier', () {
      expect(rules.medalPoints({'bronze': 2, 'silver': 1, 'gold': 1}), 9);
      expect(rules.medalPoints(const {}), 0);
      expect(() => rules.medalPoints({'platinum': 1}), throwsArgumentError);
    });

    test('HQ-05 HQ-06 SOC-29 the HQ manager has the most medal points', () {
      final manager = rules.hqManager(const [
        ManagerCandidate(
          playerId: 'p1',
          medals: {'bronze': 4},
          commanderXp: 900,
        ),
        ManagerCandidate(playerId: 'p2', medals: {'gold': 1}, commanderXp: 10),
      ], FixedRandom([0]));

      expect(manager.playerId, 'p2');
    });

    test('SOC-29 on a points tie, the commander with the most XP', () {
      final manager = rules.hqManager(const [
        ManagerCandidate(playerId: 'p1', medals: {'gold': 1}, commanderXp: 100),
        ManagerCandidate(playerId: 'p2', medals: {'gold': 1}, commanderXp: 300),
        ManagerCandidate(playerId: 'p3', medals: {}, commanderXp: 900),
      ], FixedRandom([0]));

      expect(manager.playerId, 'p2');
    });

    test('decision 211 a full tie is drawn', () {
      const candidates = [
        ManagerCandidate(
          playerId: 'p2',
          medals: {'silver': 1},
          commanderXp: 50,
        ),
        ManagerCandidate(
          playerId: 'p1',
          medals: {'silver': 1},
          commanderXp: 50,
        ),
        ManagerCandidate(playerId: 'p3', medals: {}, commanderXp: 50),
      ];

      expect(rules.hqManager(candidates, FixedRandom([0])).playerId, 'p1');
      expect(rules.hqManager(candidates, FixedRandom([0.99])).playerId, 'p2');
    });

    group('HQ-07 decision 220 a player who logs in', () {
      const low = ManagerCandidate(
        playerId: 'p1',
        medals: {'bronze': 1},
        commanderXp: 10,
      );
      const high = ManagerCandidate(
        playerId: 'p2',
        medals: {'gold': 1},
        commanderXp: 10,
      );
      const twin = ManagerCandidate(
        playerId: 'p3',
        medals: {'bronze': 1},
        commanderXp: 10,
      );
      final noDraw = FixedRandom(const []);

      test('manages a team that has no manager yet', () {
        expect(
          rules
              .afterLogIn(manager: null, entering: low, random: noDraw)
              .playerId,
          'p1',
        );
      });

      test('takes the role from a lower-ranking manager, delegated or not', () {
        expect(
          rules
              .afterLogIn(manager: low, entering: high, random: noDraw)
              .playerId,
          'p2',
        );
      });

      test('leaves it to a higher-ranking manager or to himself', () {
        expect(
          rules
              .afterLogIn(manager: high, entering: low, random: noDraw)
              .playerId,
          'p2',
        );
        expect(
          rules
              .afterLogIn(manager: high, entering: high, random: noDraw)
              .playerId,
          'p2',
        );
      });

      test('Q-HQ-12 draws the role on an exact tie', () {
        expect(
          rules
              .afterLogIn(
                manager: low,
                entering: twin,
                random: FixedRandom([0]),
              )
              .playerId,
          'p1',
        );
        expect(
          rules
              .afterLogIn(
                manager: low,
                entering: twin,
                random: FixedRandom([0.99]),
              )
              .playerId,
          'p3',
        );
      });
    });

    test('a team with no player has no manager to choose', () {
      expect(
        () => rules.hqManager(const [], FixedRandom([0])),
        throwsArgumentError,
      );
    });

    test('HQ-05 the manager delegates the role to another player of the '
        'team', () {
      const manager = HqManager('p1');
      const team = {'p1', 'p2', 'p3'};
      DelegationRefusal? refusal(String by, String to) =>
          switch (manager.delegate(by: by, to: to, teamPlayers: team)) {
            DelegationRefused(:final reason) => reason,
            Delegated() => null,
          };

      expect(refusal('p2', 'p3'), DelegationRefusal.notManager);
      expect(refusal('p1', 'p9'), DelegationRefusal.notInTeam);
      expect(refusal('p1', 'p1'), DelegationRefusal.notInTeam);
      final delegated =
          manager.delegate(by: 'p1', to: 'p2', teamPlayers: team) as Delegated;
      expect(delegated.manager.playerId, 'p2');
    });
  });

  group('TeamRules on the plan data', () {
    // Plan: 2 teams by default (a battle setting), 4 guilds offered; medal
    // points 1, 3 and 10.
    late GameData data;
    late TeamRules rules;

    setUp(() {
      data = parsePlanData();
      rules = TeamRules(battle: data.battle, medals: data.medals);
    });

    TeamRules withTeams(int count) => TeamRules(
      battle: parseFixtures(battle: {'  count: 3': '  count: $count'}).battle,
      medals: data.medals,
    );

    List<double> powers(List<List<String>> teams, List<TeamSection> sections) =>
        [
          for (final team in teams)
            sections
                .where((section) => team.contains(section.sectionId))
                .fold(0, (sum, section) => sum + section.power),
        ];

    test('SOC-20 balancing with a guild larger than an even share, in 2 '
        'teams', () {
      const sections = [
        TeamSection(sectionId: 'g-a', power: 400, guildId: 'big'),
        TeamSection(sectionId: 'g-b', power: 400, guildId: 'big'),
        TeamSection(sectionId: 'g-c', power: 400, guildId: 'big'),
        TeamSection(sectionId: 's1', power: 300),
        TeamSection(sectionId: 's2', power: 250),
        TeamSection(sectionId: 's3', power: 200),
        TeamSection(sectionId: 's4', power: 100),
      ];

      final teams = rules.formTeams(sections);

      expect(data.battle.teamCount, 2);
      expect(teams.first, ['g-a', 'g-b', 'g-c']);
      expect(powers(teams, sections), [1200, 850]);
    });

    test('SOC-20 balancing in 5 teams stays within the largest block', () {
      const sections = [
        TeamSection(sectionId: 'g1', power: 300, guildId: 'guild'),
        TeamSection(sectionId: 'g2', power: 200, guildId: 'guild'),
        TeamSection(sectionId: 's1', power: 300),
        TeamSection(sectionId: 's2', power: 250),
        TeamSection(sectionId: 's3', power: 200),
        TeamSection(sectionId: 's4', power: 150),
        TeamSection(sectionId: 's5', power: 100),
        TeamSection(sectionId: 's6', power: 50),
      ];

      final teams = withTeams(5).formTeams(sections);
      final power = powers(teams, sections);

      expect(teams, hasLength(5));
      expect(power, [500, 300, 250, 250, 250]);
      expect(
        power.reduce((a, b) => a > b ? a : b) -
            power.reduce((a, b) => a < b ? a : b),
        lessThanOrEqualTo(500),
      );
    });

    test('SOC-03 SOC-07 the four guild cases', () {
      List<String> offer(List<String> optedIn, List<String> others) =>
          rules.guildOffer(
            optedIn: optedIn,
            others: others,
            random: XorshiftRandom(3),
          );
      const opted = ['o1', 'o2', 'o3', 'o4', 'o5', 'o6'];
      const others = ['x1', 'x2', 'x3', 'x4', 'x5'];

      // Enough opted in: 4 of them.
      expect(offer(opted, others), everyElement(isIn(opted)));
      expect(offer(opted, others), hasLength(4));
      // Two opted in: both, filled with two others.
      final filled = offer(['o1', 'o2'], others);
      expect(filled.take(2).toSet(), {'o1', 'o2'});
      expect(filled.skip(2), everyElement(isIn(others)));
      expect(filled, hasLength(4));
      // None opted in: 4 others.
      expect(offer(const [], others), hasLength(4));
      // Three guilds in the team: all of them.
      expect(offer(['o1'], ['x1', 'x2']).toSet(), {'o1', 'x1', 'x2'});
    });

    test('SOC-29 the HQ manager on a points tie', () {
      final manager = rules.hqManager(const [
        ManagerCandidate(
          playerId: 'gold',
          medals: {'gold': 1},
          commanderXp: 50,
        ),
        ManagerCandidate(
          playerId: 'mixed',
          medals: {'silver': 3, 'bronze': 1},
          commanderXp: 80,
        ),
      ], FixedRandom([0]));

      expect(rules.medalPoints({'gold': 1}), 10);
      expect(rules.medalPoints({'silver': 3, 'bronze': 1}), 10);
      expect(manager.playerId, 'mixed');
    });
  });
}
