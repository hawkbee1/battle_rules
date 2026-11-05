import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

void main() {
  group(MedalsData, () {
    late MedalsData medals;

    setUp(() {
      medals = MedalsData.parse(readFixture('medals.yaml'));
    });

    test('reads the version, tiers and points', () {
      expect(medals.version, 2);
      expect(medals.tiers, ['bronze', 'silver', 'gold']);
      expect(medals.points, {'bronze': 1, 'silver': 2, 'gold': 5});
    });

    test('reads the kill thresholds by target unit type', () {
      expect(medals.killThresholds.keys, ['commander', 'default']);
      expect(medals.killThresholds['commander'], {
        'bronze': 3,
        'silver': 10,
        'gold': 40,
      });
    });

    test('reads the action thresholds and kinds', () {
      expect(medals.actionThresholds, {
        'bronze': 20,
        'silver': 100,
        'gold': 400,
      });
      expect(medals.actionKinds, ['hit', 'build']);
    });

    test('decision 231 reads the friendly kill thresholds', () {
      expect(medals.friendlyKillThresholds, {
        'bronze': 2,
        'silver': 6,
        'gold': 12,
      });
    });

    test('decision 230 reads the hit-rate flag', () {
      expect(medals.hitRateFlag.sigmas, 2.5);
      expect(medals.hitRateFlag.minShots, 30);
    });
  });
}
