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
      expect(battle.ap.recoveryPerHour, 2);
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
  });
}
