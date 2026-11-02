import 'package:battle_rules/src/data/data_reader.dart';
import 'package:battle_rules/src/data/hit_box.dart';

/// The name of the units data file in messages.
const unitsFile = 'units.yaml';

/// An action a unit can do besides moving and shooting (UNIT-38,
/// decision 132). An order for an action its type does not list is refused.
enum UnitAction {
  /// Puts AP into a relic's capture pot.
  capture,

  /// Puts AP into a relic's push pot.
  push,

  /// Builds a construction.
  build,

  /// Repairs a friendly unit or structure.
  repair,

  /// Heals a friendly unit, at once.
  heal,

  /// Raises the unit's vision for a while; it cannot move meanwhile.
  observe,
}

/// An ability a unit has on top of its category and movement class.
enum Capability {
  /// Moves with the `flying` profile and is hit as a flying target.
  flying,

  /// Moves on water with the `sail` profile (decision 86).
  sail,
}

/// {@template units_data}
/// The `units.yaml` game data file: unit types, progression and evolution
/// trees.
/// {@endtemplate}
final class UnitsData {
  /// {@macro units_data}
  const new({
    required this.version,
    required this.unitTypes,
    required this.progression,
    required this.trees,
  });

  /// Parses the text of `units.yaml`. Checks types and required keys only;
  /// `GameData.parse` checks the rules between values.
  factory parse(String text) {
    final reader = DataReader.parse(unitsFile, text);
    return UnitsData(
      version: reader.integer('version'),
      unitTypes: Map.unmodifiable({
        for (final MapEntry(:key, :value) in reader.map('units').maps().entries)
          key: _readUnitType(key, value),
      }),
      progression: _readProgression(reader.map('progression')),
      trees: _readTrees(reader.map('trees')),
    );
  }

  /// The file's `version`.
  final int version;

  /// Every unit type, by id (`units`).
  final Map<String, UnitType> unitTypes;

  /// Experience, section size and commander levels (`progression`).
  final Progression progression;

  /// Evolution trees (`trees`, UNIT-23).
  final EvolutionTrees trees;
}

/// {@template unit_type}
/// One unit type of `units.yaml`.
/// {@endtemplate}
final class UnitType {
  /// {@macro unit_type}
  const new({
    required this.id,
    required this.category,
    required this.movementClass,
    required this.capabilities,
    required this.flight,
    required this.armorType,
    required this.hitBox,
    required this.stats,
    required this.weapons,
    required this.actions,
    required this.role,
    required this.permadeath,
    required this.purchasableBy,
    required this.owner,
    required this.countsInSectionCap,
    required this.storable,
  });

  /// The unit type's key in `units`, for example `soldier`.
  final String id;

  /// Its category, for example `soldier` or `vehicle`.
  final String category;

  /// Its ground movement class (`foot`, `wheeled`, `tracked`); null for a
  /// unit that moves only on water (a boat).
  final String? movementClass;

  /// Its capabilities (`flying`, `sail`).
  final Set<Capability> capabilities;

  /// Landing and take-off times of a flying unit; null when not given.
  final FlightTimes? flight;

  /// Its armor type, one of `combat.yaml` `armor_types` (COMBAT-20).
  final String armorType;

  /// Its hit volume for first-person shots (decision 183).
  final HitBox hitBox;

  /// Its stats: the `base` values of `units.yaml`, or a unit's effective
  /// values in a type that `Evolution.evolve` made (UNIT-22).
  final UnitStats stats;

  /// Its default and allowed weapons (UNIT-03).
  final WeaponLoadout weapons;

  /// The actions it can do besides moving and shooting (UNIT-38).
  final Set<UnitAction> actions;

  /// Its role values; empty when the type has no `role`. Like [stats], a
  /// unit's effective values in a type that `Evolution.evolve` made.
  final UnitRole role;

  /// Whether its death is final. Only the commander has `permadeath: false`:
  /// it resurrects in storage (decisions 80, 125).
  final bool permadeath;

  /// Who may buy it, when the file says so (`purchasable_by`).
  final String? purchasableBy;

  /// Whose section it belongs to, when the file says so (`owner`).
  final String? owner;

