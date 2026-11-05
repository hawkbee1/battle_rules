import 'package:battle_rules/src/data/data_reader.dart';
import 'package:battle_rules/src/data/hit_box.dart';

/// The name of the battle settings file in messages.
const battleFile = 'battle.yaml';

/// {@template battle_settings}
/// The `battle.yaml` game data file: the default settings of a battle and
/// the battle-wide rule values.
/// {@endtemplate}
final class BattleSettings {
  /// {@macro battle_settings}
  const new({
    required this.version,
    required this.commanderDeath,
    required this.ap,
    required this.battleStart,
    required this.teamCount,
    required this.guildsOffered,
    required this.capture,
    required this.hq,
    required this.victory,
    required this.storage,
    required this.weather,
    required this.sectionRedeployLockS,
  });

  /// Parses the text of `battle.yaml`. Checks types and required keys only;
  /// `GameData.parse` checks the rules between values.
  factory parse(String text) {
    final reader = DataReader.parse(battleFile, text);
    final death = reader.map('commander_death');
    final ap = reader.map('ap');
    final start = reader.map('battle_start');
    final capture = reader.map('capture');
    final hq = reader.map('hq');
    final victory = reader.map('victory');
    final storage = reader.map('storage');
    final weather = reader.map('weather');
    return BattleSettings(
      version: reader.integer('version'),
      commanderDeath: CommanderDeath(
        xpLossShare: death.number('xp_loss_share'),
        apLossShare: death.number('ap_loss_share'),
        moraleLoss: death.number('morale_loss'),
      ),
      ap: ApSettings(
        max: ap.number('max'),
        recoveryPerHour: ap.number('recovery_per_hour'),
      ),
      battleStart: BattleStart(
        restoreAp: start.string('restore_ap'),
        restoreHp: start.string('restore_hp'),
        restoreMorale: start.string('restore_morale'),
      ),
      teamCount: reader.map('teams').integer('count'),
      guildsOffered: reader.map('newcomers').integer('guilds_offered'),
      capture: CaptureSettings(
        durationS: capture.number('duration_s'),
        potAp: capture.number('pot_ap'),
        contributionAp: capture.number('contribution_ap'),
        radiusM: capture.number('radius_m'),
      ),
      hq: HqSettings(
        hp: hq.number('hp'),
        apMax: hq.number('ap_max'),
        apPerM: hq.number('ap_per_m'),
        speedMPerH: hq.number('speed_m_per_h'),
        hitBox: readHitBox(hq),
      ),
      victory: VictorySettings(
        relicsToHold: victory.integer('relics_to_hold'),
        holdS: victory.number('hold_s'),
      ),
      storage: StorageSettings(
        storeRadiusM: storage.number('store_radius_m'),
        recallS: storage.number('recall_s'),
        deployAp: storage.number('deploy_ap'),
        deployBlockRadiusM: storage.number('deploy_block_radius_m'),
      ),
      weather: WeatherSettings(
        mode: weather.string('mode'),
        states: weather.strings('states'),
      ),
      sectionRedeployLockS: reader.number('section_redeploy_lock_s'),
    );
  }

  /// The file's `version`.
  final int version;

  /// What a commander's death costs (decisions 80, 125).
  final CommanderDeath commanderDeath;

  /// AP maximum and recovery (decisions 167, 168, 172).
  final ApSettings ap;

  /// What every battle of a war restores at its start (decision 83).
  final BattleStart battleStart;

  /// Number of teams (`teams.count`, decisions 84, 103).
  final int teamCount;

  /// Guilds offered to a newcomer (`newcomers.guilds_offered`, SOC-03,
  /// SOC-07).
  final int guildsOffered;

  /// Relic capture (decisions 97, 170).
  final CaptureSettings capture;

  /// The HQ (decisions 109, 177).
  final HqSettings hq;

  /// Victory (decisions 45, 46c).
  final VictorySettings victory;

  /// Storage and deployment (decision 110).
  final StorageSettings storage;

  /// Weather (decision 90).
  final WeatherSettings weather;

  /// Seconds a section cannot deploy after storing all its units by choice
  /// (decision 120).
  final double sectionRedeployLockS;

