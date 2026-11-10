import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

/// A pool with [ap] AP at time 0, recovering 1 AP per hour.
ApPool _pool(double ap, {double max = 20}) =>
    ApPool(max: max, recoveryDelayS: 3600, value: ap, updatedAt: Duration.zero);

const _team = 'red';
const _friend = RadiusOccupant(team: _team);
const _enemy = RadiusOccupant(team: 'blue');

void main() {
  late CaptureRules rules;
  late UnitsData units;

  setUp(() {
    rules = CaptureRules(
      BattleSettings.parse(readFixture('battle.yaml')).capture,
    );
    units = UnitsData.parse(readFixture('units.yaml'));
  });

  ActionResult contribute({
    String unit = 'commander',
    String unitId = 'c1',
    CapturePot pot = const CapturePot(team: _team),
    ApPool? pool,
    bool insideRadius = true,
    List<RadiusOccupant> occupants = const [_friend],
    Duration now = Duration.zero,
  }) => rules.contribute(
    unit: units.unitTypes[unit]!,
    unitId: unitId,
    pot: pot,
    pool: pool ?? _pool(20),
    insideRadius: insideRadius,
    occupants: occupants,
    now: now,
  );

  CaptureContributed done(ActionResult result) => result as CaptureContributed;
  ActionRefusal refusal(ActionResult result) =>
      (result as ActionRefused).reason;

  test('RELIC-05 COMBAT-07 a unit inside the radius adds contribution_ap to '
      'its team pot', () {
    final added = done(contribute());

    expect(added.pot.ap, 4);
    expect(added.pot.contributions, {'c1': 4.0});
    expect(added.pool.value, 16);
    expect(added.pot.isUnderWay, isTrue);
    expect(added.pot.fullAt, isNull);
    expect(rules.capturedAt(added.pot), isNull);
  });

  test('RELIC-05 several units fill the pot; the capture timer starts when it '
      'is full, and the pot records each one', () {
    var pot = const CapturePot(team: _team);
    final ids = ['c1', 'c2', 'j1'];
    for (var action = 0; action < 10; action++) {
      pot = done(
        contribute(
          unit: action % 3 == 2 ? 'jeep' : 'commander',
          unitId: ids[action % 3],
          pot: pot,
          now: Duration(minutes: action),
        ),
      ).pot;
    }

    expect(pot.ap, 40);
    expect(pot.contributions, {'c1': 16.0, 'c2': 12.0, 'j1': 12.0});
    expect(pot.fullAt, const Duration(minutes: 9));
    expect(rules.capturedAt(pot), const Duration(minutes: 24));
    expect(refusal(contribute(pot: pot)), ActionRefusal.potFull);
  });

  test('RELIC-29 another unit of the team resumes a capture its first '
      'contributor left', () {
    final first = done(contribute()).pot;
    final resumed = done(contribute(unit: 'jeep', unitId: 'j1', pot: first))
        .pot;

    expect(resumed.contributions, {'c1': 4.0, 'j1': 4.0});
  });

  test('RELIC-05 a unit outside the radius cannot add', () {
    expect(
      refusal(contribute(insideRadius: false)),
      ActionRefusal.outsideRadius,
    );
  });

  test('RELIC-06 a capture is blocked while an enemy is in the radius', () {
    expect(
      refusal(contribute(occupants: const [_friend, _enemy])),
      ActionRefusal.enemyInRadius,
    );
  });

  test('RELIC-07 every unit inside counts, whatever its state', () {
    for (final presence in Presence.values) {
      expect(
        CaptureRules.enemyInRadius([
          _friend,
          RadiusOccupant(team: 'blue', presence: presence),
        ], _team),
        isTrue,
        reason: presence.name,
      );
    }
    expect(CaptureRules.enemyInRadius(const [_friend], _team), isFalse);
  });

  test('RELIC-08 COMBAT-09 an enemy entering the radius empties a running '
      'capture, progress and pot', () {
    const full = CapturePot(
      team: _team,
      contributions: {'c1': 40},
      fullAt: Duration(minutes: 1),
    );
    final lost = rules.withOccupants(full, const [_friend, _enemy]);

    expect(lost.ap, 0);
    expect(lost.fullAt, isNull);
    expect(lost.team, _team);
    expect(rules.withOccupants(full, const [_friend]), same(full));
  });

  test('decision 176 a waiting pot empties when an enemy enters, even with '
      'no unit of its team inside', () {
    const waiting = CapturePot(team: _team, contributions: {'c1': 8});

    expect(rules.withOccupants(waiting, const [_enemy]).ap, 0);
  });

  test('UNIT-38 a unit that does not list capture cannot add', () {
    expect(refusal(contribute(unit: 'radio')), ActionRefusal.notInActions);
  });

  test('COMBAT-06 a contribution waits until the unit has the AP', () {
    final added = done(contribute(pool: _pool(1)));

    expect(added.at, const Duration(hours: 3));
  });

  test('refuses a contribution that costs more than the pool can hold', () {
    expect(
      refusal(contribute(pool: _pool(3, max: 3))),
      ActionRefusal.costAboveApMax,
    );
  });

  test('RELIC-09 capture duration, pot, contribution and radius are battle '
      'settings', () {
    final settings = parsePlanData().battle.capture;
    final raw =
        (loadYaml(readPlanData('battle.yaml')) as Map)['capture'] as Map;

    expect(settings.durationS, raw['duration_s']);
    expect(settings.potAp, raw['pot_ap']);
    expect(settings.contributionAp, raw['contribution_ap']);
    expect(settings.radiusM, raw['radius_m']);
  });
}