  /// Whether it counts in the section size cap; true unless the file says
  /// otherwise (decision 127).
  final bool countsInSectionCap;

  /// Whether it can be stored; true unless the file says otherwise.
  final bool storable;

  /// Whether it has the `flying` capability.
  bool get canFly => capabilities.contains(Capability.flying);

  /// Whether it has the `sail` capability.
  bool get canSail => capabilities.contains(Capability.sail);

  /// This type with other [stats] and [role] values: a unit's effective
  /// ones (UNIT-22).
  UnitType withValues({required UnitStats stats, required UnitRole role}) =>
      UnitType(
        id: id,
        category: category,
        movementClass: movementClass,
        capabilities: capabilities,
        flight: flight,
        armorType: armorType,
        hitBox: hitBox,
        stats: stats,
        weapons: weapons,
        actions: actions,
        role: role,
        permadeath: permadeath,
        purchasableBy: purchasableBy,
        owner: owner,
        countsInSectionCap: countsInSectionCap,
        storable: storable,
      );
}

/// {@template unit_stats}
/// The base stats of a unit type (`base`), before evolution.
/// {@endtemplate}
final class UnitStats {
  /// {@macro unit_stats}
  const new({
    required this.weight,
    required this.hp,
    required this.apMax,
    required this.apPerM,
    required this.attack,
    required this.defense,
    required this.moveSpeed,
    required this.visionRange,
  });

  /// Weight, for transports (decision 91).
  final double weight;

  /// Hit points.
  final double hp;

  /// AP maximum (decision 167).
  final double apMax;

  /// AP per metre on flat grass (decisions 169, 181).
  final double apPerM;

  /// Accuracy: raises the hit chance, tightens first-person spread.
  final double attack;

  /// Evasion: lowers the chance of being hit.
  final double defense;

  /// Speed in metres per second.
  final double moveSpeed;

  /// Vision range in metres, before modifiers.
  final double visionRange;

  /// These stats with new values for the evolvable ones (UNIT-20). AP
  /// maximum and AP per metre never evolve (decision 167).
  UnitStats withEvolvable({
    required double hp,
    required double attack,
    required double defense,
    required double moveSpeed,
    required double visionRange,
  }) => UnitStats(
    weight: weight,
    hp: hp,
    apMax: apMax,
    apPerM: apPerM,
    attack: attack,
    defense: defense,
    moveSpeed: moveSpeed,
    visionRange: visionRange,
  );
}

/// {@template weapon_loadout}
/// The weapons of a unit type (`weapons`, UNIT-03, decision 52).
/// {@endtemplate}
final class WeaponLoadout {
  /// {@macro weapon_loadout}
  const new({required this.defaultWeapon, required this.allowed});

  /// The weapon type the unit comes with; null for an unarmed unit.
  final String? defaultWeapon;

  /// The weapon types it may equip or pick up.
  final List<String> allowed;
}

/// {@template flight_times}
/// Landing and take-off times of a flying unit (`flying`, decision 68).
/// {@endtemplate}
final class FlightTimes {
  /// {@macro flight_times}
  const new({required this.landTimeS, required this.takeOffTimeS});

  /// Seconds to land.
  final double landTimeS;

  /// Seconds to take off.
  final double takeOffTimeS;
}

/// {@template unit_role}
/// The role values of a unit type (`role`). Each value is null, empty or
/// false when the type does not have it.
/// {@endtemplate}
final class UnitRole {
  /// {@macro unit_role}
  const new({
    this.auraRadius,
    this.build = const [],
    this.repair = false,
    this.reportsToRadio = false,
    this.observe,
    this.heal,
    this.healAp,
    this.earnsMoneyWhenHealing = false,
    this.relayRange,
    this.sharesWith,
    this.transportable = true,
    this.maxTotalWeight,
    this.maxUnitWeight,
  });

  /// The commander's aura radius, in metres.
  final double? auraRadius;

  /// The constructions an engineer can build (`terrain.yaml` objects).
  final List<String> build;

  /// Whether the unit can repair.
  final bool repair;

  /// Whether the unit reports what it sees to radios.
  final bool reportsToRadio;

