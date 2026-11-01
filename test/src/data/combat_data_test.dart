import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

void main() {
  group(CombatData, () {
    late CombatData combat;

    setUp(() {
      combat = CombatData.parse(readFixture('combat.yaml'));
    });

    test('COMBAT-22 reads the version and the armor types', () {
      expect(combat.version, 4);
      expect(combat.armorTypes, [
        'infantry',
        'light_vehicle',
        'heavy_vehicle',
        'structure',
      ]);
    });

    test('COMBAT-20 reads a direct-fire weapon type', () {
      final rifle = combat.weaponTypes['rifle']!;

      expect(rifle.id, 'rifle');
      expect(rifle.baseDamage, 10);
      expect(rifle.rangeM, 300);
      expect(rifle.apPerShot, 2);
      expect(rifle.baseAccuracy, 0.6);
      expect(rifle.rateOfFireRpm, 30);
      expect(rifle.magazineCapacity, 8);
      expect(rifle.reloadTimeS, 2);
      expect(rifle.unloadTimeS, 1);
      expect(rifle.moveWhileLoaded, isTrue);
      expect(rifle.projectileSpeedMps, 800);
      expect(rifle.airborneFactor, 0.25);
      expect(rifle.splashRadiusM, isNull);
      expect(rifle.deformsTerrain, isFalse);
      expect(rifle.indirectFire, isFalse);
      expect(rifle.neverMisses, isFalse);
    });

    test('COMBAT-20 reads indirect fire and a weapon that never misses', () {
      final cannon = combat.weaponTypes['cannon']!;
      final charge = combat.weaponTypes['charge']!;

      expect(cannon.indirectFire, isTrue);
      expect(cannon.deformsTerrain, isTrue);
      expect(cannon.splashRadiusM, 6);
      expect(cannon.projectileSpeedMps, isNull);
      expect(charge.neverMisses, isTrue);
      expect(charge.baseAccuracy, isNull);
    });

    test('COMBAT-23 reads the damage table', () {
      expect(combat.multipliers['cannon'], {
        'infantry': 1.0,
        'light_vehicle': 1.0,
        'heavy_vehicle': 0.75,
        'structure': 1.5,
      });
    });

    test('reads splash, missed shots, friendly fire and transports', () {
      expect(combat.splash.falloff, 'linear');
      expect(combat.splash.damageFactorAtEdge, 0.25);
      expect(combat.missScatterMaxM, 80);
      expect(combat.friendlyFire.enabled, isTrue);
      expect(combat.friendlyFire.damageFactor, 0.5);
      expect(combat.transport.carriedDamageShare, 0.2);
      expect(combat.transport.ejectionDamageShareOfMaxHp, 0.4);
    });

    test('COMBAT-50 reads the morale values', () {
      final morale = combat.morale;

      expect(morale.min, 0);
      expect(morale.max, 80);
      expect(morale.base, 40);
      expect(morale.events.commanderAuraPerMin, 3);
      expect(morale.events.nearbyEnemyKilled, 4);
      expect(morale.events.nearbyAllyKilled, -6);
      expect(morale.events.outnumberedPerMin, -2);
      expect(morale.nearbyRadiusM, 40);
      expect(morale.outnumberedRatio, 2);
    });

    test('COMBAT-50 rejects a morale range without exactly two numbers', () {
      final text = readFixture('combat.yaml', {
        'range: [0, 80]': 'range: [0, 50, 80]',
      });

      expect(
        () => CombatData.parse(text),
        throwsDataError('combat.yaml', 'morale.range', [
          0.0,
          50.0,
          80.0,
        ], 'must hold two numbers: [min, max]'),
      );
    });

    test('reads the 0 HP, prisoner and ammunition rules', () {
      expect(combat.zeroHp.k, 0.5);
      expect(combat.zeroHp.defectionShare, 0.25);
      expect(combat.zeroHp.onlyWhenFinalBlowBy, 'commander');
      expect(combat.zeroHp.target, 'enemy');
      expect(combat.zeroHp.neverSpared, ['commander', 'camp']);
      expect(combat.prisoners.heldIn, 'captor_prisoner_storage');
      expect(combat.prisoners.canEscape, isFalse);
      expect(combat.prisoners.ransomFee, 0.1);
      expect(combat.prisoners.atWarEnd, 'lost');
      expect(combat.ammo.unlimited, isTrue);
      expect(combat.ammo.reloadDiscardsRemaining, isTrue);
    });

    test('reads the hit chance factors', () {
      final hit = combat.hitChance;

      expect([hit.clampMin, hit.clampMax], [0.1, 0.9]);
      expect([hit.distanceAtZero, hit.distanceAtMaxRange], [1, 0.4]);
      expect([hit.coverNone, hit.coverPartial, hit.coverFull], [1, 0.6, 0]);
      expect(hit.sizeFactor['heavy_vehicle'], 1.25);
      expect([hit.speedPerMps, hit.speedMin], [0.03, 0.4]);
      expect(hit.indirectFactor, 0.6);
      expect([hit.moraleAt0, hit.moraleAt100], [0.8, 1.2]);
    });

    test('reads aim, dropped weapons and the weapon swap', () {
      expect(combat.aim.baseSpreadDeg, 3);
      expect(combat.aim.spreadReductionPerAttack, 0.02);
      expect(combat.aim.minSpreadDeg, 0.5);
      expect(combat.droppedWeapons.pickupAp, 4);
      expect(combat.droppedWeapons.despawnAfterS, 300);
      expect(combat.weaponSwapTimeS, 6);
    });

    test('reads what costs AP and what costs only time', () {
      expect(combat.ap.atZero, 'act_at_regen_rate');
      expect(combat.ap.costsAp, ['shot', 'move']);
      expect(combat.ap.timeOnly, ['reload', 'unload']);
    });

    test('COMBAT-10 reads the role action and push values', () {
      final actions = combat.actions;
      final push = combat.push;

      expect(actions.heal.instant, isTrue);
      expect(actions.heal.targets, 'friendly_except_hq');
      expect(actions.repair.ap, 9);
      expect(actions.repair.durationS, 12);
      expect(actions.repair.hpRestored, 40);
      expect(actions.repair.targets, 'friendly_except_hq');
      expect(actions.capture.settings, 'data/battle.yaml');
      expect(actions.capture.progressOwner, 'team');
      expect(actions.interruption.apRefund, isFalse);
      expect(actions.interruption.progressKept, isTrue);
      expect(actions.interruption.resumeCost, 'proportional_to_remaining');
      expect(actions.interruption.captureProgressKept, isFalse);
      expect(push.speedMPerH, 4);
      expect(push.potApPerM, 8);
      expect(push.contributionAp, 3);
      expect(push.minPushers, 6);
      expect(push.potEmpty, 'stops');
      expect(push.crushUnitsPerExtraPusher, 2);
      expect(push.crush, 'kills');
    });
  });
}
