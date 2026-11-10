import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

Duration _seconds(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

/// A pool with [ap] AP at time 0, recovering 1 AP per hour.
ApPool _pool(double ap, {double max = 1000}) =>
    ApPool(max: max, recoveryDelayS: 3600, value: ap, updatedAt: Duration.zero);

WeaponDone _done(WeaponResult result) => result as WeaponDone;

WeaponRefusal _refusal(WeaponResult result) => (result as WeaponRefused).reason;

void main() {
  late CombatData combat;
  late Armory armory;
  late UnitsData units;
  late WeaponType rifle;
  late WeaponType cannon;

  setUp(() {
    combat = CombatData.parse(readFixture('combat.yaml'));
    armory = Armory(combat);
    units = UnitsData.parse(readFixture('units.yaml'));
    rifle = combat.weaponTypes['rifle']!;
    cannon = combat.weaponTypes['cannon']!;
  });

  group('the current plan data', () {
    late GameData data;
    late Armory planArmory;

    setUpAll(() {
      data = parsePlanData();
      planArmory = Armory(data.combat);
    });

    test('COMBAT-27 a new unit comes with its default weapon, ready', () {
      final soldier = data.units.unitTypes['soldier']!;
      final state = WeaponState.forNewUnit(soldier, data.combat);

      expect(state.weapon?.id, soldier.weapons.defaultWeapon);
      expect(state.loaded, isTrue);
      expect(state.rounds, state.weapon!.magazineCapacity);
      expect(
        WeaponState.forNewUnit(
          data.units.unitTypes['radio']!,
          data.combat,
        ).weapon,
        isNull,
      );
    });

    test('UNIT-03 every unit type starts with one weapon, its default, '
        'from its allowed list', () {
      for (final unit in data.units.unitTypes.values) {
        final weapon = WeaponState.forNewUnit(unit, data.combat).weapon;

        expect(weapon?.id, unit.weapons.defaultWeapon, reason: unit.id);
        if (weapon != null) {
          expect(unit.weapons.allowed, contains(weapon.id), reason: unit.id);
        }
      }
    });

    test('COMBAT-32 a machine gun empties its magazine at its rate of fire, '
        'then needs a reload', () {
      final gun = data.combat.weaponTypes['machine_gun']!;
      final interval = _seconds(60 / gun.rateOfFireRpm);
      var state = WeaponState.ready(gun);
      var pool = _pool(1000);
      final shotTimes = <Duration>[];
      for (var shot = 0; shot < gun.magazineCapacity; shot++) {
        final fired = _done(
          planArmory.fire(state: state, pool: pool, now: Duration.zero),
        );
        shotTimes.add(fired.at);
        (state, pool) = (fired.state, fired.pool);
      }

      expect(shotTimes.first, Duration.zero);
      expect(shotTimes.last, interval * (gun.magazineCapacity - 1));
      expect(
        _refusal(planArmory.fire(state: state, pool: pool, now: Duration.zero)),
        WeaponRefusal.emptyMagazine,
      );
      final reloaded = _done(
        planArmory.reload(state: state, pool: pool, now: shotTimes.last),
      );
      expect(reloaded.state.rounds, gun.magazineCapacity);
    });

    test('COMBAT-56 artillery fires once per reload, and must unload before '
        'moving', () {
      final artillery = data.units.unitTypes['artillery']!;
      final gun = data.combat.weaponTypes['artillery']!;
      final reloadTime = _seconds(gun.reloadTimeS);
      final unloadTime = _seconds(gun.unloadTimeS);
      var state = WeaponState.forNewUnit(artillery, data.combat);
      var pool = ApPool.full(
        max: artillery.stats.apMax,
        recoveryDelayS: data.battle.ap.recoveryDelayS,
        at: Duration.zero,
      );

      expect(state.canMoveAt(Duration.zero), isFalse);
      final first = _done(
        planArmory.fire(state: state, pool: pool, now: Duration.zero),
      );
      (state, pool) = (first.state, first.pool);
      expect(
        _refusal(planArmory.fire(state: state, pool: pool, now: Duration.zero)),
        WeaponRefusal.emptyMagazine,
      );
      final reload = _done(
        planArmory.reload(state: state, pool: pool, now: first.at),
      );
      final second = _done(
        planArmory.fire(state: reload.state, pool: pool, now: first.at),
      );
      expect(second.at - first.at, reloadTime);

      final unload = _done(
        planArmory.unload(
          state: second.state,
          pool: second.pool,
          now: second.at,
        ),
      );
      final done = unload.at + unloadTime;
      expect(
        unload.state.canMoveAt(done - const Duration(microseconds: 1)),
        isFalse,
      );
      expect(unload.state.canMoveAt(done), isTrue);
    });
  });

  group('fire', () {
    test('COMBAT-13 a unit without a weapon cannot attack', () {
      const unarmed = WeaponState.unarmed();

      expect(
        _refusal(
          armory.fire(state: unarmed, pool: _pool(10), now: Duration.zero),
        ),
        WeaponRefusal.noWeapon,
      );
      expect(
        _refusal(
          armory.reload(state: unarmed, pool: _pool(10), now: Duration.zero),
        ),
        WeaponRefusal.noWeapon,
      );
      expect(
        _refusal(
          armory.unload(state: unarmed, pool: _pool(10), now: Duration.zero),
        ),
        WeaponRefusal.noWeapon,
      );
      expect(unarmed.canMoveAt(Duration.zero), isTrue);
    });

    test('COMBAT-04 a shot costs ap_per_shot and waits for its AP', () {
      final fired = _done(
        armory.fire(
          state: WeaponState.ready(rifle),
          pool: _pool(0),
          now: Duration.zero,
        ),
      );

      // 2 AP at 1 AP per hour.
      expect(fired.at, const Duration(hours: 2));
      expect(fired.pool.value, 0);
      expect(fired.state.rounds, rifle.magazineCapacity - 1);
    });

    test('refuses a weapon without a magazine in', () {
      final unloaded = _done(
        armory.unload(
          state: WeaponState.ready(rifle),
          pool: _pool(10),
          now: Duration.zero,
        ),
      ).state;

      expect(
        _refusal(
          armory.fire(state: unloaded, pool: _pool(10), now: Duration.zero),
        ),
        WeaponRefusal.notLoaded,
      );
    });

    test('refuses a shot that costs more than the pool can hold', () {
      expect(
        _refusal(
          armory.fire(
            state: WeaponState.ready(cannon),
            pool: _pool(5, max: 10),
            now: Duration.zero,
          ),
        ),
        WeaponRefusal.costAboveApMax,
      );
    });
  });

  group('reload and unload', () {
    test('COMBAT-33 a reload gives a full magazine and discards the rest', () {
      var state = WeaponState.ready(rifle);
      var pool = _pool(100);
      for (var shot = 0; shot < 3; shot++) {
        final fired = _done(
          armory.fire(state: state, pool: pool, now: Duration.zero),
        );
        (state, pool) = (fired.state, fired.pool);
      }
      expect(state.rounds, rifle.magazineCapacity - 3);

      final reloaded = _done(
        armory.reload(
          state: state,
          pool: pool,
          now: const Duration(seconds: 10),
        ),
      );

      expect(reloaded.state.rounds, rifle.magazineCapacity);
      expect(reloaded.state.busyUntil, const Duration(seconds: 13));
    });

    test('COMBAT-05 reloading and unloading cost time, not AP', () {
      final pool = _pool(7);
      final reload = _done(
        armory.reload(
          state: WeaponState.ready(rifle),
          pool: pool,
          now: Duration.zero,
        ),
      );
      final unload = _done(
        armory.unload(state: reload.state, pool: pool, now: Duration.zero),
      );

      expect(reload.pool, same(pool));
      expect(unload.pool, same(pool));
      // The unload waits for the reload to end.
      expect(unload.at, const Duration(seconds: 3));
      expect(unload.state.busyUntil, const Duration(seconds: 4));
    });

    test('a shot waits for a reload to end', () {
      final reload = _done(
        armory.reload(
          state: WeaponState.ready(rifle),
          pool: _pool(10),
          now: Duration.zero,
        ),
      );
      final fired = _done(
        armory.fire(state: reload.state, pool: reload.pool, now: Duration.zero),
      );

      expect(fired.at, const Duration(seconds: 3));
    });
  });

  group('swap', () {
    late UnitType engineer;

    setUp(() {
      engineer = units.unitTypes['engineer']!;
    });

    WeaponResult swap({
      WeaponState? state,
      StoredWeapons storage = const StoredWeapons(['charge']),
      String weaponId = 'charge',
      bool atStorage = true,
    }) => armory.swap(
      unit: engineer,
      state: state ?? WeaponState.ready(rifle),
      pool: _pool(5),
      storage: storage,
      weaponId: weaponId,
      atStorage: atStorage,
      now: const Duration(seconds: 1),
    );

    test('UNIT-04 decision 151 swaps a stored weapon for the one in the '
        'slot', () {
      final swapped = _done(swap());

      expect(swapped.state.weapon?.id, 'charge');
      expect(swapped.state.loaded, isFalse);
      expect(swapped.storage?.weapons, ['rifle']);
      expect(swapped.at, const Duration(seconds: 1));
    });

    test('COMBAT-05 a swap takes weapon_swap.time_s and no AP', () {
      final swapped = _done(swap());

      expect(swapped.state.busyUntil, const Duration(seconds: 7));
      expect(swapped.pool.value, 5);
    });

    test('COMBAT-28 swaps only at storage', () {
      expect(_refusal(swap(atStorage: false)), WeaponRefusal.notAtStorage);
    });

    test('COMBAT-26 takes only a weapon type the unit may use', () {
      expect(
        _refusal(
          swap(storage: const StoredWeapons(['cannon']), weaponId: 'cannon'),
        ),
        WeaponRefusal.notAllowed,
      );
    });

    test('decision 151 takes only a weapon the storage holds', () {
      expect(
        _refusal(swap(storage: const StoredWeapons(['rifle']))),
        WeaponRefusal.notInStorage,
      );
    });

    test('equips an empty slot without storing anything', () {
      final swapped = _done(
        swap(
          state: const WeaponState.unarmed(),
          storage: const StoredWeapons(['charge', 'charge']),
        ),
      );

      expect(swapped.storage?.weapons, ['charge']);
      expect(swapped.state.weapon?.id, 'charge');
    });
  });

  group('dropped weapons', () {
    late UnitType commander;

    setUp(() {
      commander = units.unitTypes['commander']!;
    });

    test('COMBAT-29 a killed unit drops its weapon; nothing when unarmed', () {
      final dropped = armory.drop(
        WeaponState.ready(rifle),
        const Duration(minutes: 1),
      )!;

      expect(dropped.weapon, same(rifle));
      expect(armory.drop(const WeaponState.unarmed(), Duration.zero), isNull);
    });

    test('COMBAT-31 a dropped weapon vanishes after despawn_after_s', () {
      final dropped = armory.drop(WeaponState.ready(rifle), Duration.zero)!;

      expect(dropped.goneAt, const Duration(minutes: 5));
      expect(dropped.isGoneAt(const Duration(minutes: 4)), isFalse);
      expect(dropped.isGoneAt(const Duration(minutes: 5)), isTrue);
      expect(
        _refusal(
          armory.pickUp(
            unit: commander,
            state: const WeaponState.unarmed(),
            pool: _pool(10),
            dropped: dropped,
            now: const Duration(minutes: 5),
          ),
        ),
        WeaponRefusal.weaponGone,
      );
    });

    test('COMBAT-30 UNIT-03 a unit picks up a weapon for pickup_ap and drops '
        'its own in its place', () {
      final dropped = DroppedWeapon(
        weapon: rifle,
        goneAt: const Duration(hours: 1),
      );
      final engineer = units.unitTypes['engineer']!;
      final charge = combat.weaponTypes['charge']!;
      final picked = _done(
        armory.pickUp(
          unit: engineer,
          state: WeaponState.ready(charge),
          pool: _pool(10),
          dropped: dropped,
          now: const Duration(minutes: 2),
        ),
      );

      expect(picked.state.weapon, same(rifle));
      expect(picked.state.loaded, isFalse);
      // 10 AP and two minutes of recovery, less the pick-up.
      expect(
        picked.pool.value,
        closeTo(10 + 2 / 60 - combat.droppedWeapons.pickupAp, 1e-9),
      );
      expect(picked.dropped?.weapon, same(charge));
      expect(picked.dropped?.goneAt, const Duration(minutes: 7));
    });

    test('COMBAT-30 a unit cannot pick up a weapon type it may not use', () {
      final dropped = DroppedWeapon(
        weapon: cannon,
        goneAt: const Duration(hours: 1),
      );

      expect(
        _refusal(
          armory.pickUp(
            unit: commander,
            state: WeaponState.ready(rifle),
            pool: _pool(10),
            dropped: dropped,
            now: Duration.zero,
          ),
        ),
        WeaponRefusal.notAllowed,
      );
    });

    test('refuses a pick-up that costs more than the pool can hold', () {
      final dropped = DroppedWeapon(
        weapon: rifle,
        goneAt: const Duration(hours: 1),
      );

      expect(
        _refusal(
          armory.pickUp(
            unit: commander,
            state: const WeaponState.unarmed(),
            pool: _pool(1, max: 2),
            dropped: dropped,
            now: Duration.zero,
          ),
        ),
        WeaponRefusal.costAboveApMax,
      );
    });
  });

  test('StoredWeapons adds and removes one weapon at a time', () {
    const storage = StoredWeapons(['rifle', 'rifle']);

    expect(storage.removed('rifle').weapons, ['rifle']);
    expect(storage.added('charge').weapons, ['rifle', 'rifle', 'charge']);
    expect(() => storage.added('x').weapons.add('y'), throwsUnsupportedError);
  });
}
