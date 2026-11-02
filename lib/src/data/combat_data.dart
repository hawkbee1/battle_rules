import 'package:battle_rules/src/data/data_reader.dart';

/// The name of the combat data file in messages.
const combatFile = 'combat.yaml';

/// {@template combat_data}
/// The `combat.yaml` game data file: armor and weapon types, the damage
/// table, hit chance, morale, AP, role actions and push.
/// {@endtemplate}
final class CombatData {
  /// {@macro combat_data}
  const new({
    required this.version,
    required this.armorTypes,
    required this.weaponTypes,
    required this.multipliers,
    required this.splash,
    required this.missScatterMaxM,
    required this.friendlyFire,
    required this.transport,
    required this.morale,
    required this.zeroHp,
    required this.prisoners,
    required this.ammo,
    required this.hitChance,
    required this.aim,
    required this.droppedWeapons,
    required this.weaponSwapTimeS,
    required this.ap,
    required this.actions,
    required this.push,
  });

  /// Parses the text of `combat.yaml`. Checks types and required keys only;
  /// `GameData.parse` checks the rules between values.
  factory parse(String text) {
    final reader = DataReader.parse(combatFile, text);
    return CombatData(
      version: reader.integer('version'),
      armorTypes: reader.strings('armor_types'),
      weaponTypes: Map.unmodifiable({
        for (final MapEntry(:key, :value)
            in reader.map('weapon_types').maps().entries)
          key: _readWeaponType(key, value),
      }),
      multipliers: Map.unmodifiable({
        for (final MapEntry(:key, :value)
            in reader.map('multipliers').maps().entries)
          key: value.numberEntries(),
      }),
      splash: _readSplash(reader.map('splash')),
      missScatterMaxM: reader.map('miss_scatter').number('max_m'),
      friendlyFire: _readFriendlyFire(reader.map('friendly_fire')),
      transport: _readTransport(reader.map('transport')),
      morale: _readMorale(reader.map('morale')),
      zeroHp: _readZeroHp(reader.map('zero_hp')),
      prisoners: _readPrisoners(reader.map('prisoners')),
      ammo: _readAmmo(reader.map('ammo')),
      hitChance: _readHitChance(reader.map('hit_chance')),
      aim: _readAim(reader.map('aim')),
      droppedWeapons: _readDroppedWeapons(reader.map('dropped_weapons')),
      weaponSwapTimeS: reader.map('weapon_swap').number('time_s'),
      ap: _readApRules(reader.map('ap')),
      actions: _readRoleActions(reader.map('actions')),
      push: _readPush(reader.map('push')),
    );
  }

  /// The file's `version`.
  final int version;

  /// Every armor type (COMBAT-22).
  final List<String> armorTypes;

  /// Every weapon type, by id (`weapon_types`, COMBAT-20).
  final Map<String, WeaponType> weaponTypes;

  /// The damage table (COMBAT-23): `multipliers[weapon][armor]`.
  final Map<String, Map<String, double>> multipliers;

  /// Splash of bombard attacks (decision 136).
  final Splash splash;

  /// Farthest a missed artillery shot lands from the aimed point
  /// (`miss_scatter.max_m`, decision 154).
  final double missScatterMaxM;

  /// Friendly fire (`friendly_fire`).
  final FriendlyFire friendlyFire;

  /// Damage to units carried by a transport (decision 81).
  final TransportDamage transport;

  /// Morale values (COMBAT-50, decision 70).
  final MoraleRules morale;

  /// What happens at 0 HP after a commander's final blow (decisions 37f,
  /// 72).
  final ZeroHpRules zeroHp;

  /// Prisoners (decision 73).
  final PrisonerRules prisoners;

  /// Ammunition (decision 54).
  final AmmoRules ammo;

  /// Hit chance under orders and AI (decisions 58, 65).
  final HitChanceRules hitChance;

  /// First-person aim spread (decision 58).
  final AimRules aim;

  /// Dropped weapons (decisions 53, 63).
  final DroppedWeapons droppedWeapons;