  /// The scout's observe action (decision 119).
  final ObserveRole? observe;

  /// HP restored by one heal.
  final double? heal;

  /// AP one heal costs (decision 91).
  final double? healAp;

  /// Whether healing earns money for the section.
  final bool earnsMoneyWhenHealing;

  /// The radio's relay range, in metres.
  final double? relayRange;

  /// Who the radio shares information with.
  final String? sharesWith;

  /// Whether a transport can carry the unit; true unless the file says
  /// otherwise.
  final bool transportable;

  /// Total weight a transport carries (decision 91).
  final double? maxTotalWeight;

  /// Heaviest unit a transport carries (decision 91).
  final double? maxUnitWeight;

  /// These role values with new values for the evolvable ones (UNIT-23).
  UnitRole withEvolvable({
    required double? auraRadius,
    required double? heal,
    required double? relayRange,
    required double? maxTotalWeight,
  }) => UnitRole(
    auraRadius: auraRadius,
    build: build,
    repair: repair,
    reportsToRadio: reportsToRadio,
    observe: observe,
    heal: heal,
    healAp: healAp,
    earnsMoneyWhenHealing: earnsMoneyWhenHealing,
    relayRange: relayRange,
    sharesWith: sharesWith,
    transportable: transportable,
    maxTotalWeight: maxTotalWeight,
    maxUnitWeight: maxUnitWeight,
  );
}

/// {@template observe_role}
/// The scout's observe action (`role.observe`, decision 119).
/// {@endtemplate}
final class ObserveRole {
  /// {@macro observe_role}
  const new({
    required this.visionBonusM,
    required this.durationS,
    required this.ap,
    required this.canMove,
  });

  /// Metres added to the scout's vision.
  final double visionBonusM;

  /// How long it lasts, in seconds.
  final double durationS;

  /// AP paid up front.
  final double ap;

  /// Whether the scout can move while observing.
  final bool canMove;
}

/// {@template progression}
/// Experience, section size and commander levels (`progression`,
/// decisions 77-79).
/// {@endtemplate}
final class Progression {
  /// {@macro progression}
  const new({
    required this.xpSources,
    required this.targetScalingCap,
    required this.diminishing,
    required this.friendlyHitsGiveXp,
    required this.victoryXp,
    required this.sectionXpShare,
    required this.sectionSize,
    required this.guildCreationMinLevel,
    required this.commanderLevels,
  });

  /// XP per source (`xp_sources`).
  final XpSources xpSources;

  /// Cap of the hit and kill XP scaling by target XP (`target_scaling.cap`).
  final double targetScalingCap;

  /// Diminishing XP for repeats (`diminishing`).
  final Diminishing diminishing;

  /// Whether hitting a friend gives XP.
  final bool friendlyHitsGiveXp;

  /// XP per unit of the winning team.
  final double victoryXp;

  /// Share of each XP point moved to the section XP.
  final double sectionXpShare;

  /// The section size cap rule (`section_size`, UNIT-17, decision 127).
  final SectionSize sectionSize;

  /// Commander level needed to create a guild (decision 155).
  final int guildCreationMinLevel;

  /// The level table (`commander_levels`, UNIT-17, decision 144).
  final CommanderLevels commanderLevels;
}

/// {@template xp_sources}
/// XP earned per source (`progression.xp_sources`).
/// {@endtemplate}
final class XpSources {
  /// {@macro xp_sources}
  const new({
    required this.hit,
    required this.kill,
    required this.roleAction,
    required this.capture,
    required this.nearCommanderPerMin,
  });

  /// XP per hit.
  final double hit;

  /// XP per kill.
  final double kill;

  /// XP per completed build, repair, heal or spotting report.
  final double roleAction;

  /// XP of a capture, shared by the AP each unit put into the pot
  /// (decision 179).
  final double capture;

  /// XP per minute near the unit's commander.
  final double nearCommanderPerMin;
}

/// {@template diminishing}
/// Diminishing XP for the same target or build spot (`diminishing`).
/// {@endtemplate}
final class Diminishing {
  /// {@macro diminishing}
  const new({required this.windowS, required this.factorPerRepeat});

