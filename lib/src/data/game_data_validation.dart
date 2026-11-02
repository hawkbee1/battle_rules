import 'package:battle_rules/src/data/battle_settings.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/game_data_exception.dart';
import 'package:battle_rules/src/data/terrain_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// The unit type whose base speed caps every flying unit's (decision 174).
const _flyingSpeedReference = 'jeep';

/// The unit type whose base speed caps every sailing unit's (decision 174).
const _sailingSpeedReference = 'tank';

/// Checks the rules between the values of the game data files (M4 Issue 2).
///
/// Throws a [GameDataException] naming the file, the key and the value of
/// the first problem found.
void validateGameData({
  required UnitsData units,
  required CombatData combat,
  required TerrainData terrain,
  required BattleSettings battle,
}) {
  _checkArmorTypes(units, terrain, combat.armorTypes);
  _checkWeaponLoadouts(units, combat);
  _checkDamageTable(combat);
  _checkSizeFactors(combat);
  _checkMovementClasses(units, terrain);
  _checkTerrainColumns(terrain);
  _checkSlopeRows(terrain);
  _checkApMax(units, battle.ap.max);
  _checkProjectileSpeeds(combat);
  _checkSpeedCaps(units);
  _checkCommanderLevels(units.progression.commanderLevels);
  _checkUpFrontAp(units, combat, terrain, battle);
}

Never _fail(String file, String key, Object? value, String problem) =>
    throw GameDataException(
      file: file,
      key: key,
      value: value,
      problem: problem,
    );

String _list(Iterable<String> names) => '[${names.join(', ')}]';

/// COMBAT-20, MAP-40: every unit's and every object's armor type is one of
/// `combat.yaml` armor_types.
void _checkArmorTypes(
  UnitsData units,
  TerrainData terrain,
  List<String> armorTypes,
) {
  void check(String file, String key, String armorType) {
    if (!armorTypes.contains(armorType)) {
      _fail(
        file,
        key,
        armorType,
        'not in $combatFile armor_types ${_list(armorTypes)}',
      );
    }
  }

  for (final unit in units.unitTypes.values) {
    check(unitsFile, 'units.${unit.id}.armor_type', unit.armorType);
  }
  for (final object in terrain.objects.values) {
    check(terrainFile, 'objects.${object.id}.armor_type', object.armorType);
  }
}

/// UNIT-03: the default weapon is null (unarmed, nothing allowed) or one of
/// the allowed weapons, and every allowed weapon exists.
void _checkWeaponLoadouts(UnitsData units, CombatData combat) {
  for (final unit in units.unitTypes.values) {
    final WeaponLoadout(:defaultWeapon, :allowed) = unit.weapons;
    final key = 'units.${unit.id}.weapons';
    if (defaultWeapon == null && allowed.isNotEmpty) {
      _fail(
        unitsFile,
        '$key.default',
        null,
        'an unarmed unit allows no weapon, but allowed is ${_list(allowed)}',
      );
    }
    if (defaultWeapon != null && !allowed.contains(defaultWeapon)) {
      _fail(
        unitsFile,
        '$key.default',
        defaultWeapon,
        'not in its allowed list ${_list(allowed)}',
      );
    }
    for (final (index, weapon) in allowed.indexed) {
      if (!combat.weaponTypes.containsKey(weapon)) {
        _fail(
          unitsFile,
          '$key.allowed[$index]',
          weapon,
          'not in $combatFile weapon_types',
        );
      }
    }
  }
}

/// COMBAT-23: every weapon has a `multipliers` row with every armor type.
void _checkDamageTable(CombatData combat) {
  for (final weapon in combat.weaponTypes.keys) {
    final row = combat.multipliers[weapon];
    if (row == null) {
      _fail(combatFile, 'multipliers.$weapon', null, 'missing');
    }
    for (final armor in combat.armorTypes) {
      if (!row.containsKey(armor)) {
        _fail(combatFile, 'multipliers.$weapon.$armor', null, 'missing');
      }
    }
  }
}

/// COMBAT-15: `hit_chance.size_factor` covers every armor type.
void _checkSizeFactors(CombatData combat) {
  for (final armor in combat.armorTypes) {
    if (!combat.hitChance.sizeFactor.containsKey(armor)) {
      _fail(combatFile, 'hit_chance.size_factor.$armor', null, 'missing');
    }
  }
}

/// MAP-15: every unit's ground movement class is one of `terrain.yaml`
/// movement_classes, so its `ap_multiplier` column exists.
void _checkMovementClasses(UnitsData units, TerrainData terrain) {
  for (final unit in units.unitTypes.values) {
    final movementClass = unit.movementClass;
    if (movementClass != null &&
        !terrain.movementClasses.contains(movementClass)) {
      _fail(
        unitsFile,
        'units.${unit.id}.movement_class',
        movementClass,
        'not in $terrainFile movement_classes '
            '${_list(terrain.movementClasses)}',
      );
    }
  }
}

/// MAP-15: every terrain's `ap_multiplier` covers every movement class and
/// profile.
void _checkTerrainColumns(TerrainData terrain) {
  for (final type in terrain.terrainTypes.values) {
    for (final mode in terrain.movementModes) {
      if (!type.apMultiplier.containsKey(mode)) {
        _fail(
          terrainFile,
          'terrain.${type.id}.ap_multiplier.$mode',
          null,
          'missing: null means impassable',
        );
      }
    }
  }
}