  /// Seconds to swap a weapon at storage (`weapon_swap.time_s`).
  final double weaponSwapTimeS;

  /// What costs AP and what costs only time (`ap`).
  final ApRules ap;

  /// Role action values (COMBAT-10, decision 66).
  final RoleActions actions;

  /// Pushing a relic (COMBAT-10, decisions 171, 175).
  final PushRules push;
}

/// {@template weapon_type}
/// One weapon type of `combat.yaml` (`weapon_types`, decision 52).
/// {@endtemplate}
final class WeaponType {
  /// {@macro weapon_type}
  const new({
    required this.id,
    required this.baseDamage,
    required this.rangeM,
    required this.apPerShot,
    required this.baseAccuracy,
    required this.rateOfFireRpm,
    required this.magazineCapacity,
    required this.reloadTimeS,
    required this.unloadTimeS,
    required this.moveWhileLoaded,
    required this.projectileSpeedMps,
    required this.airborneFactor,
    required this.splashRadiusM,
    required this.deformsTerrain,
    required this.indirectFire,
    required this.neverMisses,
  });

  /// The weapon type's key in `weapon_types`, for example `rifle`.
  final String id;

  /// Damage before the armor multiplier.
  final double baseDamage;

  /// Range cap, in metres.
  final double rangeM;

  /// AP per shot.
  final double apPerShot;

  /// Starting hit chance under orders and AI; null for a weapon that never
  /// misses (decision 152).
  final double? baseAccuracy;

  /// Shots per minute while the magazine is not empty.
  final double rateOfFireRpm;

  /// Shots before a reload.
  final int magazineCapacity;

  /// Seconds to load a full magazine.
  final double reloadTimeS;

  /// Seconds to unload the weapon.
  final double unloadTimeS;

  /// Whether the unit can move with the weapon loaded.
  final bool moveWhileLoaded;

  /// Speed of a first-person shot, in metres per second (decision 183);
  /// null for indirect fire and a weapon that never misses.
  final double? projectileSpeedMps;

  /// Damage multiplier against a flying target (0: cannot hit it).
  final double airborneFactor;

  /// Splash radius of a bombard attack, in metres; null without splash.
  final double? splashRadiusM;

  /// Whether a hit deforms the terrain.
  final bool deformsTerrain;

  /// Whether it may target a ground position its section sees or a radio
  /// relays (decision 62).
  final bool indirectFire;

  /// Whether it goes off on the aimed point with no hit roll
  /// (decision 152).
  final bool neverMisses;
}

/// {@template splash}
/// Splash of bombard attacks (`splash`, decision 136).
/// {@endtemplate}
final class Splash {
  /// {@macro splash}
  const new({required this.falloff, required this.damageFactorAtEdge});

  /// How damage falls off with the distance, for example `linear`.
  final String falloff;

  /// Damage factor at the splash radius.
  final double damageFactorAtEdge;
}

/// {@template friendly_fire}
/// Friendly fire (`friendly_fire`).
/// {@endtemplate}
final class FriendlyFire {
  /// {@macro friendly_fire}
  const new({required this.enabled, required this.damageFactor});

  /// Whether shots hurt friends.
  final bool enabled;

  /// Damage factor on friends.
  final double damageFactor;
}

/// {@template transport_damage}
/// Damage to units carried by a transport (`transport`, decision 81).
/// {@endtemplate}
final class TransportDamage {
  /// {@macro transport_damage}
  const new({
    required this.carriedDamageShare,
    required this.ejectionDamageShareOfMaxHp,
  });

  /// Share of each hit on the transport that each carried unit takes.
  final double carriedDamageShare;

  /// Share of its maximum HP a carried unit loses when the transport is
  /// destroyed (decision 137).
  final double ejectionDamageShareOfMaxHp;
}

/// {@template morale_rules}
/// Morale values (`morale`, COMBAT-50, decision 70).
/// {@endtemplate}
final class MoraleRules {
  /// {@macro morale_rules}
  const new({
    required this.min,
    required this.max,
    required this.base,
    required this.events,
    required this.nearbyRadiusM,
    required this.outnumberedRatio,
  });

