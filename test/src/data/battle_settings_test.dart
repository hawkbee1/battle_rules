import 'dart:convert';

import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

void main() {
  group(BattleSettings, () {
    late BattleSettings battle;

    setUp(() {
      battle = BattleSettings.parse(readFixture('battle.yaml'));
    });

    test('reads the version and the commander death costs', () {
      expect(battle.version, 5);
      expect(battle.commanderDeath.xpLossShare, 0.2);
      expect(battle.commanderDeath.apLossShare, 0.5);
      expect(battle.commanderDeath.moraleLoss, 10);
    });

    test('reads the AP maximum and recovery', () {
      expect(battle.ap.max, 20);
      expect(battle.ap.recoveryDelayS, 1800);
    });

    test('UNIT-44 reads whether test units are allowed', () {
      expect(battle.testUnits, isFalse);
    });

    test('COMBAT-02 rejects the old recovery_per_hour key and says what '
        'replaces it', () {
      expect(
        () => BattleSettings.parse(
          readFixture('battle.yaml', {
            'recovery_delay_s: 1800': 'recovery_per_hour: 2',
          }),
        ),
        throwsDataError(
          'battle.yaml',
          'ap.recovery_per_hour',
          2,
          'recovery_delay_s',
        ),
      );
    });

    test('COMBAT-02 needs a whole number of seconds for the delay', () {
      expect(
        () => BattleSettings.parse(
          readFixture('battle.yaml', {
            'recovery_delay_s: 1800': 'recovery_delay_s: 0.5',
          }),
        ),
        throwsDataError(
          'battle.yaml',
          'ap.recovery_delay_s',
          0.5,
          'must be an integer',
        ),
      );
    });

    test('reads the battle start, the team count and the guilds offered', () {
      expect(battle.battleStart.restoreAp, 'full');
      expect(battle.battleStart.restoreHp, 'full');
      expect(battle.battleStart.restoreMorale, 'base');
      expect(battle.teamCount, 3);
      expect(battle.guildsOffered, 3);
    });

    test('reads the capture settings', () {
      expect(battle.capture.durationS, 900);
      expect(battle.capture.potAp, 40);
      expect(battle.capture.contributionAp, 4);
      expect(battle.capture.radiusM, 25);
    });

    test('reads the HQ and its hit box', () {
      final hq = battle.hq;

      expect(hq.hp, 800);
      expect(hq.apMax, 20);
      expect(hq.apPerM, 0.5);
      expect(hq.speedMPerH, 3);
      expect(
        [hq.hitBox.width, hq.hitBox.length, hq.hitBox.height],
        [15, 18, 6],
      );
    });

    test('reads victory, storage, weather and the redeploy lock', () {
      expect(battle.victory.relicsToHold, 3);
      expect(battle.victory.holdS, 3600);
      expect(battle.storage.storeRadiusM, 8);
      expect(battle.storage.recallS, 7200);
      expect(battle.storage.deployAp, 6);
      expect(battle.storage.deployBlockRadiusM, 15);
      expect(battle.weather.mode, 'random');
      expect(battle.weather.states, ['clear', 'fog']);
      expect(battle.sectionRedeployLockS, 1800);
    });

    test('AI-07 reads the fire check of server-managed units', () {
      expect(battle.serverManaged.fireChance, 0.25);
      expect(battle.serverManaged.checkIntervalS, 600);
    });

    test('writes its values back in the shape parse reads', () {
      final data = battle.toData();
      final again = BattleSettings.parse(jsonEncode(data));

      expect(again.toData(), equals(data));
      expect(again.hq.hitBox.height, 6);
      expect(again.weather.states, ['clear', 'fog']);
      expect(data['ap'], {'max': 20.0, 'recovery_delay_s': 1800});
      expect(data['test_units'], isFalse);
      expect(again.serverManaged.checkIntervalS, 600);
    });

    group('overriddenBy', () {
      test('decision 238 replaces the values it names and keeps the rest', () {
        final own = battle.overriddenBy({
          'ap': {'recovery_delay_s': 1},
          'test_units': true,
        });

        expect(own.ap.recoveryDelayS, 1);
        expect(own.testUnits, isTrue);
        expect(own.ap.max, battle.ap.max);
        expect(own.hq.hitBox.height, battle.hq.hitBox.height);
        expect(own.weather.states, battle.weather.states);
        expect(battle.ap.recoveryDelayS, 1800);
        expect(battle.testUnits, isFalse);
      });

      test('keeps every value for no override', () {
        expect(battle.overriddenBy(const {}).toData(), battle.toData());
      });

      test('names a key that is no battle setting', () {
        expect(
          () => battle.overriddenBy({
            'ap': {'recovery_per_hour': 2},
          }),
          throwsDataError(
            'battle.yaml',
            'ap.recovery_per_hour',
            2,
            'not a battle setting',
          ),
        );
        expect(
          () => battle.overriddenBy({'speed': 3}),
          throwsDataError('battle.yaml', 'speed', 3, 'not a battle setting'),
        );
      });

      test('wants a map where the file has one', () {
        expect(
          () => battle.overriddenBy({'ap': 5}),
          throwsDataError('battle.yaml', 'ap', 5, 'must be a map'),
        );
      });

      test('wants the type of the file for a value', () {
        expect(
          () => battle.overriddenBy({'test_units': 'yes'}),
          throwsDataError(
            'battle.yaml',
            'test_units',
            'yes',
            'must be true or false',
          ),
        );
      });
    });
  });
}
