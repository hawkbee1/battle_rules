import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

Guild changed(GuildChange change) => (change as GuildChanged).guild!;

GuildRefusal? refusal(GuildChange change) => switch (change) {
  GuildRefused(:final reason) => reason,
  GuildChanged() => null,
};

void main() {
  group('GuildRules on the fixtures', () {
    // Fixture: a guild needs commander level 3; it holds 2 sections at
    // level 1 and one more every 2 levels; levels at 0, 100, 300 and 600 XP.
    late GuildRules rules;
    late Guild guild;

    setUp(() {
      rules = GuildRules(parseFixtures().units.progression);
      guild = changed(
        rules.create(
          guildId: 'g1',
          sectionId: 'chief',
          inGuild: false,
          commanderLevel: 3,
        ),
      );
    });

    Guild withXp(double xp) => rules.earned(guild, xp);

    test('SOC-46 SOC-48 SOC-53 decision 155 a section at the level creates a '
        'guild alone, and is its chief', () {
      expect(guild.id, 'g1');
      expect(guild.roles, {'chief': GuildRole.chief});
      expect(guild.chief, 'chief');
      expect(guild.optedIn, isFalse);
      expect(
        refusal(
          rules.create(
            guildId: 'g2',
            sectionId: 's',
            inGuild: false,
            commanderLevel: 2,
          ),
        ),
        GuildRefusal.levelTooLow,
      );
      expect(
        refusal(
          rules.create(
            guildId: 'g2',
            sectionId: 's',
            inGuild: true,
            commanderLevel: 9,
          ),
        ),
        GuildRefusal.alreadyInGuild,
      );
    });

    test('SOC-47 Q-SOC-18 the XP its sections earn in it sets its level and '
        'its size', () {
      expect((rules.levelOf(guild), rules.maxSections(guild)), (1, 2));
      expect(rules.levelOf(withXp(100)), 2);
      expect(rules.maxSections(withXp(300)), 3);
      expect(rules.earned(withXp(250), 50).xp, 300);
    });

    test('SOC-03 SOC-52 decision 129 a section without a guild applies as a '
        'trainee', () {
      final applied = changed(
        rules.apply(guild, sectionId: 's2', inGuild: false, sameTeam: true),
      );

      expect(applied.roles['s2'], GuildRole.trainee);
      expect(
        refusal(
          rules.apply(guild, sectionId: 's2', inGuild: true, sameTeam: true),
        ),
        GuildRefusal.alreadyInGuild,
      );
    });

    test('SOC-20 a section applies only to a guild of its team', () {
      expect(
        refusal(
          rules.apply(guild, sectionId: 's2', inGuild: false, sameTeam: false),
        ),
        GuildRefusal.otherTeam,
      );
    });

    test('SOC-47 decision 213 trainees count: a full guild takes no '
        'trainee', () {
      final full = changed(
        rules.apply(guild, sectionId: 's2', inGuild: false, sameTeam: true),
      );

      expect(rules.hasRoom(guild), isTrue);
      expect(rules.hasRoom(full), isFalse);
      expect(
        refusal(
          rules.apply(full, sectionId: 's3', inGuild: false, sameTeam: true),
        ),
        GuildRefusal.guildFull,
      );
    });

    test('SOC-50 the chief accepts a trainee: it becomes a member', () {
      final trainee = changed(
        rules.apply(guild, sectionId: 's2', inGuild: false, sameTeam: true),
      );
      final member = changed(rules.accept(trainee, by: 'chief', trainee: 's2'));

      expect(member.roles['s2'], GuildRole.member);
      expect(
        refusal(rules.accept(trainee, by: 's2', trainee: 's2')),
        GuildRefusal.notChief,
      );
      expect(
        refusal(rules.accept(member, by: 'chief', trainee: 's2')),
        GuildRefusal.notTrainee,
      );
    });

    test('SOC-52 decision 153 a trainee refused by the chief leaves the guild '
        'and can apply to another', () {
      final trainee = changed(
        rules.apply(guild, sectionId: 's2', inGuild: false, sameTeam: true),
      );
      final refused = changed(
        rules.refuse(trainee, by: 'chief', trainee: 's2'),
      );
      final other = changed(
        rules.create(
          guildId: 'g2',
          sectionId: 'other-chief',
          inGuild: false,
          commanderLevel: 4,
        ),
      );

      expect(refused.roles.keys, ['chief']);
      expect(
        changed(
          rules.apply(other, sectionId: 's2', inGuild: false, sameTeam: true),
        ).roles['s2'],
        GuildRole.trainee,
      );
      expect(
        refusal(rules.refuse(trainee, by: 's2', trainee: 's2')),
        GuildRefusal.notChief,
      );
    });

    test('SOC-46 the chief cannot leave; a member or a trainee can', () {
      final trainee = changed(
        rules.apply(guild, sectionId: 's2', inGuild: false, sameTeam: true),
      );

      expect(
        refusal(rules.leave(trainee, sectionId: 'chief')),
        GuildRefusal.chiefCannotLeave,
      );
      expect(changed(rules.leave(trainee, sectionId: 's2')).roles.keys, [
        'chief',
      ]);
      expect(
        refusal(rules.leave(trainee, sectionId: 'nobody')),
        GuildRefusal.notInGuild,
      );
    });

    test('SOC-46 decision 214 the chief hands his role to a member, and the '
        'camp with it', () {
      final member = changed(
        rules.accept(
          changed(
            rules.apply(guild, sectionId: 's2', inGuild: false, sameTeam: true),
          ),
          by: 'chief',
          trainee: 's2',
        ),
      );
      final handed = changed(rules.handOver(member, by: 'chief', to: 's2'));

      expect(handed.chief, 's2');
      expect(handed.roles['chief'], GuildRole.member);
      expect(
        refusal(rules.handOver(member, by: 's2', to: 'chief')),
        GuildRefusal.notChief,
      );
      final trainee = changed(
        rules.apply(guild, sectionId: 's3', inGuild: false, sameTeam: true),
      );
      expect(
        refusal(rules.handOver(trainee, by: 'chief', to: 's3')),
        GuildRefusal.notMember,
      );
    });

    test('SOC-46 decision 214 the chief disbands the guild; its camp is '
        'destroyed', () {
      final trainee = changed(
        rules.apply(guild, sectionId: 's2', inGuild: false, sameTeam: true),
      );

      expect(
        (rules.disband(trainee, by: 'chief') as GuildChanged).guild,
        isNull,
      );
      expect(refusal(rules.disband(trainee, by: 's2')), GuildRefusal.notChief);
    });

    test('SOC-08 decision 215 only the chief puts the guild on the newcomer '
        'list or takes it off', () {
      final trainee = changed(
        rules.apply(guild, sectionId: 's2', inGuild: false, sameTeam: true),
      );
      final listed = changed(rules.optIn(trainee, by: 'chief', optedIn: true));

      expect(listed.optedIn, isTrue);
      expect(
        changed(rules.optIn(listed, by: 'chief', optedIn: false)).optedIn,
        isFalse,
      );
      expect(
        refusal(rules.optIn(trainee, by: 's2', optedIn: true)),
        GuildRefusal.notChief,
      );
    });
  });

  group('GuildRules on the plan data', () {
    test('SOC-53 Q-SOC-18 a guild needs commander level 10; it holds 5 '
        'sections at level 1, 16 at 60', () {
      final progression = parsePlanData().units.progression;

      expect(progression.guildCreationMinLevel, 10);
      expect(progression.guildSize.sectionsAt(1), 5);
      expect(progression.guildSize.sectionsAt(6), 6);
      expect(progression.guildSize.sectionsAt(60), 16);
    });
  });
}