  /// Lowest morale (`range[0]`).
  final double min;

  /// Highest morale (`range[1]`).
  final double max;

  /// Morale of a newly bought unit.
  final double base;

  /// Morale change per event (`events`).
  final MoraleEvents events;

  /// Radius of "nearby" events, in metres.
  final double nearbyRadiusM;

  /// Local enemy to ally ratio above which a unit is outnumbered.
  final double outnumberedRatio;
}

/// {@template morale_events}
/// Morale change per event (`morale.events`).
/// {@endtemplate}
final class MoraleEvents {
  /// {@macro morale_events}
  const new({
    required this.commanderAuraPerMin,
    required this.nearbyEnemyKilled,
    required this.nearbyAllyKilled,
    required this.outnumberedPerMin,
  });

  /// Per minute inside its own commander's aura.
  final double commanderAuraPerMin;

  /// When a nearby enemy is killed.
  final double nearbyEnemyKilled;

  /// When a nearby ally is killed.
  final double nearbyAllyKilled;

  /// Per minute while outnumbered.
  final double outnumberedPerMin;
}

/// {@template zero_hp_rules}
/// What happens at 0 HP (`zero_hp`, decisions 37f, 72, 131, 149):
/// `p_spared = k × ((100 − morale)/100 + (1 − ap/ap_max)) / 2`.
/// {@endtemplate}
final class ZeroHpRules {
  /// {@macro zero_hp_rules}
  const new({
    required this.k,
    required this.defectionShare,
    required this.onlyWhenFinalBlowBy,
    required this.target,
    required this.neverSpared,
  });

  /// The factor k.
  final double k;

  /// Share of spared units that defect rather than become prisoners.
  final double defectionShare;

  /// Who must deal the final blow for a unit to be spared.
  final String onlyWhenFinalBlowBy;

  /// Which units can be spared, for example `enemy`.
  final String target;

  /// Unit types never spared.
  final List<String> neverSpared;
}

/// {@template prisoner_rules}
/// Prisoners (`prisoners`, decisions 73, 94).
/// {@endtemplate}
final class PrisonerRules {
  /// {@macro prisoner_rules}
  const new({
    required this.heldIn,
    required this.canEscape,
    required this.ransomFee,
    required this.atWarEnd,
  });

  /// Where prisoners are held.
  final String heldIn;

  /// Whether a prisoner can escape.
  final bool canEscape;

  /// Fee taken on a ransom.
  final double ransomFee;

  /// What happens to prisoners at the end of the war.
  final String atWarEnd;
}

/// {@template ammo_rules}
/// Ammunition (`ammo`, decision 54).
/// {@endtemplate}
final class AmmoRules {
  /// {@macro ammo_rules}
  const new({required this.unlimited, required this.reloadDiscardsRemaining});

  /// Whether ammunition is unlimited.
  final bool unlimited;

  /// Whether a reload discards the rounds left in the magazine.
  final bool reloadDiscardsRemaining;
}

/// {@template hit_chance_rules}
/// Hit chance under orders and AI (`hit_chance`, decisions 58, 65, 71).
/// {@endtemplate}
final class HitChanceRules {
  /// {@macro hit_chance_rules}
  const new({
    required this.clampMin,
    required this.clampMax,
    required this.distanceAtZero,
    required this.distanceAtMaxRange,
    required this.coverNone,
    required this.coverPartial,
    required this.coverFull,
    required this.sizeFactor,
    required this.speedPerMps,
    required this.speedMin,
    required this.indirectFactor,
    required this.moraleAt0,
    required this.moraleAt100,
  });

  /// Lowest hit chance (`clamp.min`).
  final double clampMin;

  /// Highest hit chance (`clamp.max`).
  final double clampMax;

  /// Distance factor at distance 0.
  final double distanceAtZero;

  /// Distance factor at the weapon's range.
  final double distanceAtMaxRange;

