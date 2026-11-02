import 'package:battle_rules/src/data/battle_settings.dart';
import 'package:battle_rules/src/data/combat_data.dart';
import 'package:battle_rules/src/data/economy_data.dart';
import 'package:battle_rules/src/data/game_data_exception.dart';
import 'package:battle_rules/src/data/game_data_validation.dart';
import 'package:battle_rules/src/data/medals_data.dart';
import 'package:battle_rules/src/data/terrain_data.dart';
import 'package:battle_rules/src/data/units_data.dart';

/// Every game data file, parsed and checked. [GameData.parse] is the only
/// way to get one.
///
/// Flyweight (stack decision 7): one instance holds the unit, weapon and
/// terrain definitions that every unit of every battle shares.
final class GameData {
  const new _({
    required this.units,
    required this.combat,
    required this.terrain,
    required this.battle,
    required this.economy,
    required this.medals,
  });

  /// Parses the text of each game data file, then checks the rules between
  /// their values. The caller reads the files: this package reads none
  /// (stack decision 7).
  ///
  /// Throws a [GameDataException] naming the file, the key and the value of
  /// the first problem found.
  factory parse({
    required String units,
    required String combat,
    required String terrain,
    required String battle,
    required String economy,
    required String medals,
  }) {
    final data = GameData._(
      units: UnitsData.parse(units),
      combat: CombatData.parse(combat),
      terrain: TerrainData.parse(terrain),
      battle: BattleSettings.parse(battle),
      economy: EconomyData.parse(economy),
      medals: MedalsData.parse(medals),
    );
    validateGameData(
      units: data.units,
      combat: data.combat,
      terrain: data.terrain,
      battle: data.battle,
      economy: data.economy,
    );
    return data;
  }

  /// `units.yaml`.
  final UnitsData units;

  /// `combat.yaml`.
  final CombatData combat;

  /// `terrain.yaml`.
  final TerrainData terrain;

  /// `battle.yaml`: the default settings of a battle. Each battle plays
  /// with its own settings, which an admin chooses from these (decision
  /// 172) and [checkSettings] checks; the shared definitions above stay the
  /// same for every battle.
  final BattleSettings battle;

  /// `economy.yaml`.
  final EconomyData economy;

  /// `medals.yaml`.
  final MedalsData medals;

  /// [settings], one battle's own settings, once checked against the shared
  /// definitions (decision 172): the AP maximum, the up-front AP of the
  /// actions, the teams and the battle start.
  ///
  /// Throws a [GameDataException] naming `battle.yaml`, the key and the
  /// value of the first problem found.
  BattleSettings checkSettings(BattleSettings settings) {
    validateSettings(
      units: units,
      combat: combat,
      terrain: terrain,
      battle: settings,
    );
    return settings;
  }
}
