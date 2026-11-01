import 'package:battle_rules/src/data/battle_settings.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/game_data.dart';
import 'package:battle_rules/src/data/game_data_exception.dart';
import 'package:battle_rules/src/data/terrain_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// The unit type whose base speed caps every flying unit's (decision 174).
const flyingSpeedReference = 'jeep';

/// The unit type whose base speed caps every sailing unit's (decision 174).
const sailingSpeedReference = 'tank';

/// Checks the rules between the values of the game data files (M4 Issue 2).
///
/// Throws a [GameDataException] naming the file, the key and the value of
/// the first problem found.
void validateGameData(GameData data) {
  _checkUnitArmorTypes(data);
  _checkWeaponLoadouts(data);
  _checkDamageTable(data.combat);
  _checkSizeFactors(data.combat);
  _checkTerrainColumns(data.terrain);
  _checkSlopeRows(data.terrain);
  _checkApMax(data);
  _checkProjectileSpeeds(data.combat);
  _checkSpeedCaps(data.units);
  _checkCommanderLevels(data.units.progression.commanderLevels);
  _checkObjectArmorTypes(data);
  _checkUpFrontAp(data);
}

Never _fail(String file, String key, Object? value, String problem) =>
    throw GameDataException(
      file: file,
      key: key,
      value: value,
      problem: problem,
    );

String _list(Iterable<String> names) => '[${names.join(', ')}]';

/// COMBAT-20: every unit's armor type is one of `combat.yaml` armor_types.
void _checkUnitArmorTypes(GameData data) {
  final armorTypes = data.combat.armorTypes;
  for (final unit in data.units.unitTypes.values) {
    if (!armorTypes.contains(unit.armorType)) {
      _fail(
        unitsFile,
        'units.${unit.id}.armor_type',
        unit.armorType,
        'not in $combatFile armor_types ${_list(armorTypes)}',
      );
    }
  }
}

/// UNIT-03: the default weapon is null (unarmed, nothing allowed) or one of
/// the allowed weapons, and every allowed weapon exists.
void _checkWeaponLoadouts(GameData data) {
  for (final unit in data.units.unitTypes.values) {
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
      if (!data.combat.weaponTypes.containsKey(weapon)) {
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

/// `hit_chance.size_factor` covers every armor type.
void _checkSizeFactors(CombatData combat) {
  for (final armor in combat.armorTypes) {
    if (!combat.hitChance.sizeFactor.containsKey(armor)) {
      _fail(combatFile, 'hit_chance.size_factor.$armor', null, 'missing');
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

/// Decision 167: every unit's `ap_max` is the one AP maximum, `battle.yaml`
/// `ap.max`.
void _checkApMax(GameData data) {
  final max = data.battle.ap.max;
  for (final unit in data.units.unitTypes.values) {
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

/// Decision 183: every weapon that flies a first-person shot has a
/// projectile speed; indirect fire and a weapon that never misses do not.
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
  UnitType reference(String id) =>
      units.unitTypes[id] ??
      _fail(
        unitsFile,
        'units.$id',
        null,
        'missing: it caps the base speed of other units (decision 174)',
      );
  final flyingCap = reference(flyingSpeedReference).stats.moveSpeed;
  final sailingCap = reference(sailingSpeedReference).stats.moveSpeed;
  for (final unit in units.unitTypes.values) {
    final speed = unit.stats.moveSpeed;
    if (unit.canFly && speed > flyingCap) {
      _fail(
        unitsFile,
        'units.${unit.id}.base.move_speed',
        speed,
        'a flying unit is not faster than the $flyingSpeedReference '
            '($flyingCap)',
      );
    }
    if (unit.canSail && speed > sailingCap) {
      _fail(
        unitsFile,
        'units.${unit.id}.base.move_speed',
        speed,
        'a sailing unit is not faster than the $sailingSpeedReference '
            '($sailingCap)',
      );
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

/// MAP-40: every terrain object's armor type is one of `combat.yaml`
/// armor_types.
void _checkObjectArmorTypes(GameData data) {
  final armorTypes = data.combat.armorTypes;
  for (final object in data.terrain.objects.values) {
    if (!armorTypes.contains(object.armorType)) {
      _fail(
        terrainFile,
        'objects.${object.id}.armor_type',
        object.armorType,
        'not in $combatFile armor_types ${_list(armorTypes)}',
      );
    }
  }
}

/// UNIT-38, decision 132: no action a unit lists costs more AP up front
/// than its `ap_max`.
void _checkUpFrontAp(GameData data) {
  for (final unit in data.units.unitTypes.values) {
    for (final action in unit.actions) {
      final ap = _upFrontAp(data, unit, action);
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
double _upFrontAp(GameData data, UnitType unit, UnitAction action) {
  final key = 'units.${unit.id}.role';
  return switch (action) {
    UnitAction.capture => data.battle.capture.contributionAp,
    UnitAction.push => data.combat.push.contributionAp,
    UnitAction.repair => data.combat.actions.repair.ap,
    UnitAction.heal =>
      unit.role.healAp ??
          _fail(unitsFile, '$key.heal_ap', null, 'missing: it lists heal'),
    UnitAction.observe =>
      unit.role.observe?.ap ??
          _fail(unitsFile, '$key.observe', null, 'missing: it lists observe'),
    UnitAction.build => _dearestConstruction(data.terrain, unit, key),
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