  /// Cover factor without cover.
  final double coverNone;

  /// Cover factor behind partial cover.
  final double coverPartial;

  /// Cover factor behind full cover.
  final double coverFull;

  /// Size factor by target armor type.
  final Map<String, double> sizeFactor;

  /// Speed factor removed per metre per second of target speed.
  final double speedPerMps;

  /// Lowest speed factor.
  final double speedMin;

  /// Factor of indirect fire.
  final double indirectFactor;

  /// Morale factor at attacker morale 0.
  final double moraleAt0;

  /// Morale factor at attacker morale 100.
  final double moraleAt100;
}

/// {@template aim_rules}
/// First-person aim spread (`aim`, decisions 58, 95).
/// {@endtemplate}
final class AimRules {
  /// {@macro aim_rules}
  const new({
    required this.baseSpreadDeg,
    required this.spreadReductionPerAttack,
    required this.minSpreadDeg,
  });

  /// Spread before attack and morale, in degrees.
  final double baseSpreadDeg;

  /// Share of the spread removed per attack point.
  final double spreadReductionPerAttack;

  /// Smallest spread, in degrees.
  final double minSpreadDeg;
}

/// {@template dropped_weapons}
/// Dropped weapons (`dropped_weapons`, decisions 53, 63).
/// {@endtemplate}
final class DroppedWeapons {
  /// {@macro dropped_weapons}
  const new({required this.pickupAp, required this.despawnAfterS});

  /// AP to pick up a dropped weapon.
  final double pickupAp;

  /// Seconds before a dropped weapon vanishes.
  final double despawnAfterS;
}

/// {@template ap_rules}
/// What costs AP and what costs only time (`ap`, decisions 55, 56, 68).
/// {@endtemplate}
final class ApRules {
  /// {@macro ap_rules}
  const new({
    required this.atZero,
    required this.costsAp,
    required this.timeOnly,
  });

  /// What a unit does at 0 AP, for example `act_at_regen_rate`.
  final String atZero;

  /// Kinds of action that cost AP.
  final List<String> costsAp;

  /// Kinds of action that cost only time.
  final List<String> timeOnly;
}

/// {@template role_actions}
/// Role action values (`actions`, COMBAT-10, decision 66).
/// {@endtemplate}
final class RoleActions {
  /// {@macro role_actions}
  const new({
    required this.heal,
    required this.repair,
    required this.capture,
    required this.interruption,
  });

  /// Healing; its AP and HP come from the healer's role.
  final HealAction heal;

  /// Repairing.
  final RepairAction repair;

  /// Capturing; its values are in `battle.yaml` `capture`.
  final CaptureAction capture;

  /// Interrupted actions (decisions 67, 97).
  final Interruption interruption;
}

/// {@template heal_action}
/// Healing (`actions.heal`, decisions 91, 139).
/// {@endtemplate}
final class HealAction {
  /// {@macro heal_action}
  const new({required this.instant, required this.targets});

  /// Whether healing is instant.
  final bool instant;

  /// Who can be healed.
  final String targets;
}

/// {@template repair_action}
/// Repairing (`actions.repair`, decisions 13, 139).
/// {@endtemplate}
final class RepairAction {
  /// {@macro repair_action}
  const new({
    required this.ap,
    required this.durationS,
    required this.hpRestored,
    required this.targets,
  });

  /// AP paid up front.
  final double ap;

  /// Seconds the repair takes.
  final double durationS;

  /// HP restored.
  final double hpRestored;

  /// What can be repaired.
  final String targets;
}

/// {@template capture_action}
/// Capturing (`actions.capture`, decisions 97, 140, 170, 173).
/// {@endtemplate}
final class CaptureAction {
  /// {@macro capture_action}
  const new({required this.settings, required this.progressOwner});

  /// Where the capture values live.
  final String settings;

  /// Who owns capture progress.
  final String progressOwner;
}

