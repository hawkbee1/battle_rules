import 'dart:io';

import 'package:battle_rules/battle_rules.dart';

/// Plays a scenario file and prints its event log, its summary and one
/// machine-readable line (M4 Issue 11).
///
/// ```sh
/// dart run bin/scenario.dart scenarios/rifle_squad_vs_jeep.yaml
/// dart run bin/scenario.dart <file> --data <plan data directory>
/// ```
///
/// The data directory defaults to `../../apps/battle_team/plan/data`, the
/// plan in the hawkbee checkout; `economy.yaml` is read from the
/// `milestones` folder next to it. Only this tool reads files: the rules
/// core takes text.
void main(List<String> arguments) {
  final args = [...arguments];
  var dataDir = '../../apps/battle_team/plan/data';
  final dataFlag = args.indexOf('--data');
  if (dataFlag >= 0 && dataFlag + 1 < args.length) {
    dataDir = args[dataFlag + 1];
    args.removeRange(dataFlag, dataFlag + 2);
  }
  if (args.length != 1) {
    stderr.writeln('usage: dart run bin/scenario.dart <file> [--data <dir>]');
    exitCode = 64;
    return;
  }
  String read(String path) => File(path).readAsStringSync();
  final data = GameData.parse(
    units: read('$dataDir/units.yaml'),
    combat: read('$dataDir/combat.yaml'),
    terrain: read('$dataDir/terrain.yaml'),
    battle: read('$dataDir/battle.yaml'),
    economy: read('$dataDir/../milestones/economy.yaml'),
    medals: read('$dataDir/medals.yaml'),
  );
  final report = ScenarioRunner(data).run(Scenario.parse(read(args.single)));
  stdout
    ..writeln(report.text)
    ..writeln(report.machineLine);
}
