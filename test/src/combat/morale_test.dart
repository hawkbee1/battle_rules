import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

void main() {
  late CombatData combat;
  late Morale morale;

  setUp(() {
    combat = CombatData.parse(readFixture('combat.yaml'));
    morale = Morale(combat.morale);
  });

  test('COMBAT-46 a new unit starts at the base morale, within 0 to 100', () {
    final plan = parsePlanData().combat.morale;

    expect(Morale(plan).base, plan.base);
    expect([plan.min, plan.max], [0, 100]);
    expect(morale.base, 40);
  });

  test('COMBAT-47 morale changes only through events: no event, no '
      'change', () {
    for (final event in MoraleEvent.values) {
      expect(morale.after(30, event, times: 0), 30, reason: event.name);
    }
  });

  test('COMBAT-48 the aura, nearby kills and deaths, and being outnumbered '
      'change morale', () {
    expect(morale.after(30, MoraleEvent.commanderAuraMinute, times: 10), 60);
    expect(morale.after(30, MoraleEvent.nearbyEnemyKilled), 34);
    expect(morale.after(30, MoraleEvent.nearbyAllyKilled), 24);
    expect(morale.after(30, MoraleEvent.outnumberedMinute, times: 5), 20);
  });

  test('COMBAT-46 morale stays within its range', () {
    expect(morale.after(78, MoraleEvent.nearbyEnemyKilled), 80);
    expect(morale.after(3, MoraleEvent.nearbyAllyKilled), 0);
  });

  test('COMBAT-48 a kill counts within the nearby radius', () {
    expect(morale.isNearby(45), isTrue);
    expect(morale.isNearby(46), isFalse);
  });

  test('COMBAT-48 a unit is outnumbered above the enemy to ally ratio', () {
    expect(morale.isOutnumbered(enemies: 5, allies: 2), isTrue);
    expect(morale.isOutnumbered(enemies: 4, allies: 2), isFalse);
    expect(morale.isOutnumbered(enemies: 1, allies: 0), isTrue);
    expect(morale.isOutnumbered(enemies: 0, allies: 0), isFalse);
  });

  test('COMBAT-49 morale raised by events raises the hit chance', () {
    final hitChance = HitChance(combat);
    final raised = morale.after(40, MoraleEvent.nearbyEnemyKilled);

    expect(
      hitChance.moraleFactor(raised),
      greaterThan(hitChance.moraleFactor(40)),
    );
  });
}