/// {@template interruption}
/// Interrupted actions (`actions.interruption`, decisions 67, 97).
/// {@endtemplate}
final class Interruption {
  /// {@macro interruption}
  const new({
    required this.apRefund,
    required this.progressKept,
    required this.resumeCost,
    required this.captureProgressKept,
  });

  /// Whether the AP paid come back.
  final bool apRefund;

  /// Whether the progress is kept.
  final bool progressKept;

  /// What resuming costs.
  final String resumeCost;

  /// Whether a capture keeps its progress.
  final bool captureProgressKept;
}

/// {@template push_rules}
/// Pushing a relic (`push`, decisions 98, 115, 138, 171, 175).
/// {@endtemplate}
final class PushRules {
  /// {@macro push_rules}
  const new({
    required this.speedMPerH,
    required this.potApPerM,
    required this.contributionAp,
    required this.minPushers,
    required this.potEmpty,
    required this.crushUnitsPerExtraPusher,
    required this.crush,
  });

  /// Speed of a pushed relic, in metres per hour.
  final double speedMPerH;

  /// AP the pot pays per metre on flat grass.
  final double potApPerM;

  /// AP a pusher adds to the pot per action.
  final double contributionAp;

  /// Fewest pushers for the relic to move.
  final int minPushers;

  /// What an empty pot does, for example `stops`.
  final String potEmpty;

  /// Units crushed per pusher above [minPushers].
  final int crushUnitsPerExtraPusher;

  /// What crushing does, for example `kills`.
  final String crush;
}

WeaponType _readWeaponType(String id, DataReader weapon) => WeaponType(
  id: id,
  baseDamage: weapon.number('base_damage'),
  rangeM: weapon.number('range_m'),
  apPerShot: weapon.number('ap_per_shot'),
  baseAccuracy: weapon.optionalNumber('base_accuracy'),
  rateOfFireRpm: weapon.number('rate_of_fire_rpm'),
  magazineCapacity: weapon.integer('magazine_capacity'),
  reloadTimeS: weapon.number('reload_time_s'),
  unloadTimeS: weapon.number('unload_time_s'),
  moveWhileLoaded: weapon.boolean('move_while_loaded'),
  projectileSpeedMps: weapon.optionalNumber('projectile_speed_mps'),
  airborneFactor: weapon.number('airborne_factor'),
  splashRadiusM: weapon.optionalNumber('splash_radius_m'),
  deformsTerrain: weapon.optionalBoolean('deforms_terrain', absent: false),
  indirectFire: weapon.optionalBoolean('indirect_fire', absent: false),
  neverMisses: weapon.optionalBoolean('never_misses', absent: false),
);

Splash _readSplash(DataReader splash) => Splash(
  falloff: splash.string('falloff'),
  damageFactorAtEdge: splash.number('damage_factor_at_edge'),
);

FriendlyFire _readFriendlyFire(DataReader friendlyFire) => FriendlyFire(
  enabled: friendlyFire.boolean('enabled'),
  damageFactor: friendlyFire.number('damage_factor'),
);

TransportDamage _readTransport(DataReader transport) => TransportDamage(
  carriedDamageShare: transport.number('carried_damage_share'),
  ejectionDamageShareOfMaxHp: transport.number(
    'ejection_damage_share_of_max_hp',
  ),
);

MoraleRules _readMorale(DataReader morale) {
  final range = morale.numbers('range');
  if (range.length != 2) {
    morale.fail('range', range, 'must hold two numbers: [min, max]');
  }
  final events = morale.map('events');
  return MoraleRules(
    min: range[0],
    max: range[1],
    base: morale.number('base'),
    events: MoraleEvents(
      commanderAuraPerMin: events.number('commander_aura_per_min'),
      nearbyEnemyKilled: events.number('nearby_enemy_killed'),
      nearbyAllyKilled: events.number('nearby_ally_killed'),
      outnumberedPerMin: events.number('outnumbered_per_min'),
    ),
    nearbyRadiusM: morale.number('nearby_radius_m'),
    outnumberedRatio: morale.number('outnumbered_ratio'),
  );
}

