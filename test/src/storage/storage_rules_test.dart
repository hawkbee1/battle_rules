import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

const _hour = Duration(hours: 1);
const _microsecond = Duration(microseconds: 1);

void main() {
  group('StorageRules on the fixtures', () {
    // Fixture storage: stored at once within 8 m, a recall takes 2 h,
    // deploying costs 6 AP, an enemy within 15 m blocks, the lock lasts
    // 30 min. Commander death: 20 % of unspent XP, half of ap_max, 10
    // morale. Morale 0 to 80; AP at most 20, 2 per hour.
    late GameData data;
    late StorageRules storage;

    setUp(() {
      data = parseFixtures();
      storage = StorageRules(battle: data.battle, morale: data.combat.morale);
    });

    UnitType type(String id) => data.units.unitTypes[id]!;

    ApPool pool(double value, {Duration at = Duration.zero}) =>
        ApPool(max: 20, recoveryPerHour: 2, value: value, updatedAt: at);

    StoreOrder store(
      UnitLocation location, {
      String unit = 'engineer',
      double distanceM = 100,
      bool carriesUnits = false,
      Duration now = Duration.zero,
    }) => storage.store(
      type: type(unit),
      location: location,
      distanceM: distanceM,
      carriesUnits: carriesUnits,
      now: now,
    );

    StoreRefusal? storeRefusal(StoreOrder order) => switch (order) {
      StoreRefused(:final reason) => reason,
      _ => null,
    };

    DeployOrder deploy({
      UnitLocation location = const Stored(),
      ApPool? from,
      Duration now = Duration.zero,
      double? nearestEnemyM,
      Duration? lockedUntil,
    }) => storage.deploy(
      location: location,
      pool: from ?? pool(20),
      now: now,
      nearestEnemyM: nearestEnemyM,
      lockedUntil: lockedUntil,
    );

    DeployRefusal? deployRefusal(DeployOrder order) => switch (order) {
      DeployRefused(:final reason) => reason,
      DeployStarts() => null,
    };

    test('HQ-27 HQ-28 HQ-38 HQ-41 ECO-07 HQ-46 the portal is the guild camp, '
        'or the HQ without a guild or a camp', () {
      expect(
        storage.placeOf(inGuild: true, guildHasCamp: true),
        StoragePlace.guildCamp,
      );
      expect(
        storage.placeOf(inGuild: true, guildHasCamp: false),
        StoragePlace.hq,
      );
      expect(
        storage.placeOf(inGuild: false, guildHasCamp: false),
        StoragePlace.hq,
      );
    });

    test('HQ-13 HQ-31 UNIT-29 a unit within store_radius_m is stored at once, '
        'carried or not, whether the HQ moves or not', () {
      expect(store(const Deployed(), distanceM: 8), isA<StoredAtOnce>());
      expect(store(const Carried('boat-1'), distanceM: 3), isA<StoredAtOnce>());
    });

    test('HQ-32 elsewhere a recall takes recall_s; the unit stays on the '
        'field', () {
      final order = store(const Deployed(), distanceM: 8.1, now: _hour);

      final location = (order as RecallStarted).location;
      expect(location, isA<Deployed>());
      expect(location.recallDoneAt, _hour * 3);
      expect(location.onField, isTrue);
    });

    test('HQ-32 nothing stops a recall: it ends in storage at its time, '
        'carried or set down', () {
      final recalled = (store(
        const Carried('boat-1'),
        distanceM: 500,
      ) as RecallStarted).location;
      final setDown = (recalled as Carried).setDown();

      expect(recalled.at(_hour * 2 - _microsecond), same(recalled));
      expect(setDown.recallDoneAt, _hour * 2);
      expect(setDown.at(_hour * 2), isA<Stored>());
      expect(recalled.at(_hour * 3), isA<Stored>());
      expect(const Deployed().at(_hour * 100), isA<Deployed>());
    });

    test('HQ-31 a recalled unit that reaches its storage place is stored at '
        'once; it is not recalled twice', () {
      const recalled = Deployed(recallDoneAt: Duration(hours: 2));

      expect(store(recalled, distanceM: 5), isA<StoredAtOnce>());
      expect(
        storeRefusal(store(recalled, distanceM: 50)),
        StoreRefusal.alreadyRecalled,
      );
    });

    test('HQ-30 HQ-47 UNIT-42 the guild camp is never stored', () {
      expect(
        storeRefusal(store(const Deployed(), unit: 'camp', distanceM: 0)),
        StoreRefusal.neverStored,
      );
    });

    test('HQ-49 decision 206 a loaded transport is neither stored nor '
        'recalled, and a recalled one takes no passengers', () {
      expect(
        storeRefusal(
          store(
            const Deployed(),
            unit: 'boat',
            distanceM: 2,
            carriesUnits: true,
          ),
        ),
        StoreRefusal.carriesUnits,
      );
      final recalled =
          (store(const Deployed(), unit: 'boat') as RecallStarted).location;

      expect(const Deployed().takesPassengers, isTrue);
      expect(recalled.takesPassengers, isFalse);
    });

    test('only a unit on the field is stored or recalled', () {
      expect(storeRefusal(store(const Stored())), StoreRefusal.notOnField);
      expect(
        storeRefusal(store(const Prisoner('enemy'))),
        StoreRefusal.notOnField,
      );
    });

    test('HQ-29 UNIT-37 COMBAT-43 stored units and prisoners are off the '
        'field: never seen nor attacked', () {
      expect(const Deployed().onField, isTrue);
      expect(const Carried('boat-1').onField, isTrue);
      expect(const Stored().onField, isFalse);
      expect(const Prisoner('enemy').onField, isFalse);
    });

    test('COMBAT-51 a radio is stored like any unit', () {
      expect(
        store(const Deployed(), unit: 'radio', distanceM: 1),
        isA<StoredAtOnce>(),
      );
    });

    test('HQ-33 deploying costs deploy_ap; the unit is then on the field', () {
      final order = deploy(from: pool(20), now: _hour) as DeployStarts;

      expect(order.at, _hour);
      expect(order.pool.apAt(_hour), 14);
    });

    test('HQ-34 COMBAT-06 a stored unit short of AP deploys once it has '
        'recovered them', () {
      final order = deploy(from: pool(2)) as DeployStarts;

      // 4 AP missing at 2 AP per hour.
      expect(order.at, _hour * 2);
      expect(order.pool.apAt(_hour * 2), 0);
    });

    test('HQ-33 a deployment above the AP maximum is refused', () {
      expect(
        deployRefusal(
          deploy(
            from: ApPool(
              max: 5,
              recoveryPerHour: 1,
              value: 5,
              updatedAt: Duration.zero,
            ),
          ),
        ),
        DeployRefusal.costAboveApMax,
      );
    });

    test('only a stored unit deploys', () {
      expect(
        deployRefusal(deploy(location: const Deployed())),
        DeployRefusal.notStored,
      );
      expect(
        deployRefusal(deploy(location: const Prisoner('enemy'))),
        DeployRefusal.notStored,
      );
    });

    test('HQ-36 HQ-46 decision 147 an enemy within deploy_block_radius_m '
        'blocks deployment and arrival', () {
      expect(storage.blocks(null), isFalse);
      expect(storage.blocks(15), isTrue);
      expect(storage.blocks(15.1), isFalse);
      expect(
        deployRefusal(deploy(nearestEnemyM: 15)),
        DeployRefusal.blockedByEnemy,
      );
      expect(deployRefusal(deploy(nearestEnemyM: 15.1)), isNull);
    });

    test('HQ-35 a locked section deploys once its lock ends', () {
      const until = Duration(minutes: 30);

      expect(storage.isLocked(lockedUntil: null, now: Duration.zero), isFalse);
      expect(
        deployRefusal(deploy(lockedUntil: until, now: until - _microsecond)),
        DeployRefusal.sectionLocked,
      );
      expect(deployRefusal(deploy(lockedUntil: until, now: until)), isNull);
    });

    test('HQ-35 decision 120 a storage that leaves no unit on the field '
        'starts the lock', () {
      Duration? lockWith(UnitLocation engineer) => storage.lockAfter(
        at: _hour,
        units: [
          (type('commander'), const Stored()),
          (type('engineer'), engineer),
        ],
        byCommanderDeath: false,
      );

      expect(lockWith(const Stored()), _hour + const Duration(minutes: 30));
      expect(lockWith(const Carried('boat-1')), isNull);
    });

    test('decision 204 the lock runs from the death, capture or defection of '
        'the last unit on the field', () {
      // The medic was the last on the field: dead or defected, it is gone;
      // taken prisoner, its section cannot store it.
      for (final units in [
        [(type('commander'), const Stored())],
        [
          (type('commander'), const Stored()),
          (type('medic'), const Prisoner('enemy')),
        ],
      ]) {
        expect(
          storage.lockAfter(
            at: _hour * 5,
            units: units,
            byCommanderDeath: false,
          ),
          _hour * 5 + const Duration(minutes: 30),
        );
      }
    });

    test('decision 204 HQ-30 the guild camp on the field does not hold the '
        'lock off', () {
      expect(
        storage.lockAfter(
          at: Duration.zero,
          units: [
            (type('commander'), const Stored()),
            (type('camp'), const Deployed()),
          ],
          byCommanderDeath: false,
        ),
        const Duration(minutes: 30),
      );
    });

    test("decision 125 a storage forced by the commander's death never "
        'starts the lock', () {
      expect(
        storage.lockAfter(
          at: _hour,
          units: [(type('commander'), const Stored())],
          byCommanderDeath: true,
        ),
        isNull,
      );
    });

    test("UNIT-29 the commander's death stores his units on the field, "
        'carried ones included, with the AP and morale losses', () {
      for (final location in [const Deployed(), const Carried('jeep-2')]) {
        final after = storage.atCommanderDeath(
          type: type('engineer'),
          location: location,
          pool: pool(16),
          morale: 30,
          at: _hour,
        );

        expect(after.location, isA<Stored>());
        // 16 + 2 recovered, minus half of the 20 AP maximum.
        expect(after.pool.apAt(_hour), 8);
        expect(after.morale, 20);
      }
    });

    test('UNIT-29 the losses stop at 0 AP and at the lowest morale', () {
      final after = storage.atCommanderDeath(
        type: type('scout'),
        location: const Deployed(),
        pool: pool(4),
        morale: 5,
        at: Duration.zero,
      );

      expect(after.pool.apAt(Duration.zero), 0);
      expect(after.morale, 0);
    });

    test('UNIT-29 HQ-30 units already stored, prisoners and the guild camp '
        'stay as they are', () {
      final ap = pool(12);
      for (final (unit, location) in [
        ('engineer', const Stored()),
        ('medic', const Prisoner('enemy')),
        ('camp', const Deployed()),
      ]) {
        final after = storage.atCommanderDeath(
          type: type(unit),
          location: location,
          pool: ap,
          morale: 30,
          at: _hour,
        );

        expect(after.location, same(location));
        expect(after.pool, same(ap));
        expect(after.morale, 30);
      }
    });

    test('decision 206 the units of other sections his transports carry are '
        'set down where they are', () {
      const passenger = Carried('boat-1');

      expect(passenger.setDown(), isA<Deployed>());
      expect(passenger.setDown().recallDoneAt, isNull);
    });

    test('UNIT-28 UNIT-29 decision 207 the commander resurrects at once in '
        'storage, with full HP, the losses and less XP', () {
      final resurrected = storage.resurrect(
        commander: type('commander'),
        pool: pool(20),
        morale: 40,
        xp: const UnitXp(earned: 500, unspent: 100),
        at: _hour,
      );

      expect(resurrected.condition.location, isA<Stored>());
      expect(resurrected.condition.pool.apAt(_hour), 10);
      expect(resurrected.condition.morale, 30);
      expect(resurrected.health.current, 100);
      expect(resurrected.health.max, 100);
      // 20 % of his 100 unspent XP, from his earned XP too.
      expect(resurrected.xp.unspent, 80);
      expect(resurrected.xp.earned, 480);
    });

    test("HQ-19 HQ-20 decision 208 an eliminated team's units on the field "
        'are stored, its guild camp too; stored ones and prisoners stay', () {
      expect(storage.atElimination(const Deployed()), isA<Stored>());
      expect(storage.atElimination(const Carried('boat-1')), isA<Stored>());
      const stored = Stored();
      const prisoner = Prisoner('enemy');
      expect(storage.atElimination(stored), same(stored));
      expect(storage.atElimination(prisoner), same(prisoner));
    });

    test('COMBAT-36 a unit whose death is final never resurrects', () {
      expect(
        () => storage.resurrect(
          commander: type('engineer'),
          pool: pool(20),
          morale: 40,
          xp: const UnitXp(),
          at: Duration.zero,
        ),
        throwsArgumentError,
      );
    });
  });

  group('StorageRules on the plan data', () {
    // Plan storage: at once within 10 m, a recall takes 6 h, deploying
    // costs 10 AP, an enemy within 20 m blocks, the lock lasts 24 h.
    // Commander death: 25 % of unspent XP, all AP, 20 morale.
    late GameData data;
    late StorageRules storage;

    setUp(() {
      data = parsePlanData();
      storage = StorageRules(battle: data.battle, morale: data.combat.morale);
    });

    UnitType type(String id) => data.units.unitTypes[id]!;

    ApPool full(Duration at) =>
        ApPool.full(max: 30, recoveryPerHour: 1, at: at);

    test('HQ-31 storing at 10 m is at once; at 10.5 m it is a recall', () {
      StoreOrder at(double distanceM) => storage.store(
        type: type('soldier'),
        location: const Deployed(),
        distanceM: distanceM,
        carriesUnits: false,
        now: Duration.zero,
      );

      expect(at(10), isA<StoredAtOnce>());
      expect(at(10.5), isA<RecallStarted>());
    });

    test('HQ-32 a recall completes after 6 hours while the unit is under '
        'fire', () {
      final soldier = type('soldier');
      final recalled = (storage.store(
        type: soldier,
        location: const Deployed(),
        distanceM: 300,
        carriesUnits: false,
        now: Duration.zero,
      ) as RecallStarted).location;
      final rifle = data.combat.weaponTypes['rifle']!;
      final hit = Damage(data.combat)
          .hit(rifle, DamageTarget(armorType: soldier.armorType));
      var health = Health.full(soldier.stats.hp);

      // Hit every hour: it keeps its recall and is stored at 6 hours.
      for (var hour = 1; hour < 6; hour++) {
        health = health.damaged(hit);
        expect(recalled.at(_hour * hour), same(recalled));
      }

      expect(health.isZero, isFalse);
      expect(recalled.at(_hour * 6 - _microsecond), same(recalled));
      expect(recalled.at(_hour * 6), isA<Stored>());
    });

    test('HQ-32 decision 204 a unit killed during its recall dies; the last '
        'on the field, it starts the lock at its death', () {
      final soldier = type('soldier');
      final health = Health.full(soldier.stats.hp).damaged(soldier.stats.hp);

      expect(health.isZero, isTrue);
      expect(
        storage.lockAfter(
          at: _hour * 3,
          units: [(type('commander'), const Stored())],
          byCommanderDeath: false,
        ),
        _hour * 27,
      );
    });

    test('HQ-36 HQ-39 a deployment blocked by an enemy at 20 m, with no '
        'fallback to the HQ', () {
      DeployOrder deploy(double nearestEnemyM) => storage.deploy(
        location: const Stored(),
        pool: full(Duration.zero),
        now: Duration.zero,
        nearestEnemyM: nearestEnemyM,
        lockedUntil: null,
      );

      expect(
        storage.placeOf(inGuild: true, guildHasCamp: true),
        StoragePlace.guildCamp,
      );
      expect(
        (deploy(20) as DeployRefused).reason,
        DeployRefusal.blockedByEnemy,
      );
      expect(deploy(20.5), isA<DeployStarts>());
    });

    test('HQ-35 the 24-hour lock after a full storage by choice', () {
      final lockedUntil = storage.lockAfter(
        at: _hour * 2,
        units: [
          (type('commander'), const Stored()),
          (type('soldier'), const Stored()),
        ],
        byCommanderDeath: false,
      );
      DeployOrder deployAt(Duration now) => storage.deploy(
        location: const Stored(),
        pool: full(now),
        now: now,
        nearestEnemyM: null,
        lockedUntil: lockedUntil,
      );

      expect(lockedUntil, _hour * 26);
      expect(
        (deployAt(_hour * 26 - _microsecond) as DeployRefused).reason,
        DeployRefusal.sectionLocked,
      );
      expect((deployAt(_hour * 26) as DeployStarts).at, _hour * 26);
    });

    test("decision 125 no lock after a commander's death: each unit deploys "
        'again once it has its 10 AP', () {
      final resurrected = storage.resurrect(
        commander: type('commander'),
        pool: full(Duration.zero),
        morale: 50,
        xp: const UnitXp(earned: 1000, unspent: 400),
        at: _hour,
      );
      final lockedUntil = storage.lockAfter(
        at: _hour,
        units: [(type('commander'), resurrected.condition.location)],
        byCommanderDeath: true,
      );
      final order = storage.deploy(
        location: resurrected.condition.location,
        pool: resurrected.condition.pool,
        now: _hour,
        nearestEnemyM: null,
        lockedUntil: lockedUntil,
      ) as DeployStarts;

      expect(lockedUntil, isNull);
      // ap_loss_share 1.0 leaves 0 AP, back at 1 AP per hour.
      expect(order.at, _hour * 11);
      expect(resurrected.condition.morale, 30);
      expect(resurrected.xp.unspent, 300);
      expect(resurrected.xp.earned, 900);
    });

    test("UNIT-29 a commander's death with a carried unit in the section", () {
      // His soldier is on the field, his medic in another section's truck,
      // his engineer stored, his truck carries another section's scout.
      final section = {
        'soldier': ('soldier', const Deployed() as UnitLocation),
        'medic': ('medic', const Carried('their-truck')),
        'engineer': ('engineer', const Stored()),
        'truck': ('truck', const Deployed()),
      };
      final after = {
        for (final MapEntry(:key, value: (unit, location)) in section.entries)
          key: storage
              .atCommanderDeath(
                type: type(unit),
                location: location,
                pool: full(Duration.zero),
                morale: 50,
                at: _hour,
              )
              .location,
      };
      const theirScout = Carried('truck');

      expect(after.values, everyElement(isA<Stored>()));
      expect(after['engineer'], same(section['engineer']!.$2));
      expect(theirScout.setDown(), isA<Deployed>());
    });
  });
}