  /// These settings in the shape of `battle.yaml`: [BattleSettings.parse]
  /// reads them back from their JSON text. A battle's snapshot keeps its
  /// own settings this way (decision 172, stack decision 2).
  Map<String, Object> toData() => {
    'version': version,
    'commander_death': {
      'xp_loss_share': commanderDeath.xpLossShare,
      'ap_loss_share': commanderDeath.apLossShare,
      'morale_loss': commanderDeath.moraleLoss,
    },
    'ap': {'max': ap.max, 'recovery_per_hour': ap.recoveryPerHour},
    'battle_start': {
      'restore_ap': battleStart.restoreAp,
      'restore_hp': battleStart.restoreHp,
      'restore_morale': battleStart.restoreMorale,
    },
    'teams': {'count': teamCount},
    'newcomers': {'guilds_offered': guildsOffered},
    'capture': {
      'duration_s': capture.durationS,
      'pot_ap': capture.potAp,
      'contribution_ap': capture.contributionAp,
      'radius_m': capture.radiusM,
    },
    'hq': {
      'hp': hq.hp,
      'ap_max': hq.apMax,
      'ap_per_m': hq.apPerM,
      'speed_m_per_h': hq.speedMPerH,
      'hit_box_m': {
        'width': hq.hitBox.width,
        'length': hq.hitBox.length,
        'height': hq.hitBox.height,
      },
    },
    'victory': {
      'relics_to_hold': victory.relicsToHold,
      'hold_s': victory.holdS,
    },
    'storage': {
      'store_radius_m': storage.storeRadiusM,
      'recall_s': storage.recallS,
      'deploy_ap': storage.deployAp,
      'deploy_block_radius_m': storage.deployBlockRadiusM,
    },
    'weather': {'mode': weather.mode, 'states': weather.states},
    'section_redeploy_lock_s': sectionRedeployLockS,
  };
}

/// {@template commander_death}
/// What a commander's death costs (`commander_death`, decisions 80, 125).
/// {@endtemplate}
final class CommanderDeath {
  /// {@macro commander_death}
  const new({
    required this.xpLossShare,
    required this.apLossShare,
    required this.moraleLoss,
  });

  /// Share of the commander's unspent XP lost.
  final double xpLossShare;

  /// Share of `ap_max` removed from each stored unit.
  final double apLossShare;

  /// Morale removed from each stored unit.
  final double moraleLoss;
}

/// {@template ap_settings}
/// AP maximum and recovery (`ap`, decisions 167, 168, 172).
/// {@endtemplate}
final class ApSettings {
  /// {@macro ap_settings}
  const new({required this.max, required this.recoveryPerHour});

  /// AP maximum of every unit (decision 167).
  final double max;

  /// AP every unit recovers per hour.
  final double recoveryPerHour;
}

/// {@template battle_start}
/// What every battle of a war restores at its start (`battle_start`,
/// decision 83).
/// {@endtemplate}
final class BattleStart {
  /// {@macro battle_start}
  const new({
    required this.restoreAp,
    required this.restoreHp,
    required this.restoreMorale,
  });

  /// How AP are restored, for example `full`.
  final String restoreAp;

  /// How HP are restored, for example `full`.
  final String restoreHp;

  /// How morale is restored, for example `base`.
  final String restoreMorale;
}

/// {@template capture_settings}
/// Relic capture (`capture`, decisions 97, 170, 176).
/// {@endtemplate}
final class CaptureSettings {
  /// {@macro capture_settings}
  const new({
    required this.durationS,
    required this.potAp,
    required this.contributionAp,
    required this.radiusM,
  });

  /// Seconds the capture takes once the pot is full.
  final double durationS;

  /// AP the team pot needs.
  final double potAp;

  /// AP a unit adds to the pot per action.
  final double contributionAp;

  /// Radius to capture and to block, in metres.
  final double radiusM;
}

/// {@template hq_settings}
/// The HQ (`hq`, decisions 109, 114, 177, 183).
/// {@endtemplate}
final class HqSettings {
  /// {@macro hq_settings}
  const new({
    required this.hp,
    required this.apMax,
    required this.apPerM,
    required this.speedMPerH,
    required this.hitBox,
  });

  /// Hit points.
  final double hp;

  /// AP maximum.
  final double apMax;

  /// AP per metre on flat grass, times the `push` profile.
  final double apPerM;

  /// Speed, in metres per hour.
  final double speedMPerH;

  /// Hit volume for first-person shots.
  final HitBox hitBox;
}

/// {@template victory_settings}
/// Victory (`victory`, decisions 45, 46c).
/// {@endtemplate}
final class VictorySettings {
  /// {@macro victory_settings}
  const new({required this.relicsToHold, required this.holdS});

  /// Relics a team must hold.
  final int relicsToHold;

  /// Seconds they must be held.
  final double holdS;
}

/// {@template storage_settings}
/// Storage and deployment (`storage`, decision 110).
/// {@endtemplate}
final class StorageSettings {
  /// {@macro storage_settings}
  const new({
    required this.storeRadiusM,
    required this.recallS,
    required this.deployAp,
    required this.deployBlockRadiusM,
  });

  /// A unit this close to its storage place is stored at once, in metres.
  final double storeRadiusM;

  /// Seconds to recall a unit from anywhere else.
  final double recallS;

  /// AP a unit pays to deploy.
  final double deployAp;

  /// An enemy this close to the storage place blocks deployment, in metres.
  final double deployBlockRadiusM;
}

/// {@template weather_settings}
/// Weather (`weather`, decision 90).
/// {@endtemplate}
final class WeatherSettings {
  /// {@macro weather_settings}
  const new({required this.mode, required this.states});

  /// How the weather changes, for example `random`.
  final String mode;

  /// The weather states a battle can have (`terrain.yaml` `weather`).
  final List<String> states;
}