ZeroHpRules _readZeroHp(DataReader zeroHp) => ZeroHpRules(
  k: zeroHp.number('k'),
  defectionShare: zeroHp.number('defection_share'),
  onlyWhenFinalBlowBy: zeroHp.string('only_when_final_blow_by'),
  target: zeroHp.string('target'),
  neverSpared: zeroHp.strings('never_spared'),
);

PrisonerRules _readPrisoners(DataReader prisoners) => PrisonerRules(
  heldIn: prisoners.string('held_in'),
  canEscape: prisoners.boolean('can_escape'),
  ransomFee: prisoners.number('ransom_fee'),
  atWarEnd: prisoners.string('at_war_end'),
);

AmmoRules _readAmmo(DataReader ammo) => AmmoRules(
  unlimited: ammo.boolean('unlimited'),
  reloadDiscardsRemaining: ammo.boolean('reload_discards_remaining'),
);

HitChanceRules _readHitChance(DataReader hitChance) {
  final clamp = hitChance.map('clamp');
  final distance = hitChance.map('distance_factor');
  final cover = hitChance.map('cover_factor');
  final speed = hitChance.map('speed_factor');
  final morale = hitChance.map('morale_factor');
  return HitChanceRules(
    clampMin: clamp.number('min'),
    clampMax: clamp.number('max'),
    distanceAtZero: distance.number('at_zero'),
    distanceAtMaxRange: distance.number('at_max_range'),
    coverNone: cover.number('none'),
    coverPartial: cover.number('partial'),
    coverFull: cover.number('full'),
    sizeFactor: hitChance.map('size_factor').numberEntries(),
    speedPerMps: speed.number('per_mps'),
    speedMin: speed.number('min'),
    indirectFactor: hitChance.number('indirect_factor'),
    moraleAt0: morale.number('at_0'),
    moraleAt100: morale.number('at_100'),
  );
}

AimRules _readAim(DataReader aim) => AimRules(
  baseSpreadDeg: aim.number('base_spread_deg'),
  spreadReductionPerAttack: aim.number('spread_reduction_per_attack'),
  minSpreadDeg: aim.number('min_spread_deg'),
);

DroppedWeapons _readDroppedWeapons(DataReader dropped) => DroppedWeapons(
  pickupAp: dropped.number('pickup_ap'),
  despawnAfterS: dropped.number('despawn_after_s'),
);

ApRules _readApRules(DataReader ap) => ApRules(
  atZero: ap.string('at_zero'),
  costsAp: ap.strings('costs_ap'),
  timeOnly: ap.strings('time_only'),
);

RoleActions _readRoleActions(DataReader actions) {
  final heal = actions.map('heal');
  final repair = actions.map('repair');
  final capture = actions.map('capture');
  final interruption = actions.map('interruption');
  return RoleActions(
    heal: HealAction(
      instant: heal.boolean('instant'),
      targets: heal.string('targets'),
    ),
    repair: RepairAction(
      ap: repair.number('ap'),
      durationS: repair.number('duration_s'),
      hpRestored: repair.number('hp_restored'),
      targets: repair.string('targets'),
    ),
    capture: CaptureAction(
      settings: capture.string('settings'),
      progressOwner: capture.string('progress_owner'),
    ),
    interruption: Interruption(
      apRefund: interruption.boolean('ap_refund'),
      progressKept: interruption.boolean('progress_kept'),
      resumeCost: interruption.string('resume_cost'),
      captureProgressKept: interruption.boolean('capture_progress_kept'),
    ),
  );
}

PushRules _readPush(DataReader push) => PushRules(
  speedMPerH: push.number('speed_m_per_h'),
  potApPerM: push.number('pot_ap_per_m'),
  contributionAp: push.number('contribution_ap'),
  minPushers: push.integer('min_pushers'),
  potEmpty: push.string('pot_empty'),
  crushUnitsPerExtraPusher: push.integer('crush_units_per_extra_pusher'),
  crush: push.string('crush'),
);
