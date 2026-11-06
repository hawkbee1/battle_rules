import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixed_random.dart';
import '../../helpers/plan_data.dart';

void main() {
  group(ServerFireCheck, () {
    test('AI-07 fires when the draw is below the chance, the same at each '
        'check', () {
      const check = ServerFireCheck(
        ServerManagedSettings(fireChance: 0.25, checkIntervalS: 600),
      );
      final random = FixedRandom([0.1, 0.25, 0.9, 0.24]);

      expect(
        [for (var i = 0; i < 4; i++) check.fires(random)],
        [true, false, false, true],
      );
      expect(check.interval, const Duration(minutes: 10));
    });

    test('decision 229 checks fall every interval from the battle start', () {
      const check = ServerFireCheck(
        ServerManagedSettings(fireChance: 0.25, checkIntervalS: 600),
      );

      expect(check.nextAfter(Duration.zero), const Duration(minutes: 10));
      expect(
        check.nextAfter(const Duration(minutes: 3)),
        const Duration(minutes: 10),
      );
      expect(
        check.nextAfter(const Duration(minutes: 10)),
        const Duration(minutes: 20),
      );
    });

    test('AI-07 decision 196 the plan fires at 50 % every 30 minutes', () {
      final check = ServerFireCheck(parsePlanData().battle.serverManaged);

      expect(check.interval, const Duration(minutes: 30));
      expect(check.fires(FixedRandom([0.49])), isTrue);
      expect(check.fires(FixedRandom([0.5])), isFalse);
    });
  });
}