  /// The window, in seconds.
  final double windowS;

  /// The XP factor per repeat within the window.
  final double factorPerRepeat;
}

/// {@template section_size}
/// The section size cap rule (`section_size`, decision 127):
/// `cap = cap_at_level_1 + floor((level - 1) / extra_unit_every_levels)`.
/// {@endtemplate}
final class SectionSize {
  /// {@macro section_size}
  const new({
    required this.capAtLevel1,
    required this.extraUnitEveryLevels,
    required this.maxUnitsFactor,
  });

  /// Active units allowed at commander level 1.
  final int capAtLevel1;

  /// Levels between two extra active units.
  final int extraUnitEveryLevels;

  /// Units owned (active and stored) at most, as a multiple of the cap.
  final int maxUnitsFactor;

  /// The cap on active units, the commander included, at commander
  /// [level] (UNIT-39).
  int capAt(int level) => capAtLevel1 + (level - 1) ~/ extraUnitEveryLevels;

  /// Whether a section at commander [level] with [activeUnits] on the
  /// field has room for one more: a defector needs it (UNIT-39).
  bool hasRoom({required int level, required int activeUnits}) =>
      activeUnits < capAt(level);
}

/// {@template commander_levels}
/// The commander level table (`commander_levels`, UNIT-17, decision 144).
/// {@endtemplate}
final class CommanderLevels {
  /// {@macro commander_levels}
  const new({required this.maxLevel, required this.sectionXp});

  /// The highest level.
  final int maxLevel;

  /// `sectionXp[i]` is the section XP needed to reach level `i + 1`.
  final List<int> sectionXp;
}

/// {@template evolution_trees}
/// Evolution trees (`trees`, UNIT-23, decisions 78, 118).
/// {@endtemplate}
final class EvolutionTrees {
  /// {@macro evolution_trees}
  const new({
    required this.statCapOfBase,
    required this.defaultTree,
    required this.extraStats,
  });

  /// Every evolved stat is capped at this multiple of its base value.
  final double statCapOfBase;

  /// The tree every unit type has (`default`).
  final DefaultTree defaultTree;

  /// Stats some unit types add to the default tree, by unit type
  /// (`overrides.<type>.extra_stats`).
  final Map<String, List<String>> extraStats;
}

/// {@template default_tree}
/// The default evolution tree (`trees.default`, UNIT-23): for each stat, a
/// chain of steps; step n adds [stepBonus] of the base value and costs
/// [costBase] × n XP.
/// {@endtemplate}
final class DefaultTree {
  /// {@macro default_tree}
  const new({
    required this.stats,
    required this.stepBonus,
    required this.costBase,
  });

  /// The evolvable stats.
  final List<String> stats;

  /// Share of the base value one step adds.
  final double stepBonus;

  /// XP of step 1; step n costs n times as much.
  final double costBase;
}

UnitType _readUnitType(String id, DataReader unit) {
  final base = unit.map('base');
  final weapons = unit.map('weapons');
  final flight = unit.optionalMap('flying');
  return UnitType(
    id: id,
    category: unit.string('category'),
    movementClass: unit.optionalString('movement_class'),
    capabilities: Set.unmodifiable(
      _readNames(unit, 'capabilities', Capability.values.asNameMap()),
    ),
    flight: flight == null
        ? null
        : FlightTimes(
            landTimeS: flight.number('land_time_s'),
            takeOffTimeS: flight.number('take_off_time_s'),
          ),
    armorType: unit.string('armor_type'),
    hitBox: readHitBox(unit),
    stats: UnitStats(
      weight: base.number('weight'),
      hp: base.number('hp'),
      apMax: base.number('ap_max'),
      apPerM: base.number('ap_per_m'),
      attack: base.number('attack'),
      defense: base.number('defense'),
      moveSpeed: base.number('move_speed'),
      visionRange: base.number('vision_range'),
    ),
    weapons: WeaponLoadout(
      defaultWeapon: weapons.stringOrNull('default'),
      allowed: weapons.strings('allowed'),
    ),
    actions: Set.unmodifiable(
      _readNames(unit, 'actions', UnitAction.values.asNameMap()),
    ),
    role: _readRole(unit.optionalMap('role')),
    permadeath: unit.optionalBoolean('permadeath', absent: true),
    purchasableBy: unit.optionalString('purchasable_by'),
    owner: unit.optionalString('owner'),
    countsInSectionCap: unit.optionalBoolean(
      'counts_in_section_cap',
      absent: true,
    ),
    storable: unit.optionalBoolean('storable', absent: true),
  );
}

