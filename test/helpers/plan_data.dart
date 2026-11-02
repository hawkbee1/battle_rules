import 'dart:io';

import 'package:battle_rules/battle_rules.dart';

/// The Battle Team plan in the hawkbee checkout, relative to this package
/// (stack decision 7). Tests run from the package folder.
///
/// The data is never copied into the package: tests on real values read it
/// from here, so the code and the data cannot drift apart silently.
const planPath = '../../apps/battle_team/plan';

/// Reads the text of the plan file at [pathInPlan], for example
/// `data/units.yaml`.
///
/// Throws a [StateError] naming the missing path when the package is not
/// inside a hawkbee checkout.
String readPlanFile(String pathInPlan) {
  final file = File('$planPath/$pathInPlan');
  if (!file.existsSync()) {
    throw StateError(
      '${file.absolute.path} not found. battle_rules tests read the game '
      'data from a hawkbee checkout: git clone --recurse-submodules '
      'https://github.com/hawkbee1/hawkbee.git',
    );
  }
  return file.readAsStringSync();
}

/// Reads the text of the game data file [fileName] (for example
/// `units.yaml`) from `plan/data/`.
String readPlanData(String fileName) => readPlanFile('data/$fileName');

/// Reads the text of `economy.yaml`, which lives in `plan/milestones/`
/// rather than `plan/data/` (owner, 2026-11-01).
String readPlanEconomy() => readPlanFile('milestones/economy.yaml');

/// Parses the current game data of the plan.
GameData parsePlanData() => GameData.parse(
  units: readPlanData('units.yaml'),
  combat: readPlanData('combat.yaml'),
  terrain: readPlanData('terrain.yaml'),
  battle: readPlanData('battle.yaml'),
  economy: readPlanEconomy(),
  medals: readPlanData('medals.yaml'),
);
