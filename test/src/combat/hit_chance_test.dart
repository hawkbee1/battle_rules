import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixed_random.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/plan_data.dart';

void main() {
  late CombatData combat;
  late HitChance hitChance;
  late WeaponType rifle;
  late WeaponType cannon;

  setUp(() {
    combat = CombatData.parse(readFixture('combat.yaml'));
    hitChance = HitChance(combat);
    rifle = combat.weaponTypes['rifle']!;
    cannon = combat.weaponTypes['cannon']!;
  });

  /// The fixture chance with neutral factors: rifle, equal attack and
  /// defense, morale 40 of [0, 80], a light vehicle standing at 0 m in the
  /// open: 0.6.
  double chance({
    WeaponType? weapon,
    double attack = 10,
    double morale = 40,
    double defense = 10,
    String armor = 'light_vehicle',
    double speed = 0,
    double distance = 0,
    Cover cover = Cover.none,
  }) => hitChance.of(
    weapon: weapon ?? rifle,
    attack: attack,
    morale: morale,
    defense: defense,
    targetArmor: armor,
    targetSpeedMps: speed,
    distanceM: distance,
    cover: cover,
  );

  group('of', () {
    test('COMBAT-15 starts from the weapon base accuracy', () {
      expect(chance(), closeTo(0.6, 1e-9));
    });

    test('COMBAT-17 attack raises the chance', () {
      expect(chance(attack: 30), closeTo(0.72, 1e-9));
    });

    test('COMBAT-18 defense lowers the chance', () {
      expect(chance(defense: 30), closeTo(0.48, 1e-9));
    });

    test('COMBAT-15 distance lowers it linearly up to the weapon range', () {
      expect(chance(distance: 150), closeTo(0.42, 1e-9));
      expect(chance(distance: 300), closeTo(0.24, 1e-9));
      expect(chance(distance: 600), closeTo(0.24, 1e-9));
    });

    test('COMBAT-53 partial cover lowers the chance; full cover leaves the '
        'minimum', () {
      expect(chance(cover: Cover.partial), closeTo(0.36, 1e-9));
      expect(chance(cover: Cover.full), 0.1);
    });

    test('COMBAT-15 bigger targets are easier to hit', () {
      expect(chance(armor: 'heavy_vehicle'), closeTo(0.75, 1e-9));
      expect(chance(armor: 'infantry'), closeTo(0.45, 1e-9));
    });

    test('COMBAT-15 a fast target is harder to hit, down to the speed '
        'minimum', () {
      expect(chance(speed: 10), closeTo(0.42, 1e-9));
      expect(chance(speed: 30), closeTo(0.24, 1e-9));
    });

    test('COMBAT-49 the attacker morale scales the chance', () {
      expect(chance(morale: 0), closeTo(0.48, 1e-9));
      expect(chance(morale: 80), closeTo(0.72, 1e-9));
      expect(hitChance.moraleFactor(40), closeTo(1, 1e-9));
    });

    test('COMBAT-12 indirect fire has the indirect factor', () {
      // 0.3 × 0.6.
      expect(chance(weapon: cannon), closeTo(0.18, 1e-9));
    });

    test('COMBAT-15 the chance is clamped to [min, max]', () {
      expect(chance(attack: 100, defense: 0), 0.9);
      expect(chance(defense: 100, attack: 0), 0.1);
    });

    test('COMBAT-15 combines every factor', () {
      final combined = chance(
        attack: 20,
        defense: 5,
        morale: 60,
        armor: 'heavy_vehicle',
        speed: 5,
        distance: 100,
        cover: Cover.partial,
      );

      // 0.6 × 1.15 × 0.8 × 0.6 × 1.25 × 0.85 × 1.1.
      expect(
        combined,
        closeTo(0.6 * 1.15 * 0.8 * 0.6 * 1.25 * 0.85 * 1.1, 1e-9),
      );
    });

    test('rejects a weapon that never misses and an unknown armor type', () {
      expect(
        () => chance(weapon: combat.weaponTypes['charge']),
        throwsArgumentError,
      );
      expect(() => chance(armor: 'titanium'), throwsArgumentError);
    });

    test('COMBAT-19 attack and defense change the chance, never the '
        'damage', () {
      final damage = Damage(combat);
      const target = DamageTarget(armorType: 'light_vehicle');

      expect(chance(attack: 30), isNot(chance()));
      // Damage takes no attack or defense at all.
      expect(damage.hit(rifle, target), 5);
    });
  });

  group('roll', () {
    test('COMBAT-15 10,000 seeded rolls hit as often as the chance, within '
        '1 %', () {
      final data = parsePlanData();
      final planChance = HitChance(data.combat).of(
        weapon: data.combat.weaponTypes['rifle']!,
        attack: data.units.unitTypes['soldier']!.stats.attack,
        morale: data.combat.morale.base,
        defense: data.units.unitTypes['soldier']!.stats.defense,
        targetArmor: 'infantry',
        targetSpeedMps: 0,
        distanceM: 100,
      );
      final random = XorshiftRandom(7);
      var hits = 0;
      for (var roll = 0; roll < 10000; roll++) {
        if (HitChance.roll(planChance, random).hits) hits++;
      }

      expect(hits / 10000, closeTo(planChance, 0.01));
    });

    test('a roll below the chance hits; a miss measures how badly', () {
      final hit = HitChance.roll(0.5, FixedRandom([0.25]));
      final miss = HitChance.roll(0.5, FixedRandom([0.75]));

      expect(hit.hits, isTrue);
      expect(hit.missImportance, 0);
      expect(miss.hits, isFalse);
      expect(miss.missImportance, 0.5);
      expect(miss.roll, 0.75);
      expect(miss.chance, 0.5);
    });

    test('the seeded random draws the same numbers on every platform and '
        'release', () {
      final random = XorshiftRandom(1);

      expect(
        [for (var draw = 0; draw < 3; draw++) random.nextDouble()],
        [0.961217265327276, 0.9649285603562618, 0.412078295084913],
      );
    });

    test('the same seed gives the same rolls', () {
      final first = XorshiftRandom(3);
      final second = XorshiftRandom(3);

      expect(first.seed, 3);
      expect(
        [for (var i = 0; i < 5; i++) first.nextDouble()],
        [for (var i = 0; i < 5; i++) second.nextDouble()],
      );
    });

    test('a random resumed at its state draws what it would have drawn', () {
      final live = XorshiftRandom(5)..nextDouble();
      final resumed = XorshiftRandom.resume(seed: 5, state: live.state);

      expect(resumed.seed, 5);
      expect(resumed.state, live.state);
      expect(
        [for (var i = 0; i < 5; i++) resumed.nextDouble()],
        [for (var i = 0; i < 5; i++) live.nextDouble()],
      );
    });

    test('a random resumes only from four 32-bit words', () {
      expect(
        () => XorshiftRandom.resume(seed: 1, state: [1, 2, 3]),
        throwsArgumentError,
      );
      expect(
        () => XorshiftRandom.resume(seed: 1, state: [1, 2, 3, 4, 5]),
        throwsArgumentError,
      );
      expect(
        () => XorshiftRandom.resume(seed: 1, state: [1, 2, -3, 4]),
        throwsArgumentError,
      );
      expect(
        () => XorshiftRandom.resume(seed: 1, state: [1, 2, 3, 0x100000000]),
        throwsArgumentError,
      );
    });
  });

  group('indirect fire', () {
    test('COMBAT-12 artillery targets a position its section sees or a '
        'radio relays, within range', () {
      bool canTarget({
        WeaponType? weapon,
        double distance = 500,
        bool seen = false,
        bool relayed = false,
      }) => HitChance.canTargetPosition(
        weapon: weapon ?? cannon,
        distanceM: distance,
        seenBySection: seen,
        relayedByRadio: relayed,
      );

      expect(canTarget(seen: true), isTrue);
      expect(canTarget(relayed: true), isTrue);
      expect(canTarget(), isFalse);
      expect(canTarget(seen: true, distance: 901), isFalse);
      expect(canTarget(weapon: rifle, seen: true, distance: 100), isFalse);
    });

    test('decision 154 a hit lands on the aimed point', () {
      final landed = hitChance.landingPoint(
        weapon: cannon,
        artillery: Vec3.zero,
        aimed: const Vec3(500, 0, 3),
        roll: const HitRoll(roll: 0.1, chance: 0.5),
        random: FixedRandom([0.25]),
      );

      expect(landed.x, 500);
      expect(landed.z, 3);
    });

    test('decision 154 a miss lands max_m × its importance away, in a random '
        'direction', () {
      final landed = hitChance.landingPoint(
        weapon: cannon,
        artillery: Vec3.zero,
        aimed: const Vec3(500, 0, 3),
        roll: const HitRoll(roll: 0.75, chance: 0.5),
        random: FixedRandom([0.25]),
      );

      // A quarter turn: north of the aimed point, 80 × 0.5.
      expect(landed.x, closeTo(500, 1e-9));
      expect(landed.y, closeTo(40, 1e-9));
      expect(landed.z, 3);
    });

    test('decision 154 a miss beyond the range comes back to the range', () {
      final landed = hitChance.landingPoint(
        weapon: cannon,
        artillery: Vec3.zero,
        aimed: const Vec3(890, 0, 0),
        roll: const HitRoll(roll: 0.75, chance: 0.5),
        random: FixedRandom([0]),
      );

      expect(landed.x, closeTo(900, 1e-9));
      expect(landed.y, closeTo(0, 1e-9));
    });
  });
}