/// MAP-21: every movement class and profile has a `slope` row.
void _checkSlopeRows(TerrainData terrain) {
  for (final mode in terrain.movementModes) {
    if (!terrain.slope.containsKey(mode)) {
      _fail(terrainFile, 'slope.$mode', null, 'missing');
    }
  }
}

/// COMBAT-01, decision 167: every unit's `ap_max` is the one AP maximum,
/// `battle.yaml` `ap.max`.
void _checkApMax(UnitsData units, double max) {
  for (final unit in units.unitTypes.values) {
    if (unit.stats.apMax != max) {
      _fail(
        unitsFile,
        'units.${unit.id}.base.ap_max',
        unit.stats.apMax,
        'differs from $battleFile ap.max $max',
      );
    }
  }
}

/// COMBAT-14, decision 183: every weapon that flies a first-person shot has
/// a projectile speed; indirect fire and a weapon that never misses do not.
void _checkProjectileSpeeds(CombatData combat) {
  for (final weapon in combat.weaponTypes.values) {
    if (!weapon.indirectFire &&
        !weapon.neverMisses &&
        weapon.projectileSpeedMps == null) {
      _fail(
        combatFile,
        'weapon_types.${weapon.id}.projectile_speed_mps',
        null,
        'missing: a direct-fire weapon needs it for first-person shots',
      );
    }
  }
}

/// Decisions 174, 178: a flying unit's base speed is at most the jeep's, a
/// sailing unit's at most the tank's.
void _checkSpeedCaps(UnitsData units) {
  final caps = [
    ('flying', (UnitType unit) => unit.canFly, _flyingSpeedReference),
    ('sailing', (UnitType unit) => unit.canSail, _sailingSpeedReference),
  ];
  for (final (kind, applies, reference) in caps) {
    final cap =
        units.unitTypes[reference]?.stats.moveSpeed ??
        _fail(
          unitsFile,
          'units.$reference',
          null,
          'missing: it caps the base speed of other units (decision 174)',
        );
    for (final unit in units.unitTypes.values.where(applies)) {
      if (unit.stats.moveSpeed > cap) {
        _fail(
          unitsFile,
          'units.${unit.id}.base.move_speed',
          unit.stats.moveSpeed,
          'a $kind unit is not faster than the $reference ($cap)',
        );
      }
    }
  }
}

/// UNIT-17: `section_xp` has `max_level` values, in increasing order.
void _checkCommanderLevels(CommanderLevels levels) {
  const key = 'progression.commander_levels.section_xp';
  final CommanderLevels(:maxLevel, :sectionXp) = levels;
  if (sectionXp.length != maxLevel) {
    _fail(
      unitsFile,
      key,
      sectionXp.length,
      'has ${sectionXp.length} values, but max_level is $maxLevel',
    );
  }
  for (var index = 1; index < sectionXp.length; index++) {
    if (sectionXp[index] <= sectionXp[index - 1]) {
      _fail(
        unitsFile,
        '$key[$index]',
        sectionXp[index],
        'not above the previous value ${sectionXp[index - 1]}',
      );
    }
  }
}

/// UNIT-38, decision 132: no action a unit lists costs more AP up front
/// than its `ap_max`.
void _checkUpFrontAp(
  UnitsData units,
  CombatData combat,
  TerrainData terrain,
  BattleSettings battle,
) {
  for (final unit in units.unitTypes.values) {
    for (final action in unit.actions) {
      final ap = _upFrontAp(unit, action, combat, terrain, battle);
      if (ap > unit.stats.apMax) {
        _fail(
          unitsFile,
          'units.${unit.id}.actions',
          action.name,
          'costs $ap AP up front, more than its ap_max ${unit.stats.apMax}',
        );
      }
    }
  }
}

/// The AP [unit] pays up front for [action] (COMBAT-07, COMBAT-08): a
/// contribution to a capture or push pot, the repair AP, the healer's and
/// the scout's role AP, and the dearest construction it builds.
double _upFrontAp(
  UnitType unit,
  UnitAction action,
  CombatData combat,
  TerrainData terrain,
  BattleSettings battle,
) {
  final key = 'units.${unit.id}.role';
  return switch (action) {
    UnitAction.capture => battle.capture.contributionAp,
    UnitAction.push => combat.push.contributionAp,
    UnitAction.repair => combat.actions.repair.ap,
    UnitAction.heal =>
      unit.role.healAp ??
          _fail(unitsFile, '$key.heal_ap', null, 'missing: it lists heal'),
    UnitAction.observe =>
      unit.role.observe?.ap ??
          _fail(unitsFile, '$key.observe', null, 'missing: it lists observe'),
    UnitAction.build => _dearestConstruction(terrain, unit, key),
  };
}

double _dearestConstruction(TerrainData terrain, UnitType unit, String key) {
  final builds = unit.role.build;
  if (builds.isEmpty) {
    _fail(unitsFile, '$key.build', null, 'missing: it lists build');
  }
  var dearest = 0.0;
  for (final (index, id) in builds.indexed) {
    final construction = terrain.objects[id]?.construction;
    if (construction == null) {
      _fail(
        unitsFile,
        '$key.build[$index]',
        id,
        'not a construction of $terrainFile objects',
      );
    }
    if (construction.ap > dearest) dearest = construction.ap;
  }
  return dearest;
}