/// Reads the list at [key] as names of [byName]; absent reads as empty.
List<T> _readNames<T>(DataReader reader, String key, Map<String, T> byName) => [
  for (final (index, name) in reader.optionalStrings(key).indexed)
    byName[name] ??
        reader.fail(
          '$key[$index]',
          name,
          'unknown, expected one of ${byName.keys.join(', ')}',
        ),
];

UnitRole _readRole(DataReader? role) {
  if (role == null) return const UnitRole();
  final observe = role.optionalMap('observe');
  return UnitRole(
    auraRadius: role.optionalNumber('aura_radius'),
    build: role.optionalStrings('build'),
    repair: role.optionalBoolean('repair', absent: false),
    reportsToRadio: role.optionalBoolean('reports_to_radio', absent: false),
    observe: observe == null
        ? null
        : ObserveRole(
            visionBonusM: observe.number('vision_bonus_m'),
            durationS: observe.number('duration_s'),
            ap: observe.number('ap'),
            canMove: observe.boolean('can_move'),
          ),
    heal: role.optionalNumber('heal'),
    healAp: role.optionalNumber('heal_ap'),
    earnsMoneyWhenHealing: role.optionalBoolean(
      'earns_money_when_healing',
      absent: false,
    ),
    relayRange: role.optionalNumber('relay_range'),
    sharesWith: role.optionalString('shares_with'),
    transportable: role.optionalBoolean('transportable', absent: true),
    maxTotalWeight: role.optionalNumber('max_total_weight'),
    maxUnitWeight: role.optionalNumber('max_unit_weight'),
  );
}

Progression _readProgression(DataReader progression) {
  final xp = progression.map('xp_sources');
  final diminishing = progression.map('diminishing');
  final size = progression.map('section_size');
  final levels = progression.map('commander_levels');
  return Progression(
    xpSources: XpSources(
      hit: xp.number('hit'),
      kill: xp.number('kill'),
      roleAction: xp.number('role_action'),
      capture: xp.number('capture'),
      nearCommanderPerMin: xp.number('near_commander_per_min'),
    ),
    targetScalingCap: progression.map('target_scaling').number('cap'),
    diminishing: Diminishing(
      windowS: diminishing.number('window_s'),
      factorPerRepeat: diminishing.number('factor_per_repeat'),
    ),
    friendlyHitsGiveXp: progression.boolean('friendly_hits_give_xp'),
    victoryXp: progression.number('victory_xp'),
    sectionXpShare: progression.number('section_xp_share'),
    sectionSize: SectionSize(
      capAtLevel1: size.integer('cap_at_level_1'),
      extraUnitEveryLevels: size.integer('extra_unit_every_levels'),
      maxUnitsFactor: size.integer('max_units_factor'),
    ),
    guildCreationMinLevel: progression.integer('guild_creation_min_level'),
    commanderLevels: CommanderLevels(
      maxLevel: levels.integer('max_level'),
      sectionXp: levels.integers('section_xp'),
    ),
  );
}

EvolutionTrees _readTrees(DataReader trees) {
  final defaultTree = trees.map('default');
  return EvolutionTrees(
    statCapOfBase: trees.number('stat_cap_of_base'),
    defaultTree: DefaultTree(
      stats: defaultTree.strings('stats'),
      stepBonus: defaultTree.number('step_bonus'),
      costBase: defaultTree.number('cost_base'),
    ),
    extraStats: Map.unmodifiable({
      for (final MapEntry(:key, :value)
          in (trees.optionalMap('overrides')?.maps() ?? const {}).entries)
        key: value.strings('extra_stats'),
    }),
  );
}
